# Models Requirements

## Scope

Applies to `macos/ValveProvisioningApp/Sources/ValveDomain/Models.swift`.

R001  Statement: Define credential mode enum with snake_case raw values matching the Valve API wire format.
Design: `CredentialMode` is a `String`-backed enum with cases `ed25519` and `hmac_sha256`, conforming to `Codable`, `CaseIterable`, and `Sendable`.
Tests:
- R001-T01: Verify that `CredentialMode.ed25519.rawValue` equals `"ed25519"`.
- R001-T02: Verify that `CredentialMode.hmac_sha256.rawValue` equals `"hmac_sha256"`.

R005  Statement: Define request and response models with JSON coding keys matching the Valve API snake_case contract.
Design: `RegisterCredentialRequest`, `RegisterCredentialResponse`, `RevokeCredentialRequest`, `RevokeCredentialResponse`, `RotateCredentialRequest`, `RotateCredentialResponse`, `CredentialRecord`, `ListCredentialsResponse`, and `ErrorEnvelope` use explicit `CodingKeys` enums mapping camelCase properties to snake_case JSON keys.
Tests:
- R005-T01: Verify that encoding a `RegisterCredentialRequest` produces JSON with `tenant_id` key (not `tenantID`).
- R005-T02: Verify that decoding a JSON payload with `credential_id` key produces a valid `RegisterCredentialResponse`.
- R005-T03: Verify that `CredentialRecord` conforms to `Identifiable` with `id` returning `credentialID`.

## Changelog

- 2026-05-16: Initial per-file requirements for Swift traceability.
