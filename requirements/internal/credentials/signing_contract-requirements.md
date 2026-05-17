# Signing Contract Requirements

## Scope

Applies to `internal/credentials/signing_contract.go`.

R001  Statement: The signing contract constant must enumerate all required request headers and the canonical string construction rule.
Design: `SigningContract` is an exported string constant that names the five required headers (`X-Manifold-Credential-ID`, `X-Manifold-Timestamp`, `X-Manifold-Batch-ID`, `X-Manifold-Body-SHA256`, `X-Manifold-Signature`) and specifies the canonical string as `METHOD + "\n" + PATH + "\n" + TIMESTAMP + "\n" + BATCH_ID + "\n" + BODY_SHA256`.
Tests:
- R001-T01: Verify that `SigningContract` contains the substring `X-Manifold-Credential-ID`.
- R001-T02: Verify that `SigningContract` contains the substring `X-Manifold-Signature`.
- R001-T03: Verify that `SigningContract` contains the canonical string field order (`METHOD`, `PATH`, `TIMESTAMP`, `BATCH_ID`, `BODY_SHA256`).
- R001-T04: Verify adjacent contract validation paths accept fully valid register payload wiring.
- R001-T05: Verify adjacent contract validation paths reject unknown credential modes.
- R001-T06: Verify adjacent contract validation paths reject disabled HMAC mode.
- R001-T07: Verify adjacent contract validation paths reject missing Ed25519 keys.
- R001-T08: Verify adjacent contract validation paths reject non-base64 Ed25519 keys.
- R001-T09: Verify adjacent contract validation paths reject invalid-length Ed25519 keys.
- R001-T10: Verify adjacent contract validation paths accept canonical Ed25519 payloads.
- R001-T11: Verify adjacent contract validation paths accept canonical HMAC payloads when enabled.

R005  Statement: The signing contract must document Ed25519 and HMAC-SHA256 signing and verification semantics.
Design: `SigningContract` includes an Ed25519 section stating that the signature is `ed25519_sign(canonical_string)` verified with the Valve-registered public key, and an HMAC section stating that the signature is `HMAC-SHA256(secret, canonical_string)` verified with the Valve-managed secret.
Tests:
- R005-T01: Verify that `SigningContract` contains the substring `Ed25519` or `ed25519`.
- R005-T02: Verify that `SigningContract` contains the substring `HMAC` or `hmac`.
- R005-T03: Verify that `SigningContract` references both a public key (Ed25519) and a secret (HMAC).
- R005-T04: Verify downstream revoke validation success paths remain consistent with documented signing contract semantics.

## Changelog

- 2026-05-16: Numbered test bullets with R###-T## scheme.
- 2026-05-16: Rewrote with concrete content-presence acceptance criteria.
- 2026-05-10: Added requirements coverage for backend source traceability.
