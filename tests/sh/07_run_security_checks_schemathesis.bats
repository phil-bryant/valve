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
  make_go_stub_until_cleanup
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
  make_go_stub_until_cleanup
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
