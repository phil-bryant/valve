package credentials

import (
	"context"
	"errors"
	"fmt"
	"time"

	"valve/internal/auth"
	"valve/internal/security"
)

var (
	ErrUnauthorized   = errors.New("unauthorized")
	ErrInvalidInput   = errors.New("invalid input")
	ErrNotFound       = errors.New("credential not found")
	ErrTenantMismatch = errors.New("credential tenant mismatch")
	ErrInvalidState   = errors.New("credential invalid state")
)

type Store interface {
	CreateCredential(ctx context.Context, rec CredentialRecord, hmacSecretEncrypted []byte, hmacSecretHash string) error
	GetCredential(ctx context.Context, credentialID string) (CredentialRecord, []byte, string, error)
	ListCredentials(ctx context.Context, tenantID string, installID string) ([]CredentialRecord, error)
	RevokeCredential(ctx context.Context, tenantID string, credentialID string) (*time.Time, error)
	RotateCredential(ctx context.Context, oldCredentialID string, oldTenantID string, oldInstallID string, replacement CredentialRecord, hmacSecretEncrypted []byte, hmacSecretHash string) error
	WriteAudit(ctx context.Context, audit AuditEntry) error
	LookupVerification(ctx context.Context, credentialID string) (VerificationResponse, error)
}

type Service struct {
	store           Store
	authorizer      auth.Authorizer
	uploadEndpoint  string
	hmacModeEnabled bool
	devAllowNoActor bool
}

func NewService(store Store, authorizer auth.Authorizer, uploadEndpoint string, hmacModeEnabled bool, devAllowNoActor bool) *Service {
	return &Service{
		store:           store,
		authorizer:      authorizer,
		uploadEndpoint:  uploadEndpoint,
		hmacModeEnabled: hmacModeEnabled,
		devAllowNoActor: devAllowNoActor,
	}
}

func (s *Service) Register(ctx context.Context, req RegisterRequest) (RegisterResponse, error) {
	if err := ValidateRegister(req, s.devAllowNoActor, s.hmacModeEnabled); err != nil {
		return RegisterResponse{}, fmt.Errorf("%w: %v", ErrInvalidInput, err)
	}
	allowed, err := s.authorizer.CanProvisionIngestCredential(ctx, req.ActorUserID, req.TenantID)
	if err != nil {
		return RegisterResponse{}, err
	}
	if !allowed {
		_ = s.store.WriteAudit(ctx, AuditEntry{
			ActorUserID: req.ActorUserID,
			TenantID:    req.TenantID,
			InstallID:   req.InstallID,
			Action:      "credential_registration_denied",
		})
		return RegisterResponse{}, ErrUnauthorized
	}

	credentialID, err := NewCredentialID()
	if err != nil {
		return RegisterResponse{}, err
	}

	var hmacSecret string
	var hmacEncrypted []byte
	var hmacHash string
	if req.CredentialMode == ModeHMACSHA256 {
		hmacSecret, err = security.GenerateRandomSecretBase64(32)
		if err != nil {
			return RegisterResponse{}, err
		}
		// TODO: replace with KMS envelope encryption in production.
		hmacEncrypted = []byte(hmacSecret)
		hmacHash = security.HashSecretHex(hmacSecret)
	}

	record := CredentialRecord{
		CredentialID:   credentialID,
		TenantID:       req.TenantID,
		InstallID:      req.InstallID,
		ActorUserID:    req.ActorUserID,
		AppBundleID:    req.AppBundleID,
		AppVersion:     req.AppVersion,
		AppBuild:       req.AppBuild,
		Platform:       req.Platform,
		CredentialMode: req.CredentialMode,
		PublicKey:      req.PublicKey,
		Status:         StatusActive,
		DeviceLabel:    req.DeviceLabel,
	}
	if err := s.store.CreateCredential(ctx, record, hmacEncrypted, hmacHash); err != nil {
		return RegisterResponse{}, err
	}

	_ = s.store.WriteAudit(ctx, AuditEntry{
		ActorUserID:  req.ActorUserID,
		TenantID:     req.TenantID,
		InstallID:    req.InstallID,
		CredentialID: credentialID,
		Action:       "credential_registered",
		MetadataJSON: fmt.Sprintf(`{"credential_mode":%q}`, req.CredentialMode),
	})

	return RegisterResponse{
		CredentialID:     credentialID,
		TenantScope:      req.TenantID,
		InstallID:        req.InstallID,
		UploadEndpoint:   s.uploadEndpoint,
		SigningAlgorithm: req.CredentialMode,
		Secret:           hmacSecret,
		Status:           StatusActive,
	}, nil
}

