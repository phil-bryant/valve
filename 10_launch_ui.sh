#!/usr/bin/env bash
umask 007
#R001: Run in strict fail-fast mode from repository root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

#R005: Fail fast when Swift toolchain is unavailable.
if ! command -v swift >/dev/null 2>&1; then
  echo "❌ Missing required command: swift"
  echo "Install prerequisites with: ./01_install_prerequisites.sh"
  exit 1
fi
if ! swift --version >/dev/null 2>&1; then
  echo "❌ Missing required command: swift"
  echo "Install prerequisites with: ./01_install_prerequisites.sh"
  exit 1
fi

UI_PACKAGE_DIR="${UI_PACKAGE_DIR:-${SCRIPT_DIR}/macos/ValveProvisioningApp}"
#R010: Validate UI package directory and manifest before launch/build.
if [ ! -d "$UI_PACKAGE_DIR" ]; then
  echo "❌ UI package directory not found: ${UI_PACKAGE_DIR}"
  exit 1
fi
if [ ! -f "${UI_PACKAGE_DIR}/Package.swift" ]; then
  echo "❌ UI package manifest not found: ${UI_PACKAGE_DIR}/Package.swift"
  exit 1
fi

UI_LAUNCH_MODE="${UI_LAUNCH_MODE:-run}"
#R015: Support deterministic build-only mode and default launch mode.
if [ "$UI_LAUNCH_MODE" = "build" ]; then
  echo "▶ Building Valve Provisioning UI package"
  swift build --package-path "$UI_PACKAGE_DIR"
elif [ "$UI_LAUNCH_MODE" = "run" ]; then
  echo "▶ Launching Valve Provisioning UI"
  swift run --package-path "$UI_PACKAGE_DIR" ValveProvisioningApp
else
  echo "❌ Unsupported UI_LAUNCH_MODE: ${UI_LAUNCH_MODE} (expected run or build)"
  exit 1
fi

#R020: Emit concise completion output for automation and operators.
echo "✅ UI launch workflow completed for mode: ${UI_LAUNCH_MODE}"
