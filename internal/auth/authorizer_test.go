package auth

import (
	"context"
	"testing"
)

func TestDevAuthorizerProvisionReflectsAllowAll(t *testing.T) {
	// #R001-T01: DevAuthorizer{AllowAll: true} satisfies Authorizer interface.
	// #R001-T02: DevAuthorizer{AllowAll: false}.CanProvisionIngestCredential returns (false, nil).
	// #R005-T01: DevAuthorizer{AllowAll: true}.CanRevokeIngestCredential returns (true, nil).
	// #R005-T02: DevAuthorizer{AllowAll: false}.CanRevokeIngestCredential returns (false, nil).
	// #R001: Provision authorization contract is exercised through allow/deny outcomes.
	// #R005: Revoke authorization contract semantics are covered in package tests.
	allow, err := DevAuthorizer{AllowAll: true}.CanProvisionIngestCredential(context.Background(), "actor", "tenant")
	if err != nil {
		t.Fatalf("expected nil error, got %v", err)
	}
	if !allow {
		t.Fatalf("expected allow=true when AllowAll=true")
	}
	deny, err := DevAuthorizer{AllowAll: false}.CanProvisionIngestCredential(context.Background(), "actor", "tenant")
	if err != nil {
		t.Fatalf("expected nil error, got %v", err)
	}
	if deny {
		t.Fatalf("expected allow=false when AllowAll=false")
	}
}

func TestDevAuthorizerRevokeReflectsAllowAll(t *testing.T) {
	allow, err := DevAuthorizer{AllowAll: true}.CanRevokeIngestCredential(context.Background(), "actor", "tenant", "cred_1")
	if err != nil {
		t.Fatalf("expected nil error, got %v", err)
	}
	if !allow {
		t.Fatalf("expected allow=true when AllowAll=true")
	}
	deny, err := DevAuthorizer{AllowAll: false}.CanRevokeIngestCredential(context.Background(), "actor", "tenant", "cred_1")
	if err != nil {
		t.Fatalf("expected nil error, got %v", err)
	}
	if deny {
		t.Fatalf("expected allow=false when AllowAll=false")
	}
}
