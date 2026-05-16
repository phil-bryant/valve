package credentials

import (
	"crypto/ed25519"
	"encoding/base64"
	"errors"
	"fmt"
)

// #R001: Validate register payloads, mode constraints, and key requirements.
func ValidateRegister(req RegisterRequest, allowEmptyActor bool, hmacEnabled bool) error {
	if req.TenantID == "" {
		return errors.New("tenant_id is required")
	}
	if req.ActorUserID == "" && !allowEmptyActor {
		return errors.New("actor_user_id is required")
	}
	if req.InstallID == "" {
		return errors.New("install_id is required")
	}
	if req.AppBundleID == "" {
		return errors.New("app_bundle_id is required")
	}
	if req.Platform != "macOS" {
		return errors.New("platform must be macOS")
	}
	if req.CredentialMode != ModeEd25519 && req.CredentialMode != ModeHMACSHA256 {
		return errors.New("credential_mode must be ed25519 or hmac_sha256")
	}
	if req.CredentialMode == ModeHMACSHA256 && !hmacEnabled {
		return errors.New("hmac mode is disabled")
	}
	if req.CredentialMode == ModeEd25519 {
		if req.PublicKey == "" {
			return errors.New("public_key is required for ed25519 mode")
		}
		decoded, err := base64.StdEncoding.DecodeString(req.PublicKey)
		if err != nil {
			return fmt.Errorf("public_key must be base64 encoded: %w", err)
		}
		if len(decoded) != ed25519.PublicKeySize {
			return errors.New("public_key has invalid ed25519 key length")
		}
	}
	return nil
}

// #R005: Validate revoke payload identifiers and actor policy constraints.
func ValidateRevoke(req RevokeRequest, allowEmptyActor bool) error {
	if req.TenantID == "" {
		return errors.New("tenant_id is required")
	}
	if req.ActorUserID == "" && !allowEmptyActor {
		return errors.New("actor_user_id is required")
	}
	if req.CredentialID == "" {
		return errors.New("credential_id is required")
	}
	return nil
}

// #R010: Validate rotation payloads including mode-specific replacement key checks.
func ValidateRotate(req RotateRequest, allowEmptyActor bool, hmacEnabled bool) error {
	if req.TenantID == "" {
		return errors.New("tenant_id is required")
	}
	if req.ActorUserID == "" && !allowEmptyActor {
		return errors.New("actor_user_id is required")
	}
	if req.OldCredentialID == "" {
		return errors.New("old_credential_id is required")
	}
	if req.InstallID == "" {
		return errors.New("install_id is required")
	}
	if req.CredentialMode != ModeEd25519 && req.CredentialMode != ModeHMACSHA256 {
		return errors.New("credential_mode must be ed25519 or hmac_sha256")
	}
	if req.CredentialMode == ModeHMACSHA256 && !hmacEnabled {
		return errors.New("hmac mode is disabled")
	}
	if req.CredentialMode == ModeEd25519 {
		if req.NewPublicKey == "" {
			return errors.New("new_public_key is required for ed25519 mode")
		}
		decoded, err := base64.StdEncoding.DecodeString(req.NewPublicKey)
		if err != nil {
			return fmt.Errorf("new_public_key must be base64 encoded: %w", err)
		}
		if len(decoded) != ed25519.PublicKeySize {
			return errors.New("new_public_key has invalid ed25519 key length")
		}
	}
	return nil
}

// #R015: Validate upload target request identifiers before service dispatch.
func ValidateUploadTargetRequest(req UploadTargetRequest) error {
	if req.TenantID == "" {
		return errors.New("tenant_id is required")
	}
	if req.InstallID == "" {
		return errors.New("install_id is required")
	}
	if req.CredentialID == "" {
		return errors.New("credential_id is required")
	}
	return nil
}
