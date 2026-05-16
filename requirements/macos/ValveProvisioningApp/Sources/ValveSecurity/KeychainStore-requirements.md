# KeychainStore Requirements

## Scope

Applies to `macos/ValveProvisioningApp/Sources/ValveSecurity/KeychainStore.swift`.

R001  Statement: Persist arbitrary data to the macOS Keychain under a service-scoped account key.
Design: `KeychainStore.save` deletes any existing item for the key, then calls `SecItemAdd` with `kSecClassGenericPassword`, the configured `serviceName`, and the account key. A non-success status throws `KeychainError.unhandled(status)`.
Tests:
- R001-T01: Verify that saving and loading the same key returns the original data.
- R001-T02: Verify that saving to the same key twice overwrites without error.

R005  Statement: Load previously persisted data from the Keychain, returning nil when the item does not exist.
Design: `KeychainStore.load` queries with `kSecReturnData` and `kSecMatchLimitOne`; returns `nil` for `errSecItemNotFound`, the data for `errSecSuccess`, and throws `KeychainError.unhandled` otherwise.
Tests:
- R005-T01: Verify that loading a non-existent key returns nil without throwing.
- R005-T02: Verify that a non-success/non-not-found status throws `KeychainError.unhandled`.

## Changelog

- 2026-05-16: Initial per-file requirements for Swift traceability.
