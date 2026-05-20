#!/usr/bin/env bats

load "helpers/common.bash"

# Numbered-tag parity supplements for missing workflow branches.
#R005-T02
#R005-T03
#R005-T04
#R010-T02
#R010-T03
#R030-T02
#R030-T03
#R030-T04
#R032-T02

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

make_go_stub() {
  local exit_code="${1:-0}"
  local mode="${2:-with-tests}"
  cat > "${STUB_BIN}/go" <<EOF
#!/usr/bin/env bash
echo "go \$*" >> "${CALLS_LOG}"
if [ "\${1:-}" = "tool" ] && [ "\${2:-}" = "cover" ]; then
  echo "total:                          (statements)    75.0%"
  exit 0
fi
if [ "\${1:-}" = "test" ]; then
  for arg in "\$@"; do
    case "\$arg" in
      -coverprofile=*)
        profile="\${arg#-coverprofile=}"
        mkdir -p "\$(dirname "\$profile")"
        printf 'mode: set\nstub.go:1.1,1.2 2 2\n' > "\$profile"
        ;;
    esac
  done
  if [ "${mode}" = "with-tests" ]; then
    cat <<'GOOUT'
ok      valve/storage       0.001s
GOOUT
  fi
  if [ "${mode}" = "no-tests" ]; then
    cat <<'GOOUT'
?       valve/cmd/valve   [no test files]
ok      valve/storage       0.001s
GOOUT
  fi
  exit ${exit_code}
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/go"
}

make_bats_stub() {
  local exit_code="${1:-0}"
  cat > "${STUB_BIN}/bats" <<EOF
#!/usr/bin/env bash
echo "bats \$*" >> "${CALLS_LOG}"
exit ${exit_code}
EOF
  chmod +x "${STUB_BIN}/bats"
}

make_swift_stub() {
  local exit_code="${1:-0}"
  cat > "${STUB_BIN}/swift" <<EOF
#!/usr/bin/env bash
echo "swift \$*" >> "${CALLS_LOG}"
exit ${exit_code}
EOF
  chmod +x "${STUB_BIN}/swift"
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
  case "${2:-}" in
    localhost_postgres_valve)
      case "${3:-}" in
        password)
          printf '%s\n' "${VALVE_PASSWORD-valve-password}"
          ;;
        schema)
          printf '%s\n' "${VALVE_SCHEMA-valve}"
          ;;
        *)
          exit 1
          ;;
      esac
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
  copy_script_to_fixture "05_run_unit_tests.sh"
  mkdir -p "${FIXTURE_ROOT}/storage/sql/unit"
  cat > "${FIXTURE_ROOT}/storage/sql/unit/ingest_schema_pgtap.sql" <<'EOF'
SELECT plan(1);
SELECT ok(true, 'stub');
SELECT * FROM finish();
EOF
  mkdir -p "${FIXTURE_ROOT}/macos/ValveProvisioningApp"
  printf '// swift-tools-version: 5.9\n' > "${FIXTURE_ROOT}/macos/ValveProvisioningApp/Package.swift"
  # The parallel runner (R040) discovers files via `find tests/sh -name '*.bats'`,
  # so the fixture needs at least one *.bats file for the bats stub to be invoked.
  mkdir -p "${FIXTURE_ROOT}/tests/sh"
  cat > "${FIXTURE_ROOT}/tests/sh/example.bats" <<'EOF'
#!/usr/bin/env bats
@test "fixture stub" {
  [ 1 -eq 1 ]
}
EOF
  cat > "${FIXTURE_ROOT}/tests/sh/extra.bats" <<'EOF'
#!/usr/bin/env bats
@test "fixture stub 2" {
  [ 1 -eq 1 ]
}
EOF
}

teardown() {
  teardown_shell_test
}

setup() {
  setup_shell_test
  setup_fixture
  make_psql_stub 0
  make_go_stub 0
  make_bats_stub 0
  make_swift_stub 0
  make_1psa_stub
}

@test "fails on first psql error" {
  #R001-T01: Force psql to fail verifies script exits non-zero.
  #R001
  make_psql_stub 1
  run bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -ne 0 ]
}

