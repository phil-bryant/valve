# Credential ID Requirements

## Scope

Applies to `internal/credentials/ids.go`.

R001  Statement: Credential IDs must be generated from 16 cryptographically random bytes encoded as base32.
Design: `NewCredentialID` fills a 16-byte buffer using `crypto/rand`, encodes it with standard base32 without padding, and returns the result. A failure from `rand.Read` is propagated as an error.
Tests:
- R001-T01: Verify that two successive calls return distinct values.
- R001-T02: Verify that the non-prefix portion of the ID is 26 characters (16 bytes × 8 bits / 5 bits per base32 char = 25.6, padded to 26 without padding chars).
- R001-T03: Verify that the non-prefix portion contains only lowercase base32 characters (`a-z`, `2-7`).

R005  Statement: Credential IDs must carry a stable `cred_` prefix and be fully lowercase.
Design: The returned string is `"cred_"` concatenated with the lowercased base32 encoding, producing IDs of the form `cred_<26 lowercase chars>`.
Tests:
- R005-T01: Verify that every generated ID starts with `cred_`.
- R005-T02: Verify that the full ID string contains no uppercase characters.

## Changelog

- 2026-05-16: Numbered test bullets with R###-T## scheme.
- 2026-05-16: Rewrote with concrete structural and entropy acceptance criteria.
- 2026-05-10: Added requirements coverage for backend source traceability.
