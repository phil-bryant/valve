# Crypto Helper Requirements

## Scope

Applies to `internal/security/crypto.go`.

R001  Statement: Random secret generation must use cryptographic randomness and return a standard base64-encoded string.
Design: `GenerateRandomSecretBase64(size)` fills a `size`-byte buffer using `crypto/rand.Read` and returns `base64.StdEncoding.EncodeToString` of that buffer. A `rand.Read` failure is returned as an error.
Tests:
- R001-T01: Verify that two successive calls with the same size return distinct strings.
- R001-T02: Verify that the returned string is valid standard base64 (decodable without error).
- R001-T03: Verify that decoding the returned string produces exactly `size` bytes.
- R001-T04: Verify that register validation consumers reject malformed base64 key material when decoding fails.

R005  Statement: Secret hashing must produce a deterministic, lowercase SHA-256 hex digest.
Design: `HashSecretHex(secret)` computes `sha256.Sum256([]byte(secret))` and returns `hex.EncodeToString` of the result, which is always 64 lowercase hex characters.
Tests:
- R005-T01: Verify that the same input always produces the same output (determinism).
- R005-T02: Verify that the output is exactly 64 characters long.
- R005-T03: Verify that the output contains only lowercase hex characters (`0-9`, `a-f`).
- R005-T04: Verify that two distinct inputs produce distinct digests.

## Changelog

- 2026-05-16: Numbered test bullets with R###-T## scheme.
- 2026-05-16: Rewrote with concrete entropy, encoding, and determinism acceptance criteria.
- 2026-05-10: Added requirements coverage for backend source traceability.
