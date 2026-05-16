# Destroy Database Requirements

## Scope

Applies to `98_destroy_database.sh`.

R001  Statement: Run with bash and fail fast on unrecoverable errors.
Design: Use `set -e` with non-zero exits on failed operations.
Tests:
- R001-T01: Force a failing SQL command and verify non-zero exit.

R005  Statement: Require `1psa` and resolve postgres password from configured source.
Design: Check `1psa` and `psql`, then read postgres password via default or override field plus valve host/port from `localhost_postgres_valve` fields.
Tests:
- R005-T01: Run without `1psa` and verify clear failure message.

R010  Statement: Require explicit destructive confirmation.
Design: Prompt user to type `destroy` before any database teardown.
Tests:
- R010-T01: Provide wrong confirmation and verify teardown does not run.

R015  Statement: Clean dependent resources before dropping prod database.
Design: If target database exists, terminate active sessions for that database before drop.
Tests:
- R015-T01: With live sessions, verify terminate query executes before database drop.

R020  Statement: Drop target database and teller roles idempotently.
Design: Execute `DROP DATABASE IF EXISTS valve` and `DROP ROLE IF EXISTS valve` (or overridden names) via postgres connection.
Tests:
- R020-T01: Run script twice and verify second run remains safe.

R025  Statement: Print completion status after teardown steps finish.
Design: Emit final cleanup completion line.
Tests:
- R025-T01: Verify successful run prints completion message.

## Changelog

- 2026-05-16: Numbered test bullets with R###-T## scheme.
- 2026-05-10: Reswizzled destroy script requirements from teller teardown to valve database/role teardown.
- 2026-04-19: Initial reverse-engineered requirements for `98_destroy_database.sh`.
