#!/usr/bin/env bash
#R001: Run QED LLM eval workflows in strict fail-fast mode from repository root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"
VALVE_ROOT="${SCRIPT_DIR}"

QED_REPO_PATH="${QED_REPO_PATH:-/Users/phil/local/src/qed}"
QED_ENTRYPOINT="${QED_REPO_PATH}/cmd/qed"
DEFAULT_MODE="run"
MODE="${1:-${DEFAULT_MODE}}"

#R005: Fail fast when go is unavailable.
if ! command -v go >/dev/null; then
  echo "go is required but was not found on PATH."
  exit 1
fi

#R005: Fail fast when 1psa is unavailable.
if ! command -v 1psa >/dev/null; then
  echo "1psa is required but was not found on PATH."
  exit 1
fi

#R010: Fail fast when the local QED repository entrypoint is unavailable.
if [ ! -d "${QED_ENTRYPOINT}" ]; then
  echo "QED entrypoint not found at ${QED_ENTRYPOINT}."
  echo "Set QED_REPO_PATH to your local qed repository path."
  exit 1
fi

#R015: Validate mode argument and print usage for unsupported values.
if [ "${MODE}" != "run" ] && [ "${MODE}" != "save-baseline" ] && [ "${MODE}" != "compare" ] && [ "${MODE}" != "all" ] && [ "${MODE}" != "repo-quality-only" ] && [ "${MODE}" != "live-only" ]; then
  echo "Usage: ./11_run_llm_evals.sh [run|save-baseline|compare|all|repo-quality-only|live-only]"
  exit 1
fi

read_1psa_secret() {
  local item="$1"
  1psa -p "${item}"
}

#R020: Read OpenAI and Anthropic API keys from 1psa before invoking QED.
OPENAI_API_KEY="$(read_1psa_secret "openai_api_key")"
if [ -z "${OPENAI_API_KEY}" ]; then
  echo "Failed to read OPENAI_API_KEY from 1psa item: openai_api_key"
  exit 1
fi

ANTHROPIC_API_KEY="$(read_1psa_secret "anthropic_api_key")"
if [ -z "${ANTHROPIC_API_KEY}" ]; then
  echo "Failed to read ANTHROPIC_API_KEY from 1psa item: anthropic_api_key"
  exit 1
fi

export OPENAI_API_KEY
export ANTHROPIC_API_KEY

run_qed() {
  go -C "${QED_REPO_PATH}" run ./cmd/qed "$@"
}

run_suite() {
  local spec_path="$1"
  local report_path="$2"
  local baseline_path="$3"
  echo ""
  echo "▶ Running eval suite: ${spec_path}"
  run_qed eval run --spec "${VALVE_ROOT}/${spec_path}" --json "${VALVE_ROOT}/${report_path}" --baseline "${VALVE_ROOT}/${baseline_path}" --ci
}

save_suite_baseline() {
  local spec_path="$1"
  local report_path="$2"
  local baseline_path="$3"
  echo ""
  echo "▶ Saving baseline from suite: ${spec_path}"
  run_qed eval run --spec "${VALVE_ROOT}/${spec_path}" --json "${VALVE_ROOT}/${report_path}" --baseline "${VALVE_ROOT}/${baseline_path}" --save-baseline --ci
}

compare_suite() {
  local spec_path="$1"
  local report_path="$2"
  local baseline_path="$3"
  echo ""
  echo "▶ Comparing suite report vs baseline: ${spec_path}"
  run_qed eval compare --current "${VALVE_ROOT}/${report_path}" --baseline "${VALVE_ROOT}/${baseline_path}" --ci
}

