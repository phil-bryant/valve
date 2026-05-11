# Credential Service Requirements

## Scope

Applies to `internal/credentials/service.go`.

R001  Statement: Registration flow must validate inputs, authorize actor, and persist credential state.
Design: Design: Register validates request, checks authorizer, creates new ID, persists credential, and emits audit records.
Tests:
- Add/maintain targeted tests that validate r001 behavior.

R005  Statement: Revoke flow must enforce tenant ownership and active credential lifecycle transitions.
Design: Design: Revoke validates request, authorizes actor, verifies tenant match, updates credential status, and emits audit records.
Tests:
- Add/maintain targeted tests that validate r005 behavior.

R010  Statement: Rotation flow must atomically replace active credential and surface replacement metadata.
Design: Design: Rotate validates request, authorizes actor, verifies prior credential invariants, stores replacement, and returns old/new identifiers.
Tests:
- Add/maintain targeted tests that validate r010 behavior.

R015  Statement: Read-only endpoints must enforce required arguments and normalize not-found behavior.
Design: Design: List validates tenant/install inputs; verification lookup validates credential id and maps storage misses to domain not found errors.
Tests:
- Add/maintain targeted tests that validate r015 behavior.

## Changelog

- 2026-05-10: Added requirements coverage for backend source traceability.
