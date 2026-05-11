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
`macos/ValveProvisioningApp/Sources/ValveFeatures/RootView.swift`
`macos/ValveProvisioningApp/Sources/ValveProvisioningApp/ValveProvisioningApp.swift`
`macos/ValveProvisioningApp/Tests/ValveDomainTests/ValidationTests.swift`
`macos/ValveProvisioningApp/Tests/ValveNetworkingTests/ValveAPIClientTests.swift`

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
