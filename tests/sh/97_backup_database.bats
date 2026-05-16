#!/usr/bin/env bats

load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "97_backup_database.sh"
}

teardown() {
  teardown_shell_test
}

@test "fails when pg_dump is missing" {
  #R001-T01: Verify script exits on unset variable and failing command paths.
  #R005-T01: Remove pg_dump from PATH verifies clear failure message.
  #R010-T01: Override field verifies lookup path succeeds.
  #R015-T01: Force empty 1psa result verifies script exits non-zero.
  #R001 #R005 #R010 #R015
  cat > "${STUB_BIN}/1psa" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-p" ]; then
  echo "postgres-pass"
  exit 0
fi
if [ "$1" = "-f" ] && [ "$2" = "localhost_postgres_valve" ] && [ "$3" = "host" ]; then
  echo "localhost"
  exit 0
fi
if [ "$1" = "-f" ] && [ "$2" = "localhost_postgres_valve" ] && [ "$3" = "port" ]; then
  echo "5432"
  exit 0
fi
exit 1
EOF
  chmod +x "${STUB_BIN}/1psa"
  stub_cmd pg_dumpall "exit 0"

  run bash "${FIXTURE_ROOT}/97_backup_database.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"pg_dump is required"* ]]
}

@test "fails when valve host or port lookup is invalid" {
  #R010 #R015
  cat > "${STUB_BIN}/1psa" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-p" ]; then
  echo "postgres-pass"
  exit 0
fi
if [ "$1" = "-f" ] && [ "$3" = "host" ]; then
  echo ""
  exit 0
fi
if [ "$1" = "-f" ] && [ "$3" = "port" ]; then
  echo "not-a-port"
  exit 0
fi
exit 1
EOF
  chmod +x "${STUB_BIN}/1psa"
  stub_cmd pg_dump "exit 0"
  stub_cmd pg_dumpall "exit 0"

  run bash "${FIXTURE_ROOT}/97_backup_database.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to read valve host"* || "$output" == *"Failed to read valve port"* ]]
}

@test "creates dump and globals artifacts using valve host and port" {
  #R020-T01: Remove directory verifies recreation with expected permissions.
  #R025-T01: Verify output .dump file exists with timestamped naming.
  #R030-T01: Verify globals file exists beside database dump.
  #R035-T01: Verify file modes and output lines after successful run.
  #R020 #R025 #R030 #R035
  cat > "${STUB_BIN}/1psa" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-p" ]; then
  echo "postgres-pass"
  exit 0
fi
if [ "$1" = "-f" ] && [ "$2" = "localhost_postgres_valve" ] && [ "$3" = "host" ]; then
  echo "db.internal"
  exit 0
fi
if [ "$1" = "-f" ] && [ "$2" = "localhost_postgres_valve" ] && [ "$3" = "port" ]; then
  echo "6543"
  exit 0
fi
exit 1
EOF
  chmod +x "${STUB_BIN}/1psa"
  cat > "${STUB_BIN}/pg_dump" <<'EOF'
#!/usr/bin/env bash
echo "pg_dump $*" >> "${CALLS_LOG}"
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "-f" ]]; then
    touch "$2"
    shift 2
    continue
  fi
  shift
done
exit 0
EOF
  chmod +x "${STUB_BIN}/pg_dump"
  cat > "${STUB_BIN}/pg_dumpall" <<'EOF'
#!/usr/bin/env bash
echo "pg_dumpall $*" >> "${CALLS_LOG}"
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "-f" ]]; then
    touch "$2"
    shift 2
    continue
  fi
  shift
done
exit 0
EOF
  chmod +x "${STUB_BIN}/pg_dumpall"

  run bash "${FIXTURE_ROOT}/97_backup_database.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Backup written:"* ]]
  [[ "$output" == *"Globals written:"* ]]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"pg_dump -w -h db.internal -p 6543"* ]]
  [[ "$calls" == *"pg_dumpall -w -h db.internal -p 6543"* ]]
}
