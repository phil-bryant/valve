# ValveProvisioningApp Entry Point Requirements

## Scope

Requirements-only mode: true.
Applies to `macos/ValveProvisioningApp/Sources/ValveProvisioningApp/ValveProvisioningApp.swift`.

R001  Statement: The app entry point must wire the lifecycle delegate and present the root view with a live context.
Design: `ValveProvisioningApp` uses `@main`, binds `ValveAppLifecycleDelegate` via `@NSApplicationDelegateAdaptor`, and presents `RootView(context: .liveFromEnvironment())` inside a `WindowGroup`.
Tests:
- R001-T01: Verify that the app struct conforms to `App` protocol (compilation check).
- R001-T02: Verify that `ValveProvisioningApp` uses `@NSApplicationDelegateAdaptor` with `ValveAppLifecycleDelegate`.

## Changelog

- 2026-05-16: Initial per-file requirements for Swift traceability.
