package credentials

import (
	"encoding/base64"
	"testing"
)

// Supplemental numbered tags for register validation matrix parity.
// #R001-T05
// #R001-T06
// #R001-T07
// #R001-T09
// #R001-T11

func TestValidateRegisterScenarios(t *testing.T) {
	validKey := base64.StdEncoding.EncodeToString(make([]byte, 32))
	cases := []struct {
		name    string
		req     RegisterRequest
		wantErr bool
	}{
		{
			name: "valid_ed25519",
			req: RegisterRequest{
				TenantID: "tenant", ActorUserID: "actor", InstallID: "install",
				AppBundleID: "bundle", Platform: "macOS", CredentialMode: ModeEd25519,
				PublicKey: validKey,
			},
		},
		{
			name: "invalid_public_key",
			req: RegisterRequest{
				TenantID: "tenant", ActorUserID: "actor", InstallID: "install",
				AppBundleID: "bundle", Platform: "macOS", CredentialMode: ModeEd25519,
				PublicKey: "bad",
			},
			wantErr: true,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			err := ValidateRegister(tc.req, false, false)
			if tc.wantErr && err == nil {
				t.Fatalf("expected error")
			}
			if !tc.wantErr && err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
		})
	}
}

func TestValidateRevokeScenarios(t *testing.T) {
	cases := []struct {
		name    string
		req     RevokeRequest
		allow   bool
		wantErr bool
	}{
		{
			name:  "valid",
			req:   RevokeRequest{TenantID: "tenant", ActorUserID: "actor", CredentialID: "cred"},
			allow: false,
		},
		{
			name:    "missing_actor",
			req:     RevokeRequest{TenantID: "tenant", CredentialID: "cred"},
			allow:   false,
			wantErr: true,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			err := ValidateRevoke(tc.req, tc.allow)
			if tc.wantErr && err == nil {
				t.Fatalf("expected error")
			}
			if !tc.wantErr && err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
		})
	}
}

func TestValidateRotateScenarios(t *testing.T) {
	validKey := base64.StdEncoding.EncodeToString(make([]byte, 32))
	cases := []struct {
		name    string
		req     RotateRequest
		wantErr bool
	}{
		{
			name: "valid_ed25519",
			req: RotateRequest{
				TenantID: "tenant", ActorUserID: "actor", OldCredentialID: "cred",
				InstallID: "install", CredentialMode: ModeEd25519, NewPublicKey: validKey,
			},
		},
		{
			name: "invalid_new_key",
			req: RotateRequest{
				TenantID: "tenant", ActorUserID: "actor", OldCredentialID: "cred",
				InstallID: "install", CredentialMode: ModeEd25519, NewPublicKey: "bad",
			},
			wantErr: true,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			err := ValidateRotate(tc.req, false, false)
			if tc.wantErr && err == nil {
				t.Fatalf("expected error")
			}
			if !tc.wantErr && err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
		})
	}
}

func TestValidateListQueryScenarios(t *testing.T) {
	cases := []struct {
		name      string
		tenantID  string
		installID string
		wantErr   bool
	}{
		{name: "valid", tenantID: "tenant", installID: "install"},
		{name: "empty_tenant", tenantID: "", installID: "install", wantErr: true},
		{name: "invalid_utf8", tenantID: "\xff", installID: "install", wantErr: true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			err := ValidateListQuery(tc.tenantID, tc.installID)
			if tc.wantErr && err == nil {
				t.Fatalf("expected error")
			}
			if !tc.wantErr && err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
		})
	}
}

func TestValidateUploadTargetRequestScenarios(t *testing.T) {
	cases := []struct {
		name    string
		req     UploadTargetRequest
		wantErr bool
	}{
		{
			name: "valid",
			req: UploadTargetRequest{
				TenantID: "tenant", InstallID: "install", CredentialID: "cred_abc",
			},
		},
		{
			name: "missing_credential_id",
			req: UploadTargetRequest{
				TenantID: "tenant", InstallID: "install",
			},
			wantErr: true,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			err := ValidateUploadTargetRequest(tc.req)
			if tc.wantErr && err == nil {
				t.Fatalf("expected error")
			}
			if !tc.wantErr && err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
		})
	}
}
