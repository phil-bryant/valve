#!/usr/bin/env bash
# Shared stubs and per-test setup for the 07_run_security_checks_*.bats split
# files. Loaded after helpers/common.bash, which provides setup_shell_test,
# create_repo_fixture, copy_script_to_fixture, copy_openapi_to_fixture, and
# setup_file_shared_fixture. Splitting the original 1212-line file into four
# lane-specific files lets the parallel-by-file bats runner (R040 in
# 05_run_unit_tests.sh) finish 07_* in roughly one quarter of its previous
# wall-clock time while preserving every single test.

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

setup_security_fixture() {
  create_repo_fixture
  copy_script_to_fixture "07_run_security_checks.sh"
  copy_openapi_to_fixture
}

setup_security_test() {
  setup_shell_test
  setup_security_fixture
  make_go_vet_stub '{}'
}
