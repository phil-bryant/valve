package storage

import (
	"context"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	"valve/internal/credentials"
)

func TestPostgresIntegrationCredentialLifecycle(t *testing.T) {
	// #R001: Store initializes postgres pool and readiness interactions.
	// #R005: Credential lifecycle persistence is validated end-to-end.
	// #R010: Audit and verification persistence paths are exercised.
	// #R015: Schema application from SQL file is required for integration setup.
	databaseURL := integrationDatabaseURL(t)
	ctx := context.Background()

	store, err := NewPostgresStore(ctx, databaseURL)
	if err != nil {
		t.Fatalf("new store failed: %v", err)
	}
	defer store.Close()

	_, file, _, _ := runtime.Caller(0)
	schemaPath := filepath.Join(filepath.Dir(file), "schema.sql")
	if err := store.ApplySchemaFromFile(ctx, schemaPath); err != nil {
		t.Fatalf("apply schema failed: %v", err)
	}

	tenantID := "tenant_it_" + time.Now().UTC().Format("150405")
	installID := "install_it_1"
	credentialID := "cred_it_active"
	pubKey := "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

	create := credentials.CredentialRecord{
		CredentialID:   credentialID,
		TenantID:       tenantID,
		InstallID:      installID,
		ActorUserID:    "user_it",
		AppBundleID:    "com.example.App",
		AppVersion:     "1.0.0",
		AppBuild:       "1000",
		Platform:       "macOS",
		CredentialMode: credentials.ModeEd25519,
		PublicKey:      pubKey,
		Status:         credentials.StatusActive,
	}
	if err := store.CreateCredential(ctx, create, nil, ""); err != nil {
		t.Fatalf("create failed: %v", err)
	}

	got, _, _, err := store.GetCredential(ctx, credentialID)
	if err != nil {
		t.Fatalf("get failed: %v", err)
	}
	if got.TenantID != tenantID || got.InstallID != installID {
		t.Fatalf("unexpected record %+v", got)
	}

	list, err := store.ListCredentials(ctx, tenantID, installID)
	if err != nil {
		t.Fatalf("list failed: %v", err)
	}
	if len(list) == 0 {
		t.Fatalf("expected list to contain credential")
	}

	verify, err := store.LookupVerification(ctx, credentialID)
	if err != nil {
		t.Fatalf("verification lookup failed: %v", err)
	}
	if verify.PublicKey == "" || verify.Status != credentials.StatusActive {
		t.Fatalf("unexpected verification response %+v", verify)
	}

	if err := store.WriteAudit(ctx, credentials.AuditEntry{
		ActorUserID:  "user_it",
		TenantID:     tenantID,
		InstallID:    installID,
		CredentialID: credentialID,
		Action:       "credential_registered",
	}); err != nil {
		t.Fatalf("audit insert failed: %v", err)
	}

	revokedAt, err := store.RevokeCredential(ctx, tenantID, credentialID)
	if err != nil {
		t.Fatalf("revoke failed: %v", err)
	}
	if revokedAt == nil {
		t.Fatalf("expected revoked_at")
	}
}

func TestPostgresIntegrationRotateCredential(t *testing.T) {
	databaseURL := integrationDatabaseURL(t)
	ctx := context.Background()

	store, err := NewPostgresStore(ctx, databaseURL)
	if err != nil {
		t.Fatalf("new store failed: %v", err)
	}
	defer store.Close()

	_, file, _, _ := runtime.Caller(0)
	schemaPath := filepath.Join(filepath.Dir(file), "schema.sql")
	if err := store.ApplySchemaFromFile(ctx, schemaPath); err != nil {
		t.Fatalf("apply schema failed: %v", err)
	}

	tenantID := "tenant_rotate_" + time.Now().UTC().Format("150405")
	installID := "install_rotate_1"
	oldID := "cred_old_rotate_it"
	newID := "cred_new_rotate_it"
	pubKey := "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

	old := credentials.CredentialRecord{
		CredentialID:   oldID,
		TenantID:       tenantID,
		InstallID:      installID,
		ActorUserID:    "user_it",
		AppBundleID:    "com.example.App",
		AppVersion:     "1.0.0",
		AppBuild:       "1000",
		Platform:       "macOS",
		CredentialMode: credentials.ModeEd25519,
		PublicKey:      pubKey,
		Status:         credentials.StatusActive,
	}
	if err := store.CreateCredential(ctx, old, nil, ""); err != nil {
		t.Fatalf("create old failed: %v", err)
	}

	newRec := credentials.CredentialRecord{
		CredentialID:   newID,
		TenantID:       tenantID,
		InstallID:      installID,
		ActorUserID:    "user_it",
		AppBundleID:    "com.example.App",
		AppVersion:     "1.1.0",
		AppBuild:       "1100",
		Platform:       "macOS",
		CredentialMode: credentials.ModeEd25519,
		PublicKey:      pubKey,
		Status:         credentials.StatusActive,
	}
	if err := store.RotateCredential(ctx, oldID, tenantID, installID, newRec, nil, ""); err != nil {
		t.Fatalf("rotate failed: %v", err)
	}

	oldAfter, _, _, err := store.GetCredential(ctx, oldID)
	if err != nil {
		t.Fatalf("get old failed: %v", err)
	}
	if oldAfter.Status != credentials.StatusRotated {
		t.Fatalf("expected rotated old status, got %s", oldAfter.Status)
	}
	newAfter, _, _, err := store.GetCredential(ctx, newID)
	if err != nil {
		t.Fatalf("get new failed: %v", err)
	}
	if newAfter.Status != credentials.StatusActive {
		t.Fatalf("expected active new status, got %s", newAfter.Status)
	}
}

func integrationDatabaseURL(t *testing.T) string {
	t.Helper()
	for _, key := range []string{"VALVE_TEST_DATABASE_URL", "VALVE_DATABASE_URL"} {
		if value := strings.TrimSpace(os.Getenv(key)); value != "" {
			return value
		}
	}
	t.Skip("integration DB URL not set (set VALVE_TEST_DATABASE_URL or VALVE_DATABASE_URL)")
	return ""
}
