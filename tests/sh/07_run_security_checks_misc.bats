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
  run env RUN_SAST=false RUN_DAST=true DAST_AUTO_BOOT=false RUN_SCHEMATHESIS=false \
    DAST_HEALTH_PROBE_TIMEOUT_SECONDS=1 DAST_HEALTH_PROBE_INTERVAL_SECONDS=0.05 \
    PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
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

@test "canonical openapi includes credential routes" {
  #R065-T01: Verify openapi defines register and verification paths.
  #R065
  run grep -F "/v1/valve/credentials/register" "${FIXTURE_ROOT}/openapi/valve.v1.yaml"
  [ "$status" -eq 0 ]
  run grep -F "/v1/valve/credentials/{credential_id}/verification" "${FIXTURE_ROOT}/openapi/valve.v1.yaml"
  [ "$status" -eq 0 ]
}

@test "defaults schemathesis mode and example budget" {
  #R070-T01: Verify script defaults SCHEMATHESIS_MODE to all and max examples to 200.
  #R070
  run grep -F 'SCHEMATHESIS_MODE="${SCHEMATHESIS_MODE:-all}"' "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 0 ]
  run grep -F 'SCHEMATHESIS_MAX_EXAMPLES="${SCHEMATHESIS_MAX_EXAMPLES:-200}"' "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 0 ]
  run grep -F 'SCHEMATHESIS_CHECKS="${SCHEMATHESIS_CHECKS:-' "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 0 ]
  run grep -F 'VALVE_DEV_AUTH_ALLOW_ALL="${VALVE_DEV_AUTH_ALLOW_ALL:-true}"' "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 0 ]
}
