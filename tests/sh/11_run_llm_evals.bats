#!/usr/bin/env bats

load "helpers/common.bash"

make_go_qed_stub() {
  cat > "${STUB_BIN}/go" <<EOF
#!/usr/bin/env bash
echo "go \$*" >> "${CALLS_LOG}"
if [[ "\$1" == "-C" ]] && [[ "\$3" == "run" ]] && [[ "\$4" == "./cmd/qed" ]]; then
  exit 0
fi
exit 1
EOF
  chmod +x "${STUB_BIN}/go"
}

make_1psa_llm_stub() {
  cat > "${STUB_BIN}/1psa" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "-p" ]; then
  case "${2:-}" in
    openai_api_key)
      printf '%s\n' "${OPENAI_STUB_KEY-openai-stub-key}"
      ;;
    anthropic_api_key)
      printf '%s\n' "${ANTHROPIC_STUB_KEY-anthropic-stub-key}"
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

make_curl_stub() {
  local exit_code="${1:-0}"
  cat > "${STUB_BIN}/curl" <<EOF
#!/usr/bin/env bash
echo "curl \$*" >> "${CALLS_LOG}"
exit ${exit_code}
EOF
  chmod +x "${STUB_BIN}/curl"
}

setup_qed_repo() {
  export QED_REPO_PATH="${TEST_TMPDIR}/qed"
  mkdir -p "${QED_REPO_PATH}/cmd/qed"
}

setup_eval_artifacts() {
  mkdir -p "${FIXTURE_ROOT}/.qed/evals/results"
  mkdir -p "${FIXTURE_ROOT}/.qed/baselines"
  touch "${FIXTURE_ROOT}/.qed/evals/api_recorded.yaml"
  touch "${FIXTURE_ROOT}/.qed/evals/scripts_recorded.yaml"
  touch "${FIXTURE_ROOT}/.qed/evals/repo_quality_recorded.yaml"
  touch "${FIXTURE_ROOT}/.qed/evals/combined_recorded.yaml"
  touch "${FIXTURE_ROOT}/.qed/evals/api_live.yaml"
  touch "${FIXTURE_ROOT}/.qed/evals/results/api-recorded-report.json"
  touch "${FIXTURE_ROOT}/.qed/evals/results/scripts-recorded-report.json"
  touch "${FIXTURE_ROOT}/.qed/evals/results/repo-quality-recorded-report.json"
  touch "${FIXTURE_ROOT}/.qed/evals/results/combined-recorded-report.json"
  touch "${FIXTURE_ROOT}/.qed/evals/results/api-live-smoke-report.json"
  touch "${FIXTURE_ROOT}/.qed/baselines/api-recorded-baseline.json"
  touch "${FIXTURE_ROOT}/.qed/baselines/scripts-recorded-baseline.json"
  touch "${FIXTURE_ROOT}/.qed/baselines/repo-quality-recorded-baseline.json"
  touch "${FIXTURE_ROOT}/.qed/baselines/combined-recorded-baseline.json"
  touch "${FIXTURE_ROOT}/.qed/baselines/api-live-smoke-baseline.json"
}

setup_fixture() {
  create_repo_fixture
  copy_script_to_fixture "11_run_llm_evals.sh"
  setup_qed_repo
  setup_eval_artifacts
}

setup() {
  setup_shell_test
  setup_fixture
}

teardown() {
  teardown_shell_test
}

run_llm_evals() {
  run env QED_REPO_PATH="${QED_REPO_PATH}" PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/11_run_llm_evals.sh" "$@"
}

@test "runs default mode from non-repo cwd" {
  #R001-T01: Run from non-repo cwd with stubs and verify successful completion.
  #R001
  make_go_qed_stub
  make_1psa_llm_stub
  mkdir -p "${TEST_TMPDIR}/elsewhere"
  run env QED_REPO_PATH="${QED_REPO_PATH}" PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash -c "cd '${TEST_TMPDIR}/elsewhere' && bash '${FIXTURE_ROOT}/11_run_llm_evals.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"QED eval workflow complete (run)."* ]]
}

@test "fails when go is missing" {
  #R005-T01: Run with go missing from PATH and verify non-zero failure output.
  #R005
  make_1psa_llm_stub
  run env QED_REPO_PATH="${QED_REPO_PATH}" PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/11_run_llm_evals.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"go is required"* ]]
}

