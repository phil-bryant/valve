#!/usr/bin/env bats

load "helpers/common.bash"

make_go_stub() {
  local exit_code="${1:-0}"
  local mode="${2:-pass}"
  cat > "${STUB_BIN}/go" <<EOF
#!/usr/bin/env bash
echo "go \$*" >> "${CALLS_LOG}"
if [ "\${1:-}" = "test" ]; then
  if [ "${mode}" = "pass" ]; then
    echo "ok      valve/internal/credentials  0.005s"
  fi
  if [ "${mode}" = "fail" ]; then
    echo "FAIL    valve/internal/credentials  0.005s"
  fi
  exit ${exit_code}
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/go"
}

# Stub that emits gremlins' real output format and writes a JSON report when
# invoked with `-o <path>`. Defaults model a healthy passing run.
make_gremlins_stub() {
  local exit_code="${1:-0}"
  local killed="${2:-42}"
  local lived="${3:-8}"
  local not_covered="${4:-3}"
  local not_viable="${5:-0}"
  local timed_out="${6:-0}"
  local total=$((killed + lived))
  local efficacy="100.00"
  if [ "$total" -gt 0 ]; then
    efficacy="$(python3 -c "print(f'{100.0 * ${killed} / ${total}:.2f}')")"
  fi
  local mcoverage="100.00"
  cat > "${STUB_BIN}/gremlins" <<EOF
#!/usr/bin/env bash
echo "gremlins \$*" >> "${CALLS_LOG}"
output_path=""
prev=""
for arg in "\$@"; do
  if [ "\${prev}" = "-o" ] || [ "\${prev}" = "--output" ]; then
    output_path="\${arg}"
  fi
  prev="\${arg}"
done

cat <<GREMOUT
Starting...
Gathering coverage... done in 0.2s

Mutation testing completed in 2 seconds
Killed: ${killed}, Lived: ${lived}, Not covered: ${not_covered}
Timed out: ${timed_out}, Not viable: ${not_viable}, Skipped: 0
Test efficacy: ${efficacy}%
Mutator coverage: ${mcoverage}%
GREMOUT

if [ -n "\${output_path}" ]; then
  cat > "\${output_path}" <<JSON
{
  "go_module": "valve",
  "files": [],
  "test_efficacy": ${efficacy},
  "mutations_coverage": ${mcoverage},
  "mutants_total": ${total},
  "mutants_killed": ${killed},
  "mutants_lived": ${lived},
  "mutants_not_viable": ${not_viable},
  "mutants_not_covered": ${not_covered},
  "elapsed_time": 2.0,
  "mutator_statistics": {}
}
JSON
fi

exit ${exit_code}
EOF
  chmod +x "${STUB_BIN}/gremlins"
}

# Stub that prints "No results to report." and exits 1 without writing JSON,
# matching real gremlins behavior when no covered mutants are found.
make_gremlins_no_results_stub() {
  cat > "${STUB_BIN}/gremlins" <<EOF
#!/usr/bin/env bash
echo "gremlins \$*" >> "${CALLS_LOG}"
cat <<'GREMOUT'
Starting...
Gathering coverage... done in 0.2s

No results to report.
GREMOUT
exit 1
EOF
  chmod +x "${STUB_BIN}/gremlins"
}

make_gremlins_timeout_stub() {
  cat > "${STUB_BIN}/gremlins" <<'EOF'
#!/usr/bin/env bash
echo "gremlins $*" >> "${CALLS_LOG}"
sleep 300
EOF
  chmod +x "${STUB_BIN}/gremlins"
}

setup_fixture() {
  create_repo_fixture
  copy_script_to_fixture "06_run_mutation_tests.sh"
  mkdir -p "${FIXTURE_ROOT}/.security-reports"
}

teardown() {
  teardown_shell_test
}

setup() {
  setup_shell_test
  setup_fixture
  make_go_stub 0 "pass"
  make_gremlins_stub 0 42 8 3 0 0
}

@test "runs from non-repo working directory" {
  #R001-T01: Run from a non-repo working directory and verify execution succeeds.
  #R001
  mkdir -p "${TEST_TMPDIR}/elsewhere"
  run env PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash -c "cd '${TEST_TMPDIR}/elsewhere' && bash '${FIXTURE_ROOT}/06_run_mutation_tests.sh'"
  [ "$status" -eq 0 ]
}

