package auth

import "context"

type Authorizer interface {
	CanProvisionIngestCredential(ctx context.Context, actorUserID string, tenantID string) (bool, error)
	CanRevokeIngestCredential(ctx context.Context, actorUserID string, tenantID string, credentialID string) (bool, error)
}
