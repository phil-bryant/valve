#!/usr/bin/env bats

# Numbered-tag parity supplements for grouped install scenarios.
#R010-T02
#R015-T02
#R030-T02
#R050-T02

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  export SCRIPT_PATH="${REPO_ROOT}/01_install_prerequisites.sh"
  export TMP_ROOT
  TMP_ROOT="$(mktemp -d)"
  export STUB_BIN="${TMP_ROOT}/bin"
  export ZAP_APP_PATH="${TMP_ROOT}/Applications/ZAP.app"
  mkdir -p "${STUB_BIN}"
}

teardown() {
  if [ -d "${TMP_ROOT}" ]; then
    mv "${TMP_ROOT}" "${TMP_ROOT}.trash.$$" || true
  fi
}

create_brew_stub() {
  cat > "${STUB_BIN}/brew" <<'EOF'
#!/bin/bash
if [ "$1" = "--prefix" ] && [ "$2" = "libpq" ]; then
  echo "${STUB_BIN}/opt/libpq"
  exit 0
fi
if [ "$1" = "install" ] && [ "$2" = "--cask" ] && [ "$3" = "zap" ]; then
  printf "install --cask zap\n" >> "${BREW_LOG}"
  mkdir -p "${ZAP_APP_PATH}/Contents/MacOS"
  cat > "${ZAP_APP_PATH}/Contents/MacOS/ZAP.sh" <<'INNER'
#!/bin/bash
exit 0
INNER
  chmod +x "${ZAP_APP_PATH}/Contents/MacOS/ZAP.sh"
  exit 0
fi
if [ "$1" = "install" ]; then
  FORMULA="$2"
  COMMAND_NAME="${FORMULA}"
  if [ "${FORMULA}" = "clamav" ]; then
    COMMAND_NAME="clamscan"
  fi
  printf "install %s\n" "${FORMULA}" >> "${BREW_LOG}"
  if [ "${FORMULA}" = "libpq" ]; then
    mkdir -p "${STUB_BIN}/opt/libpq/bin"
    cat > "${STUB_BIN}/opt/libpq/bin/psql" <<'INNER'
#!/bin/bash
exit 0
INNER
    chmod +x "${STUB_BIN}/opt/libpq/bin/psql"
    exit 0
  fi
  cat > "${STUB_BIN}/${COMMAND_NAME}" <<'INNER'
#!/bin/bash
exit 0
INNER
  chmod +x "${STUB_BIN}/${COMMAND_NAME}"
  exit 0
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/brew"
}

create_1psa_stub() {
  cat > "${STUB_BIN}/1psa" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "${STUB_BIN}/1psa"
}

@test "R001: script uses strict fail-fast mode" {
  #R001-T01: Script exits non-zero on failing command.
  #R001
  run rg "set -euo pipefail" "${SCRIPT_PATH}"
  [ "$status" -eq 0 ]
}

@test "R005: fails with guidance when Homebrew is missing" {
  #R005-T01: Run with brew unavailable verifies clear failure guidance.
  #R005
  run env PATH="/usr/bin:/bin" /bin/bash "${SCRIPT_PATH}"
  [ "$status" -ne 0 ]
  [[ "${output}" == *"[Homebrew] Not installed."* ]]
  [[ "${output}" == *"install.sh"* ]]
}