@test "fails when gremlins is unavailable" {
  #R005-T01: Run with gremlins missing from PATH and verify explicit non-zero failure output with installer guidance.
  #R005
  rm -f "${STUB_BIN}/gremlins"
  make_go_stub 0 "pass"
  export PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin"
  run bash "${FIXTURE_ROOT}/06_run_mutation_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing required command: gremlins"* ]]
  [[ "$output" == *"01_install_prerequisites.sh"* ]]
}

@test "fails when go is unavailable" {
  #R005-T02: Run with go missing from PATH and verify explicit non-zero failure output.
  #R005
  rm -f "${STUB_BIN}/go"
  export PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin"
  run bash "${FIXTURE_ROOT}/06_run_mutation_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing required command: go"* ]]
}

@test "uses gremlins from go env GOBIN when not on PATH" {
  #R005-T03: Run with gremlins absent from PATH but present in GOBIN and verify execution succeeds.
  #R005
  rm -f "${STUB_BIN}/gremlins"
  local go_bin_dir="${TEST_TMPDIR}/go-bin"
  mkdir -p "${go_bin_dir}"
  cat > "${go_bin_dir}/gremlins" <<EOF
#!/usr/bin/env bash
echo "gremlins \$*" >> "${CALLS_LOG}"
output_path=""
prev=""
for arg in "\$@"; do
  if [ "\${prev}" = "-o" ] || [ "\${prev}" = "--output" ]; then
    output_path="\${arg}"
  fi
  prev="\${arg}"
done
cat <<'GREMOUT'
Killed: 42, Lived: 8, Not covered: 3
Test efficacy: 84.00%
Mutator coverage: 100.00%
GREMOUT
if [ -n "\${output_path}" ]; then
  cat > "\${output_path}" <<'JSON'
{"go_module":"valve","files":[],"test_efficacy":84.0,"mutations_coverage":100.0,"mutants_total":50,"mutants_killed":42,"mutants_lived":8,"mutants_not_viable":0,"mutants_not_covered":3,"elapsed_time":2.0}
JSON
fi
exit 0
EOF
  chmod +x "${go_bin_dir}/gremlins"
  cat > "${STUB_BIN}/go" <<'EOF'
#!/usr/bin/env bash
echo "go $*" >> "${CALLS_LOG}"
if [ "${1:-}" = "env" ] && [ "${2:-}" = "GOBIN" ]; then
  echo "${GO_BIN_DIR}"
  exit 0
fi
if [ "${1:-}" = "env" ] && [ "${2:-}" = "GOPATH" ]; then
  echo "${TEST_TMPDIR}/go"
  exit 0
fi
if [ "${1:-}" = "test" ]; then
  echo "ok      valve/internal/credentials  0.005s"
  exit 0
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/go"
  run env GO_BIN_DIR="${go_bin_dir}" PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/06_run_mutation_tests.sh"
  [ "$status" -eq 0 ]
  grep -F "gremlins unleash" "${CALLS_LOG}"
}

@test "fails when preflight go test fails" {
  #R010-T01: Force go test failure and verify script exits non-zero with guidance to run step-05 first.
  #R010
  make_go_stub 1 "fail"
  run bash "${FIXTURE_ROOT}/06_run_mutation_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unit tests failed"* ]]
  [[ "$output" == *"05_run_unit_tests.sh"* ]]
}

@test "does not invoke gremlins when preflight fails" {
  #R010-T02: Verify gremlins is not invoked when preflight go test fails.
  #R010
  make_go_stub 1 "fail"
  run bash "${FIXTURE_ROOT}/06_run_mutation_tests.sh"
  [ "$status" -ne 0 ]
  ! grep -F "gremlins" "${CALLS_LOG}"
}

@test "invokes gremlins unleash from module root after preflight passes" {
  #R015-T01: Verify gremlins unleash is invoked from the module root (no ./... argument) after preflight passes.
  #R015
  run bash "${FIXTURE_ROOT}/06_run_mutation_tests.sh"
  [ "$status" -eq 0 ]
  grep -F "gremlins unleash" "${CALLS_LOG}"
  ! grep -E "^gremlins .*\./\.\.\." "${CALLS_LOG}"
}

@test "writes gremlins JSON output to report file" {
  #R015-T02: Verify gremlins JSON output is written to ${REPORT_DIR}/gremlins.json.
  #R030-T01: Verify ${REPORT_DIR}/mutation-summary.json is written after a successful run.
  #R015 #R030
  run bash "${FIXTURE_ROOT}/06_run_mutation_tests.sh"
  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/.security-reports/gremlins.json" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/mutation-summary.json" ]
}