#R025: Default recorded eval execution across all bundled suites.
run_all_suites() {
  run_suite ".qed/evals/api_recorded.yaml" ".qed/evals/results/api-recorded-report.json" ".qed/baselines/api-recorded-baseline.json"
  run_suite ".qed/evals/scripts_recorded.yaml" ".qed/evals/results/scripts-recorded-report.json" ".qed/baselines/scripts-recorded-baseline.json"
  run_suite ".qed/evals/repo_quality_recorded.yaml" ".qed/evals/results/repo-quality-recorded-report.json" ".qed/baselines/repo-quality-recorded-baseline.json"
  run_suite ".qed/evals/combined_recorded.yaml" ".qed/evals/results/combined-recorded-report.json" ".qed/baselines/combined-recorded-baseline.json"
}

#R030: Support baseline, compare, and selective suite modes.
save_all_baselines() {
  save_suite_baseline ".qed/evals/api_recorded.yaml" ".qed/evals/results/api-recorded-report.json" ".qed/baselines/api-recorded-baseline.json"
  save_suite_baseline ".qed/evals/scripts_recorded.yaml" ".qed/evals/results/scripts-recorded-report.json" ".qed/baselines/scripts-recorded-baseline.json"
  save_suite_baseline ".qed/evals/repo_quality_recorded.yaml" ".qed/evals/results/repo-quality-recorded-report.json" ".qed/baselines/repo-quality-recorded-baseline.json"
  save_suite_baseline ".qed/evals/combined_recorded.yaml" ".qed/evals/results/combined-recorded-report.json" ".qed/baselines/combined-recorded-baseline.json"
}

compare_all_suites() {
  compare_suite ".qed/evals/api_recorded.yaml" ".qed/evals/results/api-recorded-report.json" ".qed/baselines/api-recorded-baseline.json"
  compare_suite ".qed/evals/scripts_recorded.yaml" ".qed/evals/results/scripts-recorded-report.json" ".qed/baselines/scripts-recorded-baseline.json"
  compare_suite ".qed/evals/repo_quality_recorded.yaml" ".qed/evals/results/repo-quality-recorded-report.json" ".qed/baselines/repo-quality-recorded-baseline.json"
  compare_suite ".qed/evals/combined_recorded.yaml" ".qed/evals/results/combined-recorded-report.json" ".qed/baselines/combined-recorded-baseline.json"
}

if [ "${MODE}" = "run" ]; then
  run_all_suites
fi

if [ "${MODE}" = "save-baseline" ]; then
  save_all_baselines
fi

if [ "${MODE}" = "compare" ]; then
  compare_all_suites
fi

if [ "${MODE}" = "all" ]; then
  run_all_suites
  save_all_baselines
  compare_all_suites
fi

if [ "${MODE}" = "repo-quality-only" ]; then
  run_suite ".qed/evals/repo_quality_recorded.yaml" ".qed/evals/results/repo-quality-recorded-report.json" ".qed/baselines/repo-quality-recorded-baseline.json"
fi

#R035: Support optional live eval mode with graceful skip and health preflight.
if [ "${MODE}" = "live-only" ]; then
  if [ -z "${VALVE_DATABASE_URL:-}" ] && [ -z "${VALVE_TEST_DATABASE_URL:-}" ]; then
    echo "ℹ️  Live QED eval skipped: set VALVE_DATABASE_URL or VALVE_TEST_DATABASE_URL."
    exit 0
  fi
  if [ -z "${VALVE_BASE_URL:-}" ]; then
    export VALVE_BASE_URL="http://127.0.0.1:8090"
  fi
  if ! curl -fsS "${VALVE_BASE_URL%/}/healthz" >/dev/null 2>&1; then
    echo "ℹ️  Live QED eval expects a running Valve at ${VALVE_BASE_URL}."
    echo "Start backend with ./09_run_backend.sh or export VALVE_BASE_URL to a reachable service."
    exit 1
  fi
  run_suite ".qed/evals/api_live.yaml" ".qed/evals/results/api-live-smoke-report.json" ".qed/baselines/api-live-smoke-baseline.json"
fi

echo ""
echo "✅ QED eval workflow complete (${MODE})."
