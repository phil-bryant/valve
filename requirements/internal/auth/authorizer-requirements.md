# Authorizer Interface Requirements

## Scope

Applies to `internal/auth/authorizer.go`.

R001  Statement: The authorizer interface must define a provision authorization method with context, actor, and tenant parameters.
Design: `Authorizer` exposes `CanProvisionIngestCredential(ctx context.Context, actorUserID string, tenantID string) (bool, error)`. Implementations return `(true, nil)` to allow, `(false, nil)` to deny, or `(false, err)` when the authorization check itself fails.
Tests:
- R001-T01: Verify that `DevAuthorizer{AllowAll: true}` satisfies the `Authorizer` interface.
- R001-T02: Verify that `DevAuthorizer{AllowAll: false}.CanProvisionIngestCredential` returns `(false, nil)`.

R005  Statement: The authorizer interface must define a revoke authorization method with context, actor, tenant, and credential parameters.
Design: `Authorizer` exposes `CanRevokeIngestCredential(ctx context.Context, actorUserID string, tenantID string, credentialID string) (bool, error)`. The credential ID parameter allows implementations to enforce per-credential ownership checks.
Tests:
- R005-T01: Verify that `DevAuthorizer{AllowAll: true}.CanRevokeIngestCredential` returns `(true, nil)`.
- R005-T02: Verify that `DevAuthorizer{AllowAll: false}.CanRevokeIngestCredential` returns `(false, nil)`.

## Changelog

- 2026-05-16: Numbered test bullets with R###-T## scheme.
- 2026-05-16: Rewrote with concrete interface contract and behavioral acceptance criteria.
- 2026-05-10: Added requirements coverage for backend source traceability.
