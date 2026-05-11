# Credential Validation Requirements

## Scope

Applies to `internal/credentials/validation.go`.

R001  Statement: Register validation must enforce required fields and supported modes.
Design: Design: Validate tenant, actor policy, install, app metadata, platform, mode, and mode-specific key requirements.
Tests:
- Add/maintain targeted tests that validate r001 behavior.

R005  Statement: Revoke validation must enforce required identifiers and actor policy.
Design: Design: Validate tenant, actor policy, and credential id before revoke operations.
Tests:
- Add/maintain targeted tests that validate r005 behavior.

R010  Statement: Rotate validation must enforce replacement invariants and mode-specific key constraints.
Design: Design: Validate tenant, actor policy, old credential id, install id, credential mode, and new key constraints.
Tests:
- Add/maintain targeted tests that validate r010 behavior.

## Changelog

- 2026-05-10: Added requirements coverage for backend source traceability.
