# Launch UI Requirements

## Scope

Applies to `10_launch_ui.sh`.

R001  Statement: Run UI launcher in strict fail-fast mode from repository root.
Design: Use strict bash mode (`set -euo pipefail`), resolve script directory from `${BASH_SOURCE[0]}`, and `cd` into script directory before executing launch/build logic.
Tests:
- R001-T01: Run script from a non-repo working directory and verify package path resolution still uses script-root defaults.

R005  Statement: Fail fast when the Swift toolchain is unavailable with actionable install guidance.
Design: Validate `swift` on PATH before any UI package operations and print `./01_install_prerequisites.sh` guidance when missing.
Tests:
- R005-T01: Run with `swift` missing from PATH and verify explicit non-zero failure with installer guidance output.

R010  Statement: Refuse launch/build when UI package inputs are missing.
Design: Validate `UI_PACKAGE_DIR` exists and contains `Package.swift` before invoking SwiftPM commands.
Tests:
- R010-T01: Run with missing package directory and verify explicit non-zero failure output.
- R010-T02: Run with missing `Package.swift` and verify explicit non-zero failure output.

R015  Statement: Support deterministic launch behavior with explicit mode control.
Design: Default `UI_LAUNCH_MODE` to `run` and invoke `swift run --package-path <dir> ValveProvisioningApp`; support `UI_LAUNCH_MODE=build` with `swift build --package-path <dir>`; fail for unsupported modes.
Tests:
- R015-T01: Run in default mode and verify `swift run` invocation targets `ValveProvisioningApp`.
- R015-T02: Run with `UI_LAUNCH_MODE=build` and verify `swift build` invocation is used.
- R015-T03: Run with unsupported `UI_LAUNCH_MODE` and verify explicit non-zero failure output.

R020  Statement: Emit deterministic completion output for operators and automation.
Design: Print a single final success line containing the selected launch mode when launch/build command succeeds.
Tests:
- R020-T01: Run with successful stubbed Swift command and verify final completion line includes mode value.

## Changelog

- 2026-05-16: Numbered test bullets with R###-T## scheme.
- 2026-05-11: Renumbered UI launcher workflow from step-08 to step-09.
