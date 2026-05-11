# Storage Schema Requirements

## Scope

Applies to `internal/storage/schema.sql`.

R001  Statement: Define credential storage table with lifecycle metadata and integrity constraints.
Design: Design: Schema creates `valve_credentials` with required identity columns, credential mode/status checks, timestamps, and uniqueness constraints.
Tests:
- Add/maintain targeted tests that validate r001 behavior.

R005  Statement: Define query-supporting indexes for credential lookup and filtering.
Design: Design: Schema creates tenant/install, status, and tenant+status indexes.
Tests:
- Add/maintain targeted tests that validate r005 behavior.

R010  Statement: Define audit log table for credential operations.
Design: Design: Schema creates `valve_audit_log` with actor/tenant/install/credential fields, action metadata, and JSON payload column.
Tests:
- Add/maintain targeted tests that validate r010 behavior.

## Changelog

- 2026-05-10: Added requirements coverage for backend source traceability.