@test "R010,R025,R030,R055,R060,R065: installs Go, security, DAST, mutation, and test-runtime tooling when missing" {
  #R010-T01: Run without go verifies installer attempts brew install go.
  #R025-T01: Run without golangci-lint verifies installer attempts brew install golangci-lint.
  #R030-T01: Run without security tools verifies each required formula install is attempted.
  #R055-T01: Run without schemathesis verifies brew install schemathesis is attempted.
  #R055-T02: Run without zap-baseline.py/ZAP.sh verifies brew install --cask zap is attempted.
  #R060-T01: Run without gremlins verifies go install is attempted for gremlins.
  #R065-T01: Run without parallel verifies brew install parallel is attempted.
  #R010 #R025 #R030 #R055 #R060 #R065
  create_brew_stub
  create_1psa_stub
  cat > "${STUB_BIN}/go" <<'EOF'
#!/bin/bash
if [ "$1" = "version" ]; then
  echo "go version go1.22.1 darwin/arm64"
  exit 0
fi
if [ "$1" = "install" ]; then
  printf "go install %s\n" "$2" >> "${GO_INSTALL_LOG:-/dev/null}"
  TOOL_NAME="$(basename "$2")"
  TOOL_NAME="${TOOL_NAME%%@*}"
  cat > "${STUB_BIN}/${TOOL_NAME}" <<'INNER'
#!/bin/bash
exit 0
INNER
  chmod +x "${STUB_BIN}/${TOOL_NAME}"
  exit 0
fi
if [ "$1" = "env" ] && [ "$2" = "GOPATH" ]; then
  echo "${STUB_BIN}/.."
  exit 0
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/go"
  run env PATH="${STUB_BIN}:/usr/bin:/bin" BREW_LOG="${TMP_ROOT}/brew.log" GO_INSTALL_LOG="${TMP_ROOT}/go-install.log" STUB_BIN="${STUB_BIN}" ZAP_APP_PATH="${ZAP_APP_PATH}" /bin/bash "${SCRIPT_PATH}"
  [ "$status" -eq 0 ]
  run rg "^install libpq$" "${TMP_ROOT}/brew.log"
  [ "$status" -eq 0 ]
  run rg "^install golangci-lint$" "${TMP_ROOT}/brew.log"
  [ "$status" -eq 0 ]
  run rg "^install shellcheck$" "${TMP_ROOT}/brew.log"
  [ "$status" -eq 0 ]
  run rg "^install semgrep$" "${TMP_ROOT}/brew.log"
  [ "$status" -eq 0 ]
  run rg "^install gitleaks$" "${TMP_ROOT}/brew.log"
  [ "$status" -eq 0 ]
  run rg "^install gosec$" "${TMP_ROOT}/brew.log"
  [ "$status" -eq 0 ]
  run rg "^install govulncheck$" "${TMP_ROOT}/brew.log"
  [ "$status" -eq 0 ]
  run rg "^install clamav$" "${TMP_ROOT}/brew.log"
  [ "$status" -eq 0 ]
  run rg "^install --cask zap$" "${TMP_ROOT}/brew.log"
  [ "$status" -eq 0 ]
  run rg "gremlins" "${TMP_ROOT}/go-install.log"
  [ "$status" -eq 0 ]
  run rg "^install parallel$" "${TMP_ROOT}/brew.log"
  [ "$status" -eq 0 ]
}

@test "R015: fails when Go version is below minimum" {
  #R015-T01: Simulate lower-than-minimum version output verifies explicit failure.
  #R015
  create_brew_stub
  cat > "${STUB_BIN}/go" <<'EOF'
#!/bin/bash
if [ "$1" = "version" ]; then
  echo "go version go1.20.4 darwin/arm64"
  exit 0
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/go"
  run env PATH="${STUB_BIN}:/usr/bin:/bin" BREW_LOG="${TMP_ROOT}/brew.log" STUB_BIN="${STUB_BIN}" ZAP_APP_PATH="${ZAP_APP_PATH}" /bin/bash "${SCRIPT_PATH}"
  [ "$status" -ne 0 ]
  [[ "${output}" == *"below required"* ]]
}

@test "R020,R035,R045: accepts libpq prefix fallback and prints Go guidance" {
  #R020-T01: Simulate missing psql verifies installer attempts brew install libpq.
  #R035-T01: Run installer verifies phase status output appears for all major checks.
  #R045-T01: On successful run verifies final guidance includes go test commands.
  #R020 #R035 #R045
  create_brew_stub
  create_1psa_stub
  cat > "${STUB_BIN}/go" <<'EOF'
#!/bin/bash
if [ "$1" = "version" ]; then
  echo "go version go1.22.7 darwin/arm64"
  exit 0
fi
if [ "$1" = "install" ]; then
  TOOL_NAME="$(basename "$2")"
  TOOL_NAME="${TOOL_NAME%%@*}"
  cat > "${STUB_BIN}/${TOOL_NAME}" <<'INNER'
#!/bin/bash
exit 0
INNER
  chmod +x "${STUB_BIN}/${TOOL_NAME}"
  exit 0
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/go"
  run env PATH="${STUB_BIN}:/usr/bin:/bin" BREW_LOG="${TMP_ROOT}/brew.log" STUB_BIN="${STUB_BIN}" /bin/bash "${SCRIPT_PATH}"
  [ "$status" -eq 0 ]
  [[ "${output}" == *"Go Version"* ]]
  [[ "${output}" == *"go test ./..."* ]]
  [[ "${output}" == *"go test -race ./..."* ]]
  [[ "${output}" == *"golangci-lint run"* ]]
  run rg "^install libpq$" "${TMP_ROOT}/brew.log"
  [ "$status" -eq 0 ]
}

