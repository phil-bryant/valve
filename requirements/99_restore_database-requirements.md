# Restore Database Requirements

## Scope

Applies to `99_restore_database.sh`.

R001  Statement: Run in strict shell mode with private-default file permissions.
Design: Use `umask 007` and `set -euo pipefail`.
Tests:
- R001-T01: Verify script exits on failing command and unset variable paths.

R005  Statement: Accept optional backup source path and support latest-backup defaulting.
Design: Parse `--from`; otherwise select newest `.dump` in local backups directory.
Tests:
- R005-T01: Run without args and verify newest dump is selected.
- R005-T02: Run with `--from` and verify provided path is selected.

R010  Statement: Require restore dependencies before restore operations.
Design: Validate `1psa`, `pg_restore`, and `psql` are available on PATH.
Tests:
- R010-T01: Remove `pg_restore` from PATH and verify clear failure.

R015  Statement: Resolve postgres password and target host/port from 1psa.
Design: Read postgres password via `1psa -p` default or `1psa -f` override field, then read `localhost_postgres_valve` `host`/`port` and validate non-empty/valid values.
Tests:
- R015-T01: Force empty password response and verify non-zero exit.

R020  Statement: Require dump and matching globals files before restore.
Design: Validate selected `.dump` path and require sibling `_globals.sql` file before running restore.
Tests:
- R020-T01: Run restore with missing globals file and verify restore is refused.

R025  Statement: Refuse restore when target database already contains ingest schema objects.
Design: Query target database and abort when table `public.ingest_batches` already exists.
Tests:
- R025-T01: Restore into existing initialized db and verify refusal message.

R030  Statement: Restore globals before database content.
Design: Run globals SQL with `psql`, then run `pg_restore --clean --if-exists --create` against postgres.
Tests:
- R030-T01: Verify restore order is globals first, then database content.

R035  Statement: Print completion output with selected backup path.
Design: Emit final restore-complete message with selected dump file path after successful replay.
Tests:
- R035-T01: Verify successful run prints completion line with backup path.

R040  Statement: Globals restore must be idempotent when role definitions already exist.
Design: Replay globals through a duplicate-safe transform that preserves hard failures but tolerates `CREATE ROLE` duplicate-object cases.
Tests:
- R040-T01: Run restore with globals replay against an environment that already has target roles and verify script continues to database restore.

R045  Statement: Globals restore must be scoped to Valve role principals.
Design: During globals replay, include only Valve-specific role statements (default allow-list: `valve`, `app_owner`, `app_user`, `app_readonly`) and ignore unrelated cluster principals/memberships.
Tests:
- R045-T01: Run restore with mixed globals content and verify unrelated roles (for example `manifold`, `teller`, personal roles) are not replayed.

## Changelog

- 2026-05-16: Numbered test bullets with R###-T## scheme.
- 2026-05-10: Reswizzled restore requirements from teller-specific scoped restore/credential sync logic to valve full-restore flow.
- 2026-05-10: Added idempotent globals replay requirement for duplicate role creation handling.
- 2026-05-10: Added Valve-scoped globals replay requirement to avoid cross-service role restoration.
- 2026-04-19: Initial reverse-engineered requirements for `99_restore_database.sh`.
