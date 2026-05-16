# CredentialKeyManager Requirements

## Scope

Applies to `macos/ValveProvisioningApp/Sources/ValveSecurity/CredentialKeyManager.swift`.

R001  Statement: Generate Ed25519 key pairs and return the public key as base64 with the raw private key data.
Design: `makePublicKeyBase64` creates a `Curve25519.Signing.PrivateKey`, returns `publicKey.rawRepresentation.base64EncodedString()` and `privateKey.rawRepresentation`.
Tests:
- R001-T01: Verify that `makePublicKeyBase64` returns a base64 string that decodes to exactly 32 bytes.
- R001-T02: Verify that two successive calls return distinct public keys.

R005  Statement: Persist private key and HMAC secret material through the keychain store abstraction.
Design: `storePrivateKey` saves raw key data under `credential.<id>.privateKey`; `storeHMACSecret` saves UTF-8 encoded secret under `credential.<id>.hmacSecret`.
Tests:
- R005-T01: Verify that `storePrivateKey` calls `keychainStore.save` with the expected key path.
- R005-T02: Verify that `storeHMACSecret` calls `keychainStore.save` with UTF-8 encoded data.

## Changelog

- 2026-05-16: Initial per-file requirements for Swift traceability.