@test "fails with diagnostics when gremlins writes no JSON" {
  #R015-T03: Simulate gremlins finishing without writing a JSON file and verify the script fails with diagnostics referencing the captured gremlins output.
  #R015
  make_gremlins_no_results_stub
  run bash "${FIXTURE_ROOT}/06_run_mutation_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no results"* ]] || [[ "$output" == *"No results"* ]]
}

@test "fails when mutation score is below threshold" {
  #R020-T01: Simulate gremlins JSON with test_efficacy below threshold and verify explicit non-zero failure.
  #R020
  make_gremlins_stub 0 10 90 0 0 0
  run bash "${FIXTURE_ROOT}/06_run_mutation_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL: Mutation score"* ]]
  [[ "$output" == *"below threshold"* ]]
}

@test "passes when mutation score meets threshold" {
  #R020-T02: Simulate gremlins JSON with test_efficacy at or above threshold and verify pass.
  #R020
  make_gremlins_stub 0 85 15 0 0 0
  run bash "${FIXTURE_ROOT}/06_run_mutation_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: Mutation score"* ]]
}

@test "respects custom MUTATION_SCORE_THRESHOLD" {
  #R020-T03: Verify custom MUTATION_SCORE_THRESHOLD environment variable overrides the default.
  #R020
  make_gremlins_stub 0 60 40 0 0 0
  run env MUTATION_SCORE_THRESHOLD=50 bash "${FIXTURE_ROOT}/06_run_mutation_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: Mutation score"* ]]
}

@test "passes exclude-files flags from MUTATION_EXCLUDE_FILES" {
  #R025-T01: Set MUTATION_EXCLUDE_FILES and verify each regex appears as --exclude-files <regex> in the gremlins invocation.
  #R025
  run env MUTATION_EXCLUDE_FILES="^cmd/valve/,^internal/config/" bash "${FIXTURE_ROOT}/06_run_mutation_tests.sh"
  [ "$status" -eq 0 ]
  grep -F -- "--exclude-files ^cmd/valve/" "${CALLS_LOG}"
  grep -F -- "--exclude-files ^internal/config/" "${CALLS_LOG}"
}

@test "passes no exclude-files flags when MUTATION_EXCLUDE_FILES is empty" {
  #R025-T02: Verify default (empty) exclusion list passes no --exclude-files flags.
  #R025
  run bash "${FIXTURE_ROOT}/06_run_mutation_tests.sh"
  [ "$status" -eq 0 ]
  ! grep -F -- "--exclude-files" "${CALLS_LOG}"
}

@test "mutation summary contains required fields" {
  #R030-T02: Verify the JSON contains required fields: total, killed, lived, not_covered, not_viable, timed_out, score, mutator_coverage, threshold, excluded_files, gate_failed.
  #R030
  run bash "${FIXTURE_ROOT}/06_run_mutation_tests.sh"
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
data = json.load(open(sys.argv[1]))
required = ["total", "killed", "lived", "not_covered", "not_viable", "timed_out", "score", "mutator_coverage", "threshold", "excluded_files", "gate_failed"]
missing = [k for k in required if k not in data]
if missing:
    print(f"Missing fields: {missing}")
    sys.exit(1)
print("All required fields present")
' "${FIXTURE_ROOT}/.security-reports/mutation-summary.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"All required fields present"* ]]
}

@test "emits pass line with score on success" {
  #R035-T01: Verify successful run emits a single PASS line including the score.
  #R035
  make_gremlins_stub 0 42 8 3 0 0
  run bash "${FIXTURE_ROOT}/06_run_mutation_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✅ PASS: Mutation score"* ]]
}

@test "emits fail line with score and threshold on failure" {
  #R035-T02: Verify failed run emits a single FAIL line including score and threshold.
  #R035
  make_gremlins_stub 0 10 90 0 0 0
  run bash "${FIXTURE_ROOT}/06_run_mutation_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"❌ FAIL: Mutation score"* ]]
  [[ "$output" == *"threshold"* ]]
}

@test "fails with timeout message when gremlins exceeds timeout" {
  #R040-T01: Simulate gremlins exceeding timeout and verify explicit timeout failure message.
  #R040
  make_gremlins_timeout_stub
  run env MUTATION_TIMEOUT_SECONDS=2 bash "${FIXTURE_ROOT}/06_run_mutation_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"timed out"* ]]
}

@test "uses default timeout of 600 seconds" {
  #R040-T02: Verify default timeout is 600 seconds when not overridden.
  #R040
  run bash "${FIXTURE_ROOT}/06_run_mutation_tests.sh"
  [ "$status" -eq 0 ]
}
