package credentials

import (
	"context"
	"encoding/base64"
	"errors"
	"strings"
	"testing"
	"time"

	"valve/internal/auth"
)

func TestRegisterEd25519CredentialSucceeds(t *testing.T) {
	// #R001: Registration validates, authorizes, persists, and returns active credentials.
	// #R005: Revoke flow enforces tenant ownership and lifecycle transitions.
	// #R010: Rotation flow replaces active credentials and records lineage.
	// #R015: Read-only list and verification lookups enforce required identifiers.
	store := newMockStore()
	svc := NewService(store, auth.DevAuthorizer{AllowAll: true}, "https://ingest.example.com/v1/events/batch", false, false)

	pubKey := base64.StdEncoding.EncodeToString(make([]byte, 32))
	resp, err := svc.Register(context.Background(), RegisterRequest{
		TenantID:       "tenant_abc",
		ActorUserID:    "user_123",
		InstallID:      "install_1",
		AppBundleID:    "com.example.App",
		AppVersion:     "1.8.3",
		AppBuild:       "1842",
		Platform:       "macOS",
		CredentialMode: ModeEd25519,
		PublicKey:      pubKey,
	})
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if resp.CredentialID == "" || !strings.HasPrefix(resp.CredentialID, "cred_") {
		t.Fatalf("expected opaque credential id, got %q", resp.CredentialID)
	}
	if resp.SigningAlgorithm != ModeEd25519 {
		t.Fatalf("unexpected algorithm %q", resp.SigningAlgorithm)
	}
}

func TestRegisterEd25519InvalidPublicKeyFails(t *testing.T) {
	store := newMockStore()
	svc := NewService(store, auth.DevAuthorizer{AllowAll: true}, "https://ingest.example.com/v1/events/batch", false, false)

	_, err := svc.Register(context.Background(), RegisterRequest{
		TenantID:       "tenant_abc",
		ActorUserID:    "user_123",
		InstallID:      "install_1",
		AppBundleID:    "com.example.App",
		Platform:       "macOS",
		CredentialMode: ModeEd25519,
		PublicKey:      "bad",
	})
	if !errors.Is(err, ErrInvalidInput) {
		t.Fatalf("expected ErrInvalidInput, got %v", err)
	}
}

func TestRegisterMissingTenantFails(t *testing.T) {
	store := newMockStore()
	svc := NewService(store, auth.DevAuthorizer{AllowAll: true}, "https://ingest.example.com/v1/events/batch", false, false)

	_, err := svc.Register(context.Background(), RegisterRequest{
		ActorUserID:    "user_123",
		InstallID:      "install_1",
		AppBundleID:    "com.example.App",
		Platform:       "macOS",
		CredentialMode: ModeEd25519,
		PublicKey:      base64.StdEncoding.EncodeToString(make([]byte, 32)),
	})
	if !errors.Is(err, ErrInvalidInput) {
		t.Fatalf("expected ErrInvalidInput, got %v", err)
	}
}

func TestRegisterMissingInstallFails(t *testing.T) {
	store := newMockStore()
	svc := NewService(store, auth.DevAuthorizer{AllowAll: true}, "https://ingest.example.com/v1/events/batch", false, false)

	_, err := svc.Register(context.Background(), RegisterRequest{
		TenantID:       "tenant_abc",
		ActorUserID:    "user_123",
		AppBundleID:    "com.example.App",
		Platform:       "macOS",
		CredentialMode: ModeEd25519,
		PublicKey:      base64.StdEncoding.EncodeToString(make([]byte, 32)),
	})
	if !errors.Is(err, ErrInvalidInput) {
		t.Fatalf("expected ErrInvalidInput, got %v", err)
	}
}

