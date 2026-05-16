# HTTPTypes Requirements

## Scope

Applies to `macos/ValveProvisioningApp/Sources/ValveNetworking/HTTPTypes.swift`.

R001  Statement: Define API error cases covering URL construction, HTTP status, decoding, and transport failures.
Design: `APIError` is a `Sendable` enum with cases `invalidURL`, `requestFailed(Int, String)`, `decodingFailed(String)`, and `transportError(String)`, conforming to `LocalizedError` with human-readable descriptions.
Tests:
- R001-T01: Verify that `APIError.invalidURL.errorDescription` contains "Invalid API URL".
- R001-T02: Verify that `APIError.requestFailed(403, "unauthorized").errorDescription` contains "403".
- R001-T03: Verify that `APIError.transportError("timeout").errorDescription` contains "timeout".

## Changelog

- 2026-05-16: Initial per-file requirements for Swift traceability.
