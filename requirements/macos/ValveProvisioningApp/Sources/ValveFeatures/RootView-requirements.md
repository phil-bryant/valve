# RootView Requirements

## Scope

Applies to `macos/ValveProvisioningApp/Sources/ValveFeatures/RootView.swift` and `macos/ValveProvisioningApp/Tests/ValveFeaturesTests/InventoryCopyTests.swift` and `macos/ValveProvisioningApp/Tests/ValveFeaturesTests/RootViewTests.swift`.

R001  Statement: The root view model must support credential provisioning, revocation, rotation, listing, and health checking through the injected context.
Design: `RootViewModel` exposes async methods `provision`, `revoke`, `rotate`, `refreshList`, and `checkHealth` that validate inputs, call the API client with retry logic, persist key material on success, and update published state.
Tests:
- R001-T01: Verify that `provision` with a mock API client updates `lastMessage` to contain the provisioned credential ID.
- R001-T02: Verify that `revoke` with a mock API client updates `lastMessage` to contain the revoked credential ID.
- R001-T03: Verify that `refreshList` populates `records` from the mock API response.
- R001-T04: Verify that `RootViewModel` initializes `tenantID` and `installID` from `AppContext` environment values.
- R001-T05: Verify that `checkHealth` sets `isHealthy` to `true` when `healthCheck` and `readinessCheck` both succeed.

R005  Statement: The inventory view must support direct copying of any provisioned credential ID to the system pasteboard.
Design: `RootViewModel.copyCredentialID` sets `NSPasteboard.general` string content to the credential ID and updates `lastMessage` with confirmation text.
Tests:
- R005-T01: Verify that `copyCredentialID` sets the pasteboard string to the provided credential ID.
- R005-T02: Verify that `copyCredentialID` updates `lastMessage` to contain the credential ID.

## Changelog

- 2026-05-19: Added R001-T04/T05 and RootViewTests.swift scope for env-init and health coverage.
- 2026-05-16: Initial per-file requirements for Swift traceability.