func TestRegisterDeniedByAuthorizerFails(t *testing.T) {
	store := newMockStore()
	svc := NewService(store, auth.DevAuthorizer{AllowAll: false}, "https://ingest.example.com/v1/events/batch", false, false)

	_, err := svc.Register(context.Background(), RegisterRequest{
		TenantID:       "tenant_abc",
		ActorUserID:    "user_123",
		InstallID:      "install_1",
		AppBundleID:    "com.example.App",
		Platform:       "macOS",
		CredentialMode: ModeEd25519,
		PublicKey:      base64.StdEncoding.EncodeToString(make([]byte, 32)),
	})
	if !errors.Is(err, ErrUnauthorized) {
		t.Fatalf("expected ErrUnauthorized, got %v", err)
	}
}

func TestHMACRegistrationDisabledFails(t *testing.T) {
	store := newMockStore()
	svc := NewService(store, auth.DevAuthorizer{AllowAll: true}, "https://ingest.example.com/v1/events/batch", false, false)

	_, err := svc.Register(context.Background(), RegisterRequest{
		TenantID:       "tenant_abc",
		ActorUserID:    "user_123",
		InstallID:      "install_1",
		AppBundleID:    "com.example.App",
		Platform:       "macOS",
		CredentialMode: ModeHMACSHA256,
	})
	if !errors.Is(err, ErrInvalidInput) {
		t.Fatalf("expected ErrInvalidInput, got %v", err)
	}
}

func TestHMACRegistrationEnabledReturnsSecretOnce(t *testing.T) {
	store := newMockStore()
	svc := NewService(store, auth.DevAuthorizer{AllowAll: true}, "https://ingest.example.com/v1/events/batch", true, false)

	resp, err := svc.Register(context.Background(), RegisterRequest{
		TenantID:       "tenant_abc",
		ActorUserID:    "user_123",
		InstallID:      "install_1",
		AppBundleID:    "com.example.App",
		Platform:       "macOS",
		CredentialMode: ModeHMACSHA256,
	})
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if resp.Secret == "" {
		t.Fatalf("expected one-time secret in register response")
	}
	lookup, err := svc.VerificationLookup(context.Background(), resp.CredentialID)
	if err != nil {
		t.Fatalf("lookup failed: %v", err)
	}
	if lookup.PublicKey != "" {
		t.Fatalf("did not expect hmac secret/public key in verification response")
	}
}

func TestHMACSecretNotReturnedByListOrGetEndpoints(t *testing.T) {
	store := newMockStore()
	svc := NewService(store, auth.DevAuthorizer{AllowAll: true}, "https://ingest.example.com/v1/events/batch", true, false)

	resp, err := svc.Register(context.Background(), RegisterRequest{
		TenantID:       "tenant_abc",
		ActorUserID:    "user_123",
		InstallID:      "install_1",
		AppBundleID:    "com.example.App",
		Platform:       "macOS",
		CredentialMode: ModeHMACSHA256,
	})
	if err != nil {
		t.Fatalf("register failed: %v", err)
	}
	listResp, err := svc.List(context.Background(), "tenant_abc", "install_1")
	if err != nil {
		t.Fatalf("list failed: %v", err)
	}
	if len(listResp.Credentials) != 1 {
		t.Fatalf("expected one credential")
	}
	if listResp.Credentials[0].PublicKey != "" {
		t.Fatalf("did not expect public key in hmac list response")
	}
	verifyResp, err := svc.VerificationLookup(context.Background(), resp.CredentialID)
	if err != nil {
		t.Fatalf("verification failed: %v", err)
	}
	if verifyResp.PublicKey != "" {
		t.Fatalf("did not expect public key in hmac verification")
	}
}

func TestRevokeActiveCredentialSucceeds(t *testing.T) {
	store := newMockStore()
	credID := "cred_abc"
	store.records[credID] = CredentialRecord{
		CredentialID: credID,
		TenantID:     "tenant_abc",
		InstallID:    "install_1",
		AppBundleID:  "com.example.App",
		Platform:     "macOS",
		Status:       StatusActive,
		CreatedAt:    time.Now(),
	}
	svc := NewService(store, auth.DevAuthorizer{AllowAll: true}, "https://ingest.example.com/v1/events/batch", true, false)

	resp, err := svc.Revoke(context.Background(), RevokeRequest{
		TenantID:     "tenant_abc",
		ActorUserID:  "user_123",
		CredentialID: credID,
		Reason:       "device_lost",
	})
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if resp.Status != StatusRevoked || resp.RevokedAt == nil {
		t.Fatalf("expected revoked response")
	}
}

