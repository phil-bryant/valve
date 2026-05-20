#!/usr/bin/env bash
#R001: Enforce strict fail-fast execution semantics.
set -euo pipefail

#R005: Resolve valve credential from dedicated 1psa item.
VALVE_PSA_ITEM="${VALVE_PSA_ITEM:-localhost_postgres_valve}"
VALVE_PSA_FIELD="${VALVE_PSA_FIELD:-password}"
DB_HOST="localhost"
DB_PORT="5432"
DB_NAME="valve"
DB_USER="valve"

if ! command -v 1psa >/dev/null; then
  echo "1psa is required but was not found on PATH."
  exit 1
fi

read_1psa_secret() {
  local item="$1"
  local field="$2"
  if [ "$field" = "password" ]; then
    1psa -p "$item"
  else
    1psa -f "$item" "$field"
  fi
}

DB_PASSWORD="$(read_1psa_secret "$VALVE_PSA_ITEM" "$VALVE_PSA_FIELD")"
if [ -z "$DB_PASSWORD" ]; then
  echo "Failed to resolve valve password from 1psa item: ${VALVE_PSA_ITEM}"
  exit 1
fi
DB_SCHEMA="$(read_1psa_secret "$VALVE_PSA_ITEM" "schema")"
if [ -z "$DB_SCHEMA" ]; then
  echo "Failed to resolve valve schema name from 1psa item: ${VALVE_PSA_ITEM}"
  exit 1
