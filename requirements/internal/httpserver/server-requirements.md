# HTTP Server Requirements

## Scope

Applies to `internal/httpserver/server.go`.

R001  Statement: Build HTTP router with baseline middleware and request logging.
Design: Design: Initialize chi router with request id, real ip, panic recoverer, and request log middleware.
Tests:
- Add/maintain targeted tests that validate r001 behavior.

R005  Statement: Expose health and readiness endpoints for service probing.
Design: Design: `/healthz` returns ok; `/readyz` checks dependency ping under timeout and returns ready/not ready status.
Tests:
- Add/maintain targeted tests that validate r005 behavior.

R010  Statement: Expose credential routes and protect verification endpoint with service auth middleware.
Design: Design: Register credential handlers under `/v1/valve/credentials` and gate verification route with service key middleware.
Tests:
- Add/maintain targeted tests that validate r010 behavior.

## Changelog

- 2026-05-10: Added requirements coverage for backend source traceability.