func TestRevokeWrongTenantFails(t *testing.T) {
	store := newMockStore()
	credID := "cred_abc"
	store.records[credID] = CredentialRecord{
		CredentialID: credID,
		TenantID:     "tenant_other",
		InstallID:    "install_1",
		AppBundleID:  "com.example.App",
		Platform:     "macOS",
		Status:       StatusActive,
		CreatedAt:    time.Now(),
	}
	svc := NewService(store, auth.DevAuthorizer{AllowAll: true}, "https://ingest.example.com/v1/events/batch", true, false)

	_, err := svc.Revoke(context.Background(), RevokeRequest{
		TenantID:     "tenant_abc",
		ActorUserID:  "user_123",
		CredentialID: credID,
	})
	if !errors.Is(err, ErrTenantMismatch) {
		t.Fatalf("expected ErrTenantMismatch, got %v", err)
	}
}

func TestRevokeDeniedByAuthorizerFails(t *testing.T) {
	store := newMockStore()
	credID := "cred_abc"
	store.records[credID] = CredentialRecord{
		CredentialID: credID,
		TenantID:     "tenant_abc",
		InstallID:    "install_1",
		AppBundleID:  "com.example.App",
		Platform:     "macOS",
		Status:       StatusActive,
		CreatedAt:    time.Now(),
	}
	svc := NewService(store, auth.DevAuthorizer{AllowAll: false}, "https://ingest.example.com/v1/events/batch", true, false)

	_, err := svc.Revoke(context.Background(), RevokeRequest{
		TenantID:     "tenant_abc",
		ActorUserID:  "user_123",
		CredentialID: credID,
	})
	if !errors.Is(err, ErrUnauthorized) {
		t.Fatalf("expected ErrUnauthorized, got %v", err)
	}
}

func TestRotateCredentialSucceedsAndMarksOldRotated(t *testing.T) {
	store := newMockStore()
	oldID := "cred_old"
	store.records[oldID] = CredentialRecord{
		CredentialID:   oldID,
		TenantID:       "tenant_abc",
		InstallID:      "install_1",
		AppBundleID:    "com.example.App",
		AppVersion:     "1.0.0",
		AppBuild:       "1000",
		Platform:       "macOS",
		CredentialMode: ModeEd25519,
		PublicKey:      base64.StdEncoding.EncodeToString(make([]byte, 32)),
		Status:         StatusActive,
		CreatedAt:      time.Now(),
	}
	svc := NewService(store, auth.DevAuthorizer{AllowAll: true}, "https://ingest.example.com/v1/events/batch", true, false)

	resp, err := svc.Rotate(context.Background(), RotateRequest{
		TenantID:        "tenant_abc",
		ActorUserID:     "user_123",
		OldCredentialID: oldID,
		InstallID:       "install_1",
		CredentialMode:  ModeEd25519,
		NewPublicKey:    base64.StdEncoding.EncodeToString(make([]byte, 32)),
	})
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if resp.OldStatus != StatusRotated || resp.NewCredentialID == "" {
		t.Fatalf("unexpected rotate response: %+v", resp)
	}
	if store.records[oldID].Status != StatusRotated {
		t.Fatalf("expected old credential rotated")
	}
}

