#!/usr/bin/env bats

load "helpers/common.bash"

setup_fixture() {
  create_repo_fixture
  copy_script_to_fixture "08_run_backend.sh"
}

make_go_stub() {
  cat > "${STUB_BIN}/go" <<'EOF'
#!/usr/bin/env bash
echo "go $*" >> "${CALLS_LOG}"
if [ "${1:-}" = "run" ] && [ "${2:-}" != "./cmd/valve" ]; then
  if [ "${GO_RESOLVER_STUB_EXIT_CODE:-0}" -ne 0 ]; then
    if [ -n "${GO_RESOLVER_STUB_STDERR:-}" ]; then
      printf '%s\n' "${GO_RESOLVER_STUB_STDERR}" >&2
    fi
    exit "${GO_RESOLVER_STUB_EXIT_CODE:-1}"
  fi
  printf '%s\n' "${GO_RESOLVER_HOST_VALUE:-node.local}"
  exit 0
fi
echo "VALVE_ADDR=${VALVE_ADDR:-}" >> "${CALLS_LOG}"
echo "VALVE_DATABASE_URL=${VALVE_DATABASE_URL:-}" >> "${CALLS_LOG}"
echo "VALVE_UPLOAD_ENDPOINT=${VALVE_UPLOAD_ENDPOINT:-}" >> "${CALLS_LOG}"
exit "${GO_STUB_EXIT_CODE:-0}"
EOF
  chmod +x "${STUB_BIN}/go"
}

make_1psa_stub() {
  cat > "${STUB_BIN}/1psa" <<'EOF'
#!/usr/bin/env bash
if [ "$#" -eq 3 ] && [ "$1" = "-f" ] && [ "$2" = "${VALVE_PSA_ITEM:-localhost_postgres_valve}" ] && [ "$3" = "username" ]; then
  printf '%s' "${ONEPSA_DATABASE_USERNAME_VALUE:-valve}"
  exit 0
fi
if [ "$#" -eq 3 ] && [ "$1" = "-f" ] && [ "$2" = "${VALVE_PSA_ITEM:-localhost_postgres_valve}" ] && [ "$3" = "password" ]; then
  printf '%s' "${ONEPSA_DATABASE_PW_VALUE:-valvepw}"
  exit 0
fi
if [ "$#" -eq 3 ] && [ "$1" = "-f" ] && [ "$2" = "${VALVE_PSA_ITEM:-localhost_postgres_valve}" ] && [ "$3" = "host" ]; then
  printf '%s' "${ONEPSA_DATABASE_HOST_VALUE:-localhost}"
  exit 0
fi
if [ "$#" -eq 3 ] && [ "$1" = "-f" ] && [ "$2" = "${VALVE_PSA_ITEM:-localhost_postgres_valve}" ] && [ "$3" = "port" ]; then
  printf '%s' "${ONEPSA_DATABASE_PORT_VALUE:-5432}"
  exit 0
fi
exit 2
EOF
  chmod +x "${STUB_BIN}/1psa"
}

setup() {
  setup_shell_test
  setup_fixture
  make_go_stub
  make_1psa_stub
}

teardown() {
  teardown_shell_test
}

@test "runs from non-repo cwd and resolves backend launch from script root" {
  #R001
  mkdir -p "${TEST_TMPDIR}/elsewhere"
  run env PATH="${PATH}" VALVE_UPLOAD_ENDPOINT="https://upload" bash -c "cd '${TEST_TMPDIR}/elsewhere' && bash '${FIXTURE_ROOT}/08_run_backend.sh'"
  [ "$status" -eq 0 ]
  grep -F "go run ./cmd/valve" "${CALLS_LOG}"
}

@test "fails fast with installer guidance when go is missing" {
  #R005
  run env PATH="/usr/bin:/bin:/usr/sbin:/sbin" VALVE_UPLOAD_ENDPOINT="https://upload" bash "${FIXTURE_ROOT}/08_run_backend.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing required command: go"* ]]
  [[ "$output" == *"./01_install_prerequisites.sh"* ]]
}

