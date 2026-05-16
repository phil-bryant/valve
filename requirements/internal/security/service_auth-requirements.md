# Service Auth Requirements

## Scope

Applies to `internal/security/service_auth.go`.

R001  Statement: Service key validation must reject empty values and use constant-time comparison to prevent timing attacks.
Design: `IsServiceAuthorized(expected, provided)` returns `false` immediately when either argument is empty, then compares `[]byte(expected)` and `[]byte(provided)` using `subtle.ConstantTimeCompare`, returning `true` only when the result is `1`.
Tests:
- R001-T01: Verify that an empty `expected` returns `false`.
- R001-T02: Verify that an empty `provided` returns `false`.
- R001-T03: Verify that matching non-empty values return `true`.
- R001-T04: Verify that non-matching values return `false`.

R005  Statement: The service auth middleware must reject unauthorized requests before downstream handlers execute and return a JSON-encoded error body matching the OpenAPI ErrorResponse contract.
Design: `ServiceAuthMiddleware` reads the `X-Valve-Service-Key` header and calls `IsServiceAuthorized`. On failure it sets `Content-Type: application/json`, writes HTTP 401, and writes `{"error":"unauthorized"}\n`. On success it calls `next.ServeHTTP`.
Tests:
- R005-T01: Verify that a missing `X-Valve-Service-Key` header returns HTTP 401 with `Content-Type: application/json` and a body containing `"error"`.
- R005-T02: Verify that an incorrect key returns HTTP 401 with `Content-Type: application/json` and a body containing `"error"`.
- R005-T03: Verify that a correct key allows the request to reach the downstream handler.
- R005-T04: Verify that the 401 response body is valid JSON with a non-empty `error` field.

## Changelog

- 2026-05-16: Numbered test bullets with R###-T## scheme.
- 2026-05-16: Rewrote with concrete timing-safety and HTTP contract acceptance criteria.
- 2026-05-15: Required JSON-encoded 401 body from `ServiceAuthMiddleware` to match the OpenAPI ErrorResponse contract.
- 2026-05-10: Added requirements coverage for backend source traceability.
