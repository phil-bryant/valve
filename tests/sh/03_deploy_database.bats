#!/usr/bin/env bats

load "helpers/common.bash"

make_psql_stub() {
  local exit_code="${1:-0}"
  cat > "${STUB_BIN}/psql" <<EOF
#!/usr/bin/env bash
echo "psql \$*" >> "${CALLS_LOG}"
exit ${exit_code}
EOF
  chmod +x "${STUB_BIN}/psql"
  : > "${CALLS_LOG}"
}

make_1psa_stub() {
  cat > "${STUB_BIN}/1psa" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "-p" ]; then
  case "${2:-}" in
    localhost_postgres_postgres)
      printf '%s\n' "${POSTGRES_PASSWORD-postgres-password}"
      ;;
    localhost_postgres_valve)
      printf '%s\n' "${VALVE_PASSWORD-valve-password}"
      ;;
    *)
      exit 1
      ;;
  esac
  exit 0
fi
if [ "${1:-}" = "-f" ]; then
  case "${2:-}:${3:-}" in
    localhost_postgres_valve:host)
      printf '%s\n' "${ONEPSA_VALVE_HOST-localhost}"
      ;;
    localhost_postgres_valve:port)
      printf '%s\n' "${ONEPSA_VALVE_PORT-5432}"
      ;;
    localhost_postgres_postgres:password)
      printf '%s\n' "${POSTGRES_PASSWORD-postgres-password}"
      ;;
    localhost_postgres_valve:password)
      printf '%s\n' "${VALVE_PASSWORD-valve-password}"
      ;;
    *)
      exit 1
      ;;
  esac
  exit 0
fi
exit 1
EOF
  chmod +x "${STUB_BIN}/1psa"
}

setup_fixture() {
  create_repo_fixture
  copy_script_to_fixture "03_deploy_database.sh"
  mkdir -p "${FIXTURE_ROOT}/storage"
  cat > "${FIXTURE_ROOT}/storage/schema.sql" <<'EOF'
CREATE TABLE IF NOT EXISTS ingest_batches (id BIGINT PRIMARY KEY);
EOF
}

teardown() {
  teardown_shell_test
}

setup() {
  setup_shell_test
  setup_fixture
  make_psql_stub 0
  make_1psa_stub
}

@test "exits non-zero when schema apply fails" {
  #R001
  make_psql_stub 1
  run bash "${FIXTURE_ROOT}/03_deploy_database.sh"
  [ "$status" -ne 0 ]
}

@test "fails when 1psa is unavailable" {
  #R005
  export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
  run bash "${FIXTURE_ROOT}/03_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"1psa is required"* ]]
}

@test "fails when valve 1psa credential lookup is empty" {
  #R005
  run env VALVE_PASSWORD= bash "${FIXTURE_ROOT}/03_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to resolve valve password from 1psa item"* ]]
}

@test "fails when valve 1psa host/port lookup is empty or invalid" {
  #R005
  run env ONEPSA_VALVE_HOST= bash "${FIXTURE_ROOT}/03_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to resolve valve host from 1psa item"* ]]

  run env ONEPSA_VALVE_PORT=invalid bash "${FIXTURE_ROOT}/03_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to resolve valve port from 1psa item"* ]]
}

@test "fails when psql is unavailable" {
  #R010
  rm -f "${STUB_BIN}/psql"
  make_1psa_stub
  export PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin"
  run bash "${FIXTURE_ROOT}/03_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"psql is required"* ]]
}

@test "resolves schema path relative to script from different cwd" {
  #R015
  run bash "${FIXTURE_ROOT}/03_deploy_database.sh"
  [ "$status" -eq 0 ]
  grep -F "storage/schema.sql" "${CALLS_LOG}"
}

@test "fails when schema file is missing" {
  #R020
  mv "${FIXTURE_ROOT}/storage/schema.sql" "${FIXTURE_ROOT}/storage/schema.sql.trash"
  run bash "${FIXTURE_ROOT}/03_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Schema file not found"* ]]
}

@test "applies schema using fail-fast psql flags and 1psa credentials" {
  #R025
  run env ONEPSA_VALVE_HOST=db.internal ONEPSA_VALVE_PORT=6543 bash "${FIXTURE_ROOT}/03_deploy_database.sh"
  [ "$status" -eq 0 ]
  grep -F -- "-U postgres" "${CALLS_LOG}"
  grep -F -- "-h db.internal" "${CALLS_LOG}"
  grep -F -- "-p 6543" "${CALLS_LOG}"
  grep -F -- "-U valve" "${CALLS_LOG}"
  grep -F -- "-d valve" "${CALLS_LOG}"
  grep -F "ON_ERROR_STOP=1" "${CALLS_LOG}"
  grep -F "storage/schema.sql" "${CALLS_LOG}"
}

@test "prints pass line after successful deploy" {
  #R030
  run bash "${FIXTURE_ROOT}/03_deploy_database.sh"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c "✅ PASS:")" -eq 1 ]
}
