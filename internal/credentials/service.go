package credentials

import (
	"context"
	"errors"
	"fmt"
	"net/url"
	"strings"
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
	store                    Store
	authorizer               auth.Authorizer
	uploadEndpoint           string
	hmacModeEnabled          bool
	devAllowNoActor          bool
	uploadTargetTTL          time.Duration
	routingVersion           string
	tenantUploadEndpointByID map[string]string
	allowedUploadTargetHosts map[string]struct{}
}

func NewService(store Store, authorizer auth.Authorizer, uploadEndpoint string, hmacModeEnabled bool, devAllowNoActor bool) *Service {
	allowedHosts := map[string]struct{}{}
	if parsed, err := url.Parse(uploadEndpoint); err == nil {
		if hostname := strings.ToLower(parsed.Hostname()); hostname != "" {
			allowedHosts[hostname] = struct{}{}
		}
	}
	return &Service{
		store:                    store,
		authorizer:               authorizer,
		uploadEndpoint:           uploadEndpoint,
		hmacModeEnabled:          hmacModeEnabled,
		devAllowNoActor:          devAllowNoActor,
		uploadTargetTTL:          5 * time.Minute,
		routingVersion:           "v1",
		tenantUploadEndpointByID: map[string]string{},
		allowedUploadTargetHosts: allowedHosts,
	}
}

type UploadTargetDiscoveryConfig struct {
	TTLSeconds               int
	RoutingVersion           string
	TenantUploadEndpointByID map[string]string
	AllowedUploadTargetHosts []string
}

// #R025: Validate and apply upload target discovery configuration atomically.
func (s *Service) ConfigureUploadTargetDiscovery(cfg UploadTargetDiscoveryConfig) error {
	if cfg.TTLSeconds <= 0 {
		return fmt.Errorf("%w: upload target ttl_seconds must be > 0", ErrInvalidInput)
	}
	if cfg.RoutingVersion == "" {
		return fmt.Errorf("%w: routing_version is required", ErrInvalidInput)
	}

	allowedHosts := map[string]struct{}{}
	for _, raw := range cfg.AllowedUploadTargetHosts {
		host := normalizeAllowedHost(raw)
		if host == "" {
			continue
		}
		allowedHosts[host] = struct{}{}
	}

	parsedDefault, err := parseUploadTargetURL(s.uploadEndpoint)
	if err != nil {
		return err
	}
	if _, ok := allowedHosts[parsedDefault.Hostname()]; !ok {
		return fmt.Errorf("%w: upload endpoint host is not allowlisted", ErrInvalidInput)
	}

	routes := make(map[string]string, len(cfg.TenantUploadEndpointByID))
	for tenantID, endpoint := range cfg.TenantUploadEndpointByID {
		if tenantID == "" {
			return fmt.Errorf("%w: tenant route key cannot be empty", ErrInvalidInput)
		}
		parsedRoute, parseErr := parseUploadTargetURL(endpoint)
		if parseErr != nil {
			return parseErr
		}
		if _, ok := allowedHosts[parsedRoute.Hostname()]; !ok {
			return fmt.Errorf("%w: tenant route host is not allowlisted", ErrInvalidInput)
		}
		routes[tenantID] = parsedRoute.String()
	}

	s.uploadTargetTTL = time.Duration(cfg.TTLSeconds) * time.Second
	s.routingVersion = cfg.RoutingVersion
	s.tenantUploadEndpointByID = routes
	s.allowedUploadTargetHosts = allowedHosts
	return nil
}

// #R001: Register credentials through validation, authorization, persistence, and audit writes.
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

// #R005: Revoke active credentials with tenant ownership checks and audit events.
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

// #R010: Rotate credentials by replacing active key material and recording lineage.
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

// #R015: Validate read-only lookup inputs and normalize missing-resource semantics.
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