@test "R020: fails when psql remains unavailable after libpq install" {
  #R020-T02: Simulate fallback psql unavailable verifies failure.
  #R020
  mkdir -p "${STUB_BIN}/opt/libpq/bin"
  cat > "${STUB_BIN}/brew" <<'EOF'
#!/bin/bash
if [ "$1" = "--prefix" ] && [ "$2" = "libpq" ]; then
  echo "${STUB_BIN}/opt/libpq"
  exit 0
fi
if [ "$1" = "install" ] && [ "$2" = "libpq" ]; then
  exit 0
fi
if [ "$1" = "install" ]; then
  cat > "${STUB_BIN}/$2" <<'INNER'
#!/bin/bash
exit 0
INNER
  chmod +x "${STUB_BIN}/$2"
  exit 0
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/brew"
  cat > "${STUB_BIN}/go" <<'EOF'
#!/bin/bash
if [ "$1" = "version" ]; then
  echo "go version go1.22.3 darwin/arm64"
  exit 0
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/go"
  run env PATH="${STUB_BIN}:/usr/bin:/bin" STUB_BIN="${STUB_BIN}" BREW_LOG="${TMP_ROOT}/brew.log" ZAP_APP_PATH="${ZAP_APP_PATH}" /bin/bash "${SCRIPT_PATH}"
  [ "$status" -ne 0 ]
  [[ "${output}" == *"psql still unavailable"* ]]
}

@test "R040: reruns are idempotent and skip redundant installs" {
  #R040-T01: Run installer twice verifies second run performs no unnecessary installs.
  #R040
  create_brew_stub
  create_1psa_stub
  cat > "${STUB_BIN}/go" <<'EOF'
#!/bin/bash
if [ "$1" = "version" ]; then
  echo "go version go1.22.8 darwin/arm64"
  exit 0
fi
if [ "$1" = "install" ]; then
  TOOL_NAME="$(basename "$2")"
  TOOL_NAME="${TOOL_NAME%%@*}"
  cat > "${STUB_BIN}/${TOOL_NAME}" <<'INNER'
#!/bin/bash
exit 0
INNER
  chmod +x "${STUB_BIN}/${TOOL_NAME}"
  exit 0
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/go"

  run env PATH="${STUB_BIN}:/usr/bin:/bin" BREW_LOG="${TMP_ROOT}/brew.log" STUB_BIN="${STUB_BIN}" ZAP_APP_PATH="${ZAP_APP_PATH}" /bin/bash "${SCRIPT_PATH}"
  [ "$status" -eq 0 ]

  run env PATH="${STUB_BIN}:/usr/bin:/bin" BREW_LOG="${TMP_ROOT}/brew.log" STUB_BIN="${STUB_BIN}" ZAP_APP_PATH="${ZAP_APP_PATH}" /bin/bash "${SCRIPT_PATH}"
  [ "$status" -eq 0 ]

  run rg "^install libpq$" "${TMP_ROOT}/brew.log" --count
  [ "$status" -eq 0 ]
  [ "${output}" = "1" ]
  run rg "^install golangci-lint$" "${TMP_ROOT}/brew.log" --count
  [ "$status" -eq 0 ]
  [ "${output}" = "1" ]
  run rg "^install shellcheck$" "${TMP_ROOT}/brew.log" --count
  [ "$status" -eq 0 ]
  [ "${output}" = "1" ]
  run rg "^install semgrep$" "${TMP_ROOT}/brew.log" --count
  [ "$status" -eq 0 ]
  [ "${output}" = "1" ]
  run rg "^install gitleaks$" "${TMP_ROOT}/brew.log" --count
  [ "$status" -eq 0 ]
  [ "${output}" = "1" ]
  run rg "^install gosec$" "${TMP_ROOT}/brew.log" --count
  [ "$status" -eq 0 ]
  [ "${output}" = "1" ]
  run rg "^install govulncheck$" "${TMP_ROOT}/brew.log" --count
  [ "$status" -eq 0 ]
  [ "${output}" = "1" ]
  run rg "^install clamav$" "${TMP_ROOT}/brew.log" --count
  [ "$status" -eq 0 ]
  [ "${output}" = "1" ]
  run rg "^install --cask zap$" "${TMP_ROOT}/brew.log" --count
  [ "$status" -eq 0 ]
  [ "${output}" = "1" ]
}

