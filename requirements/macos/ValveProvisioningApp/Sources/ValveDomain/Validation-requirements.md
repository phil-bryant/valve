# Validation Requirements

## Scope

Applies to `macos/ValveProvisioningApp/Sources/ValveDomain/Validation.swift` and `macos/ValveProvisioningApp/Tests/ValveDomainTests/ValidationTests.swift`.

R001  Statement: Register validation must reject missing required fields, invalid platform, and invalid public key.
Design: `CredentialRequestValidator.validateRegister` throws `ValidationError.missingField` for empty `tenantID`, `actorUserID`, `installID`, `appBundleID`, `appVersion`, `appBuild`, or `deviceLabel`; throws `.invalidPlatform` when platform is not `"macOS"`; throws `.invalidPublicKey` when the public key is not valid base64 decoding to exactly 32 bytes.
Tests:
- R001-T01: Verify that an empty `tenantID` throws `missingField("tenant_id")`.
- R001-T02: Verify that a non-macOS platform throws `invalidPlatform`.
- R001-T03: Verify that a public key decoding to fewer than 32 bytes throws `invalidPublicKey`.
- R001-T04: Verify that a fully valid register request does not throw.

R005  Statement: Rotate validation must reject missing identifiers and invalid replacement public key.
Design: `CredentialRequestValidator.validateRotate` throws for empty common fields, empty `oldCredentialID`, `appVersion`, `appBuild`, `deviceLabel`, or invalid `newPublicKey`.
Tests:
- R005-T01: Verify that an empty `oldCredentialID` throws `missingField("old_credential_id")`.
- R005-T02: Verify that a fully valid rotate request does not throw.

R010  Statement: Revoke validation must reject missing identifiers and empty reason.
Design: `CredentialRequestValidator.validateRevoke` throws for empty `tenantID`, `actorUserID`, `credentialID`, or `reason`.
Tests:
- R010-T01: Verify that an empty `credentialID` throws `missingField("credential_id")`.
- R010-T02: Verify that an empty `reason` throws `missingField("reason")`.
- R010-T03: Verify that a fully valid revoke request does not throw.

## Changelog

- 2026-05-16: Initial per-file requirements for Swift traceability.
