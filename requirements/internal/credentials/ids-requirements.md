# Credential ID Requirements

## Scope

Applies to `internal/credentials/ids.go`.

R001  Statement: Generate opaque random credential identifiers.
Design: Design: Use cryptographic randomness and base32 encoding from 16 random bytes.
Tests:
- Add/maintain targeted tests that validate r001 behavior.

R005  Statement: Credential identifiers must use stable API prefix.
Design: Design: Return generated IDs with `cred_` prefix and lowercased encoded body.
Tests:
- Add/maintain targeted tests that validate r005 behavior.

## Changelog

- 2026-05-10: Added requirements coverage for backend source traceability.
