#!/usr/bin/env bash
umask 007
#R001: Run native Go fuzz tests with bounded runtime from repository root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

#R010: Default fuzz packages and per-target runtime.
FUZZ_TIME="${GO_FUZZ_TIME:-30s}"
FUZZ_PACKAGES="${GO_FUZZ_PACKAGES:-./internal/credentials ./internal/security}"
FUZZ_VERBOSE="${GO_FUZZ_VERBOSE:-true}"

#R005: Fail fast when go is unavailable.
if ! command -v go >/dev/null; then
  echo "go is required but was not found on PATH."
  exit 1
fi

echo "▶ Running Go fuzz tests (${FUZZ_TIME} per fuzz target)"
total_targets=0
failed_targets=0
#R020: new interesting counts are informational; only fuzz target failures fail the lane.
for pkg in ${FUZZ_PACKAGES}; do
  fuzz_found=false
  while IFS= read -r fuzz_test; do
    [ -z "${fuzz_test}" ] && continue
    fuzz_found=true
    total_targets=$((total_targets + 1))
    echo "▶ Fuzzing ${pkg} (${fuzz_test})"
    if [ "${FUZZ_VERBOSE}" = "true" ]; then
      if go test "${pkg}" -fuzz="${fuzz_test}" -fuzztime="${FUZZ_TIME}"; then
        echo "✅ PASS: ${pkg} (${fuzz_test})"
      else
        echo "❌ FAIL: ${pkg} (${fuzz_test})"
        failed_targets=$((failed_targets + 1))
      fi
      continue
    fi

    fuzz_output="$(mktemp)"
    if go test "${pkg}" -fuzz="${fuzz_test}" -fuzztime="${FUZZ_TIME}" >"${fuzz_output}" 2>&1; then
      echo "✅ PASS: ${pkg} (${fuzz_test})"
    else
      echo "❌ FAIL: ${pkg} (${fuzz_test})"
      echo "   Last 40 lines of output:"
      tail -n 40 "${fuzz_output}" | sed 's/^/   /'
      failed_targets=$((failed_targets + 1))
    fi
    rm -f "${fuzz_output}"
  done < <(go test "${pkg}" -list=Fuzz 2>/dev/null | grep '^Fuzz' || true)
  if [ "${fuzz_found}" != "true" ]; then
    echo "❌ No fuzz tests found in ${pkg}"
    exit 1
  fi
done
if [ "${failed_targets}" -gt 0 ]; then
  echo "❌ FAIL: ${failed_targets}/${total_targets} fuzz targets failed."
  exit 1
fi
#R015: Emit concise success output on completion.
echo "✅ PASS: Go fuzz tests completed."
