# Postgres Store Requirements

## Scope

Applies to `internal/storage/postgres.go`.

R001  Statement: The store must create a pgxpool connection pool and expose close and ping lifecycle operations.
Design: `NewPostgresStore` calls `pgxpool.New` and returns a `*PostgresStore` wrapping the pool. `Close` calls `pool.Close`. `Ping` calls `pool.Ping` and returns any error.
Tests:
- R001-T01: Verify that `NewPostgresStore` returns a non-nil store when given a valid database URL (integration).
- R001-T02: Verify that `Ping` returns nil when the database is reachable (integration).
- R001-T03: Verify that `Ping` returns an error when the database is unreachable (integration).

R005  Statement: The store must persist and retrieve credential lifecycle records through create, get, list, revoke, and rotate operations.
Design: `CreateCredential` inserts a full `CredentialRecord` row with nullable optional fields. `GetCredential` returns the record, encrypted HMAC secret bytes, and HMAC hash for a given credential ID. `ListCredentials` returns all records for a tenant/install pair ordered by `created_at DESC`. `RevokeCredential` updates `status = 'revoked'` and `revoked_at = now()` only when the current status is `active`, returning `ErrNotFound` when no row is updated. `RotateCredential` runs a transaction that marks the old credential `status = 'rotated'` and inserts the replacement record atomically, returning `ErrNotFound` when the old credential is not active.
Tests:
- R005-T01: Verify that `CreateCredential` followed by `GetCredential` returns the same record (integration).
- R005-T02: Verify that `ListCredentials` returns records in descending creation order (integration).
- R005-T03: Verify that `RevokeCredential` on an active credential returns a non-nil `revoked_at` (integration).
- R005-T04: Verify that `RevokeCredential` on a non-active credential returns `ErrNotFound` (integration).
- R005-T05: Verify that `RotateCredential` marks the old credential `rotated` and inserts the new one in a single transaction (integration).

R010  Statement: The store must persist audit log entries and resolve verification payloads, mapping missing rows to a domain error and normalizing nullable fields.
Design: `WriteAudit` inserts into `valve_audit_log`; an empty `MetadataJSON` is stored as `{}`. `LookupVerification` queries `valve_credentials` for the verification projection; `pgx.ErrNoRows` is mapped to `ErrNotFound`. Nullable `public_key_base64` and `revoked_at` columns are normalized to empty string and nil pointer respectively when NULL.
Tests:
- R010-T01: Verify that `WriteAudit` with an empty `MetadataJSON` stores `{}` in the database (integration).
- R010-T02: Verify that `LookupVerification` for a known credential returns the correct `TenantID` and `CredentialMode` (integration).
- R010-T03: Verify that `LookupVerification` for an unknown credential returns `ErrNotFound` (integration).
- R010-T04: Verify that `LookupVerification` for an HMAC credential returns an empty `PublicKey` field (integration).

R015  Statement: Schema bootstrapping must load SQL from disk and execute it through the pool connection.
Design: `ApplySchemaFromFile` reads the file at the approved path using `os.ReadFile` and executes the content via `pool.Exec`. A file read error or execution error is returned to the caller.
Tests:
- R015-T01: Verify that `ApplySchemaFromFile` with the approved path succeeds against a live database (integration).
- R015-T02: Verify that `ApplySchemaFromFile` returns an error when the file does not exist (integration).

R020  Statement: Schema bootstrapping must reject any path other than the approved repository schema path.
Design: `ApplySchemaFromFile` compares `filepath.Clean(schemaPath)` against `filepath.Clean("internal/storage/schema.sql")` and returns an error immediately when they differ, before any disk access.
Tests:
- R020-T01: Verify that passing `"internal/storage/schema.sql"` is accepted.
- R020-T02: Verify that passing `"../etc/passwd"` returns an error without reading any file.
- R020-T03: Verify that passing an empty string returns an error.
- R020-T04: Verify that passing a path with traversal components that clean to the approved path is accepted.

## Changelog

- 2026-05-16: Numbered test bullets with R###-T## scheme.
- 2026-05-16: Rewrote with concrete behavioral and security acceptance criteria.
- 2026-05-10: Added schema-path restriction requirement for secure bootstrap file reads.
- 2026-05-10: Added requirements coverage for backend source traceability.