// #R020: Validate, authorize, and resolve upload target for active credentials.
func (s *Service) UploadTarget(ctx context.Context, req UploadTargetRequest) (UploadTargetResponse, error) {
	if err := ValidateUploadTargetRequest(req); err != nil {
		return UploadTargetResponse{}, fmt.Errorf("%w: %v", ErrInvalidInput, err)
	}
	record, _, _, err := s.store.GetCredential(ctx, req.CredentialID)
	if err != nil {
		return UploadTargetResponse{}, ErrNotFound
	}
	if record.InstallID != req.InstallID {
		return UploadTargetResponse{}, ErrNotFound
	}
	if record.TenantID != req.TenantID {
		return UploadTargetResponse{}, ErrTenantMismatch
	}
	if record.Status != StatusActive {
		return UploadTargetResponse{}, ErrUnauthorized
	}

	uploadURL, err := s.resolveUploadEndpoint(req.TenantID)
	if err != nil {
		return UploadTargetResponse{}, err
	}

	expiresAt := time.Now().UTC().Add(s.uploadTargetTTL)
	ttlSeconds := int(s.uploadTargetTTL / time.Second)
	_ = s.store.WriteAudit(ctx, AuditEntry{
		TenantID:     req.TenantID,
		InstallID:    req.InstallID,
		CredentialID: req.CredentialID,
		Action:       "upload_target_discovered",
		MetadataJSON: fmt.Sprintf(`{"routing_version":%q}`, s.routingVersion),
	})
	return UploadTargetResponse{
		UploadURL:      uploadURL,
		ExpiresAt:      expiresAt,
		TTLSeconds:     ttlSeconds,
		RoutingVersion: s.routingVersion,
	}, nil
}

func (s *Service) resolveUploadEndpoint(tenantID string) (string, error) {
	uploadURL := s.uploadEndpoint
	if tenantRoute, ok := s.tenantUploadEndpointByID[tenantID]; ok {
		uploadURL = tenantRoute
	}
	parsed, err := parseUploadTargetURL(uploadURL)
	if err != nil {
		return "", err
	}
	if len(s.allowedUploadTargetHosts) > 0 {
		if _, ok := s.allowedUploadTargetHosts[parsed.Hostname()]; !ok {
			return "", fmt.Errorf("%w: resolved upload target host is not allowlisted", ErrInvalidInput)
		}
	}
	return parsed.String(), nil
}

func parseUploadTargetURL(raw string) (*url.URL, error) {
	parsed, err := url.Parse(raw)
	if err != nil {
		return nil, fmt.Errorf("%w: invalid upload target url", ErrInvalidInput)
	}
	if parsed.Scheme != "https" && !(parsed.Scheme == "http" && isLocalHostname(parsed.Hostname())) {
		return nil, fmt.Errorf("%w: upload target url must use https", ErrInvalidInput)
	}
	if parsed.Hostname() == "" {
		return nil, fmt.Errorf("%w: upload target url host is required", ErrInvalidInput)
	}
	parsed.Host = strings.ToLower(parsed.Host)
	return parsed, nil
}

func isLocalHostname(host string) bool {
	normalized := strings.ToLower(strings.TrimSpace(host))
	switch normalized {
	case "localhost", "127.0.0.1", "::1":
		return true
	default:
		return false
	}
}

func normalizeAllowedHost(raw string) string {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return ""
	}
	if strings.Contains(trimmed, "://") {
		parsed, err := url.Parse(trimmed)
		if err == nil && parsed.Hostname() != "" {
			return strings.ToLower(parsed.Hostname())
		}
		return ""
	}
	if strings.Contains(trimmed, "/") {
		return ""
	}
	if strings.Contains(trimmed, ":") {
		host, _, found := strings.Cut(trimmed, ":")
		if found && host != "" {
			return strings.ToLower(host)
		}
	}
	return strings.ToLower(trimmed)
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if v != "" {
			return v
		}
	}
	return ""
}
