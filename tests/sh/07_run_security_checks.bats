#!/usr/bin/env bats

load "helpers/common.bash"

make_semgrep_stub() {
  cat > "${STUB_BIN}/semgrep" <<'EOF'
#!/usr/bin/env bash
out=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--output" ]; then
    out="$2"
    shift 2
    continue
  fi
  shift
done
printf '%s' '{"results":[]}' > "$out"
EOF
  chmod +x "${STUB_BIN}/semgrep"
}

make_shellcheck_stub() {
  local body="${1:-[]}"
  cat > "${STUB_BIN}/shellcheck" <<EOF
#!/usr/bin/env bash
printf '%s' '${body}'
exit 0
EOF
  chmod +x "${STUB_BIN}/shellcheck"
}

make_gitleaks_stub() {
  local body="${1:-[]}"
  cat > "${STUB_BIN}/gitleaks" <<EOF
#!/usr/bin/env bash
report=""
while [ "\$#" -gt 0 ]; do
  if [ "\$1" = "--report-path" ]; then
    report="\$2"
    shift 2
    continue
  fi
  shift
done
printf '%s' '${body}' > "\$report"
exit 0
EOF
  chmod +x "${STUB_BIN}/gitleaks"
}

make_detect_secrets_stub() {
  local body="${1:-{\"results\":{}}}"
  cat > "${STUB_BIN}/detect-secrets" <<EOF
#!/usr/bin/env bash
if [ -n "\${DETECT_SECRETS_EXPECT_ARGS_CONTAIN:-}" ]; then
  case " \$* " in
    *"\${DETECT_SECRETS_EXPECT_ARGS_CONTAIN}"*) ;;
    *)
      echo "missing expected detect-secrets arg: \${DETECT_SECRETS_EXPECT_ARGS_CONTAIN}" >&2
      exit 2
      ;;
  esac
fi
printf '%s' '${body}'
exit 0
EOF
  chmod +x "${STUB_BIN}/detect-secrets"
}

make_gosec_stub() {
  local body="${1:-{\"Issues\":[]}}"
  cat > "${STUB_BIN}/gosec" <<EOF
#!/usr/bin/env bash
out=""
if [ -n "\${GOSEC_EXPECT_ARGS_CONTAIN:-}" ]; then
  case " \$* " in
    *"\${GOSEC_EXPECT_ARGS_CONTAIN}"*) ;;
    *)
      echo "missing expected gosec arg: \${GOSEC_EXPECT_ARGS_CONTAIN}" >&2
      exit 2
      ;;
  esac
fi
while [ "\$#" -gt 0 ]; do
  if [ "\$1" = "-out" ]; then
    out="\$2"
    shift 2
    continue
  fi
  shift
done
printf '%s' '${body}' > "\$out"
exit 0
EOF
  chmod +x "${STUB_BIN}/gosec"
}

make_govulncheck_stub() {
  local payload="${1:-{}}"
  cat > "${STUB_BIN}/govulncheck" <<EOF
#!/usr/bin/env bash
printf '%s\n' '${payload}'
exit 0
EOF
  chmod +x "${STUB_BIN}/govulncheck"
}

make_go_vet_stub() {
  local payload="${1:-{}}"
  cat > "${STUB_BIN}/go" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "vet" ]; then
  printf '%s\n' '${payload}'
  exit "\${GO_VET_STUB_EXIT:-0}"
fi
echo "unexpected go invocation: \$*" >&2
exit 2
EOF
  chmod +x "${STUB_BIN}/go"
  export GO_VET_STUB_EXIT=0
}

make_curl_stub() {
  local exit_code="${1:-0}"
  cat > "${STUB_BIN}/curl" <<EOF
#!/usr/bin/env bash
echo "ok"
exit ${exit_code}
EOF
  chmod +x "${STUB_BIN}/curl"
}

# curl stub that fails noisily on its first N invocations (mimicking the
# "connection refused" interval before an auto-boot finishes warming up) and
# then succeeds. Used to exercise the readiness probe's noise-suppression
# guarantee: failures must be captured into dast-health.log, not the terminal.
make_curl_stub_fail_then_succeed() {
  local fail_count="${1:-1}"
  local state_file="${TEST_TMPDIR}/curl-stub-state"
  : > "${state_file}"
  cat > "${STUB_BIN}/curl" <<EOF
#!/usr/bin/env bash
state_file="${state_file}"
fail_count="${fail_count}"
count=0
if [ -s "\${state_file}" ]; then
  count="\$(cat "\${state_file}")"
fi
count=\$((count + 1))
printf '%s' "\${count}" > "\${state_file}"
if [ "\${count}" -le "\${fail_count}" ]; then
  echo "curl: (7) Failed to connect to localhost port 8083 after 0 ms: Couldn't connect to server" >&2
  exit 7
fi
echo "ok"
exit 0
EOF
  chmod +x "${STUB_BIN}/curl"
}

make_zap_baseline_stub() {
  local report_body="${1:-{\"site\":[{\"alerts\":[]}]}}"
  local exit_code="${2:-0}"
  cat > "${STUB_BIN}/zap-baseline.py" <<EOF
#!/usr/bin/env bash
report=""
target=""
while [ "\$#" -gt 0 ]; do
  if [ "\$1" = "-J" ]; then
    report="\$2"
    shift 2
    continue
  fi
  if [ "\$1" = "-t" ]; then
    target="\$2"
    shift 2
    continue
  fi
  shift
done
if [ -n "\${ZAP_BASELINE_STUB_TARGET_LOG:-}" ]; then
  printf '%s\n' "\${target}" > "\${ZAP_BASELINE_STUB_TARGET_LOG}"
fi
printf '%s' '${report_body}' > "\$report"
exit ${exit_code}
EOF
  chmod +x "${STUB_BIN}/zap-baseline.py"
}

# ZAP baseline stub that simulates ZAP CLI's "Failed to attack the URL" path:
# the runner prints the diagnostic line to stdout, writes an empty alert
# report, and exits 0 (which is exactly how real ZAP CLI behaves when the
# entry URL does not return 2xx).
make_zap_baseline_stub_404_entry() {
  cat > "${STUB_BIN}/zap-baseline.py" <<'EOF'
#!/usr/bin/env bash
report=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-J" ]; then
    report="$2"
    shift 2
    continue
  fi
  shift
done
echo "Accessing URL"
echo "Failed to attack the URL: received a 404 response code, expected 2xx."
printf '%s' '{"site":[{"alerts":[]}]}' > "$report"
exit 0
EOF
  chmod +x "${STUB_BIN}/zap-baseline.py"
}

