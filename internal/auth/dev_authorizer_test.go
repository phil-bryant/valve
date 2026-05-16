package auth

import (
	"context"
	"testing"
)

func TestDevAuthorizerPeerMethodsMirrorAllowAll(t *testing.T) {
	// #R001-T01: DevAuthorizer{AllowAll: true} returns true from both authorization methods.
	// #R001-T02: DevAuthorizer{AllowAll: false} returns false from both authorization methods.
	// #R005-T01: CanProvisionIngestCredential with AllowAll=true returns (true, nil).
	// #R005-T02: CanProvisionIngestCredential with AllowAll=false returns (false, nil).
	// #R010-T01: CanRevokeIngestCredential with AllowAll=true returns (true, nil).
	// #R010-T02: CanRevokeIngestCredential with AllowAll=false returns (false, nil).
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
