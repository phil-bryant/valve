#!/usr/bin/env bats

load "helpers/common.bash"

make_psql_happy() {
  cat > "${STUB_BIN}/psql" <<'PY'
#!/usr/bin/env python3
import os
import sys

def log_line():
  path = os.environ.get("PSQL_LOG", "")
  if not path:
    return
  with open(path, "a", encoding="utf-8") as h:
    h.write("psql " + " ".join(sys.argv[1:]) + "\n")

def get_sql(args):
  if "-c" in args:
    return args[args.index("-c") + 1]
  return ""

def main():
  log_line()
  args = sys.argv[1:]
  sql = get_sql(args)
  if "expected(table_name)" in sql and "valve_credentials" in sql:
    print(os.environ.get("MISSING_TABLES", ""), end="")
    return
  if "expected(index_name)" in sql and "idx_valve_credentials_tenant_install" in sql:
    print(os.environ.get("MISSING_INDEXES", ""), end="")
    return
  if "conname = 'valve_credentials_tenant_id_install_id_credential_id_key'" in sql:
    print("f" if os.environ.get("UNIQUE_MISSING") == "1" else "t", end="")
    return
  print("t", end="")

if __name__ == "__main__":
  main()
PY
  chmod +x "${STUB_BIN}/psql"
}

make_1psa_stub() {
  cat > "${STUB_BIN}/1psa" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "-p" ]; then
  case "${2:-}" in
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
    localhost_postgres_valve:password)
      printf '%s\n' "${VALVE_PASSWORD-valve-password}"
      ;;
    localhost_postgres_valve:database)
      printf '%s\n' "${ONEPSA_VALVE_DATABASE-valve}"
      ;;
    localhost_postgres_valve:schema)
      printf '%s\n' "${ONEPSA_VALVE_SCHEMA-valve}"
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

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "04_verify_deploy_database.sh"
  export PSQL_LOG="${TEST_TMPDIR}/psql.log"
  : > "${PSQL_LOG}"
  make_psql_happy
  make_1psa_stub
  export PATH="${STUB_BIN}:/usr/bin:/bin"
  export PSQL_LOG
}

teardown() {
  teardown_shell_test
}

@test "fails on first psql error" {
  #R001
  cat > "${STUB_BIN}/psql" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "${STUB_BIN}/psql"
  run sh "${FIXTURE_ROOT}/04_verify_deploy_database.sh"
  [ "$status" -ne 0 ]
}

@test "fails when 1psa is unavailable" {
  #R005
  export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
  run sh "${FIXTURE_ROOT}/04_verify_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"1psa is required"* ]]
}

@test "fails when valve 1psa credential lookup is empty" {
  #R005
  run env VALVE_PASSWORD= sh "${FIXTURE_ROOT}/04_verify_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to resolve valve password from 1psa item"* ]]
}

@test "fails when valve 1psa host/port lookup is empty or invalid" {
  #R005
  run env ONEPSA_VALVE_HOST= sh "${FIXTURE_ROOT}/04_verify_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to resolve valve host from 1psa item"* ]]

  run env ONEPSA_VALVE_PORT=bad sh "${FIXTURE_ROOT}/04_verify_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to resolve valve port from 1psa item"* ]]
}

@test "fails when valve 1psa database lookup is empty" {
  #R005
  run env ONEPSA_VALVE_DATABASE= sh "${FIXTURE_ROOT}/04_verify_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to resolve valve database name from 1psa item"* ]]
}

@test "fails when valve 1psa schema lookup is empty or invalid" {
  #R005
  run env ONEPSA_VALVE_SCHEMA= sh "${FIXTURE_ROOT}/04_verify_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to resolve valve schema name from 1psa item"* ]]

  run env ONEPSA_VALVE_SCHEMA="bad-schema" sh "${FIXTURE_ROOT}/04_verify_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to resolve valve schema name from 1psa item"* ]]
}

@test "fails when psql is unavailable" {
  #R010
  rm -f "${STUB_BIN}/psql"
  make_1psa_stub
  export PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin"
  run sh "${FIXTURE_ROOT}/04_verify_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"psql is required"* ]]
}

@test "fails when required tables are missing" {
  #R015
  : > "${PSQL_LOG}"
  make_psql_happy
  run env MISSING_TABLES=valve_credentials \
    sh "${FIXTURE_ROOT}/04_verify_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing tables"* ]]
  [[ "$output" == *"valve_credentials"* ]]
}

@test "fails when required indexes are missing" {
  #R020
  : > "${PSQL_LOG}"
  make_psql_happy
  run env MISSING_INDEXES=idx_valve_credentials_status \
    sh "${FIXTURE_ROOT}/04_verify_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing indexes"* ]]
  [[ "$output" == *"idx_valve_credentials_status"* ]]
}

@test "fails when valve credential uniqueness contract is missing" {
  #R025
  : > "${PSQL_LOG}"
  make_psql_happy
  run env UNIQUE_MISSING=1 sh "${FIXTURE_ROOT}/04_verify_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing unique constraint: valve_credentials(tenant_id, install_id, credential_id)"* ]]
}

@test "emits a single pass line for successful verification" {
  #R030
  : > "${PSQL_LOG}"
  make_psql_happy
  run sh "${FIXTURE_ROOT}/04_verify_deploy_database.sh"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c "✅ PASS:")" -eq 1 ]
}

@test "uses fail-fast psql options with 1psa-resolved target and valve user" {
  #R035
  : > "${PSQL_LOG}"
  make_psql_happy
  run env ONEPSA_VALVE_HOST=db.internal ONEPSA_VALVE_PORT=6543 ONEPSA_VALVE_DATABASE=valve_shadow ONEPSA_VALVE_SCHEMA=valve_app sh "${FIXTURE_ROOT}/04_verify_deploy_database.sh"
  [ "$status" -eq 0 ]
  grep -F -- "-h db.internal" "${PSQL_LOG}"
  grep -F -- "-p 6543" "${PSQL_LOG}"
  grep -F -- "-U valve" "${PSQL_LOG}"
  grep -F -- "-d valve_shadow" "${PSQL_LOG}"
  grep -F -- "table_schema = 'valve_app'" "${PSQL_LOG}"
  grep -F "ON_ERROR_STOP=1" "${PSQL_LOG}"
}
