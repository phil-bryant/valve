package credentials

import "testing"

func FuzzValidateRegister(f *testing.F) {
	f.Add("tenant", "actor", "install", "com.example.app", "macOS", "ed25519", "AAAA")
	f.Fuzz(func(t *testing.T, tenantID, actorUserID, installID, bundleID, platform, mode, publicKey string) {
		req := RegisterRequest{
			TenantID:       tenantID,
			ActorUserID:    actorUserID,
			InstallID:      installID,
			AppBundleID:    bundleID,
			Platform:       platform,
			CredentialMode: mode,
			PublicKey:      publicKey,
		}
		_ = ValidateRegister(req, false, true)
	})
}

func FuzzValidateRevoke(f *testing.F) {
	f.Add("tenant", "actor", "cred")
	f.Fuzz(func(t *testing.T, tenantID, actorUserID, credentialID string) {
		req := RevokeRequest{
			TenantID:     tenantID,
			ActorUserID:  actorUserID,
			CredentialID: credentialID,
		}
		_ = ValidateRevoke(req, false)
	})
}

func FuzzValidateRotate(f *testing.F) {
	f.Add("tenant", "actor", "old", "install", "ed25519", "AAAA")
	f.Fuzz(func(t *testing.T, tenantID, actorUserID, oldCredentialID, installID, mode, publicKey string) {
		req := RotateRequest{
			TenantID:        tenantID,
			ActorUserID:     actorUserID,
			OldCredentialID: oldCredentialID,
			InstallID:       installID,
			CredentialMode:  mode,
			NewPublicKey:    publicKey,
		}
		_ = ValidateRotate(req, false, true)
	})
}