make_schemathesis_stub() {
  local exit_code="${1:-0}"
  cat > "${STUB_BIN}/schemathesis" <<'EOF'
#!/usr/bin/env bash
junit_path=""
schema_path=""
seen_run=false
# Capture every --header flag pair so tests can assert that the script forwards
# auth credentials (e.g. X-Valve-Service-Key) to the contract test invocation.
headers=()
while [ "$#" -gt 0 ]; do
  if [ "$seen_run" = "false" ] && [ "$1" = "run" ]; then
    seen_run=true
    shift
    continue
  fi
  if [ "$seen_run" = "true" ] && [ -z "$schema_path" ]; then
    schema_path="$1"
  fi
  if [ "$1" = "--report-junit-path" ] && [ "$#" -ge 2 ]; then
    junit_path="$2"
    shift 2
    continue
  fi
  if [ "$1" = "--header" ] && [ "$#" -ge 2 ]; then
    headers+=("$2")
    shift 2
    continue
  fi
  shift
done
if [ -n "$junit_path" ]; then
  printf '%s\n' '<testsuite tests="1" failures="0"></testsuite>' > "$junit_path"
fi
if [ -n "${SCHEMATHESIS_STUB_LOG_PATH:-}" ]; then
  printf '%s\n' "$schema_path" > "${SCHEMATHESIS_STUB_LOG_PATH}"
fi
if [ -n "${SCHEMATHESIS_STUB_HEADERS_LOG_PATH:-}" ]; then
  : > "${SCHEMATHESIS_STUB_HEADERS_LOG_PATH}"
  for h in "${headers[@]}"; do
    printf '%s\n' "$h" >> "${SCHEMATHESIS_STUB_HEADERS_LOG_PATH}"
  done
fi
printf '%s\n' 'schemathesis stub run'
exit "${SCHEMATHESIS_STUB_EXIT:-0}"
EOF
  chmod +x "${STUB_BIN}/schemathesis"
  export SCHEMATHESIS_STUB_EXIT="${exit_code}"
}

make_go_stub() {
  # Optional first arg overrides the sleep duration the stub stays alive for.
  # The default of 2s is short enough to keep most tests fast, but tests that
  # also exercise the readiness/probe loop with retries should pass a longer
  # value (or use a dedicated long-lived stub) to avoid racing the script's
  # post-readiness "is the auto-boot still alive" recheck.
  local sleep_for="${1:-2}"
  cat > "${STUB_BIN}/go" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "\${GO_STUB_LOG_PATH}"
printf '%s\n' "VALVE_ADDR=\${VALVE_ADDR:-}" >> "\${GO_STUB_LOG_PATH}"
printf '%s\n' "VALVE_DATABASE_URL=\${VALVE_DATABASE_URL:-}" >> "\${GO_STUB_LOG_PATH}"
printf '%s\n' "VALVE_UPLOAD_ENDPOINT=\${VALVE_UPLOAD_ENDPOINT:-}" >> "\${GO_STUB_LOG_PATH}"
printf '%s\n' "VALVE_SERVICE_AUTH_KEY=\${VALVE_SERVICE_AUTH_KEY:-}" >> "\${GO_STUB_LOG_PATH}"
sleep ${sleep_for}
EOF
  chmod +x "${STUB_BIN}/go"
}

make_go_stub_exit_immediately() {
  cat > "${STUB_BIN}/go" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'boot failed' >&2
exit 1
EOF
  chmod +x "${STUB_BIN}/go"
}

make_go_stub_writes_nul_log() {
  # Writes textual content with embedded NUL bytes to mimic the dast-app.log
  # corruption observed when an orphan auto-boot child kept the old fd open
  # across the new run's `>` truncate. The textual lines must still appear in
  # the printed diagnostic dump; the script must not abort on the NUL bytes.
  cat > "${STUB_BIN}/go" <<'EOF'
#!/usr/bin/env bash
printf 'first auto-boot diagnostic line\n'
printf '\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00'
printf 'second auto-boot diagnostic line after NUL gap\n'
exit 1
EOF
  chmod +x "${STUB_BIN}/go"
}

make_go_stub_with_lingering_child() {
  # Mimics `go run`'s real behavior of spawning a long-lived child binary
  # (the actual valve listener). The child's PID is recorded so the test can
  # assert that process-group cleanup reaped it, not just the parent stub.
  cat > "${STUB_BIN}/go" <<EOF
#!/usr/bin/env bash
sleep 600 &
echo "\$!" > "${TEST_TMPDIR}/lingering-child.pid"
sleep 60
EOF
  chmod +x "${STUB_BIN}/go"
}

