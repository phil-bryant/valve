# Authorizer Interface Requirements

## Scope

Applies to `internal/auth/authorizer.go`.

R001  Statement: Define credential authorization contract for provision operations.
Design: Design: Expose `CanProvisionIngestCredential` with context and identity parameters plus `(bool, error)` result.
Tests:
- Add/maintain targeted tests that validate r001 behavior.

R005  Statement: Define credential authorization contract for revoke operations.
Design: Design: Expose `CanRevokeIngestCredential` with context, actor, tenant, and credential identifiers plus `(bool, error)` result.
Tests:
- Add/maintain targeted tests that validate r005 behavior.

## Changelog

- 2026-05-10: Added requirements coverage for backend source traceability.