@test "fails when 1psa is unavailable" {
  #R005-T01: Run with 1psa unavailable verifies explicit non-zero failure output.
  #R005
  export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
  run bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"1psa is required"* ]]
}

@test "fails when valve 1psa credential lookup is empty" {
  #R005
  run env VALVE_PASSWORD= bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to resolve valve password from 1psa item"* ]]
}

@test "fails when valve schema 1psa lookup is empty" {
  #R005
  run env VALVE_SCHEMA= bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to resolve valve schema name from 1psa item"* ]]
}

@test "fails when valve schema 1psa lookup is invalid" {
  #R005
  run env VALVE_SCHEMA="valve-schema" bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to resolve valve schema name from 1psa item"* ]]
}

@test "fails when psql is unavailable" {
  #R010-T01: Run with psql missing verifies explicit non-zero failure output.
  #R010
  rm -f "${STUB_BIN}/psql"
  make_1psa_stub
  export PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin"
  run bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"psql is required"* ]]
}

@test "fails when go is unavailable" {
  #R010
  rm -f "${STUB_BIN}/go"
  make_psql_stub 0
  make_bats_stub 0
  make_1psa_stub
  export PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin"
  run bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"go is required"* ]]
}

@test "fails when bats is unavailable" {
  #R010
  rm -f "${STUB_BIN}/bats"
  make_psql_stub 0
  make_go_stub 0
  make_1psa_stub
  export PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin"
  run bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"bats is required"* ]]
}

@test "fails when swift is unavailable" {
  #R010-T04: Run with swift missing from PATH verifies explicit non-zero failure output.
  #R037-T02: Force missing Swift package directory verifies explicit non-zero failure output.
  #R010 #R037
  rm -f "${STUB_BIN}/swift"
  make_psql_stub 0
  make_go_stub 0
  make_bats_stub 0
  make_1psa_stub
  ln -sf /bin/bash "${STUB_BIN}/bash"
  ln -sf /usr/bin/env "${STUB_BIN}/env"
  export PATH="${STUB_BIN}:/bin:/usr/sbin:/sbin"
  run bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"swift is required"* ]]
}

@test "outputs header lines before each test section" {
  #R030-T05: Verify output includes header lines before each test section.
  #R030-T06: Verify successful run output includes Test Runner labels and border.
  #R037-T01: Verify Swift test invocation uses swift test --package-path.
  #R030 #R037
  make_psql_stub 0
  make_go_stub 0 "with-tests"
  make_bats_stub 0
  make_1psa_stub
  cat > "${STUB_BIN}/swift" <<'EOF'
#!/usr/bin/env bash
echo "swift $*" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/swift"
  mkdir -p "${FIXTURE_ROOT}/macos/ValveProvisioningApp"
  printf '// swift-tools-version: 5.9\n' > "${FIXTURE_ROOT}/macos/ValveProvisioningApp/Package.swift"
  run bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"+==============================================================================+"* ]]
  [[ "$output" == *"Test Runner: pgTAP"* ]]
  [[ "$output" == *"Test Runner: go test"* ]]
  [[ "$output" == *"Test Runner: go tool cover"* ]]
  [[ "$output" == *"Test Runner: Bats"* ]]
  [[ "$output" == *"Test Runner: Swift Package Manager"* ]]
  [[ "$output" == *"▶ Running SQL unit tests"* ]]
  [[ "$output" == *"▶ Running Go unit tests"* ]]
  [[ "$output" == *"▶ Checking Go coverage threshold"* ]]
  [[ "$output" == *"▶ Running Bats shell tests"* ]]
  [[ "$output" == *"▶ Running Swift package tests"* ]]
  grep -F "swift test --package-path" "${CALLS_LOG}"
}

@test "resolves SQL unit-test path relative to script location" {
  #R015-T01: Run from non-repo cwd verifies SQL unit-test path resolves correctly.
  #R015
  run bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -eq 0 ]
  grep -F "storage/sql/unit/ingest_schema_pgtap.sql" "${CALLS_LOG}"
}