func TestRotateCredentialFromWrongTenantFails(t *testing.T) {
	store := newMockStore()
	oldID := "cred_old"
	store.records[oldID] = CredentialRecord{
		CredentialID:   oldID,
		TenantID:       "tenant_other",
		InstallID:      "install_1",
		AppBundleID:    "com.example.App",
		Platform:       "macOS",
		CredentialMode: ModeEd25519,
		PublicKey:      base64.StdEncoding.EncodeToString(make([]byte, 32)),
		Status:         StatusActive,
		CreatedAt:      time.Now(),
	}
	svc := NewService(store, auth.DevAuthorizer{AllowAll: true}, "https://ingest.example.com/v1/events/batch", true, false)

	_, err := svc.Rotate(context.Background(), RotateRequest{
		TenantID:        "tenant_abc",
		ActorUserID:     "user_123",
		OldCredentialID: oldID,
		InstallID:       "install_1",
		CredentialMode:  ModeEd25519,
		NewPublicKey:    base64.StdEncoding.EncodeToString(make([]byte, 32)),
	})
	if !errors.Is(err, ErrTenantMismatch) {
		t.Fatalf("expected ErrTenantMismatch, got %v", err)
	}
}

func TestListCredentialsWorks(t *testing.T) {
	store := newMockStore()
	store.records["cred_1"] = CredentialRecord{
		CredentialID: "cred_1",
		TenantID:     "tenant_abc",
		InstallID:    "install_1",
		AppBundleID:  "com.example.App",
		Platform:     "macOS",
		Status:       StatusActive,
		CreatedAt:    time.Now(),
	}
	svc := NewService(store, auth.DevAuthorizer{AllowAll: true}, "https://ingest.example.com/v1/events/batch", true, false)

	listResp, err := svc.List(context.Background(), "tenant_abc", "install_1")
	if err != nil {
		t.Fatalf("list failed: %v", err)
	}
	if len(listResp.Credentials) != 1 {
		t.Fatalf("expected one credential, got %d", len(listResp.Credentials))
	}
}

func TestVerificationLookupReturnsPublicKeyForActiveCredential(t *testing.T) {
	store := newMockStore()
	store.records["cred_1"] = CredentialRecord{
		CredentialID:   "cred_1",
		TenantID:       "tenant_abc",
		InstallID:      "install_1",
		AppBundleID:    "com.example.App",
		Platform:       "macOS",
		CredentialMode: ModeEd25519,
		PublicKey:      base64.StdEncoding.EncodeToString(make([]byte, 32)),
		Status:         StatusActive,
		CreatedAt:      time.Now(),
	}
	svc := NewService(store, auth.DevAuthorizer{AllowAll: true}, "https://ingest.example.com/v1/events/batch", true, false)

	resp, err := svc.VerificationLookup(context.Background(), "cred_1")
	if err != nil {
		t.Fatalf("lookup failed: %v", err)
	}
	if resp.PublicKey == "" || resp.Status != StatusActive {
		t.Fatalf("unexpected verification response: %+v", resp)
	}
}

func TestVerificationLookupReturnsRevokedStatus(t *testing.T) {
	store := newMockStore()
	now := time.Now()
	store.records["cred_1"] = CredentialRecord{
		CredentialID:   "cred_1",
		TenantID:       "tenant_abc",
		InstallID:      "install_1",
		AppBundleID:    "com.example.App",
		Platform:       "macOS",
		CredentialMode: ModeEd25519,
		PublicKey:      base64.StdEncoding.EncodeToString(make([]byte, 32)),
		Status:         StatusRevoked,
		RevokedAt:      &now,
		CreatedAt:      time.Now(),
	}
	svc := NewService(store, auth.DevAuthorizer{AllowAll: true}, "https://ingest.example.com/v1/events/batch", true, false)

	resp, err := svc.VerificationLookup(context.Background(), "cred_1")
	if err != nil {
		t.Fatalf("lookup failed: %v", err)
	}
	if resp.Status != StatusRevoked {
		t.Fatalf("expected revoked status, got %s", resp.Status)
	}
}