func (s *Service) Revoke(ctx context.Context, req RevokeRequest) (RevokeResponse, error) {
	if err := ValidateRevoke(req, s.devAllowNoActor); err != nil {
		return RevokeResponse{}, fmt.Errorf("%w: %v", ErrInvalidInput, err)
	}
	allowed, err := s.authorizer.CanRevokeIngestCredential(ctx, req.ActorUserID, req.TenantID, req.CredentialID)
	if err != nil {
		return RevokeResponse{}, err
	}
	if !allowed {
		_ = s.store.WriteAudit(ctx, AuditEntry{
			ActorUserID:  req.ActorUserID,
			TenantID:     req.TenantID,
			CredentialID: req.CredentialID,
			Action:       "credential_revoke_denied",
		})
		return RevokeResponse{}, ErrUnauthorized
	}

	record, _, _, err := s.store.GetCredential(ctx, req.CredentialID)
	if err != nil {
		return RevokeResponse{}, ErrNotFound
	}
	if record.TenantID != req.TenantID {
		return RevokeResponse{}, ErrTenantMismatch
	}
	revokedAt, err := s.store.RevokeCredential(ctx, req.TenantID, req.CredentialID)
	if err != nil {
		return RevokeResponse{}, ErrNotFound
	}
	_ = s.store.WriteAudit(ctx, AuditEntry{
		ActorUserID:  req.ActorUserID,
		TenantID:     req.TenantID,
		InstallID:    record.InstallID,
		CredentialID: req.CredentialID,
		Action:       "credential_revoked",
		Reason:       req.Reason,
	})
	return RevokeResponse{
		CredentialID: req.CredentialID,
		Status:       StatusRevoked,
		RevokedAt:    revokedAt,
	}, nil
}

func (s *Service) Rotate(ctx context.Context, req RotateRequest) (RotateResponse, error) {
	if err := ValidateRotate(req, s.devAllowNoActor, s.hmacModeEnabled); err != nil {
		return RotateResponse{}, fmt.Errorf("%w: %v", ErrInvalidInput, err)
	}
	allowed, err := s.authorizer.CanRevokeIngestCredential(ctx, req.ActorUserID, req.TenantID, req.OldCredentialID)
	if err != nil {
		return RotateResponse{}, err
	}
	if !allowed {
		return RotateResponse{}, ErrUnauthorized
	}

	oldRecord, _, _, err := s.store.GetCredential(ctx, req.OldCredentialID)
	if err != nil {
		return RotateResponse{}, ErrNotFound
	}
	if oldRecord.TenantID != req.TenantID {
		return RotateResponse{}, ErrTenantMismatch
	}
	if oldRecord.InstallID != req.InstallID {
		return RotateResponse{}, ErrInvalidInput
	}
	if oldRecord.Status != StatusActive {
		return RotateResponse{}, ErrInvalidState
	}

	newCredentialID, err := NewCredentialID()
	if err != nil {
		return RotateResponse{}, err
	}
	newRecord := CredentialRecord{
		CredentialID:   newCredentialID,
		TenantID:       oldRecord.TenantID,
		InstallID:      oldRecord.InstallID,
		ActorUserID:    req.ActorUserID,
		AppBundleID:    oldRecord.AppBundleID,
		AppVersion:     firstNonEmpty(req.AppVersion, oldRecord.AppVersion),
		AppBuild:       firstNonEmpty(req.AppBuild, oldRecord.AppBuild),
		Platform:       oldRecord.Platform,
		CredentialMode: req.CredentialMode,
		PublicKey:      req.NewPublicKey,
		Status:         StatusActive,
		DeviceLabel:    firstNonEmpty(req.DeviceLabel, oldRecord.DeviceLabel),
	}

	var hmacSecret string
	var hmacEncrypted []byte
	var hmacHash string
	if req.CredentialMode == ModeHMACSHA256 {
		hmacSecret, err = security.GenerateRandomSecretBase64(32)
		if err != nil {
			return RotateResponse{}, err
		}
		// TODO: replace with KMS envelope encryption in production.
		hmacEncrypted = []byte(hmacSecret)
		hmacHash = security.HashSecretHex(hmacSecret)
	}

	if err := s.store.RotateCredential(ctx, req.OldCredentialID, req.TenantID, req.InstallID, newRecord, hmacEncrypted, hmacHash); err != nil {
		return RotateResponse{}, err
	}

	_ = s.store.WriteAudit(ctx, AuditEntry{
		ActorUserID:  req.ActorUserID,
		TenantID:     req.TenantID,
		InstallID:    req.InstallID,
		CredentialID: req.OldCredentialID,
		Action:       "credential_rotated",
		MetadataJSON: fmt.Sprintf(`{"new_credential_id":%q,"credential_mode":%q}`, newCredentialID, req.CredentialMode),
	})

	return RotateResponse{
		OldCredentialID:  req.OldCredentialID,
		OldStatus:        StatusRotated,
		NewCredentialID:  newCredentialID,
		TenantScope:      req.TenantID,
		InstallID:        req.InstallID,
		SigningAlgorithm: req.CredentialMode,
		Status:           StatusActive,
		Secret:           hmacSecret,
	}, nil
}

func (s *Service) List(ctx context.Context, tenantID string, installID string) (ListResponse, error) {
	if tenantID == "" || installID == "" {
		return ListResponse{}, fmt.Errorf("%w: tenant_id and install_id are required", ErrInvalidInput)
	}
	records, err := s.store.ListCredentials(ctx, tenantID, installID)
	if err != nil {
		return ListResponse{}, err
	}
	return ListResponse{Credentials: records}, nil
}

func (s *Service) VerificationLookup(ctx context.Context, credentialID string) (VerificationResponse, error) {
	if credentialID == "" {
		return VerificationResponse{}, fmt.Errorf("%w: credential_id is required", ErrInvalidInput)
	}
	resp, err := s.store.LookupVerification(ctx, credentialID)
	if err != nil {
		return VerificationResponse{}, ErrNotFound
	}
	_ = s.store.WriteAudit(ctx, AuditEntry{
		TenantID:     resp.TenantID,
		InstallID:    resp.InstallID,
		CredentialID: resp.CredentialID,
		Action:       "credential_lookup_for_verification",
	})
	return resp, nil
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if v != "" {
			return v
		}
	}
	return ""
}
