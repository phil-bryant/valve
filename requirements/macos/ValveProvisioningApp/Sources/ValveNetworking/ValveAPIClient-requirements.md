# ValveAPIClient Requirements

## Scope

Applies to `macos/ValveProvisioningApp/Sources/ValveNetworking/ValveAPIClient.swift` and `macos/ValveProvisioningApp/Tests/ValveNetworkingTests/ValveAPIClientTests.swift`.

R001  Statement: Define a protocol-based API client contract for all credential lifecycle operations and health probes.
Design: `ValveAPIClientProtocol` declares async throwing methods for `registerCredential`, `revokeCredential`, `rotateCredential`, `listCredentials`, `healthCheck`, and `readinessCheck`. `ValveAPIClient` implements the protocol using `URLSession`.
Tests:
- R001-T01: Verify that `ValveAPIClient` conforms to `ValveAPIClientProtocol`.
- R001-T02: Verify that a register call against a mock server returns a decoded `RegisterCredentialResponse`.

R005  Statement: Map non-2xx HTTP responses to structured `APIError.requestFailed` with server error message.
Design: `decodeResponse` checks the HTTP status code; for non-2xx it attempts to decode an `ErrorEnvelope` and throws `APIError.requestFailed(statusCode, message)`.
Tests:
- R005-T01: Verify that a 403 response throws `APIError.requestFailed` with status 403.
- R005-T02: Verify that a 200 response with valid JSON decodes successfully.

## Changelog

- 2026-05-16: Initial per-file requirements for Swift traceability.