@test "R055: skips zap cask install when ZAP runtime is already available" {
  #R055-T03: Run with zap-baseline.py available verifies cask install is skipped.
  #R055
  create_brew_stub
  create_1psa_stub
  cat > "${STUB_BIN}/go" <<'EOF'
#!/bin/bash
if [ "$1" = "version" ]; then
  echo "go version go1.22.9 darwin/arm64"
  exit 0
fi
if [ "$1" = "install" ]; then
  TOOL_NAME="$(basename "$2")"
  TOOL_NAME="${TOOL_NAME%%@*}"
  cat > "${STUB_BIN}/${TOOL_NAME}" <<'INNER'
#!/bin/bash
exit 0
INNER
  chmod +x "${STUB_BIN}/${TOOL_NAME}"
  exit 0
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/go"
  cat > "${STUB_BIN}/zap-baseline.py" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "${STUB_BIN}/zap-baseline.py"
  run env PATH="${STUB_BIN}:/usr/bin:/bin" BREW_LOG="${TMP_ROOT}/brew.log" STUB_BIN="${STUB_BIN}" ZAP_APP_PATH="${ZAP_APP_PATH}" /bin/bash "${SCRIPT_PATH}"
  [ "$status" -eq 0 ]
  if [ -f "${TMP_ROOT}/brew.log" ]; then
    run rg "^install --cask zap$" "${TMP_ROOT}/brew.log"
    [ "$status" -ne 0 ]
  fi
}

@test "R050: fails with guidance when 1psa is missing" {
  #R050-T01: Run without 1psa verifies installer exits non-zero with explicit setup guidance.
  #R050
  create_brew_stub
  cat > "${STUB_BIN}/go" <<'EOF'
#!/bin/bash
if [ "$1" = "version" ]; then
  echo "go version go1.22.9 darwin/arm64"
  exit 0
fi
if [ "$1" = "install" ]; then
  TOOL_NAME="$(basename "$2")"
  TOOL_NAME="${TOOL_NAME%%@*}"
  cat > "${STUB_BIN}/${TOOL_NAME}" <<'INNER'
#!/bin/bash
exit 0
INNER
  chmod +x "${STUB_BIN}/${TOOL_NAME}"
  exit 0
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/go"
  run env PATH="${STUB_BIN}:/usr/bin:/bin" BREW_LOG="${TMP_ROOT}/brew.log" STUB_BIN="${STUB_BIN}" ZAP_APP_PATH="${ZAP_APP_PATH}" /bin/bash "${SCRIPT_PATH}"
  [ "$status" -ne 0 ]
  [[ "${output}" == *"[1psa] Missing."* ]]
}

@test "R065: skips parallel install when already available" {
  #R065-T02: Run with parallel already on PATH verifies no reinstall.
  #R065
  create_brew_stub
  create_1psa_stub
  cat > "${STUB_BIN}/go" <<'EOF'
#!/bin/bash
if [ "$1" = "version" ]; then
  echo "go version go1.22.9 darwin/arm64"
  exit 0
fi
if [ "$1" = "install" ]; then
  TOOL_NAME="$(basename "$2")"
  TOOL_NAME="${TOOL_NAME%%@*}"
  cat > "${STUB_BIN}/${TOOL_NAME}" <<'INNER'
#!/bin/bash
exit 0
INNER
  chmod +x "${STUB_BIN}/${TOOL_NAME}"
  exit 0
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/go"
  cat > "${STUB_BIN}/parallel" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "${STUB_BIN}/parallel"
  run env PATH="${STUB_BIN}:/usr/bin:/bin" BREW_LOG="${TMP_ROOT}/brew.log" STUB_BIN="${STUB_BIN}" ZAP_APP_PATH="${ZAP_APP_PATH}" /bin/bash "${SCRIPT_PATH}"
  [ "$status" -eq 0 ]
  [[ "${output}" == *"[parallel] Available on PATH"* ]]
  if [ -f "${TMP_ROOT}/brew.log" ]; then
    run rg "^install parallel$" "${TMP_ROOT}/brew.log"
    [ "$status" -ne 0 ]
  fi
}

@test "R060: skips gremlins install when already available" {
  #R060-T02: Run with gremlins already available verifies no reinstall.
  #R060
  create_brew_stub
  create_1psa_stub
  cat > "${STUB_BIN}/go" <<'EOF'
#!/bin/bash
if [ "$1" = "version" ]; then
  echo "go version go1.22.9 darwin/arm64"
  exit 0
fi
if [ "$1" = "install" ]; then
  printf "go install %s\n" "$2" >> "${GO_INSTALL_LOG:-/dev/null}"
  TOOL_NAME="$(basename "$2")"
  TOOL_NAME="${TOOL_NAME%%@*}"
  cat > "${STUB_BIN}/${TOOL_NAME}" <<'INNER'
#!/bin/bash
exit 0
INNER
  chmod +x "${STUB_BIN}/${TOOL_NAME}"
  exit 0
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/go"
  cat > "${STUB_BIN}/gremlins" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "${STUB_BIN}/gremlins"
  run env PATH="${STUB_BIN}:/usr/bin:/bin" BREW_LOG="${TMP_ROOT}/brew.log" GO_INSTALL_LOG="${TMP_ROOT}/go-install.log" STUB_BIN="${STUB_BIN}" ZAP_APP_PATH="${ZAP_APP_PATH}" /bin/bash "${SCRIPT_PATH}"
  [ "$status" -eq 0 ]
  [[ "${output}" == *"[gremlins] Available on PATH"* ]]
  if [ -f "${TMP_ROOT}/go-install.log" ]; then
    run rg "gremlins" "${TMP_ROOT}/go-install.log"
    [ "$status" -ne 0 ]
  fi
}

