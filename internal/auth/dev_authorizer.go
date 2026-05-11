package auth

import "context"

// #R001: Dev authorizer carries environment-level allow-all decision flag.
type DevAuthorizer struct {
	AllowAll bool
}

// #R005: Provision decisions mirror AllowAll for local development mode.
func (a DevAuthorizer) CanProvisionIngestCredential(_ context.Context, _ string, _ string) (bool, error) {
	return a.AllowAll, nil
}

// #R010: Revoke decisions mirror AllowAll for local development mode.
func (a DevAuthorizer) CanRevokeIngestCredential(_ context.Context, _ string, _ string, _ string) (bool, error) {
	return a.AllowAll, nil
}
