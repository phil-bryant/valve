# Credentials Handler Requirements

## Scope

Applies to `internal/credentials/handler.go`.

R001  Statement: HTTP handlers must decode request payloads and dispatch to service methods.
Design: Design: Register/Revoke/Rotate handlers decode JSON body, call service, and encode JSON response.
Tests:
- Add/maintain targeted tests that validate r001 behavior.

R005  Statement: Listing and verification endpoints must map URL/query inputs to service calls.
Design: Design: List reads `tenant_id`/`install_id`; verification reads chi URL param `credential_id`.
Tests:
- Add/maintain targeted tests that validate r005 behavior.

R010  Statement: Service errors must map to stable HTTP status responses.
Design: Design: `writeServiceError` maps domain errors to 400/403/404/409/500 response codes.
Tests:
- Add/maintain targeted tests that validate r010 behavior.

## Changelog

- 2026-05-10: Added requirements coverage for backend source traceability.
