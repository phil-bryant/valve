# Signing Contract Requirements

## Scope

Applies to `internal/credentials/signing_contract.go`.

R001  Statement: Publish canonical request-signing contract text for integrators.
Design: Design: Keep signed header set and canonical string format in exported contract constant.
Tests:
- Add/maintain targeted tests that validate r001 behavior.

R005  Statement: Document both Ed25519 and HMAC signing semantics.
Design: Design: Contract text must include algorithm-specific generation and verification notes for both modes.
Tests:
- Add/maintain targeted tests that validate r005 behavior.

## Changelog

- 2026-05-10: Added requirements coverage for backend source traceability.