func TestAuditLogWrittenForRegisterRevokeRotate(t *testing.T) {
	store := newMockStore()
	svc := NewService(store, auth.DevAuthorizer{AllowAll: true}, "https://ingest.example.com/v1/events/batch", true, false)
	pubKey := base64.StdEncoding.EncodeToString(make([]byte, 32))

	registerResp, err := svc.Register(context.Background(), RegisterRequest{
		TenantID:       "tenant_abc",
		ActorUserID:    "user_123",
		InstallID:      "install_1",
		AppBundleID:    "com.example.App",
		Platform:       "macOS",
		CredentialMode: ModeEd25519,
		PublicKey:      pubKey,
	})
	if err != nil {
		t.Fatalf("register failed: %v", err)
	}
	if _, err := svc.Revoke(context.Background(), RevokeRequest{
		TenantID:     "tenant_abc",
		ActorUserID:  "user_123",
		CredentialID: registerResp.CredentialID,
		Reason:       "test",
	}); err != nil {
		t.Fatalf("revoke failed: %v", err)
	}

	oldID := "cred_old_rotate"
	store.records[oldID] = CredentialRecord{
		CredentialID:   oldID,
		TenantID:       "tenant_abc",
		InstallID:      "install_1",
		AppBundleID:    "com.example.App",
		Platform:       "macOS",
		CredentialMode: ModeEd25519,
		PublicKey:      pubKey,
		Status:         StatusActive,
		CreatedAt:      time.Now(),
	}
	if _, err := svc.Rotate(context.Background(), RotateRequest{
		TenantID:        "tenant_abc",
		ActorUserID:     "user_123",
		OldCredentialID: oldID,
		InstallID:       "install_1",
		CredentialMode:  ModeEd25519,
		NewPublicKey:    pubKey,
	}); err != nil {
		t.Fatalf("rotate failed: %v", err)
	}

	if len(store.audits) < 3 {
		t.Fatalf("expected audit writes for register/revoke/rotate, got %d", len(store.audits))
	}
}

func TestCredentialIDsAreOpaqueAndNonSequential(t *testing.T) {
	id1, err := NewCredentialID()
	if err != nil {
		t.Fatalf("failed to generate id: %v", err)
	}
	id2, err := NewCredentialID()
	if err != nil {
		t.Fatalf("failed to generate id: %v", err)
	}
	if id1 == id2 {
		t.Fatalf("expected distinct ids")
	}
	if !strings.HasPrefix(id1, "cred_") || !strings.HasPrefix(id2, "cred_") {
		t.Fatalf("expected cred_ prefix")
	}
}

func TestUploadTargetReturnsDefaultRouteAndTTL(t *testing.T) {
	store := newMockStore()
	credentialID := "cred_upload_default"
	store.records[credentialID] = CredentialRecord{
		CredentialID: credentialID,
		TenantID:     "tenant_abc",
		InstallID:    "install_1",
		Status:       StatusActive,
	}
	svc := NewService(store, auth.DevAuthorizer{AllowAll: true}, "https://ingest.example.com/v1/events/batch", true, false)
	if err := svc.ConfigureUploadTargetDiscovery(UploadTargetDiscoveryConfig{
		TTLSeconds:               120,
		RoutingVersion:           "routing-v1",
		AllowedUploadTargetHosts: []string{"ingest.example.com"},
	}); err != nil {
		t.Fatalf("configure discovery failed: %v", err)
	}

	resp, err := svc.UploadTarget(context.Background(), UploadTargetRequest{
		TenantID:     "tenant_abc",
		InstallID:    "install_1",
		CredentialID: credentialID,
	})
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if resp.UploadURL != "https://ingest.example.com/v1/events/batch" {
		t.Fatalf("unexpected upload url %q", resp.UploadURL)
	}
	if resp.TTLSeconds != 120 {
		t.Fatalf("unexpected ttl %d", resp.TTLSeconds)
	}
	if resp.RoutingVersion != "routing-v1" {
		t.Fatalf("unexpected routing version %q", resp.RoutingVersion)
	}
}

