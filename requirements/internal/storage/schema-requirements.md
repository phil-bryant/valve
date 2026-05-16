# Storage Schema Requirements

## Scope

Applies to `internal/storage/schema.sql`.

R001  Statement: Define credential storage table with lifecycle metadata and integrity constraints.
Design: Schema creates `valve_credentials` with required identity columns, credential mode/status checks, timestamps, and uniqueness constraints.
Tests:
- R001-T01: Verify `valve_credentials` table exists with `credential_id`, `tenant_id`, `install_id`, `credential_mode`, and `status` columns.
- R001-T02: Verify that inserting a row with an invalid `status` value is rejected by the check constraint.

R005  Statement: Define query-supporting indexes for credential lookup and filtering.
Design: Schema creates indexes on `(tenant_id, install_id)`, `status`, and `(tenant_id, status)`.
Tests:
- R005-T01: Verify that the `(tenant_id, install_id)` index exists on `valve_credentials`.

R010  Statement: Define audit log table for credential operations.
Design: Schema creates `valve_audit_log` with `actor_user_id`, `tenant_id`, `install_id`, `credential_id`, `action`, `reason`, and `metadata` (JSONB) columns.
Tests:
- R010-T01: Verify `valve_audit_log` table exists with `action` and `metadata` columns.
- R010-T02: Verify that inserting an audit row with a valid JSON metadata value succeeds.

## Changelog

- 2026-05-16: Numbered test bullets with R###-T## scheme; improved test specificity.
- 2026-05-10: Added requirements coverage for backend source traceability.