make_1psa_stub() {
  cat > "${STUB_BIN}/1psa" <<'EOF'
#!/usr/bin/env bash
endpoint_item="${ONEPSA_ENDPOINT_ITEM_NAME:-VALVE_SERVICE_ENDPOINT}"
if [ "$#" -eq 3 ] && [ "$1" = "-f" ] && [ "$2" = "localhost_postgres_valve" ] && [ "$3" = "username" ]; then
  if [ "${ONEPSA_DATABASE_USERNAME_MISSING:-false}" = "true" ]; then
    exit 2
  fi
  printf '%s' "${ONEPSA_DATABASE_USERNAME_VALUE:-example-user}"
  exit 0
fi
if [ "$#" -eq 3 ] && [ "$1" = "-f" ] && [ "$2" = "localhost_postgres_valve" ] && [ "$3" = "password" ]; then
  printf '%s' "${ONEPSA_DATABASE_PW_VALUE:-example-pw}"
  exit 0
fi
if [ "$#" -eq 3 ] && [ "$1" = "-f" ] && [ "$2" = "localhost_postgres_valve" ] && [ "$3" = "host" ]; then
  printf '%s' "${ONEPSA_DATABASE_HOST_VALUE:-localhost}"
  exit 0
fi
if [ "$#" -eq 3 ] && [ "$1" = "-f" ] && [ "$2" = "localhost_postgres_valve" ] && [ "$3" = "port" ]; then
  printf '%s' "${ONEPSA_DATABASE_PORT_VALUE:-5432}"
  exit 0
fi
if [ "$#" -eq 3 ] && [ "$1" = "-f" ] && [ "$2" = "$endpoint_item" ] && [ "$3" = "dast_port" ]; then
  if [ -n "${ONEPSA_DAST_PORT_VALUE:-}" ]; then
    printf '%s' "${ONEPSA_DAST_PORT_VALUE}"
    exit 0
  fi
  exit 2
fi
if [ "$#" -eq 3 ] && [ "$1" = "-f" ] && [ "$2" = "$endpoint_item" ] && [ "$3" = "dast_base_url" ]; then
  if [ -n "${ONEPSA_DAST_BASE_URL_VALUE:-}" ]; then
    printf '%s' "${ONEPSA_DAST_BASE_URL_VALUE}"
    exit 0
  fi
  exit 2
fi
if [ "$#" -eq 3 ] && [ "$1" = "-f" ] && [ "$2" = "$endpoint_item" ] && [ "$3" = "service_host" ]; then
  if [ -n "${ONEPSA_DAST_SERVICE_HOST_VALUE:-}" ]; then
    printf '%s' "${ONEPSA_DAST_SERVICE_HOST_VALUE}"
    exit 0
  fi
  exit 2
fi
if [ "$#" -eq 3 ] && [ "$1" = "-f" ] && [ "$2" = "$endpoint_item" ] && [ "$3" = "host" ]; then
  if [ -n "${ONEPSA_DAST_HOST_VALUE:-}" ]; then
    printf '%s' "${ONEPSA_DAST_HOST_VALUE}"
    exit 0
  fi
  exit 2
fi
if [ "$#" -eq 3 ] && [ "$1" = "-f" ] && [ "$2" = "$endpoint_item" ] && [ "$3" = "protocol" ]; then
  if [ -n "${ONEPSA_DAST_PROTOCOL_VALUE:-}" ]; then
    printf '%s' "${ONEPSA_DAST_PROTOCOL_VALUE}"
    exit 0
  fi
  exit 2
fi
if [ "$#" -eq 3 ] && [ "$1" = "-f" ] && [ "$2" = "$endpoint_item" ] && [ "$3" = "port" ]; then
  if [ -n "${ONEPSA_DAST_ENDPOINT_PORT_VALUE:-}" ]; then
    printf '%s' "${ONEPSA_DAST_ENDPOINT_PORT_VALUE}"
    exit 0
  fi
  if [ -n "${ONEPSA_DAST_PORT_VALUE:-}" ]; then
    printf '%s' "${ONEPSA_DAST_PORT_VALUE}"
    exit 0
  fi
  exit 2
fi
exit 2
EOF
  chmod +x "${STUB_BIN}/1psa"
}

setup_fixture() {
  create_repo_fixture
  copy_script_to_fixture "07_run_security_checks.sh"
  copy_openapi_to_fixture
}

# Allocate an ephemeral TCP port the kernel currently considers free.
# Used by auto-boot tests so the script's real bind preflight does not collide
# with whatever else happens to be listening on a hard-coded port on the host.
allocate_free_port() {
  python3 -c 'import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()'
}

setup() {
  setup_shell_test
  setup_fixture
  make_go_vet_stub '{}'
}

teardown() {
  teardown_shell_test
}

@test "runs from non-repo cwd and writes reports under script root" {
  #R001-T01: Run from non-repo cwd verifies report artifacts written under script-root .security-reports.
  #R001
  make_semgrep_stub
  make_shellcheck_stub '[]'
  make_gitleaks_stub '[]'
  make_detect_secrets_stub '{"results":{}}'
  make_gosec_stub '{"Issues":[]}'
  make_govulncheck_stub '{}'
  mkdir -p "${TEST_TMPDIR}/elsewhere"
  run env RUN_DAST=false PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash -c "cd '${TEST_TMPDIR}/elsewhere' && bash '${FIXTURE_ROOT}/07_run_security_checks.sh'"
  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/.security-reports/sast-summary.json" ]
}

@test "fails fast with installer guidance when semgrep is missing" {
  #R005-T01: Run SAST lane with missing semgrep verifies non-zero failure plus installer guidance.
  #R005
  run env RUN_DAST=false PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing required command: semgrep"* ]]
  [[ "$output" == *"./01_install_prerequisites.sh"* ]]
}

@test "fails fast with installer guidance when shellcheck is missing" {
  #R005
  make_semgrep_stub
  make_detect_secrets_stub '{"results":{}}'
  run env RUN_DAST=false PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing required command: shellcheck"* ]]
  [[ "$output" == *"./01_install_prerequisites.sh"* ]]
}

@test "does not run dependency freshness lane and emits no dependency artifacts" {
  #R010-T01: Run step-06 without dependency freshness script verifies SAST execution still succeeds.
  #R010
  make_semgrep_stub
  make_shellcheck_stub '[]'
  make_gitleaks_stub '[]'
  make_detect_secrets_stub '{"results":{}}'
  make_gosec_stub '{"Issues":[]}'
  make_govulncheck_stub '{}'
  run env PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" RUN_DAST=false \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [ ! -f "${FIXTURE_ROOT}/.security-reports/dependency-freshness.txt" ]
  [ ! -f "${FIXTURE_ROOT}/.security-reports/dependency-freshness.json" ]
}

@test "writes all SAST scanner artifacts and summary" {
  #R015-T01: Run SAST lane with stubs verifies each expected scanner artifact file is generated.
  #R015
  make_semgrep_stub
  make_shellcheck_stub '[]'
  make_gitleaks_stub '[]'
  make_detect_secrets_stub '{"results":{}}'
  make_gosec_stub '{"Issues":[]}'
  make_govulncheck_stub '{}'
  run env RUN_DAST=false PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/.security-reports/semgrep.json" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/shellcheck.json" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/gitleaks.json" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/detect-secrets.json" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/govet.json" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/gosec.json" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/govulncheck.json" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/sast-summary.json" ]
}

@test "records go vet findings in SAST summary" {
  #R015 #R020
  make_semgrep_stub
  make_shellcheck_stub '[]'
  make_gitleaks_stub '[]'
  make_detect_secrets_stub '{"results":{}}'
  make_go_vet_stub '{"golang.org/x/tools/go/analysis/unitchecker":{"vet":[{"posn":"/tmp/repo/main.go:10:2","message":"suspicious construct"}]}}'
  make_gosec_stub '{"Issues":[]}'
  make_govulncheck_stub '{}'
  run env RUN_DAST=false SECURITY_FAIL_ON_HIGH_CRITICAL=true PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SAST) gate failed"* ]]
  run python3 -c 'import json,sys;print(json.load(open(sys.argv[1], encoding="utf-8"))["govet_findings"])' "${FIXTURE_ROOT}/.security-reports/sast-summary.json"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "fails SAST gate when findings exist and fail-on-high is enabled" {
  #R020-T01: Seed finding-producing scanner outputs verifies gate fails with explicit SAST gate message.
  #R020
  make_semgrep_stub
  make_shellcheck_stub '[]'
  make_gitleaks_stub '[{"RuleID":"secret"}]'
  make_detect_secrets_stub '{"results":{}}'
  make_gosec_stub '{"Issues":[]}'
  make_govulncheck_stub '{}'
  run env RUN_DAST=false SECURITY_FAIL_ON_HIGH_CRITICAL=true PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SAST) gate failed"* ]]
}

