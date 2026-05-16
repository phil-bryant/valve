# Service Auth Requirements

## Scope

Applies to `internal/security/service_auth.go`.

R001  Statement: Validate service key headers with constant-time comparison semantics.
Design: Design: `IsServiceAuthorized` rejects empty values and compares expected/provided bytes with `subtle.ConstantTimeCompare`.
Tests:
- Add/maintain targeted tests that validate r001 behavior.

R005  Statement: Middleware must reject unauthorized requests before downstream handlers execute and emit a JSON-encoded error body matching the OpenAPI ErrorResponse contract.
Design: `ServiceAuthMiddleware` reads service key header and returns HTTP 401 with `Content-Type: application/json` and body `{"error":"unauthorized"}` when authorization fails, so DAST Schemathesis preflight does not flag the documented 401 response as having an undocumented content type.
Tests:
- Verify the middleware rejects missing/invalid keys with HTTP 401, `application/json` content type, and a JSON body containing a non-empty `error` field.
- Verify authorized requests reach the downstream handler.

## Changelog

- 2026-05-15: Required JSON-encoded 401 body from `ServiceAuthMiddleware` to match the OpenAPI ErrorResponse contract used by DAST Schemathesis preflight.
- 2026-05-10: Added requirements coverage for backend source traceability.
