# Credentials Handler Requirements

## Scope

Applies to `internal/credentials/handler.go`.

R001  Statement: Register, revoke, and rotate handlers must decode JSON request bodies and dispatch to the service layer, returning JSON-encoded responses.
Design: `RegisterCredential`, `RevokeCredential`, and `RotateCredential` each decode the request body into the appropriate request struct; a decode failure returns HTTP 400 with `{"error":"invalid request"}`. On success, the service response is JSON-encoded with HTTP 200. On service error, `writeServiceError` is called.
Tests:
- R001-T01: Verify that a malformed JSON body to the register endpoint returns HTTP 400 with an `error` field.
- R001-T02: Verify that a valid register request dispatches to the service and returns HTTP 200 with a JSON body containing `credential_id`.
- R001-T03: Verify that a malformed JSON body to the revoke endpoint returns HTTP 400.
- R001-T04: Verify that a malformed JSON body to the rotate endpoint returns HTTP 400.

R005  Statement: List and verification endpoints must extract inputs from URL query parameters and chi URL parameters respectively.
Design: `ListCredentials` reads `tenant_id` and `install_id` from `r.URL.Query()`; `VerificationLookup` reads `credential_id` from `chi.URLParam(r, "credential_id")`. Both dispatch to the service and return JSON-encoded responses.
Tests:
- R005-T01: Verify that `ListCredentials` passes `tenant_id` and `install_id` query params to the service.
- R005-T02: Verify that `VerificationLookup` passes the `credential_id` URL param to the service.
- R005-T03: Verify that a service `ErrNotFound` from `VerificationLookup` returns HTTP 404.

R010  Statement: Service errors must map to stable HTTP status codes with JSON error bodies.
Design: `writeServiceError` maps `ErrInvalidInput` → 400, `ErrUnauthorized` → 403, `ErrNotFound` → 404, `ErrTenantMismatch` → 409, `ErrInvalidState` → 409, and all other errors → 500. Every error response has `Content-Type: application/json` and a body with a non-empty `error` field.
Tests:
- R010-T01: Verify `ErrInvalidInput` produces HTTP 400 with a JSON `error` field.
- R010-T02: Verify `ErrUnauthorized` produces HTTP 403 with a JSON `error` field.
- R010-T03: Verify `ErrNotFound` produces HTTP 404 with a JSON `error` field.
- R010-T04: Verify `ErrTenantMismatch` produces HTTP 409 with a JSON `error` field.
- R010-T05: Verify `ErrInvalidState` produces HTTP 409 with a JSON `error` field.
- R010-T06: Verify an unknown error produces HTTP 500 with a JSON `error` field.

R015  Statement: Upload target handler must set a Cache-Control header derived from the response TTL.
Design: `UploadTarget` decodes the JSON request body, dispatches to the service, and on success sets `Cache-Control: private, max-age=<ttl_seconds>` before writing the JSON response. A decode failure returns HTTP 400.
Tests:
- R015-T01: Verify a valid upload target request returns HTTP 200 with a `Cache-Control` header containing `private, max-age=`.
- R015-T02: Verify a malformed JSON body returns HTTP 400.

## Changelog

- 2026-05-16: Numbered test bullets with R###-T## scheme.
- 2026-05-16: Rewrote with concrete acceptance criteria; added R015.
- 2026-05-10: Added requirements coverage for backend source traceability.
