# Valve Provisioning App Requirements

## Scope

Requirements-only mode: true.
Applies to SwiftUI operator client implementation files:
`macos/ValveProvisioningApp/Package.swift`
`macos/ValveProvisioningApp/Sources/ValveDomain/AppConfig.swift`
`macos/ValveProvisioningApp/Sources/ValveDomain/Models.swift`
`macos/ValveProvisioningApp/Sources/ValveDomain/Validation.swift`
`macos/ValveProvisioningApp/Sources/ValveNetworking/HTTPTypes.swift`
`macos/ValveProvisioningApp/Sources/ValveNetworking/ValveAPIClient.swift`
`macos/ValveProvisioningApp/Sources/ValveSecurity/KeychainStore.swift`
`macos/ValveProvisioningApp/Sources/ValveSecurity/CredentialKeyManager.swift`
`macos/ValveProvisioningApp/Sources/ValveFeatures/AppContext.swift`
`macos/ValveProvisioningApp/Sources/ValveFeatures/AppLifecycle.swift`
`macos/ValveProvisioningApp/Sources/ValveFeatures/RootView.swift`
`macos/ValveProvisioningApp/Sources/ValveProvisioningApp/ValveProvisioningApp.swift`
`macos/ValveProvisioningApp/Tests/ValveDomainTests/ValidationTests.swift`
`macos/ValveProvisioningApp/Tests/ValveNetworkingTests/ValveAPIClientTests.swift`
`macos/ValveProvisioningApp/Tests/ValveFeaturesTests/AppContextTests.swift`
`macos/ValveProvisioningApp/Tests/ValveFeaturesTests/AppLifecycleTests.swift`
`macos/ValveProvisioningApp/Tests/ValveFeaturesTests/InventoryCopyTests.swift`

R001  Statement: Provide a native macOS SwiftUI admin interface for credential provisioning lifecycle actions.
Design: Implement module boundaries and SwiftUI workflows for register, revoke, rotate, and list operations against Valve APIs.
Tests:
- Run package tests in `macos/ValveProvisioningApp` and verify domain/network tests pass.

R005  Statement: Handle sensitive key material through secure local storage only.
Design: Use CryptoKit for key generation and Keychain APIs for private keys and optional HMAC secrets.
Tests:
- Provision/rotate and verify successful key persistence logic paths in app behavior/tests.

R010  Statement: Keep generated SwiftPM artifacts out of repository hygiene and traceability source inventory.
Design: Exclude `.build` and SwiftPM metadata paths through ignore policy and traceability scanner exclusions.
Tests:
- Run `./00_verify_requirements_traceability.sh` and confirm generated `.build` files are not reported as uncovered repository software files.

R015  Statement: Default Valve UI API endpoint must match local server default port.
Design: `AppContext.liveFromEnvironment()` defaults `VALVE_BASE_URL` to `http://localhost:8090` and allows override via environment variable.
Tests:
- Run package tests in `macos/ValveProvisioningApp` and verify `AppContextTests` asserts default base URL resolves to port `8090`.

R020  Statement: Closing the UI window should terminate the app process so launcher scripts return to the terminal prompt.
Design: Wire a lifecycle delegate in the macOS app that returns terminate-on-last-window-close behavior and bind it through `@NSApplicationDelegateAdaptor`.
Tests:
- Run package tests in `macos/ValveProvisioningApp` and verify `AppLifecycleTests` asserts terminate-after-last-window-close policy is enabled.

R025  Statement: Inventory view must support direct copying of any provisioned credential ID.
Design: Expose copy behavior in `RootViewModel` and wire inventory table credential rows with explicit copy affordances.
Tests:
- Run package tests in `macos/ValveProvisioningApp` and verify `InventoryCopyTests` asserts clipboard value and operator message update.