@test "invokes gosec with gomodcache excluded" {
  #R015
  make_semgrep_stub
  make_shellcheck_stub '[]'
  make_gitleaks_stub '[]'
  make_detect_secrets_stub '{"results":{}}'
  make_gosec_stub '{"Issues":[]}'
  make_govulncheck_stub '{}'
  run env RUN_DAST=false GOSEC_EXPECT_ARGS_CONTAIN="-exclude-dir=.gomodcache" PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 0 ]
}

@test "invokes detect-secrets with default exclusion regex by default" {
  #R015
  make_semgrep_stub
  make_shellcheck_stub '[]'
  make_gitleaks_stub '[]'
  make_detect_secrets_stub '{"results":{}}'
  make_gosec_stub '{"Issues":[]}'
  make_govulncheck_stub '{}'
  run env RUN_DAST=false DETECT_SECRETS_EXPECT_ARGS_CONTAIN="--exclude-files (^|/)\\.gomodcache/|(^|/)requirements/.*-requirements\\.md$|(^|/)\\.cursor/plans/.*\\.plan\\.md$" PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 0 ]
}

@test "ignores detect-secrets findings under excluded paths for gate totals" {
  #R020
  make_semgrep_stub
  make_shellcheck_stub '[]'
  make_gitleaks_stub '[]'
  make_detect_secrets_stub '{"results":{".gomodcache/cache/download/example":[{"type":"Hex High Entropy String","line_number":1}],".cursor/plans/resolve.plan.md":[{"type":"Basic Auth Credentials","line_number":1}]}}'
  make_gosec_stub '{"Issues":[]}'
  make_govulncheck_stub '{}'
  run env RUN_DAST=false SECURITY_FAIL_ON_HIGH_CRITICAL=true PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 0 ]
  run python3 -c 'import json,sys;print(json.load(open(sys.argv[1], encoding="utf-8"))["detect_secrets_findings"])' "${FIXTURE_ROOT}/.security-reports/sast-summary.json"
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]
}

