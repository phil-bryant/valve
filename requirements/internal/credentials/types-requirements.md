# Credential Type Definitions Requirements

## Scope

Applies to `internal/credentials/types.go`.

R001  Statement: Define canonical credential mode and status constants.
Design: Design: Expose string constants for supported credential modes and lifecycle statuses.
Tests:
- Add/maintain targeted tests that validate r001 behavior.

R005  Statement: Define API request/response payload models for credential workflows.
Design: Design: Maintain register, revoke, rotate, list, and verification request/response structs with JSON tags.
Tests:
- Add/maintain targeted tests that validate r005 behavior.

R010  Statement: Define persisted credential and audit data models.
Design: Design: Keep `CredentialRecord` and `AuditEntry` structures with fields needed by storage and API layers.
Tests:
- Add/maintain targeted tests that validate r010 behavior.

## Changelog

- 2026-05-10: Added requirements coverage for backend source traceability.