func TestUploadTargetUsesTenantRouteForEndpointRotation(t *testing.T) {
	store := newMockStore()
	credentialID := "cred_upload_rotation"
	store.records[credentialID] = CredentialRecord{
		CredentialID: credentialID,
		TenantID:     "tenant_abc",
		InstallID:    "install_1",
		Status:       StatusActive,
	}
	svc := NewService(store, auth.DevAuthorizer{AllowAll: true}, "https://ingest.example.com/v1/events/batch", true, false)
	if err := svc.ConfigureUploadTargetDiscovery(UploadTargetDiscoveryConfig{
		TTLSeconds:               300,
		RoutingVersion:           "routing-v2",
		AllowedUploadTargetHosts: []string{"ingest.example.com", "ingest-eu.example.com"},
		TenantUploadEndpointByID: map[string]string{
			"tenant_abc": "https://ingest-eu.example.com/v1/events/batch",
		},
	}); err != nil {
		t.Fatalf("configure discovery failed: %v", err)
	}

	resp, err := svc.UploadTarget(context.Background(), UploadTargetRequest{
		TenantID:     "tenant_abc",
		InstallID:    "install_1",
		CredentialID: credentialID,
	})
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if resp.UploadURL != "https://ingest-eu.example.com/v1/events/batch" {
		t.Fatalf("expected rotated route, got %q", resp.UploadURL)
	}
}

func TestUploadTargetRejectsRevokedCredential(t *testing.T) {
	store := newMockStore()
	credentialID := "cred_upload_revoked"
	store.records[credentialID] = CredentialRecord{
		CredentialID: credentialID,
		TenantID:     "tenant_abc",
		InstallID:    "install_1",
		Status:       StatusRevoked,
	}
	svc := NewService(store, auth.DevAuthorizer{AllowAll: true}, "https://ingest.example.com/v1/events/batch", true, false)
	if err := svc.ConfigureUploadTargetDiscovery(UploadTargetDiscoveryConfig{
		TTLSeconds:               300,
		RoutingVersion:           "routing-v1",
		AllowedUploadTargetHosts: []string{"ingest.example.com"},
	}); err != nil {
		t.Fatalf("configure discovery failed: %v", err)
	}

	_, err := svc.UploadTarget(context.Background(), UploadTargetRequest{
		TenantID:     "tenant_abc",
		InstallID:    "install_1",
		CredentialID: credentialID,
	})
	if !errors.Is(err, ErrUnauthorized) {
		t.Fatalf("expected ErrUnauthorized, got %v", err)
	}
}

func TestUploadTargetTenantMismatchReturnsConflictError(t *testing.T) {
	store := newMockStore()
	credentialID := "cred_upload_mismatch"
	store.records[credentialID] = CredentialRecord{
		CredentialID: credentialID,
		TenantID:     "tenant_abc",
		InstallID:    "install_1",
		Status:       StatusActive,
	}
	svc := NewService(store, auth.DevAuthorizer{AllowAll: true}, "https://ingest.example.com/v1/events/batch", true, false)
	if err := svc.ConfigureUploadTargetDiscovery(UploadTargetDiscoveryConfig{
		TTLSeconds:               300,
		RoutingVersion:           "routing-v1",
		AllowedUploadTargetHosts: []string{"ingest.example.com"},
	}); err != nil {
		t.Fatalf("configure discovery failed: %v", err)
	}

	_, err := svc.UploadTarget(context.Background(), UploadTargetRequest{
		TenantID:     "tenant_other",
		InstallID:    "install_1",
		CredentialID: credentialID,
	})
	if !errors.Is(err, ErrTenantMismatch) {
		t.Fatalf("expected ErrTenantMismatch, got %v", err)
	}
}

