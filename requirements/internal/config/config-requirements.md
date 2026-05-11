# Configuration Loading Requirements

## Scope

Applies to `internal/config/config.go`.

R001  Statement: Load configuration from environment with deterministic defaults.
Design: Design: `Load` populates config fields with env values and fallback defaults for optional keys.
Tests:
- Add/maintain targeted tests that validate r001 behavior.

R005  Statement: Enforce required environment keys for database and upload endpoint.
Design: Design: `Load` returns explicit errors when `VALVE_DATABASE_URL` or `VALVE_UPLOAD_ENDPOINT` are missing.
Tests:
- Add/maintain targeted tests that validate r005 behavior.

R010  Statement: Parse boolean flags safely with fallback behavior.
Design: Design: `parseBoolOrDefault` reads env, returns fallback when unset or unparseable.
Tests:
- Add/maintain targeted tests that validate r010 behavior.

## Changelog

- 2026-05-10: Added requirements coverage for backend source traceability.