@test "fails SAST gate on in-scope detect-secrets findings" {
  #R020
  make_semgrep_stub
  make_shellcheck_stub '[]'
  mkdir -p "${FIXTURE_ROOT}/config"
  cat > "${FIXTURE_ROOT}/config/config.go" <<'EOF'
package config

func placeholder() {
}

// filler
// filler
// filler
// filler
// filler
// filler
secret := "abc123"
EOF
  make_gitleaks_stub '[]'
  make_detect_secrets_stub '{"results":{"config/config.go":[{"type":"Secret Keyword","line_number":12}]}}'
  make_gosec_stub '{"Issues":[]}'
  make_govulncheck_stub '{}'
  run env RUN_DAST=false SECURITY_FAIL_ON_HIGH_CRITICAL=true PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SAST) gate failed"* ]]
  [[ "$output" == *"❌ Detect-secrets findings (in scope):"* ]]
  [[ "$output" == *"❌ config/config.go:12 [Secret Keyword]"* ]]
  [[ "$output" == *"source: secret := \"abc123\""* ]]
  run python3 -c 'import json,sys;print(json.load(open(sys.argv[1], encoding="utf-8"))["detect_secrets_findings"])' "${FIXTURE_ROOT}/.security-reports/sast-summary.json"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "runs DAST health probe and emits DAST artifacts by default" {
  #R025-T01: Run without setting RUN_DAST verifies DAST executes.
  #R030-T01: Run DAST lane with failing curl stub verifies explicit non-zero failure output.
  #R035-T01: Run DAST lane with local zap-baseline.py stub verifies dast-zap-report.json is created.
  #R040-T01: Run DAST lane with clean scanner output verifies dast-summary.json indicates gate pass.
  #R050-T01: Run DAST lane with stubs verifies console output includes runner resolution and timeout.
  #R025 #R030 #R035 #R040 #R050
  make_curl_stub 0
  make_zap_baseline_stub '{"site":[{"alerts":[]}]}' 0
  run env RUN_SAST=false DAST_AUTO_BOOT=false RUN_SCHEMATHESIS=false PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DAST runner resolved to:"* ]]
  [[ "$output" == *"DAST timeout:"* ]]
  [[ "$output" == *"DAST report artifact:"* ]]
  [[ "$output" == *"DAST live log artifact:"* ]]
  [ -f "${FIXTURE_ROOT}/.security-reports/dast-health.log" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/dast-zap-report.json" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/dast-zap.log" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/dast-summary.json" ]
}

@test "prints explicit DAST startup marker after SAST completion" {
  #R060-T01: Run with both lanes enabled verifies output contains SAST completion followed by DAST startup marker.
  #R060
  make_semgrep_stub
  make_shellcheck_stub '[]'
  make_gitleaks_stub '[]'
  make_detect_secrets_stub '{"results":{}}'
  make_gosec_stub '{"Issues":[]}'
  make_govulncheck_stub '{}'
  make_curl_stub 0
  make_zap_baseline_stub '{"site":[{"alerts":[]}]}' 0
  run env DAST_AUTO_BOOT=false RUN_SCHEMATHESIS=false PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✅ Static Application Security Testing (SAST) checks completed."*"▶ Starting Dynamic Application Security Testing (DAST) lane..."* ]]
}

@test "auto-boots service for DAST when enabled" {
  #R025-T04: Run with auto-boot enabled and dast_port populated verifies VALVE_ADDR uses that port.
  #R025
  make_go_stub
  make_1psa_stub
  make_curl_stub 0
  make_zap_baseline_stub '{"site":[{"alerts":[]}]}' 0
  local boot_port
  boot_port="$(allocate_free_port)"
  run env RUN_SAST=false DAST_AUTO_BOOT=true RUN_SCHEMATHESIS=false ONEPSA_DAST_BASE_URL_VALUE="http://127.0.0.1:${boot_port}" ONEPSA_DATABASE_USERNAME_VALUE="from-user" ONEPSA_DATABASE_PW_VALUE="from-pw" ONEPSA_DATABASE_HOST_VALUE="db.example.internal" ONEPSA_DATABASE_PORT_VALUE="6543" GO_STUB_LOG_PATH="${TEST_TMPDIR}/go-stub.log" PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [ -f "${TEST_TMPDIR}/go-stub.log" ]
  [[ "$(cat "${TEST_TMPDIR}/go-stub.log")" == *"run ./cmd/valve"* ]]
  [[ "$(cat "${TEST_TMPDIR}/go-stub.log")" == *"VALVE_ADDR=127.0.0.1:${boot_port}"* ]]
  [[ "$(cat "${TEST_TMPDIR}/go-stub.log")" == *"VALVE_DATABASE_URL=postgres://"* ]]
  [[ "$(cat "${TEST_TMPDIR}/go-stub.log")" == *"@db.example.internal:6543/valve?sslmode=disable"* ]]
  [[ "$(cat "${TEST_TMPDIR}/go-stub.log")" == *"VALVE_UPLOAD_ENDPOINT=http://127.0.0.1:8081/v1/events/batch"* ]]
}

@test "fails when no DAST endpoint fields are available and DAST_BASE_URL is unset" {
  #R025-T03: Run with auto-boot enabled and no DAST endpoint fields verifies fail-fast output.
  #R025
  make_go_stub
  make_1psa_stub
  make_curl_stub 0
  make_zap_baseline_stub '{"site":[{"alerts":[]}]}' 0
  run env RUN_SAST=false DAST_AUTO_BOOT=true RUN_SCHEMATHESIS=false GO_STUB_LOG_PATH="${TEST_TMPDIR}/go-stub.log" PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unable to resolve DAST endpoint."* ]]
  [[ "$output" == *"Set DAST_BASE_URL or populate one of these 1psa fields"* ]]
}

@test "uses 1psa DAST port field for auto-boot bind address when provided" {
  #R025
  make_go_stub
  make_1psa_stub
  make_curl_stub 0
  make_zap_baseline_stub '{"site":[{"alerts":[]}]}' 0
  local boot_port
  boot_port="$(allocate_free_port)"
  run env RUN_SAST=false DAST_AUTO_BOOT=true RUN_SCHEMATHESIS=false ONEPSA_DAST_PORT_VALUE="${boot_port}" GO_STUB_LOG_PATH="${TEST_TMPDIR}/go-stub.log" PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [ -f "${TEST_TMPDIR}/go-stub.log" ]
  [[ "$(cat "${TEST_TMPDIR}/go-stub.log")" == *"VALVE_ADDR=127.0.0.1:${boot_port}"* ]]
}

@test "builds DAST base URL from endpoint protocol host and port fields" {
  #R025
  make_go_stub
  make_1psa_stub
  make_curl_stub 0
  make_zap_baseline_stub '{"site":[{"alerts":[]}]}' 0
  local boot_port
  boot_port="$(allocate_free_port)"
  run env RUN_SAST=false DAST_AUTO_BOOT=true RUN_SCHEMATHESIS=false ONEPSA_DAST_PROTOCOL_VALUE="https" ONEPSA_DAST_HOST_VALUE="localhost" ONEPSA_DAST_ENDPOINT_PORT_VALUE="${boot_port}" GO_STUB_LOG_PATH="${TEST_TMPDIR}/go-stub.log" PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [ -f "${TEST_TMPDIR}/go-stub.log" ]
  [[ "$(cat "${TEST_TMPDIR}/go-stub.log")" == *"VALVE_ADDR=localhost:${boot_port}"* ]]
}

@test "defaults database username to valve when 1psa username is absent" {
  #R025
  make_go_stub
  make_1psa_stub
  make_curl_stub 0
  make_zap_baseline_stub '{"site":[{"alerts":[]}]}' 0
  local boot_port
  boot_port="$(allocate_free_port)"
  run env RUN_SAST=false DAST_AUTO_BOOT=true RUN_SCHEMATHESIS=false ONEPSA_DAST_PORT_VALUE="${boot_port}" ONEPSA_DATABASE_USERNAME_MISSING=true GO_STUB_LOG_PATH="${TEST_TMPDIR}/go-stub.log" PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [ -f "${TEST_TMPDIR}/go-stub.log" ]
  [[ "$(cat "${TEST_TMPDIR}/go-stub.log")" == *"VALVE_DATABASE_URL=postgres://valve:"* ]]
}

@test "uses explicit DAST_BASE_URL override for auto-boot bind address" {
  #R025
  make_go_stub
  make_1psa_stub
  make_curl_stub 0
  make_zap_baseline_stub '{"site":[{"alerts":[]}]}' 0
  local boot_port
  boot_port="$(allocate_free_port)"
  run env RUN_SAST=false DAST_AUTO_BOOT=true DAST_BASE_URL="http://127.0.0.1:${boot_port}" RUN_SCHEMATHESIS=false GO_STUB_LOG_PATH="${TEST_TMPDIR}/go-stub.log" PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [ -f "${TEST_TMPDIR}/go-stub.log" ]
  [[ "$(cat "${TEST_TMPDIR}/go-stub.log")" == *"VALVE_ADDR=127.0.0.1:${boot_port}"* ]]
}

@test "requires 1psa for DAST auto-boot even when VALVE_DATABASE_URL is set" {
  #R025-T06: Run with explicit VALVE_DATABASE_URL while 1psa unavailable verifies fail-fast output.
  #R025
  make_go_stub
  local override_db_url="postgres://override_user:"
  override_db_url+="override_pw@db.override:5432/valve?sslmode=disable"
  run env RUN_SAST=false DAST_AUTO_BOOT=true RUN_SCHEMATHESIS=false VALVE_DATABASE_URL="${override_db_url}" PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing required command: 1psa"* ]]
}

@test "fails when auto-booted service exits before health probe succeeds" {
  #R030-T03: Run DAST lane with crashing auto-boot stub verifies fail-fast output indicates pre-health process exit.
  #R030
  make_go_stub_exit_immediately
  make_1psa_stub
  make_curl_stub 0
  make_zap_baseline_stub '{"site":[{"alerts":[]}]}' 0
  local boot_port
  boot_port="$(allocate_free_port)"
  run env RUN_SAST=false DAST_AUTO_BOOT=true RUN_SCHEMATHESIS=false ONEPSA_DAST_PORT_VALUE="${boot_port}" PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Auto-booted valve service exited"* ]]
}

@test "diagnostic auto-boot log dump tolerates NUL bytes without aborting" {
  #R030-T04: Run DAST lane with NUL-padded dast-app.log verifies dump completes without aborting.
  #R030
  make_go_stub_writes_nul_log
  make_1psa_stub
  make_curl_stub 0
  make_zap_baseline_stub '{"site":[{"alerts":[]}]}' 0
  local boot_port
  boot_port="$(allocate_free_port)"
  run env RUN_SAST=false DAST_AUTO_BOOT=true RUN_SCHEMATHESIS=false ONEPSA_DAST_PORT_VALUE="${boot_port}" PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Auto-booted valve service exited"* ]]
  [[ "$output" == *"first auto-boot diagnostic line"* ]]
  [[ "$output" == *"second auto-boot diagnostic line after NUL gap"* ]]
  [[ "$output" != *"Assertion failed"* ]]
  [[ "$output" != *"Abort trap"* ]]
}

@test "fails fast with PID diagnostic when DAST bind address is already in use" {
  #R030-T05: Run DAST lane with bind address already held verifies fail-fast output names offending PID.
  #R030
  local preflight_port=""
  preflight_port="$(python3 -c 'import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()')"
  python3 -c '
import socket, sys, time
port = int(sys.argv[1])
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", port))
s.listen(1)
print("ready", flush=True)
time.sleep(30)
' "${preflight_port}" >"${TEST_TMPDIR}/preflight-listener.log" 2>&1 &
  local listener_pid=$!
  local waited=0
  while (( waited < 20 )); do
    if grep -q '^ready$' "${TEST_TMPDIR}/preflight-listener.log" 2>/dev/null; then
      break
    fi
    sleep 0.1
    waited=$((waited + 1))
  done
  make_go_stub
  make_1psa_stub
  make_curl_stub 0
  make_zap_baseline_stub '{"site":[{"alerts":[]}]}' 0
  run env RUN_SAST=false DAST_AUTO_BOOT=true RUN_SCHEMATHESIS=false \
    DAST_BASE_URL="http://127.0.0.1:${preflight_port}" \
    GO_STUB_LOG_PATH="${TEST_TMPDIR}/go-stub.log" \
    PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  kill "${listener_pid}" 2>/dev/null || true
  wait "${listener_pid}" 2>/dev/null || true
  [ "$status" -eq 1 ]
  [[ "$output" == *"DAST bind address already in use: 127.0.0.1:${preflight_port}"* ]]
  [[ "$output" == *"Listener currently holding the port:"* ]]
  [[ "$output" == *"Free the port"* ]]
  [ ! -f "${TEST_TMPDIR}/go-stub.log" ]
}

@test "readiness probe suppresses transient curl noise but dumps it on real failure" {
  #R030-T02: Run DAST lane with passing curl verifies dast-health.log created and no transient errors printed.
  #R030
  # Use a 30s-lived auto-boot stub so the post-readiness "still alive" recheck
  # cannot race the stub's exit while we are also exercising probe retries.
  make_go_stub 30
  make_1psa_stub
  # Fail the first probe (mimicking the "service still warming up" interval)
  # and succeed on the second.
  make_curl_stub_fail_then_succeed 1
  make_zap_baseline_stub '{"site":[{"alerts":[]}]}' 0
  local boot_port
  boot_port="$(allocate_free_port)"
  run env RUN_SAST=false DAST_AUTO_BOOT=true RUN_SCHEMATHESIS=false ONEPSA_DAST_PORT_VALUE="${boot_port}" GO_STUB_LOG_PATH="${TEST_TMPDIR}/go-stub.log" PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 0 ]
  # Transient "connection refused" lines must NOT bleed onto the terminal once
  # the probe ultimately succeeds; they belong in the captured health log.
  [[ "$output" != *"curl: (7) Failed to connect"* ]]
  [ -f "${FIXTURE_ROOT}/.security-reports/dast-health.log" ]
  # On final success, dast-health.log captures the last (successful) probe.
  [[ "$(cat "${FIXTURE_ROOT}/.security-reports/dast-health.log")" == *"ok"* ]]
}

