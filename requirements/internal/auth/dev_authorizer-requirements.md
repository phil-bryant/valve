# Dev Authorizer Requirements

## Scope

Applies to `internal/auth/dev_authorizer.go`.

R001  Statement: Dev authorizer must expose configurable allow-all behavior.
Design: Design: Keep `AllowAll` flag on `DevAuthorizer` to drive decision output.
Tests:
- Add/maintain targeted tests that validate r001 behavior.

R005  Statement: Provision decision must mirror `AllowAll` value.
Design: Design: `CanProvisionIngestCredential` returns `(AllowAll, nil)` regardless of request metadata.
Tests:
- Add/maintain targeted tests that validate r005 behavior.

R010  Statement: Revoke decision must mirror `AllowAll` value.
Design: Design: `CanRevokeIngestCredential` returns `(AllowAll, nil)` regardless of request metadata.
Tests:
- Add/maintain targeted tests that validate r010 behavior.

## Changelog

- 2026-05-10: Added requirements coverage for backend source traceability.
