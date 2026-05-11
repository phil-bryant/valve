# Launch UI Requirements

## Scope

Applies to `09_launch_ui.sh`.

R001  Statement: Run UI launcher in strict fail-fast mode from repository root.
Design: Use strict bash mode (`set -euo pipefail`), resolve script directory from `${BASH_SOURCE[0]}`, and `cd` into script directory before executing launch/build logic.
Tests:
- Run script from a non-repo working directory and verify package path resolution still uses script-root defaults.

R005  Statement: Fail fast when the Swift toolchain is unavailable with actionable install guidance.
Design: Validate `swift` on PATH before any UI package operations and print `./01_install_prerequisites.sh` guidance when missing.
Tests:
- Run with `swift` missing from PATH and verify explicit non-zero failure with installer guidance output.

R010  Statement: Refuse launch/build when UI package inputs are missing.
Design: Validate `UI_PACKAGE_DIR` exists and contains `Package.swift` before invoking SwiftPM commands.
Tests:
- Run with missing package directory and verify explicit non-zero failure output.
- Run with missing `Package.swift` and verify explicit non-zero failure output.

R015  Statement: Support deterministic launch behavior with explicit mode control.
Design: Default `UI_LAUNCH_MODE` to `run` and invoke `swift run --package-path <dir> ValveProvisioningApp`; support `UI_LAUNCH_MODE=build` with `swift build --package-path <dir>`; fail for unsupported modes.
Tests:
- Run in default mode and verify `swift run` invocation targets `ValveProvisioningApp`.
- Run with `UI_LAUNCH_MODE=build` and verify `swift build` invocation is used.
- Run with unsupported `UI_LAUNCH_MODE` and verify explicit non-zero failure output.

R020  Statement: Emit deterministic completion output for operators and automation.
Design: Print a single final success line containing the selected launch mode when launch/build command succeeds.
Tests:
- Run with successful stubbed Swift command and verify final completion line includes mode value.

## Changelog

- 2026-05-11: Renumbered UI launcher workflow from step-08 to step-09.
