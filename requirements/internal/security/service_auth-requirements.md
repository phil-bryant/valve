# Service Auth Requirements

## Scope

Applies to `internal/security/service_auth.go`.

R001  Statement: Validate service key headers with constant-time comparison semantics.
Design: Design: `IsServiceAuthorized` rejects empty values and compares expected/provided bytes with `subtle.ConstantTimeCompare`.
Tests:
- Add/maintain targeted tests that validate r001 behavior.

R005  Statement: Middleware must reject unauthorized requests before downstream handlers execute.
Design: Design: `ServiceAuthMiddleware` reads service key header and returns HTTP 401 when authorization fails.
Tests:
- Add/maintain targeted tests that validate r005 behavior.

## Changelog

- 2026-05-10: Added requirements coverage for backend source traceability.
