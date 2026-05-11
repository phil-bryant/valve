package auth

import (
	"context"
	"testing"
)

func TestDevAuthorizerPeerMethodsMirrorAllowAll(t *testing.T) {
	// #R001: Dev authorizer exposes explicit allow-all state.
	// #R005: Provision method returns AllowAll decision without additional logic.
	// #R010: Revoke method returns AllowAll decision without additional logic.
	a := DevAuthorizer{AllowAll: true}
	allowProvision, err := a.CanProvisionIngestCredential(context.Background(), "actor", "tenant")
	if err != nil || !allowProvision {
		t.Fatalf("expected allow=true and nil error for provision path")
	}
	allowRevoke, err := a.CanRevokeIngestCredential(context.Background(), "actor", "tenant", "cred")
	if err != nil || !allowRevoke {
		t.Fatalf("expected allow=true and nil error for revoke path")
	}
}
