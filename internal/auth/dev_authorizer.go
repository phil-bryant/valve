package auth

import "context"

type DevAuthorizer struct {
	AllowAll bool
}

func (a DevAuthorizer) CanProvisionIngestCredential(_ context.Context, _ string, _ string) (bool, error) {
	return a.AllowAll, nil
}

func (a DevAuthorizer) CanRevokeIngestCredential(_ context.Context, _ string, _ string, _ string) (bool, error) {
	return a.AllowAll, nil
}
