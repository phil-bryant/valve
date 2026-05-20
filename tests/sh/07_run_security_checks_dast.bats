#!/usr/bin/env bats

load "helpers/common.bash"
load "helpers/security_stubs.bash"

setup_file() {
  setup_file_shared_fixture "07_run_security_checks.sh"
}

setup() {
  setup_security_test
}

teardown() {
  teardown_shell_test
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

@test "auto-boot emits dast run id for tenant cleanup" {
  #R075-T01: Verify auto-boot path emits a DAST run id line used for tenant cleanup prefixing.
  #R075
  make_go_stub_until_cleanup
  make_1psa_stub
  make_curl_stub 0
  make_zap_baseline_stub '{"site":[{"alerts":[]}]}' 0
  local boot_port
  boot_port="$(allocate_free_port)"
  run env RUN_SAST=false DAST_AUTO_BOOT=true RUN_SCHEMATHESIS=false ONEPSA_DAST_PORT_VALUE="${boot_port}" GO_STUB_LOG_PATH="${TEST_TMPDIR}/go-stub.log" PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DAST run id (tenant cleanup prefix):"* ]]
}

@test "auto-boots service for DAST when enabled" {
  #R025-T04: Run with auto-boot enabled and dast_port populated verifies VALVE_ADDR uses that port.
  #R025
  make_go_stub_until_cleanup
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
  make_go_stub_until_cleanup
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
  make_go_stub_until_cleanup
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
  make_go_stub_until_cleanup
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
  make_go_stub_until_cleanup
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
  make_go_stub_until_cleanup
  make_1psa_stub
  # Fail the first probe (mimicking the "service still warming up" interval)
  # and succeed on the second.
  make_curl_stub_fail_then_succeed 1
  make_zap_baseline_stub '{"site":[{"alerts":[]}]}' 0
  local boot_port
  boot_port="$(allocate_free_port)"
  run env RUN_SAST=false DAST_AUTO_BOOT=true RUN_SCHEMATHESIS=false \
    DAST_HEALTH_PROBE_INTERVAL_SECONDS=0.05 \
    ONEPSA_DAST_PORT_VALUE="${boot_port}" GO_STUB_LOG_PATH="${TEST_TMPDIR}/go-stub.log" \
    PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
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
  run env RUN_SAST=false RUN_DAST=true DAST_AUTO_BOOT=false RUN_SCHEMATHESIS=false \
    DAST_HEALTH_PROBE_TIMEOUT_SECONDS=1 DAST_HEALTH_PROBE_INTERVAL_SECONDS=0.05 \
    PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
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
