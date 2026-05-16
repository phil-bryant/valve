# AppContext Requirements

## Scope

Applies to `macos/ValveProvisioningApp/Sources/ValveFeatures/AppContext.swift` and `macos/ValveProvisioningApp/Tests/ValveFeaturesTests/AppContextTests.swift`.

R001  Statement: Provide a live application context factory that resolves configuration from environment variables with sensible defaults.
Design: `AppContext.liveFromEnvironment()` reads `VALVE_BASE_URL` (default `http://localhost:8090`), `VALVE_TENANT_ID` (default `tenant-dev`), `VALVE_INSTALL_ID` (default `install-dev`), and `VALVE_ACTOR_USER_ID` (default `operator-dev`) from `ProcessInfo.processInfo.environment`, then wires `ValveAPIClient`, `CredentialKeyManager`, and `AppAuditLogger`.
Tests:
- R001-T01: Verify that `liveFromEnvironment()` with no env overrides produces a context with base URL port 8090.
- R001-T02: Verify that setting `VALVE_BASE_URL` env var overrides the default.

R005  Statement: Provide a local audit logger that appends JSONL entries to Application Support.
Design: `AppAuditLogger` is an actor that writes timestamped `{timestamp, action, status, details}` JSON lines to `~/Library/Application Support/ValveProvisioningApp/audit.jsonl`, creating the directory if needed.
Tests:
- R005-T01: Verify that calling `write` appends a JSON-parseable line to the audit file.

## Changelog

- 2026-05-16: Initial per-file requirements for Swift traceability.
