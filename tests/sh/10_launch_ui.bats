#!/usr/bin/env bats

load "helpers/common.bash"

# Numbered-tag parity supplements for launch-mode and package validation paths.
#R010-T02
#R015-T02
#R015-T03

setup_fixture() {
  create_repo_fixture
  copy_script_to_fixture "10_launch_ui.sh"
  mkdir -p "${FIXTURE_ROOT}/macos/ValveProvisioningApp"
  printf '%s\n' '// swift package fixture' > "${FIXTURE_ROOT}/macos/ValveProvisioningApp/Package.swift"
}

make_swift_stub() {
  cat > "${STUB_BIN}/swift" <<'EOF'
#!/usr/bin/env bash
echo "swift $*" >> "${CALLS_LOG}"
exit "${SWIFT_STUB_EXIT_CODE:-0}"
EOF
  chmod +x "${STUB_BIN}/swift"
}

make_swift_unavailable_stub() {
  cat > "${STUB_BIN}/swift" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
  chmod +x "${STUB_BIN}/swift"
}

setup() {
  setup_shell_test
  setup_fixture
  make_swift_stub
}

teardown() {
  teardown_shell_test
}

@test "runs from non-repo cwd and resolves UI package from script root" {
  #R001-T01: Run from non-repo cwd verifies package path resolution uses script-root defaults.
  #R001
  mkdir -p "${TEST_TMPDIR}/elsewhere"
  run env PATH="${PATH}" bash -c "cd '${TEST_TMPDIR}/elsewhere' && bash '${FIXTURE_ROOT}/10_launch_ui.sh'"
  [ "$status" -eq 0 ]
  grep -F "swift run --package-path ${FIXTURE_ROOT}/macos/ValveProvisioningApp ValveProvisioningApp" "${CALLS_LOG}"
}

@test "fails fast with installer guidance when swift is missing" {
  #R005-T01: Run with swift missing verifies explicit non-zero failure with installer guidance output.
  #R005
  make_swift_unavailable_stub
  run env PATH="${PATH}" bash "${FIXTURE_ROOT}/10_launch_ui.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing required command: swift"* ]]
  [[ "$output" == *"./01_install_prerequisites.sh"* ]]
}

@test "fails when UI package directory is missing" {
  #R010-T01: Run with missing package directory verifies explicit non-zero failure output.
  #R010
  run env PATH="${PATH}" UI_PACKAGE_DIR="${FIXTURE_ROOT}/missing-ui" bash "${FIXTURE_ROOT}/10_launch_ui.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"UI package directory not found"* ]]
}

@test "fails when UI package manifest is missing" {
  #R010
  mkdir -p "${FIXTURE_ROOT}/macos/EmptyUI"
  run env PATH="${PATH}" UI_PACKAGE_DIR="${FIXTURE_ROOT}/macos/EmptyUI" bash "${FIXTURE_ROOT}/10_launch_ui.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"UI package manifest not found"* ]]
}

@test "uses swift run for default launch mode" {
  #R015-T01: Run in default mode verifies swift run invocation targets ValveProvisioningApp.
  #R015
  run env PATH="${PATH}" bash "${FIXTURE_ROOT}/10_launch_ui.sh"
  [ "$status" -eq 0 ]
  grep -F "swift run --package-path ${FIXTURE_ROOT}/macos/ValveProvisioningApp ValveProvisioningApp" "${CALLS_LOG}"
}

@test "uses swift build for build mode" {
  #R015
  run env PATH="${PATH}" UI_LAUNCH_MODE=build bash "${FIXTURE_ROOT}/10_launch_ui.sh"
  [ "$status" -eq 0 ]
  grep -F "swift build --package-path ${FIXTURE_ROOT}/macos/ValveProvisioningApp" "${CALLS_LOG}"
}

@test "fails for unsupported launch mode" {
  #R015
  run env PATH="${PATH}" UI_LAUNCH_MODE=invalid bash "${FIXTURE_ROOT}/10_launch_ui.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unsupported UI_LAUNCH_MODE"* ]]
}

@test "prints deterministic completion output with selected mode" {
  #R020-T01: Run with successful stubbed Swift command verifies final completion line includes mode value.
  #R020
  run env PATH="${PATH}" UI_LAUNCH_MODE=build bash "${FIXTURE_ROOT}/10_launch_ui.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"UI launch workflow completed for mode: build"* ]]
}
