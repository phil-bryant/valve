# Verify Deploy Database Requirements

## Scope

Applies to `04_verify_deploy_database.sh`.

R001  Statement: Run in strict shell mode and fail fast.
Design: Use POSIX `sh` shebang and `set -eu`.
Tests:
- R001-T01: Cause a command failure and verify script exits non-zero.

R005  Statement: Resolve verification credentials exclusively from `1psa`.
Design: Read valve password from `localhost_postgres_valve` `password` plus connection target from `localhost_postgres_valve` `host`/`port`/`database`/`schema`, then verify schema as user `valve`.
Tests:
- R005-T01: Run with `1psa` unavailable and verify explicit non-zero failure output.
- R005-T02: Return empty valve credential from `1psa` and verify explicit non-zero failure output.
- R005-T03: Return empty/invalid valve host or port from `1psa` and verify explicit non-zero failure output.
- R005-T04: Return empty valve database name from `1psa` and verify explicit non-zero failure output.
- R005-T05: Return empty/invalid valve schema name from `1psa` and verify explicit non-zero failure output.

R010  Statement: Refuse verification when `psql` is unavailable.
Design: Verify `psql` exists on PATH before running database checks.
Tests:
- R010-T01: Run with `psql` missing and verify explicit non-zero failure output.

R015  Statement: Verify required valve credential tables exist.
Design: Assert `valve_credentials` and `valve_audit_log` exist in schema `<1psa schema>` and report missing names.
Tests:
- R015-T01: Return a missing table from fixture `psql` output and verify failure details list the table.

R020  Statement: Verify required valve credential indexes exist.
Design: Assert `idx_valve_credentials_tenant_install`, `idx_valve_credentials_status`, and `idx_valve_credentials_tenant_status` exist.
Tests:
- R020-T01: Return a missing index from fixture `psql` output and verify failure details list the index.

R025  Statement: Verify valve credential uniqueness contract exists.
Design: Assert unique constraint `valve_credentials(tenant_id, install_id, credential_id)` exists.
Tests:
- R025-T01: Return a missing uniqueness check result and verify explicit uniqueness diagnostic failure.

R030  Statement: Print explicit pass/fail verification result.
Design: Print one `✅ PASS:` line only when all checks pass; otherwise print `❌ FAIL:` header, list each failed check, and exit non-zero.
Tests:
- R030-T01: Verify all-pass run emits a single `✅ PASS:` line.
- R030-T02: Verify any failed check emits `❌ FAIL:` details and exits non-zero.

R035  Statement: Execute verification queries with fail-fast psql options.
Design: Run verification SQL via `psql -w -h <1psa host> -p <1psa port> -d <1psa database> -v ON_ERROR_STOP=1 -At` using credentials from `R005`.
Tests:
- R035-T01: Verify query invocations include `ON_ERROR_STOP=1` and host/port/database/schema resolved from `1psa`.

## Changelog

- 2026-05-16: Numbered test bullets with R###-T## scheme.
- 2026-05-11: Updated verification to resolve schema name from `1psa` and validate checks against that schema explicitly.
- 2026-05-11: Updated verification to resolve database name from `1psa` and use `current_schema()` instead of hard-coded `public`.
- 2026-05-10: Updated verification targets to credential schema objects (`valve_credentials`, `valve_audit_log`) and uniqueness contract.
- 2026-05-10: Updated verify target host/port to be sourced from `localhost_postgres_valve` `host`/`port` fields via `1psa`.
- 2026-05-09: Replaced teller-oriented verify requirements with valve storage-object verification requirements.