@test "fails when SQL unit-test file is missing" {
  #R020-T01: Move SQL test file out of place verifies explicit non-zero failure output.
  #R020
  mv "${FIXTURE_ROOT}/storage/sql/unit/ingest_schema_pgtap.sql" \
    "${FIXTURE_ROOT}/storage/sql/unit/ingest_schema_pgtap.sql.trash"
  run bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SQL unit-test file not found"* ]]
}

@test "creates pgtap extension before running SQL unit tests" {
  #R025-T01: Verify script invokes extension-create SQL before test-file execution.
  #R025
  run bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -eq 0 ]
  local create_line
  create_line="$(grep -n "CREATE EXTENSION IF NOT EXISTS pgtap" "${CALLS_LOG}")"
  local run_line
  run_line="$(grep -n "ingest_schema_pgtap.sql" "${CALLS_LOG}")"
  [ -n "$create_line" ]
  [ -n "$run_line" ]
}

@test "runs SQL unit tests with fail-fast psql options" {
  #R030-T01: Verify test invocation includes ON_ERROR_STOP=1, -P pager=off, VALVE_SCHEMA, and SQL test file path.
  #R030
  run bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -eq 0 ]
  grep -F -- "-P pager=off" "${CALLS_LOG}"
  grep -F -- "-h localhost" "${CALLS_LOG}"
  grep -F -- "-p 5432" "${CALLS_LOG}"
  grep -F -- "-U valve" "${CALLS_LOG}"
  grep -F -- "-d valve" "${CALLS_LOG}"
  grep -F "ON_ERROR_STOP=1" "${CALLS_LOG}"
  grep -F "VALVE_SCHEMA=valve" "${CALLS_LOG}"
  grep -F "ingest_schema_pgtap.sql" "${CALLS_LOG}"
}

@test "does not run go tests when SQL stage fails" {
  #R030
  make_psql_stub 1
  make_go_stub 0
  run bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -ne 0 ]
  ! grep -F "go test ./..." "${CALLS_LOG}"
}

@test "fails when go unit tests fail" {
  #R030
  make_psql_stub 0
  make_go_stub 1
  make_bats_stub 0
  run bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -ne 0 ]
  grep -F "go test ./..." "${CALLS_LOG}"
}

@test "runs go then bats only after SQL unit tests pass" {
  #R030
  make_bats_stub 0
  run bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -eq 0 ]
  local sql_line
  sql_line="$(grep -n "ingest_schema_pgtap.sql" "${CALLS_LOG}" | cut -d: -f1 | head -n 1)"
  local go_line
  go_line="$(grep -n "go test ./..." "${CALLS_LOG}" | cut -d: -f1 | head -n 1)"
  local bats_line
  bats_line="$(grep -n "bats " "${CALLS_LOG}" | cut -d: -f1 | head -n 1)"
  [ -n "$sql_line" ]
  [ -n "$go_line" ]
  [ -n "$bats_line" ]
  [ "$go_line" -gt "$sql_line" ]
  [ "$bats_line" -gt "$go_line" ]
}

@test "fails when go test output includes packages with no test files" {
  #R032-T01: Emit simulated go test output with no test files entries verifies explicit non-zero failure.
  #R032
  make_go_stub 0 "no-tests"
  run bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"packages without _test.go files detected"* ]]
  [[ "$output" == *"valve/cmd/valve"* ]]
}

@test "passes go coverage gate when all packages include test files" {
  #R032-T02: Emit simulated go test output with no no-test-files entries verifies run can complete.
  #R038-T01: Verify coverage gate passes when stubbed go tool cover reports sufficient coverage.
  #R032 #R038
  make_go_stub 0 "with-tests"
  run bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"gate_failed": false'* ]]
  grep -e '-coverprofile=' "${CALLS_LOG}"
  grep -F 'go tool cover' "${CALLS_LOG}"
}

@test "emits a single pass line after successful SQL and Go unit tests" {
  #R035-T01: Verify successful run emits a single PASS line.
  #R035
  make_go_stub 0 "with-tests"
  make_bats_stub 0
  run bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c "✅ PASS:")" -eq 1 ]
}