fi
if [[ ! "${DB_SCHEMA}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
  echo "Failed to resolve valve schema name from 1psa item: ${VALVE_PSA_ITEM}"
  exit 1
fi

#R010: Refuse SQL unit tests when psql is unavailable.
if ! command -v psql >/dev/null; then
  echo "psql is required but was not found on PATH."
  exit 1
fi

#R010: Refuse unit tests when go is unavailable.
if ! command -v go >/dev/null; then
  echo "go is required but was not found on PATH."
  exit 1
fi

#R010: Refuse unit tests when bats is unavailable.
if ! command -v bats >/dev/null; then
  echo "bats is required but was not found on PATH."
  exit 1
fi

#R010: Refuse unit tests when swift is unavailable.
if ! command -v swift >/dev/null; then
  echo "swift is required but was not found on PATH."
  exit 1
fi

#R015: Resolve SQL test file path from script directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_TEST_FILE="${SCRIPT_DIR}/storage/sql/unit/ingest_schema_pgtap.sql"
PSQL_COMMON_ARGS=(-w -P pager=off -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -v "VALVE_SCHEMA=${DB_SCHEMA}")

#R020: Fail clearly when SQL unit-test file is missing.
if [ ! -f "$SQL_TEST_FILE" ]; then
  echo "SQL unit-test file not found: ${SQL_TEST_FILE}"
  exit 1
fi

print_runner_header() {
  local runner_name="$1"
  local explainer_line_1="$2"
  local explainer_line_2="$3"
  local runner_url="$4"
  local border="+==============================================================================+"
  printf '%s\n' "$border"
  printf '| %-76s |\n' "Test Runner: ${runner_name}"
  printf '| %-76s |\n' "${explainer_line_1}"
  printf '| %-76s |\n' "${explainer_line_2}"
  printf '| %-76s |\n' "URL: ${runner_url}"
  printf '%s\n' "$border"
}

#R025: Ensure pgTAP extension exists in target database.
print_runner_header \
  "pgTAP" \
  "SQL unit testing framework for PostgreSQL stored logic." \
  "Runs ingest_schema_pgtap.sql against the local valve database." \
  "https://pgtap.org/"
echo ""
echo "▶ Running SQL unit tests (pgTAP)..."
PGPASSWORD="$DB_PASSWORD" \
  psql "${PSQL_COMMON_ARGS[@]}" -c "CREATE EXTENSION IF NOT EXISTS pgtap;"

#R030: Execute SQL unit tests first with fail-fast psql settings.
PGPASSWORD="$DB_PASSWORD" \
  psql "${PSQL_COMMON_ARGS[@]}" -f "$SQL_TEST_FILE"

#R030: Run Go unit tests only after SQL unit tests pass.
print_runner_header \
  "go test" \
  "Go native unit test runner across all repository packages." \
  "Executes _test.go files with fail-fast semantics on first failure." \
  "https://pkg.go.dev/cmd/go#hdr-Test_packages"
echo ""
echo "▶ Running Go unit tests..."
GO_COVERAGE_THRESHOLD="${GO_COVERAGE_THRESHOLD:-70}"
GO_COVERAGE_PACKAGES="${GO_COVERAGE_PACKAGES:-./internal/credentials ./internal/config ./internal/auth ./internal/httpserver ./internal/security ./internal/logging}"
COVERAGE_PROFILE="${SCRIPT_DIR}/.security-reports/go-coverage.out"
mkdir -p "${SCRIPT_DIR}/.security-reports"
GO_TEST_OUTPUT_FILE="$(mktemp)"
if ! go test ./... | tee "$GO_TEST_OUTPUT_FILE"; then
  exit 1
fi

#R038: Enforce a minimum Go line coverage threshold across core unit-tested packages.
print_runner_header \
  "go tool cover" \
  "Measures statement coverage for core internal packages." \
  "Fails when total coverage falls below GO_COVERAGE_THRESHOLD." \
  "https://pkg.go.dev/cmd/cover"
echo ""
echo "▶ Checking Go coverage threshold (${GO_COVERAGE_THRESHOLD}%)..."
go test ${GO_COVERAGE_PACKAGES} -coverprofile="${COVERAGE_PROFILE}" >/dev/null
python3 - "${COVERAGE_PROFILE}" "${GO_COVERAGE_THRESHOLD}" "${SCRIPT_DIR}/.security-reports/coverage-summary.json" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

profile = Path(sys.argv[1])
threshold = float(sys.argv[2])
summary_path = Path(sys.argv[3])

if not profile.exists():
    print(f"❌ Go coverage profile not found: {profile}")
    raise SystemExit(1)

result = subprocess.run(
    ["go", "tool", "cover", "-func", str(profile)],
    capture_output=True,
    text=True,
    check=False,
)
if result.returncode != 0:
    print(result.stderr)
    raise SystemExit(1)

coverage_percent = 0.0
for line in result.stdout.splitlines():
    if line.strip().startswith("total:"):
        coverage_percent = float(line.split()[-1].replace("%", ""))
        break

payload = {
    "coverage_percent": round(coverage_percent, 2),
    "threshold_percent": threshold,
    "gate_failed": coverage_percent < threshold,
}
summary_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
print(json.dumps(payload, indent=2))
if payload["gate_failed"]:
    print(
        f"❌ Go coverage gate failed: {coverage_percent:.2f}% < {threshold:.2f}% threshold."
    )
    raise SystemExit(1)
PY

#R030: Run Bats shell tests only after Go unit tests pass.
print_runner_header \
  "Bats" \
  "Shell script test framework for repository automation scripts." \
  "Runs tests/sh Bats specs to verify script behavior and contracts." \
  "https://bats-core.readthedocs.io/"
echo ""

#R040: Discover bats test files under tests/sh and run them in parallel by
# file via `xargs -P`, buffering each file's stdout/stderr to a tempfile and
# dumping it atomically with a "===== <basename> =====" banner once the file
# finishes. TAP formatter + --print-output-on-failure + --timing preserve
# every line bats emits today (per-test ok/not-ok, failure diagnostics, and
# per-test ms). Default concurrency is `sysctl -n hw.ncpu`. When invoked
# under an outer parallel meta-runner that exports PARALLEL_LANES>1, we
# divide so total inner+outer concurrency stays near hw.ncpu. BATS_JOBS
# overrides the default; BATS_FILTER and BATS_FILTER_STATUS forward to bats.
BATS_DIR="${SCRIPT_DIR}/tests/sh"
if [ ! -d "$BATS_DIR" ]; then
  echo "❌ Bats test directory not found: $BATS_DIR"
  exit 1
fi

bats_default_jobs="$(sysctl -n hw.ncpu 2>/dev/null || echo 8)"
if [[ "${PARALLEL_LANES:-1}" =~ ^[0-9]+$ ]] && [ "${PARALLEL_LANES:-1}" -gt 1 ]; then
  bats_default_jobs=$(( bats_default_jobs / PARALLEL_LANES ))
  [ "$bats_default_jobs" -lt 1 ] && bats_default_jobs=1
fi
BATS_JOBS_RESOLVED="${BATS_JOBS:-$bats_default_jobs}"

BATS_TMP_DIR="$(mktemp -d)"
cleanup_bats_tmp() { rm -rf "$BATS_TMP_DIR"; }
trap cleanup_bats_tmp EXIT

bats_file_count=$(find "$BATS_DIR" -maxdepth 1 -name '*.bats' | wc -l | tr -d ' ')
if [ "$bats_file_count" -eq 0 ]; then
  echo "❌ No bats files found in $BATS_DIR"
  exit 1
fi

#R040: Two parallel modes. Default is per-file xargs (no deps, file-atomic
# output). When BATS_USE_NATIVE_JOBS=true and GNU `parallel` is on PATH,
# delegate to `bats -j N` so within-file parallelism kicks in too. Both
# modes pass --print-output-on-failure --timing so failure diagnostics and
# per-test ms remain visible; both modes honor BATS_FILTER / BATS_FILTER_STATUS.
bats_native_args=(--print-output-on-failure --timing)
[ -n "${BATS_FILTER:-}" ] && bats_native_args+=(-f "${BATS_FILTER}")
[ -n "${BATS_FILTER_STATUS:-}" ] && bats_native_args+=(--filter-status "${BATS_FILTER_STATUS}")

if [ "${BATS_USE_NATIVE_JOBS:-false}" = "true" ] && command -v parallel >/dev/null 2>&1; then
  echo "▶ Running Bats shell tests (bats -j ${BATS_JOBS_RESOLVED}, files=${bats_file_count}, GNU parallel)..."
  bats -j "$BATS_JOBS_RESOLVED" --no-parallelize-within-files \
    "${bats_native_args[@]}" "$BATS_DIR"
else
  if [ "${BATS_USE_NATIVE_JOBS:-false}" = "true" ]; then
    echo "▶ BATS_USE_NATIVE_JOBS=true but GNU parallel not on PATH; falling back to xargs -P."
  fi
  echo "▶ Running Bats shell tests (parallel by file, jobs=${BATS_JOBS_RESOLVED}, files=${bats_file_count})..."
  bats_status=0
  find "$BATS_DIR" -maxdepth 1 -name '*.bats' -print0 \
    | BATS_TMP_DIR="$BATS_TMP_DIR" BATS_FILTER="${BATS_FILTER:-}" \
      BATS_FILTER_STATUS="${BATS_FILTER_STATUS:-}" \
      xargs -0 -P "$BATS_JOBS_RESOLVED" -I {} bash -c '
        f="$1"
        base="$(basename "$f")"
        out="${BATS_TMP_DIR}/${base}.tap"
        args=(--tap --print-output-on-failure --timing)
        [ -n "${BATS_FILTER}" ] && args+=(-f "${BATS_FILTER}")
        [ -n "${BATS_FILTER_STATUS}" ] && args+=(--filter-status "${BATS_FILTER_STATUS}")
        bats "${args[@]}" "$f" >"$out" 2>&1
        rc=$?
        printf "\n===== %s =====\n" "$base"
        cat "$out"
        exit $rc
      ' _ {} \
    || bats_status=$?
  if [ "$bats_status" -ne 0 ]; then
    exit "$bats_status"
  fi
fi

#R037: Run Swift package tests after Bats shell tests pass.
print_runner_header \
  "Swift Package Manager" \
  "Runs XCTest targets in the macOS ValveProvisioningApp package." \
  "Validates Swift feature code after shell and Go stages pass." \
  "https://docs.swift.org/package-manager/"
echo ""
echo "▶ Running Swift package tests..."
SWIFT_PACKAGE_DIR="${SCRIPT_DIR}/macos/ValveProvisioningApp"
if [ ! -d "$SWIFT_PACKAGE_DIR" ] || [ ! -f "${SWIFT_PACKAGE_DIR}/Package.swift" ]; then
  echo "Swift package not found at ${SWIFT_PACKAGE_DIR}"
  exit 1
fi
swift test --package-path "$SWIFT_PACKAGE_DIR"

#R032: Fail when any Go package reports no associated unit-test files.
NO_TEST_PACKAGES_FILE="$(mktemp)"
awk '$0 ~ /\[no test files\]/ { print $2 }' "$GO_TEST_OUTPUT_FILE" | sort -u > "$NO_TEST_PACKAGES_FILE"
if [ -s "$NO_TEST_PACKAGES_FILE" ]; then
  echo "❌ Go unit test coverage check failed: packages without _test.go files detected."
  sed 's/^/  - /' "$NO_TEST_PACKAGES_FILE"
  exit 1
fi

#R035: Emit concise operator-readable success output.
echo ""
echo "✅ PASS: SQL, Go, Bats, and Swift unit tests completed."