@test "fails fast with installer guidance when 1psa is missing" {
  #R005
  local go_only_bin="${TEST_TMPDIR}/go-only-bin"
  mkdir -p "${go_only_bin}"
  cp "${STUB_BIN}/go" "${go_only_bin}/go"
  chmod +x "${go_only_bin}/go"
  run env PATH="${go_only_bin}:/usr/bin:/bin:/usr/sbin:/sbin" VALVE_UPLOAD_ENDPOINT="https://upload" bash "${FIXTURE_ROOT}/08_run_backend.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing required command: 1psa"* ]]
  [[ "$output" == *"./01_install_prerequisites.sh"* ]]
}

@test "composes database url from 1psa values when env override is missing" {
  #R010
  run env PATH="${PATH}" ONEPSA_DATABASE_USERNAME_VALUE="user_a" ONEPSA_DATABASE_PW_VALUE="pw_a" ONEPSA_DATABASE_HOST_VALUE="db.local" ONEPSA_DATABASE_PORT_VALUE="6543" VALVE_UPLOAD_ENDPOINT="https://upload" bash "${FIXTURE_ROOT}/08_run_backend.sh"
  [ "$status" -eq 0 ]
  grep -F "VALVE_DATABASE_URL=postgres://user_a:pw_a@db.local:6543/valve?sslmode=disable" "${CALLS_LOG}"
}

@test "fails when 1psa port lookup is invalid" {
  #R010
  run env PATH="${PATH}" ONEPSA_DATABASE_PORT_VALUE="abc" VALVE_UPLOAD_ENDPOINT="https://upload" bash "${FIXTURE_ROOT}/08_run_backend.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to read valve database port from 1psa item"* ]]
}

@test "derives upload endpoint when VALVE_UPLOAD_ENDPOINT is missing" {
  #R015
  run env PATH="${PATH}" GO_RESOLVER_HOST_VALUE="edgebox.local" bash "${FIXTURE_ROOT}/08_run_backend.sh"
  [ "$status" -eq 0 ]
  grep -F "VALVE_UPLOAD_ENDPOINT=http://edgebox.local:8081/v1/events/batch" "${CALLS_LOG}"
}

@test "fails when derived manifold upload port is invalid" {
  #R015
  run env PATH="${PATH}" MANIFOLD_UPLOAD_PORT="invalid" bash "${FIXTURE_ROOT}/08_run_backend.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid MANIFOLD_UPLOAD_PORT"* ]]
}

@test "fails when same-box hostname resolver fails" {
  #R015
  run env PATH="${PATH}" GO_RESOLVER_STUB_EXIT_CODE=1 GO_RESOLVER_STUB_STDERR="resolver_debug stage=net.LookupIP host=phils-MacBook-Pro err=no such host" bash "${FIXTURE_ROOT}/08_run_backend.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to resolve same-box upload hostname"* ]]
  [[ "$output" == *"Resolver debug:"* ]]
  [[ "$output" == *"resolver_debug stage=net.LookupIP host=phils-MacBook-Pro err=no such host"* ]]
}

@test "uses default bind address when VALVE_ADDR is unset" {
  #R020
  run env PATH="${PATH}" VALVE_UPLOAD_ENDPOINT="https://upload" bash "${FIXTURE_ROOT}/08_run_backend.sh"
  [ "$status" -eq 0 ]
  grep -F "go run ./cmd/valve" "${CALLS_LOG}"
  grep -F "VALVE_ADDR=:8090" "${CALLS_LOG}"
}

@test "uses explicit bind address override when provided" {
  #R020
  run env PATH="${PATH}" VALVE_ADDR=":9999" VALVE_UPLOAD_ENDPOINT="https://upload" bash "${FIXTURE_ROOT}/08_run_backend.sh"
  [ "$status" -eq 0 ]
  grep -F "VALVE_ADDR=:9999" "${CALLS_LOG}"
}
