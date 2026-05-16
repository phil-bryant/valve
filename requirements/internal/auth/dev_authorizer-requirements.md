# Dev Authorizer Requirements

## Scope

Applies to `internal/auth/dev_authorizer.go`.

R001  Statement: The dev authorizer must carry a configurable allow-all flag that drives all authorization decisions.
Design: `DevAuthorizer` is a struct with a single exported `AllowAll bool` field. All authorization methods return `(AllowAll, nil)` regardless of the request parameters.
Tests:
- R001-T01: Verify that `DevAuthorizer{AllowAll: true}` returns `true` from both authorization methods.
- R001-T02: Verify that `DevAuthorizer{AllowAll: false}` returns `false` from both authorization methods.

R005  Statement: Provision decisions must mirror the `AllowAll` value without inspecting actor or tenant parameters.
Design: `CanProvisionIngestCredential` ignores `actorUserID` and `tenantID` and returns `(a.AllowAll, nil)`.
Tests:
- R005-T01: Verify that `CanProvisionIngestCredential` with `AllowAll=true` returns `(true, nil)` for any actor and tenant values, including empty strings.
- R005-T02: Verify that `CanProvisionIngestCredential` with `AllowAll=false` returns `(false, nil)`.

R010  Statement: Revoke decisions must mirror the `AllowAll` value without inspecting actor, tenant, or credential parameters.
Design: `CanRevokeIngestCredential` ignores all parameters and returns `(a.AllowAll, nil)`.
Tests:
- R010-T01: Verify that `CanRevokeIngestCredential` with `AllowAll=true` returns `(true, nil)` for any parameter values, including empty strings.
- R010-T02: Verify that `CanRevokeIngestCredential` with `AllowAll=false` returns `(false, nil)`.

## Changelog

- 2026-05-16: Numbered test bullets with R###-T## scheme.
- 2026-05-16: Rewrote with concrete behavioral acceptance criteria.
- 2026-05-10: Added requirements coverage for backend source traceability.