func TestUploadTargetUnknownInstallReturnsNotFound(t *testing.T) {
	store := newMockStore()
	credentialID := "cred_upload_not_found"
	store.records[credentialID] = CredentialRecord{
		CredentialID: credentialID,
		TenantID:     "tenant_abc",
		InstallID:    "install_1",
		Status:       StatusActive,
	}
	svc := NewService(store, auth.DevAuthorizer{AllowAll: true}, "https://ingest.example.com/v1/events/batch", true, false)
	if err := svc.ConfigureUploadTargetDiscovery(UploadTargetDiscoveryConfig{
		TTLSeconds:               300,
		RoutingVersion:           "routing-v1",
		AllowedUploadTargetHosts: []string{"ingest.example.com"},
	}); err != nil {
		t.Fatalf("configure discovery failed: %v", err)
	}

	_, err := svc.UploadTarget(context.Background(), UploadTargetRequest{
		TenantID:     "tenant_abc",
		InstallID:    "install_other",
		CredentialID: credentialID,
	})
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("expected ErrNotFound, got %v", err)
	}
}

type mockStore struct {
	records map[string]CredentialRecord
	audits  []AuditEntry
}

func newMockStore() *mockStore {
	return &mockStore{
		records: map[string]CredentialRecord{},
		audits:  []AuditEntry{},
	}
}

func (m *mockStore) CreateCredential(_ context.Context, rec CredentialRecord, _ []byte, _ string) error {
	rec.CreatedAt = time.Now()
	m.records[rec.CredentialID] = rec
	return nil
}

func (m *mockStore) GetCredential(_ context.Context, credentialID string) (CredentialRecord, []byte, string, error) {
	rec, ok := m.records[credentialID]
	if !ok {
		return CredentialRecord{}, nil, "", errors.New("not found")
	}
	return rec, nil, "", nil
}

func (m *mockStore) ListCredentials(_ context.Context, tenantID string, installID string) ([]CredentialRecord, error) {
	out := make([]CredentialRecord, 0)
	for _, rec := range m.records {
		if rec.TenantID == tenantID && rec.InstallID == installID {
			out = append(out, rec)
		}
	}
	return out, nil
}

func (m *mockStore) RevokeCredential(_ context.Context, tenantID string, credentialID string) (*time.Time, error) {
	rec, ok := m.records[credentialID]
	if !ok {
		return nil, errors.New("not found")
	}
	if rec.TenantID != tenantID {
		return nil, errors.New("not found")
	}
	now := time.Now()
	rec.Status = StatusRevoked
	rec.RevokedAt = &now
	m.records[credentialID] = rec
	return &now, nil
}

func (m *mockStore) RotateCredential(_ context.Context, oldCredentialID string, oldTenantID string, oldInstallID string, replacement CredentialRecord, _ []byte, _ string) error {
	old, ok := m.records[oldCredentialID]
	if !ok {
		return errors.New("not found")
	}
	if old.TenantID != oldTenantID || old.InstallID != oldInstallID || old.Status != StatusActive {
		return errors.New("not found")
	}
	now := time.Now()
	old.Status = StatusRotated
	old.RotatedAt = &now
	old.ReplacedByCredentialID = replacement.CredentialID
	m.records[oldCredentialID] = old
	replacement.CreatedAt = time.Now()
	m.records[replacement.CredentialID] = replacement
	return nil
}

func (m *mockStore) WriteAudit(_ context.Context, audit AuditEntry) error {
	m.audits = append(m.audits, audit)
	return nil
}

func (m *mockStore) LookupVerification(_ context.Context, credentialID string) (VerificationResponse, error) {
	rec, ok := m.records[credentialID]
	if !ok {
		return VerificationResponse{}, errors.New("not found")
	}
	return VerificationResponse{
		CredentialID:   rec.CredentialID,
		TenantID:       rec.TenantID,
		InstallID:      rec.InstallID,
		AppBundleID:    rec.AppBundleID,
		CredentialMode: rec.CredentialMode,
		PublicKey:      rec.PublicKey,
		Status:         rec.Status,
		RevokedAt:      rec.RevokedAt,
	}, nil
}