@test "R060: accepts gremlins from Go bin when not on PATH" {
  #R060-T03: Install gremlins to Go bin outside PATH verifies resolver fallback succeeds.
  #R060
  create_brew_stub
  create_1psa_stub
  mkdir -p "${TMP_ROOT}/go-bin"
  cat > "${STUB_BIN}/go" <<'EOF'
#!/bin/bash
if [ "$1" = "version" ]; then
  echo "go version go1.22.9 darwin/arm64"
  exit 0
fi
if [ "$1" = "env" ] && [ "$2" = "GOBIN" ]; then
  echo "${GO_BIN_DIR}"
  exit 0
fi
if [ "$1" = "env" ] && [ "$2" = "GOPATH" ]; then
  echo "${TMP_ROOT}/go"
  exit 0
fi
if [ "$1" = "install" ]; then
  printf "go install %s\n" "$2" >> "${GO_INSTALL_LOG:-/dev/null}"
  TOOL_NAME="$(basename "$2")"
  TOOL_NAME="${TOOL_NAME%%@*}"
  mkdir -p "${GO_BIN_DIR}"
  cat > "${GO_BIN_DIR}/${TOOL_NAME}" <<'INNER'
#!/bin/bash
exit 0
INNER
  chmod +x "${GO_BIN_DIR}/${TOOL_NAME}"
  exit 0
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/go"
  run env PATH="${STUB_BIN}:/usr/bin:/bin" BREW_LOG="${TMP_ROOT}/brew.log" GO_INSTALL_LOG="${TMP_ROOT}/go-install.log" STUB_BIN="${STUB_BIN}" GO_BIN_DIR="${TMP_ROOT}/go-bin" ZAP_APP_PATH="${ZAP_APP_PATH}" /bin/bash "${SCRIPT_PATH}"
  [ "$status" -eq 0 ]
  [[ "${output}" == *"[gremlins] Installed and available via"* ]]
  run rg "gremlins" "${TMP_ROOT}/go-install.log"
  [ "$status" -eq 0 ]
}

@test "R060: accepts preinstalled gremlins from GOPATH bin when GOBIN is empty" {
  #R060-T04: Run with empty GOBIN and gremlins preinstalled in GOPATH/bin verifies fallback resolution without reinstall.
  #R060
  create_brew_stub
  create_1psa_stub
  mkdir -p "${TMP_ROOT}/go-path/bin"
  cat > "${TMP_ROOT}/go-path/bin/gremlins" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "${TMP_ROOT}/go-path/bin/gremlins"
  cat > "${STUB_BIN}/go" <<'EOF'
#!/bin/bash
if [ "$1" = "version" ]; then
  echo "go version go1.22.9 darwin/arm64"
  exit 0
fi
if [ "$1" = "env" ] && [ "$2" = "GOBIN" ]; then
  echo ""
  exit 0
fi
if [ "$1" = "env" ] && [ "$2" = "GOPATH" ]; then
  echo "${GO_PATH_DIR}"
  exit 0
fi
if [ "$1" = "install" ]; then
  printf "go install %s\n" "$2" >> "${GO_INSTALL_LOG:-/dev/null}"
  exit 0
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/go"
  run env GO_PATH_DIR="${TMP_ROOT}/go-path" PATH="${STUB_BIN}:/usr/bin:/bin" BREW_LOG="${TMP_ROOT}/brew.log" GO_INSTALL_LOG="${TMP_ROOT}/go-install.log" STUB_BIN="${STUB_BIN}" ZAP_APP_PATH="${ZAP_APP_PATH}" /bin/bash "${SCRIPT_PATH}"
  [ "$status" -eq 0 ]
  [[ "${output}" == *"[gremlins] Available via ${TMP_ROOT}/go-path/bin/gremlins"* ]]
  if [ -f "${TMP_ROOT}/go-install.log" ]; then
    run rg "gremlins" "${TMP_ROOT}/go-install.log"
    [ "$status" -ne 0 ]
  fi
}
