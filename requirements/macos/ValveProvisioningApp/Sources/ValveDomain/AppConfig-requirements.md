# AppConfig Requirements

## Scope

Applies to `macos/ValveProvisioningApp/Sources/ValveDomain/AppConfig.swift`.

R001  Statement: Define a value-type environment configuration carrying base URL, tenant, install, and actor identity.
Design: `ValveEnvironment` is a public struct conforming to `Equatable` and `Sendable` with `baseURL: URL`, `tenantID: String`, `installID: String`, and `actorUserID: String` fields, initialized through a memberwise `init`.
Tests:
- R001-T01: Verify that two `ValveEnvironment` instances with identical fields are equal.
- R001-T02: Verify that two instances with different `baseURL` values are not equal.

## Changelog

- 2026-05-16: Initial per-file requirements for Swift traceability.
