#!/usr/bin/env bash
umask 007
#R001: Run in strict fail-fast mode from repository root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

REPORT_DIR="${MUTATION_REPORT_DIR:-./.security-reports}"
MUTATION_SCORE_THRESHOLD="${MUTATION_SCORE_THRESHOLD:-80}"
MUTATOR_COVERAGE_THRESHOLD="${MUTATOR_COVERAGE_THRESHOLD:-70}"
MUTATION_EXCLUDE_FILES="${MUTATION_EXCLUDE_FILES:-}"
MUTATION_TIMEOUT_SECONDS="${MUTATION_TIMEOUT_SECONDS:-600}"

if [[ "${REPORT_DIR}" != /* ]]; then
  REPORT_DIR="${SCRIPT_DIR}/${REPORT_DIR#./}"
fi

mkdir -p "$REPORT_DIR"

MUTATION_SUMMARY="${REPORT_DIR}/mutation-summary.json"
GREMLINS_JSON="${REPORT_DIR}/gremlins.json"

resolve_go_bin_dir() {
  local go_bin_dir=""
  go_bin_dir="$(go env GOBIN 2>/dev/null || true)"
  if [ -n "${go_bin_dir}" ]; then
    echo "${go_bin_dir}"
    return 0
  fi
  go_bin_dir="$(go env GOPATH 2>/dev/null || true)"
  if [ -n "${go_bin_dir}" ]; then
    echo "${go_bin_dir}/bin"
    return 0
  fi
  return 1
}

resolve_go_tool() {
  local tool_name="$1"
  local go_bin_dir=""
  if command -v "${tool_name}" >/dev/null 2>&1; then
    echo "${tool_name}"
    return 0
  fi
  if go_bin_dir="$(resolve_go_bin_dir)"; then
    if [ -x "${go_bin_dir}/${tool_name}" ]; then
      echo "${go_bin_dir}/${tool_name}"
      return 0
    fi
  fi
  return 1
}

#R005: Fail fast when required commands are unavailable.
if ! command -v go >/dev/null 2>&1; then
  echo "❌ Missing required command: go"
  echo "Install prerequisites with: ./01_install_prerequisites.sh"
  exit 1
fi
GREMLINS_CMD="gremlins"
if resolved_gremlins="$(resolve_go_tool gremlins)"; then
  GREMLINS_CMD="${resolved_gremlins}"
  if [ "${GREMLINS_CMD}" != "gremlins" ]; then
    export PATH="$(dirname "${GREMLINS_CMD}"):${PATH}"
  fi
else
  echo "❌ Missing required command: gremlins"
  echo "Install prerequisites with: ./01_install_prerequisites.sh"
  exit 1
fi

#R010: Require unit tests to pass before mutation testing begins.
echo ""
echo "▶ Preflight: verifying unit tests pass..."
PREFLIGHT_OUTPUT="$(mktemp)"
set +e
go test ./... > "$PREFLIGHT_OUTPUT" 2>&1
PREFLIGHT_EXIT=$?
set -e
if [ "$PREFLIGHT_EXIT" -ne 0 ]; then
  echo "❌ Unit tests failed. Fix tests first with: ./05_run_unit_tests.sh"
  cat "$PREFLIGHT_OUTPUT"
  exit 1
fi
echo "✅ Preflight passed."

#R025: Build --exclude-files regex flags from MUTATION_EXCLUDE_FILES.
GREMLINS_EXCLUDE_ARGS=()
if [ -n "$MUTATION_EXCLUDE_FILES" ]; then
  IFS=',' read -ra EXCLUDE_LIST <<< "$MUTATION_EXCLUDE_FILES"
  for regex in "${EXCLUDE_LIST[@]}"; do
    regex="$(echo "$regex" | xargs)"
    if [ -n "$regex" ]; then
      GREMLINS_EXCLUDE_ARGS+=(--exclude-files "$regex")
    fi
  done
fi

#R040: Run gremlins with timeout protection.
run_with_timeout() {
  local timeout_seconds="$1"
  shift
  python3 - "$timeout_seconds" "$@" <<'PY'
import os
import signal
import subprocess
import sys

timeout_seconds = int(sys.argv[1])
command = sys.argv[2:]
if timeout_seconds <= 0:
    timeout_seconds = 1

proc = subprocess.Popen(command, preexec_fn=os.setsid)
try:
    proc.wait(timeout=timeout_seconds)
    raise SystemExit(proc.returncode)
except subprocess.TimeoutExpired:
    os.killpg(proc.pid, signal.SIGTERM)
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.wait()
    raise SystemExit(124)
PY
}

#R015: Run gremlins from module root, capturing machine-readable JSON.
echo ""
echo "▶ Running mutation tests (gremlins)..."
GREMLINS_OUTPUT="$(mktemp)"
rm -f "$GREMLINS_JSON"
set +e
run_with_timeout "$MUTATION_TIMEOUT_SECONDS" \
  "$GREMLINS_CMD" unleash --tags '' \
  ${GREMLINS_EXCLUDE_ARGS[@]+"${GREMLINS_EXCLUDE_ARGS[@]}"} \
  -o "$GREMLINS_JSON" > "$GREMLINS_OUTPUT" 2>&1
GREMLINS_EXIT=$?
set -e

#R040: Detect timeout.
if [ "$GREMLINS_EXIT" -eq 124 ]; then
  echo "❌ Mutation testing timed out after ${MUTATION_TIMEOUT_SECONDS}s."
  exit 1
fi

#R015: Fail loudly when gremlins did not produce results (e.g. wrong path,
# no covered mutants). Reporting 0.0% on an empty run masks misconfiguration.
if [ ! -s "$GREMLINS_JSON" ]; then
  echo "❌ gremlins produced no results (no JSON written)."
  echo "    This usually means no covered mutants were found or the invocation is misconfigured."
  cat "$GREMLINS_OUTPUT"
  exit 1
fi

if [ "$GREMLINS_EXIT" -gt 1 ]; then
  echo "❌ gremlins failed to execute (exit code ${GREMLINS_EXIT})."
  cat "$GREMLINS_OUTPUT"
  exit 1
fi

#R020: Parse gremlins JSON and gate on test_efficacy.
#R022: Additionally gate on mutator coverage so that low-signal runs (many TIMED OUT
#      or NOT COVERED mutants) cannot pass on a handful of fast verdicts alone.
#R030: Persist machine-readable mutation testing report.
#R035: Emit concise operator-readable pass or fail output.
python3 - "$GREMLINS_JSON" "$MUTATION_SUMMARY" "$MUTATION_SCORE_THRESHOLD" "$MUTATOR_COVERAGE_THRESHOLD" "$MUTATION_EXCLUDE_FILES" <<'PY'
import json
import sys
from pathlib import Path

gremlins_path = Path(sys.argv[1])
summary_path = Path(sys.argv[2])
score_threshold = float(sys.argv[3])
coverage_threshold = float(sys.argv[4])
excluded_files = [p.strip() for p in sys.argv[5].split(",") if p.strip()] if sys.argv[5] else []

data = json.loads(gremlins_path.read_text(encoding="utf-8"))

killed = int(data.get("mutants_killed", 0))
lived = int(data.get("mutants_lived", 0))
not_covered = int(data.get("mutants_not_covered", 0))
not_viable = int(data.get("mutants_not_viable", 0))
total = int(data.get("mutants_total", killed + lived))
score = float(data.get("test_efficacy", 0.0))
mutator_coverage = float(data.get("mutations_coverage", 0.0))

timed_out = 0
for file_entry in data.get("files", []) or []:
    for mutation in file_entry.get("mutations", []) or []:
        if str(mutation.get("status", "")).upper() == "TIMED OUT":
            timed_out += 1

score_failed = score < score_threshold
coverage_failed = mutator_coverage < coverage_threshold
gate_failed = score_failed or coverage_failed

summary = {
    "total": total,
    "killed": killed,
    "lived": lived,
    "not_covered": not_covered,
    "not_viable": not_viable,
    "timed_out": timed_out,
    "score": score,
    "mutator_coverage": mutator_coverage,
    "threshold": score_threshold,
    "coverage_threshold": coverage_threshold,
    "excluded_files": excluded_files,
    "score_failed": score_failed,
    "coverage_failed": coverage_failed,
    "gate_failed": gate_failed,
}

summary_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")

if score_failed:
    print(f"❌ FAIL: Mutation score {score}% is below threshold {score_threshold}%.")
if coverage_failed:
    print(f"❌ FAIL: Mutator coverage {mutator_coverage}% is below threshold {coverage_threshold}%.")
if gate_failed:
    raise SystemExit(1)
print(
    f"✅ PASS: Mutation score {score}% (threshold {score_threshold}%), "
    f"mutator coverage {mutator_coverage}% (threshold {coverage_threshold}%)."
)
PY

echo ""
echo "✅ Mutation testing completed. Report: ${MUTATION_SUMMARY}"