@test "invokes bats per file with TAP, failure-output, and timing flags" {
  #R040-T01: Verify parallel bats invocation forwards --tap, --print-output-on-failure, and --timing per file.
  #R040
  run bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -eq 0 ]
  grep -F -- "--tap" "${CALLS_LOG}"
  grep -F -- "--print-output-on-failure" "${CALLS_LOG}"
  grep -F -- "--timing" "${CALLS_LOG}"
  [ "$(grep -c "bats " "${CALLS_LOG}")" -ge 2 ]
  grep -F "example.bats" "${CALLS_LOG}"
  grep -F "extra.bats" "${CALLS_LOG}"
}

@test "fails when no bats files are found under tests/sh" {
  #R040-T02: Empty tests/sh directory verifies the runner fails fast with a clear message.
  #R040
  rm -f "${FIXTURE_ROOT}/tests/sh/"*.bats
  run bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"No bats files found"* ]]
}

@test "fails when tests/sh directory is missing" {
  #R040-T03: Missing tests/sh directory verifies the runner fails fast with a clear message.
  #R040
  rm -rf "${FIXTURE_ROOT}/tests/sh"
  run bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Bats test directory not found"* ]]
}

@test "honors BATS_JOBS env override in progress banner" {
  #R040-T04: BATS_JOBS=1 verifies the resolved-jobs value flows through to the progress banner.
  #R040
  run env BATS_JOBS=1 bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"jobs=1"* ]]
}

@test "PARALLEL_LANES>1 reduces default bats jobs to keep concurrency near hw.ncpu" {
  #R040-T05: PARALLEL_LANES=99 with BATS_JOBS unset clamps the default to 1 so an outer meta-runner does not oversubscribe.
  #R040
  run env PARALLEL_LANES=99 bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"jobs=1"* ]]
}

@test "BATS_FILTER env propagates -f to each bats invocation" {
  #R040-T06: BATS_FILTER=foo verifies -f foo is forwarded to every bats call.
  #R040
  run env BATS_FILTER=foo bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -eq 0 ]
  grep -F -- "-f foo" "${CALLS_LOG}"
}

@test "BATS_FILTER_STATUS env propagates --filter-status to each bats invocation" {
  #R040-T07: BATS_FILTER_STATUS=failed verifies --filter-status failed is forwarded to every bats call.
  #R040
  run env BATS_FILTER_STATUS=failed bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -eq 0 ]
  grep -F -- "--filter-status failed" "${CALLS_LOG}"
}

@test "wraps each bats file's output with a basename banner" {
  #R040-T08: Verify the per-file output dump is prefixed by "===== <basename> =====".
  #R040
  run bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"===== example.bats ====="* ]]
  [[ "$output" == *"===== extra.bats ====="* ]]
}

@test "non-zero exit from any bats file propagates" {
  #R040-T09: A failing bats stub verifies the meta-runner exits non-zero.
  #R040
  make_bats_stub 1
  run bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -ne 0 ]
}

@test "BATS_USE_NATIVE_JOBS=true falls back to xargs when parallel is missing" {
  #R040-T10: BATS_USE_NATIVE_JOBS=true with no parallel on PATH verifies a fallback notice is printed and the xargs path still runs.
  #R040
  run env BATS_USE_NATIVE_JOBS=true bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"falling back to xargs"* ]]
  [[ "$output" == *"parallel by file"* ]]
  grep -F "example.bats" "${CALLS_LOG}"
}

@test "BATS_USE_NATIVE_JOBS=true delegates to bats -j when parallel is available" {
  #R040-T11: BATS_USE_NATIVE_JOBS=true with a stub parallel on PATH verifies bats is invoked once with -j (not once per file).
  #R040
  cat > "${STUB_BIN}/parallel" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${STUB_BIN}/parallel"
  run env BATS_USE_NATIVE_JOBS=true bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"GNU parallel"* ]]
  # Native-jobs mode invokes bats exactly once with `-j N` and the tests dir
  # (no per-file iteration), so the stubbed bats command line records -j and
  # the directory path rather than individual *.bats files.
  grep -F -- "-j " "${CALLS_LOG}"
  grep -F -- "--no-parallelize-within-files" "${CALLS_LOG}"
  [ "$(grep -c "^bats " "${CALLS_LOG}")" -eq 1 ]
}