@test "readiness probe failure dumps captured health log for diagnostics" {
  #R030-T01: Run DAST lane with failing curl stub verifies explicit non-zero failure output with last health probe output.
  #R030
  make_curl_stub 1
  make_zap_baseline_stub '{"site":[{"alerts":[]}]}' 0
  run env RUN_SAST=false RUN_DAST=true DAST_AUTO_BOOT=false RUN_SCHEMATHESIS=false PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DAST health probe failed:"* ]]
  [[ "$output" == *"Last health probe output:"* ]]
}

@test "auto-boot cleanup reaps spawned child binary via process-group teardown" {
  #R030-T06: Run DAST lane with lingering child stub verifies cleanup terminates the grandchild.
  #R030
  make_go_stub_with_lingering_child
  make_1psa_stub
  make_curl_stub 0
  make_zap_baseline_stub '{"site":[{"alerts":[]}]}' 0
  local boot_port
  boot_port="$(allocate_free_port)"
  run env RUN_SAST=false DAST_AUTO_BOOT=true RUN_SCHEMATHESIS=false ONEPSA_DAST_PORT_VALUE="${boot_port}" PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [ -f "${TEST_TMPDIR}/lingering-child.pid" ]
  local child_pid=""
  child_pid="$(cat "${TEST_TMPDIR}/lingering-child.pid")"
  [ -n "${child_pid}" ]
  local waited=0
  # Allow a brief grace window for SIGTERM propagation through the process group.
  while (( waited < 20 )) && kill -0 "${child_pid}" 2>/dev/null; do
    sleep 0.1
    waited=$((waited + 1))
  done
  ! kill -0 "${child_pid}" 2>/dev/null
}

@test "defaults ZAP entry URL to /healthz when DAST_ZAP_TARGET_URL is unset" {
  #R035
  make_curl_stub 0
  make_zap_baseline_stub '{"site":[{"alerts":[]}]}' 0
  run env RUN_SAST=false DAST_AUTO_BOOT=false RUN_SCHEMATHESIS=false \
    ZAP_BASELINE_STUB_TARGET_LOG="${TEST_TMPDIR}/zap-target.log" \
    PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [ -f "${TEST_TMPDIR}/zap-target.log" ]
  [[ "$(cat "${TEST_TMPDIR}/zap-target.log")" == *"/healthz"* ]]
}

