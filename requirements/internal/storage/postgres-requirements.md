# Postgres Store Requirements

## Scope

Applies to `internal/storage/postgres.go`.

R001  Statement: Create and manage postgres connection pool lifecycle.
Design: Design: `NewPostgresStore` creates `pgxpool` instance and exposes close/ping operations.
Tests:
- Add/maintain targeted tests that validate r001 behavior.

R005  Statement: Persist and retrieve credential lifecycle records.
Design: Design: Store supports create/get/list/revoke/rotate operations mapped to `valve_credentials` table fields.
Tests:
- Add/maintain targeted tests that validate r005 behavior.

R010  Statement: Persist audit log entries and verification lookups with normalized null handling.
Design: Design: Store writes audit entries, resolves verification payload, maps no-rows to domain not-found, and normalizes nullable values through helpers.
Tests:
- Add/maintain targeted tests that validate r010 behavior.

R015  Statement: Support schema bootstrapping from SQL file content.
Design: Design: `ApplySchemaFromFile` loads SQL from disk and executes it through pooled connection.
Tests:
- Add/maintain targeted tests that validate r015 behavior.

R020  Statement: Restrict schema bootstrapping file reads to the approved repository schema path.
Design: `ApplySchemaFromFile` validates caller input and only reads from `internal/storage/schema.sql`, rejecting other paths.
Tests:
- Add/maintain targeted tests that validate r020 behavior.

## Changelog

- 2026-05-10: Added requirements coverage for backend source traceability.
- 2026-05-10: Added schema-path restriction requirement for secure bootstrap file reads.
