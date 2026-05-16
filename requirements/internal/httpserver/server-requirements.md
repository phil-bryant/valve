# HTTP Server Requirements

## Scope

Applies to `internal/httpserver/server.go`.

R001  Statement: Build HTTP router with baseline middleware and request logging.
Design: Design: Initialize chi router with request id, real ip, panic recoverer, and request log middleware.
Tests:
- Add/maintain targeted tests that validate r001 behavior.

R005  Statement: Expose health and readiness endpoints for service probing with JSON-encoded bodies matching the OpenAPI contract.
Design: `/healthz` returns HTTP 200 with `Content-Type: application/json` and body `{"ok":true}`; `/readyz` checks dependency ping under timeout and returns `{"ok":true}` on success or HTTP 503 with `{"ok":false,"reason":"dependency_unavailable"}` on failure, both with `Content-Type: application/json` so DAST Schemathesis preflight does not flag the response as having an undocumented content type.
Tests:
- Verify `/healthz` returns 200 with `application/json` and JSON body containing `ok: true`.
- Verify `/readyz` returns 503 with `application/json` when the dependency ping fails.

R010  Statement: Expose credential routes and protect verification endpoint with service auth middleware.
Design: Design: Register credential handlers under `/v1/valve/credentials` and gate verification route with service key middleware.
Tests:
- Add/maintain targeted tests that validate r010 behavior.

R015  Statement: Apply baseline security response headers on every route.
Design: Insert a `secureResponseHeadersMiddleware` into the chi middleware chain ahead of route handlers that sets `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, and `Referrer-Policy: no-referrer` on every response, so DAST scanners and real clients do not have to rely on browser MIME-sniffing or framing defaults.
Tests:
- Verify `/healthz`, `/readyz`, and `/v1/piston/upload-target` responses all carry the three baseline security headers.

## Changelog

- 2026-05-15: Added baseline security response headers (R015) on every route to close the DAST `X-Content-Type-Options` low-severity finding and harden against MIME-sniffing/framing fallback.
- 2026-05-15: Tightened `/healthz` and `/readyz` to return JSON bodies with explicit `application/json` content type so DAST Schemathesis preflight matches the OpenAPI contract.
- 2026-05-10: Added requirements coverage for backend source traceability.