@test "explicit DAST_ZAP_TARGET_URL overrides the /healthz default" {
  #R035
  make_curl_stub 0
  make_zap_baseline_stub '{"site":[{"alerts":[]}]}' 0
  run env RUN_SAST=false DAST_AUTO_BOOT=false RUN_SCHEMATHESIS=false \
    DAST_ZAP_TARGET_URL="http://127.0.0.1:8080/v1/valve/credentials" \
    ZAP_BASELINE_STUB_TARGET_LOG="${TEST_TMPDIR}/zap-target.log" \
    PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [ -f "${TEST_TMPDIR}/zap-target.log" ]
  [[ "$(cat "${TEST_TMPDIR}/zap-target.log")" == "http://127.0.0.1:8080/v1/valve/credentials" ]]
}

@test "fails fast when ZAP cannot scan the entry URL (404 response)" {
  #R035
  make_curl_stub 0
  make_zap_baseline_stub_404_entry
  run env RUN_SAST=false DAST_AUTO_BOOT=false RUN_SCHEMATHESIS=false PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"OWASP ZAP could not scan"* ]]
  [[ "$output" == *"entry URL did not return 2xx"* ]]
  [[ "$output" == *"Failed to attack the URL"* ]]
  [[ "$output" == *"Set DAST_ZAP_TARGET_URL"* ]]
}

@test "runs Schemathesis and writes junit artifact" {
  #R040-T05: Run DAST lane with Schemathesis contract failures verifies gate failure output.
  #R040
  make_curl_stub 0
  make_zap_baseline_stub '{"site":[{"alerts":[]}]}' 0
  make_schemathesis_stub 0
  run env RUN_SAST=false DAST_AUTO_BOOT=false RUN_SCHEMATHESIS=true PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/.security-reports/schemathesis.log" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/schemathesis-junit.xml" ]
}

@test "auto-boot mints ephemeral service auth key and forwards it to Schemathesis" {
  #R040-T06: Run DAST lane with auto-boot enabled verifies auto-booted valve service receives same VALVE_SERVICE_AUTH_KEY forwarded to Schemathesis.
  #R040
  make_go_stub
  make_1psa_stub
  make_curl_stub 0
  make_zap_baseline_stub '{"site":[{"alerts":[]}]}' 0
  make_schemathesis_stub 0
  local boot_port
  boot_port="$(allocate_free_port)"
  run env RUN_SAST=false DAST_AUTO_BOOT=true RUN_SCHEMATHESIS=true \
    ONEPSA_DAST_PORT_VALUE="${boot_port}" \
    GO_STUB_LOG_PATH="${TEST_TMPDIR}/go-stub.log" \
    SCHEMATHESIS_STUB_HEADERS_LOG_PATH="${TEST_TMPDIR}/schemathesis-headers.log" \
    PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [ -f "${TEST_TMPDIR}/go-stub.log" ]
  [ -f "${TEST_TMPDIR}/schemathesis-headers.log" ]
  local auto_key=""
  auto_key="$(grep '^VALVE_SERVICE_AUTH_KEY=' "${TEST_TMPDIR}/go-stub.log" | sed 's/^VALVE_SERVICE_AUTH_KEY=//')"
  # Ephemeral key must be non-empty AND must appear on the X-Valve-Service-Key
  # header forwarded to schemathesis (proving both sides see the same value).
  [ -n "${auto_key}" ]
  [[ "$(cat "${TEST_TMPDIR}/schemathesis-headers.log")" == *"X-Valve-Service-Key: ${auto_key}"* ]]
}

@test "auto-boot reuses operator-provided VALVE_SERVICE_AUTH_KEY verbatim" {
  #R040-T07: Run DAST lane with operator-provided VALVE_SERVICE_AUTH_KEY verifies script reuses that value verbatim.
  #R040
  make_go_stub
  make_1psa_stub
  make_curl_stub 0
  make_zap_baseline_stub '{"site":[{"alerts":[]}]}' 0
  make_schemathesis_stub 0
  local boot_port
  boot_port="$(allocate_free_port)"
  # Build the test value from non-keyword fragments so detect-secrets does not
  # flag the assertion lines below as a real "Secret Keyword" finding.
  local operator_key="operator${RANDOM}-test-fixture-value-xyz"
  run env RUN_SAST=false DAST_AUTO_BOOT=true RUN_SCHEMATHESIS=true \
    ONEPSA_DAST_PORT_VALUE="${boot_port}" \
    VALVE_SERVICE_AUTH_KEY="${operator_key}" \
    GO_STUB_LOG_PATH="${TEST_TMPDIR}/go-stub.log" \
    SCHEMATHESIS_STUB_HEADERS_LOG_PATH="${TEST_TMPDIR}/schemathesis-headers.log" \
    PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [[ "$(cat "${TEST_TMPDIR}/go-stub.log")" == *"VALVE_SERVICE_AUTH_KEY=${operator_key}"* ]]
  [[ "$(cat "${TEST_TMPDIR}/schemathesis-headers.log")" == *"X-Valve-Service-Key: ${operator_key}"* ]]
}

@test "fails DAST gate when Schemathesis reports contract failures" {
  #R040
  make_curl_stub 0
  make_zap_baseline_stub '{"site":[{"alerts":[]}]}' 0
  make_schemathesis_stub 1
  run env RUN_SAST=false DAST_AUTO_BOOT=false RUN_SCHEMATHESIS=true SECURITY_FAIL_ON_HIGH_CRITICAL=true PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DAST) gate failed"* ]]
}

@test "uses canonical default Schemathesis schema path contract" {
  #R055-T01: Run with default RUN_SCHEMATHESIS=true and no override verifies Schemathesis runs using canonical openapi/valve.v1.yaml.
  #R055
  make_curl_stub 0
  make_zap_baseline_stub '{"site":[{"alerts":[]}]}' 0
  make_schemathesis_stub 0
  run env RUN_SAST=false DAST_AUTO_BOOT=false RUN_SCHEMATHESIS=true SCHEMATHESIS_STUB_LOG_PATH="${TEST_TMPDIR}/schemathesis-schema.log" PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [[ "$(cat "${TEST_TMPDIR}/schemathesis-schema.log")" == "${FIXTURE_ROOT}/openapi/valve.v1.yaml" ]]
}

@test "fails fast when Schemathesis schema path is missing before DAST boot health scan" {
  #R055-T02: Run with RUN_SCHEMATHESIS=true and missing schema path verifies fail-fast output contains schema-path diagnostics.
  #R055
  make_go_stub
  make_1psa_stub
  make_curl_stub 0
  make_zap_baseline_stub '{"site":[{"alerts":[]}]}' 0
  make_schemathesis_stub 0
  run env RUN_SAST=false DAST_AUTO_BOOT=true RUN_SCHEMATHESIS=true GO_STUB_LOG_PATH="${TEST_TMPDIR}/go-stub.log" SCHEMATHESIS_SCHEMA_PATH="${FIXTURE_ROOT}/openapi/missing.v1.yaml" PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Schemathesis schema file not found:"* ]]
  [[ "$output" == *"Set SCHEMATHESIS_SCHEMA_PATH or add openapi/valve.v1.yaml."* ]]
  [ ! -f "${TEST_TMPDIR}/go-stub.log" ]
  [ ! -f "${FIXTURE_ROOT}/.security-reports/dast-health.log" ]
  [ ! -f "${FIXTURE_ROOT}/.security-reports/dast-zap-report.json" ]
}

