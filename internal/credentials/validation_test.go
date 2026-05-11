package credentials

import (
	"encoding/base64"
	"testing"
)

func TestValidateRegisterScenarios(t *testing.T) {
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
	// #R005: Revoke validation requires tenant, actor policy, and credential id.
	if err := ValidateRevoke(RevokeRequest{TenantID: "tenant", ActorUserID: "actor", CredentialID: "cred"}, false); err != nil {
		t.Fatalf("expected valid revoke request, got %v", err)
	}
	if err := ValidateRevoke(RevokeRequest{TenantID: "tenant", CredentialID: "cred"}, false); err == nil {
		t.Fatalf("expected missing actor validation error")
	}
}

func TestValidateRotateScenarios(t *testing.T) {
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