@test "fails when 1psa is missing" {
  #R005-T02: Run with 1psa missing from PATH and verify non-zero failure output.
  #R005
  make_go_qed_stub
  run env QED_REPO_PATH="${QED_REPO_PATH}" PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/11_run_llm_evals.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"1psa is required"* ]]
}

@test "fails when qed entrypoint is missing" {
  #R010-T01: Run with QED_REPO_PATH missing cmd/qed and verify non-zero failure output.
  #R010
  make_go_qed_stub
  make_1psa_llm_stub
  run env QED_REPO_PATH="${TEST_TMPDIR}/missing-qed" PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/11_run_llm_evals.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"QED entrypoint not found"* ]]
}

@test "fails for invalid mode argument" {
  #R015-T01: Run with invalid mode and verify usage output plus non-zero exit.
  #R015
  make_go_qed_stub
  make_1psa_llm_stub
  run env QED_REPO_PATH="${QED_REPO_PATH}" PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/11_run_llm_evals.sh" invalid-mode
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage: ./11_run_llm_evals.sh"* ]]
}

@test "fails when openai key is empty" {
  #R020-T01: Run with empty OpenAI key from 1psa and verify non-zero failure output.
  #R020
  make_go_qed_stub
  make_1psa_llm_stub
  run env QED_REPO_PATH="${QED_REPO_PATH}" OPENAI_STUB_KEY="" PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/11_run_llm_evals.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to read OPENAI_API_KEY"* ]]
}

@test "fails when anthropic key is empty" {
  #R020-T02: Run with empty Anthropic key from 1psa and verify non-zero failure output.
  #R020
  make_go_qed_stub
  make_1psa_llm_stub
  run env QED_REPO_PATH="${QED_REPO_PATH}" ANTHROPIC_STUB_KEY="" PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/11_run_llm_evals.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to read ANTHROPIC_API_KEY"* ]]
}

@test "default run mode invokes all recorded suites" {
  #R025-T01: Run default mode with stubs and verify all four recorded suite spec paths appear in logs.
  #R025
  make_go_qed_stub
  make_1psa_llm_stub
  run_llm_evals
  [ "$status" -eq 0 ]
  run grep -F "api_recorded.yaml" "${CALLS_LOG}"
  [ "$status" -eq 0 ]
  run grep -F "scripts_recorded.yaml" "${CALLS_LOG}"
  [ "$status" -eq 0 ]
  run grep -F "repo_quality_recorded.yaml" "${CALLS_LOG}"
  [ "$status" -eq 0 ]
  run grep -F "combined_recorded.yaml" "${CALLS_LOG}"
  [ "$status" -eq 0 ]
}

@test "repo-quality-only mode invokes single suite" {
  #R030-T01: Run repo-quality-only with stubs and verify only repo-quality spec is invoked.
  #R030
  make_go_qed_stub
  make_1psa_llm_stub
  run_llm_evals repo-quality-only
  [ "$status" -eq 0 ]
  run grep -F "repo_quality_recorded.yaml" "${CALLS_LOG}"
  [ "$status" -eq 0 ]
  run grep -F "api_recorded.yaml" "${CALLS_LOG}"
  [ "$status" -ne 0 ]
}

@test "compare mode invokes qed eval compare" {
  #R030-T02: Run compare with stubs and verify QED eval compare --ci is invoked.
  #R030
  make_go_qed_stub
  make_1psa_llm_stub
  run_llm_evals compare
  [ "$status" -eq 0 ]
  run grep -F "eval compare" "${CALLS_LOG}"
  [ "$status" -eq 0 ]
}

@test "live-only skips when database url is unset" {
  #R035-T01: Run live-only without database URL and verify success with skip output.
  #R035
  make_go_qed_stub
  make_1psa_llm_stub
  run_llm_evals live-only
  [ "$status" -eq 0 ]
  [[ "$output" == *"Live QED eval skipped"* ]]
}

@test "live-only fails when health probe fails" {
  #R035-T02: Run live-only with database URL set but failing health probe and verify non-zero failure.
  #R035
  make_go_qed_stub
  make_1psa_llm_stub
  make_curl_stub 1
  run env QED_REPO_PATH="${QED_REPO_PATH}" VALVE_DATABASE_URL="postgres://example" PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/11_run_llm_evals.sh" live-only
  [ "$status" -ne 0 ]
  [[ "$output" == *"Live QED eval expects a running Valve"* ]]
}