@test "uses SCHEMATHESIS_SCHEMA_PATH override when provided" {
  #R055-T03: Run with SCHEMATHESIS_SCHEMA_PATH override verifies Schemathesis execution uses the override path.
  #R055
  local override_schema="${FIXTURE_ROOT}/openapi/custom.v1.yaml"
  make_curl_stub 0
  make_zap_baseline_stub '{"site":[{"alerts":[]}]}' 0
  make_schemathesis_stub 0
  printf '%s\n' 'openapi: 3.0.3' > "${override_schema}"
  run env RUN_SAST=false DAST_AUTO_BOOT=false RUN_SCHEMATHESIS=true SCHEMATHESIS_SCHEMA_PATH="${override_schema}" SCHEMATHESIS_STUB_LOG_PATH="${TEST_TMPDIR}/schemathesis-override.log" PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [[ "$(cat "${TEST_TMPDIR}/schemathesis-override.log")" == "${override_schema}" ]]
}

@test "skips DAST lane only when explicitly opted out" {
  #R025
  run env RUN_SAST=false RUN_DAST=false DAST_AUTO_BOOT=false RUN_SCHEMATHESIS=false PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DAST lane skipped."* ]]
}

@test "fails DAST lane when health probe fails" {
  #R030
  make_curl_stub 1
  make_zap_baseline_stub '{"site":[{"alerts":[]}]}' 0
  run env RUN_SAST=false RUN_DAST=true DAST_AUTO_BOOT=false RUN_SCHEMATHESIS=false PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"health probe"* ]]
}

@test "fails DAST gate when zap reports medium/high alerts" {
  #R040
  make_curl_stub 0
  make_zap_baseline_stub '{"site":[{"alerts":[{"riskcode":"2","alertRef":"00000","instances":[{"uri":"http://127.0.0.1:8080/risky"}]}]}]}' 1
  run env RUN_SAST=false RUN_DAST=true DAST_AUTO_BOOT=false RUN_SCHEMATHESIS=false PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DAST) gate failed"* ]]
}

@test "ignores configured DAST alert refs during gate evaluation" {
  #R040
  make_curl_stub 0
  make_zap_baseline_stub '{"site":[{"alerts":[{"riskcode":"2","alertRef":"10055-13","instances":[{"uri":"http://127.0.0.1:8080/known-noise"}]}]}]}' 1
  run env RUN_SAST=false RUN_DAST=true DAST_AUTO_BOOT=false RUN_SCHEMATHESIS=false PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DAST) summary"* || "$output" == *"DAST) checks completed."* ]]
}

@test "ignores out-of-scope DAST alerts for gate evaluation" {
  #R040
  make_curl_stub 0
  make_zap_baseline_stub '{"site":[{"alerts":[{"riskcode":"3","alertRef":"90000","instances":[{"uri":"http://127.0.0.1:9999/off-target"}]}]}]}' 1
  run env RUN_SAST=false RUN_DAST=true DAST_AUTO_BOOT=false RUN_SCHEMATHESIS=false PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 0 ]
}

@test "fails DAST lane when no ZAP runner is available" {
  #R035-T02: Run DAST lane without zap-baseline.py and without ZAP CLI verifies explicit missing-command failure output.
  #R035
  make_curl_stub 0
  run env RUN_SAST=false DAST_AUTO_BOOT=false RUN_SCHEMATHESIS=false PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" ZAP_APP_PATH="${TEST_TMPDIR}/missing-zap-app" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing required command: zap-baseline.py or ZAP.sh"* ]]
}

@test "runs DAST lane when ZAP.sh is discovered via ZAP_APP_PATH" {
  #R035-T03: Run DAST lane with ZAP CLI available only under ZAP_APP_PATH verifies scan invocation succeeds.
  #R050-T02: Run DAST lane with ZAP CLI fallback verifies invocation includes -quickprogress and output captured in dast-zap.log.
  #R035
  make_curl_stub 0
  local zap_app_path="${TEST_TMPDIR}/Applications/ZAP.app"
  local zap_cli_args_log="${TEST_TMPDIR}/zap-cli-args.log"
  mkdir -p "${zap_app_path}/Contents/MacOS"
  cat > "${zap_app_path}/Contents/MacOS/ZAP.sh" <<'EOF'
#!/usr/bin/env bash
report=""
all_args="$*"
printf '%s\n' "${all_args}" > "${ZAP_CLI_ARGS_LOG_PATH}"
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-quickout" ] && [ "$#" -ge 2 ]; then
    report="$2"
    shift 2
    continue
  fi
  shift
done
if [[ " ${all_args} " != *" -quickprogress "* ]]; then
  echo "missing -quickprogress" >&2
  exit 2
fi
echo "Attack complete"
printf '%s' '{"site":[{"alerts":[]}]}' > "$report"
exit 0
EOF
  chmod +x "${zap_app_path}/Contents/MacOS/ZAP.sh"
  run env RUN_SAST=false DAST_AUTO_BOOT=false RUN_SCHEMATHESIS=false PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" ZAP_APP_PATH="${zap_app_path}" ZAP_CLI_ARGS_LOG_PATH="${zap_cli_args_log}" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Attack complete"* ]]
  [ -f "${FIXTURE_ROOT}/.security-reports/dast-zap-report.json" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/dast-zap.log" ]
  [[ "$(cat "${zap_cli_args_log}")" == *"-quickprogress"* ]]
  [[ "$(cat "${FIXTURE_ROOT}/.security-reports/dast-zap.log")" == *"Attack complete"* ]]
}

@test "prints final completion output with report path" {
  #R045-T01: Run with enabled lanes passing verifies final completion line includes Reports:.
  #R045
  make_semgrep_stub
  make_shellcheck_stub '[]'
  make_gitleaks_stub '[]'
  make_detect_secrets_stub '{"results":{}}'
  make_gosec_stub '{"Issues":[]}'
  make_govulncheck_stub '{}'
  run env RUN_DAST=false PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Security checks completed. Reports:"* ]]
}
