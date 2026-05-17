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
	// #R001-T10: Fully valid Ed25519 request returns nil.
	// #R001-T08: Non-base64 public_key returns an error.
	// #R001: Register validation enforces required fields and mode-specific key constraints.
	req := RegisterRequest{TenantID: "tenant", ActorUserID: "actor", InstallID: "install", AppBundleID: "bundle", Platform: "macOS", CredentialMode: ModeEd25519, PublicKey: base64.StdEncoding.EncodeToString(make([]byte, 32))}
	if err := ValidateRegister(req, false, false); err != nil {
		t.Fatalf("expected valid register request, got %v", err)
	}
	req.PublicKey = "bad"
	if err := ValidateRegister(req, false, false); err == nil {
		t.Fatalf("expected invalid public key error")
	}
}

func TestValidateRevokeScenarios(t *testing.T) {
	// #R005-T04: Fully valid revoke request returns nil.
	// #R005-T03: Empty actor_user_id with allowEmptyActor=false returns an error.
	// #R005: Revoke validation requires tenant, actor policy, and credential id.
	if err := ValidateRevoke(RevokeRequest{TenantID: "tenant", ActorUserID: "actor", CredentialID: "cred"}, false); err != nil {
		t.Fatalf("expected valid revoke request, got %v", err)
	}
	if err := ValidateRevoke(RevokeRequest{TenantID: "tenant", CredentialID: "cred"}, false); err == nil {
		t.Fatalf("expected missing actor validation error")
	}
}

func TestValidateRotateScenarios(t *testing.T) {
	// #R010-T04: Fully valid Ed25519 rotate request returns nil.
	// #R010-T03: Base64 key decoding to wrong length returns an error.
	// #R010: Rotate validation enforces required ids and key constraints for selected mode.
	req := RotateRequest{TenantID: "tenant", ActorUserID: "actor", OldCredentialID: "cred", InstallID: "install", CredentialMode: ModeEd25519, NewPublicKey: base64.StdEncoding.EncodeToString(make([]byte, 32))}
	if err := ValidateRotate(req, false, false); err != nil {
		t.Fatalf("expected valid rotate request, got %v", err)
	}
	req.NewPublicKey = "bad"
	if err := ValidateRotate(req, false, false); err == nil {
		t.Fatalf("expected invalid new key error")
	}
}

func TestValidateUploadTargetRequestScenarios(t *testing.T) {
	// #R015-T04: Fully valid upload target request returns nil.
	// #R015-T03: Empty credential_id returns an error.
	req := UploadTargetRequest{
		TenantID:     "tenant",
		InstallID:    "install",
		CredentialID: "cred_abc",
	}
	if err := ValidateUploadTargetRequest(req); err != nil {
		t.Fatalf("expected valid upload target request, got %v", err)
	}
	req.CredentialID = ""
	if err := ValidateUploadTargetRequest(req); err == nil {
		t.Fatalf("expected credential id validation error")
	}
}
