package auth

import "context"

// #R001: Provision authorization contract for ingest credentials.
// #R005: Revoke authorization contract for ingest credentials.
type Authorizer interface {
	CanProvisionIngestCredential(ctx context.Context, actorUserID string, tenantID string) (bool, error)
	CanRevokeIngestCredential(ctx context.Context, actorUserID string, tenantID string, credentialID string) (bool, error)
}
