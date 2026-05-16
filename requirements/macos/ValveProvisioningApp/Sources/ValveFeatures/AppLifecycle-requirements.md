# AppLifecycle Requirements

## Scope

Applies to `macos/ValveProvisioningApp/Sources/ValveFeatures/AppLifecycle.swift` and `macos/ValveProvisioningApp/Tests/ValveFeaturesTests/AppLifecycleTests.swift`.

R001  Statement: The app must terminate when the last window is closed so launcher scripts return to the terminal prompt.
Design: `ValveAppLifecycleDelegate` implements `applicationShouldTerminateAfterLastWindowClosed` returning `AppLifecyclePolicy.terminateAfterLastWindowClosed` (which is `true`).
Tests:
- R001-T01: Verify that `ValveAppLifecycleDelegate().applicationShouldTerminateAfterLastWindowClosed` returns `true`.
- R001-T02: Verify that `AppLifecyclePolicy.terminateAfterLastWindowClosed` is `true`.

## Changelog

- 2026-05-16: Initial per-file requirements for Swift traceability.
