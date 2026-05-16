# HTTP Server Requirements

## Scope

Applies to `internal/httpserver/server.go`.

R001  Statement: The server constructor must build an HTTP router with baseline middleware and structured request logging.
Design: `New` initializes a chi router with `RequestID`, `RealIP`, `Recoverer`, and a structured `requestLogMiddleware` that logs method, path, and duration in milliseconds. The returned `*http.Server` uses 15-second read/write timeouts and a 60-second idle timeout.
Tests:
- R001-T01: Verify that a request to any route produces a structured log entry containing `method`, `path`, and `duration_ms`.
- R001-T02: Verify that a panicking handler is recovered and returns HTTP 500 rather than crashing the server.

R005  Statement: Health and readiness endpoints must return JSON bodies with explicit `application/json` content type.
Design: `GET /healthz` returns HTTP 200 with `Content-Type: application/json` and body `{"ok":true}`. `GET /readyz` calls `checker.Ping` under a 2-second timeout; on success it returns HTTP 200 with `{"ok":true}`; on failure it returns HTTP 503 with `{"ok":false,"reason":"dependency_unavailable"}`. Both responses use `Content-Type: application/json`.
Tests:
- R005-T01: Verify that `GET /healthz` returns HTTP 200 with `Content-Type: application/json` and a body containing `"ok":true`.
- R005-T02: Verify that `GET /readyz` returns HTTP 200 when `Ping` succeeds.
- R005-T03: Verify that `GET /readyz` returns HTTP 503 with `Content-Type: application/json` and `"ok":false` when `Ping` returns an error.

R010  Statement: Credential routes must be registered under `/v1/valve/credentials` and the verification endpoint must be protected by service auth middleware.
Design: `POST /register`, `POST /revoke`, `POST /rotate`, and `GET /` are registered without auth. `GET /{credential_id}/verification` is wrapped with `ServiceAuthMiddleware`. `POST /v1/piston/upload-target` is also wrapped with `ServiceAuthMiddleware`.
Tests:
- R010-T01: Verify that `POST /v1/valve/credentials/register` is reachable without a service key.
- R010-T02: Verify that `GET /v1/valve/credentials/{id}/verification` returns HTTP 401 when the service key header is absent.
- R010-T03: Verify that `POST /v1/piston/upload-target` returns HTTP 401 when the service key header is absent.
- R010-T04: Verify that `GET /v1/valve/credentials/{id}/verification` reaches the handler when the correct service key is provided.

R015  Statement: Baseline security response headers must be applied to every route before the downstream handler executes.
Design: `secureResponseHeadersMiddleware` sets `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, and `Referrer-Policy: no-referrer` on every response. The middleware is inserted into the chi chain before route handlers so handler-supplied values for the same header names take precedence on explicit overwrite.
Tests:
- R015-T01: Verify that `GET /healthz` response includes `X-Content-Type-Options: nosniff`.
- R015-T02: Verify that `GET /readyz` response includes `X-Frame-Options: DENY`.
- R015-T03: Verify that `POST /v1/piston/upload-target` response includes `Referrer-Policy: no-referrer`.

## Changelog

- 2026-05-16: Numbered test bullets with R###-T## scheme.
- 2026-05-16: Rewrote with concrete HTTP contract and security header acceptance criteria.
- 2026-05-15: Added baseline security response headers (R015).
- 2026-05-15: Tightened `/healthz` and `/readyz` to return JSON bodies with explicit `application/json` content type.
- 2026-05-10: Added requirements coverage for backend source traceability.
