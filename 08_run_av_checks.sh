#!/usr/bin/env bash
umask 007
#R001: Run in strict fail-fast mode from repository root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

REPORT_DIR="${SECURITY_REPORT_DIR:-./.security-reports}"
RUN_CLAMAV="${RUN_CLAMAV:-true}"
CLAMAV_SCAN_TARGET="${CLAMAV_SCAN_TARGET:-.}"
CLAMAV_SIGNATURE_MAX_AGE_HOURS="${CLAMAV_SIGNATURE_MAX_AGE_HOURS:-48}"
CLAMAV_SIGNATURE_MAX_AGE_HOURS_HARD_FAIL="${CLAMAV_SIGNATURE_MAX_AGE_HOURS_HARD_FAIL:-168}"
CLAMAV_ALLOWLIST_SIGNATURES="${CLAMAV_ALLOWLIST_SIGNATURES:-}"
CLAMAV_HEARTBEAT_SECONDS="${CLAMAV_HEARTBEAT_SECONDS:-15}"
CLAMAV_POLL_SECONDS="${CLAMAV_POLL_SECONDS:-1}"
RUN_CLAMAV_E2E="${RUN_CLAMAV_E2E:-false}"
FAIL_ON_HIGH_CRITICAL="${SECURITY_FAIL_ON_HIGH_CRITICAL:-true}"

CLAMAV_LOG="${REPORT_DIR}/clamav.log"
CLAMAV_SUMMARY="${REPORT_DIR}/clamav-summary.json"
FRESHCLAM_LOG="${REPORT_DIR}/clamav.log.freshclam.log"

mkdir -p "$REPORT_DIR"

require_command() {
  local command_name="$1"
  #R005: Fail fast with installer guidance when required commands are missing.
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "❌ Missing required command: ${command_name}"
    echo "Install prerequisites with: ./01_install_prerequisites.sh"
    exit 1
  fi
}

normalize_positive_int() {
  local value="$1"
  local fallback="$2"
  if [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -ge 1 ]; then
    echo "$value"
    return 0
  fi
  echo "$fallback"
}

detect_clamav_db_dir() {
  #R020: Detect ClamAV database directory for signature freshness reporting.
  if [ -n "${CLAMAV_DB_DIR:-}" ] && [ -d "${CLAMAV_DB_DIR}" ]; then
    echo "${CLAMAV_DB_DIR}"
    return 0
  fi

  if command -v brew >/dev/null 2>&1; then
    local brew_prefix=""
    brew_prefix="$(brew --prefix 2>/dev/null || true)"
    if [ -n "$brew_prefix" ] && [ -d "${brew_prefix}/var/lib/clamav" ]; then
      echo "${brew_prefix}/var/lib/clamav"
      return 0
    fi
  fi

  if [ -d "/var/lib/clamav" ]; then
    echo "/var/lib/clamav"
    return 0
  fi

  echo ""
}

print_signature_freshness() {
  local db_dir="$1"
  #R020: Print signature freshness details before scan execution.
  if [ -z "$db_dir" ]; then
    echo "ℹ️  ClamAV signature freshness: unknown (database directory not found)"
    return 0
  fi

  python3 - "$db_dir" "$CLAMAV_SIGNATURE_MAX_AGE_HOURS" "$CLAMAV_SIGNATURE_MAX_AGE_HOURS_HARD_FAIL" <<'PY'
import glob
import os
import sys
import time

db_dir = sys.argv[1]
warn_age_hours = int(sys.argv[2]) if sys.argv[2].isdigit() else 48
hard_fail_age_hours = int(sys.argv[3]) if sys.argv[3].isdigit() else 168
patterns = ("*.cvd", "*.cld", "*.inc")
paths = []
for pattern in patterns:
    paths.extend(glob.glob(os.path.join(db_dir, pattern)))

if not paths:
    print(f"ℹ️  ClamAV signature freshness: unknown (no signatures found in {db_dir})")
    print("ℹ️  Refresh signatures with: freshclam --stdout")
    raise SystemExit(0)

latest_mtime = max(os.path.getmtime(path) for path in paths)
age_hours = (time.time() - latest_mtime) / 3600.0
status = "fresh" if age_hours <= warn_age_hours else "stale"
print(
    "ℹ️  ClamAV signature freshness: "
    f"{age_hours:.1f}h old ({status}, threshold {warn_age_hours}h, db {db_dir})"
)
if status == "stale":
    print("⚠️  ClamAV signatures appear out of date.")
    print("ℹ️  Refresh signatures with: freshclam --stdout")
if age_hours > hard_fail_age_hours:
    print(
        f"❌ ClamAV signatures exceed hard-fail age "
        f"({age_hours:.1f}h > {hard_fail_age_hours}h)."
    )
    raise SystemExit(1)
PY
}

run_clamscan_once() {
  local report_path="$1"
  local scan_target="$2"
  local heartbeat_seconds="$3"
  local poll_seconds="$4"
  local clamscan_exit=0

  #R015: Run recursive ClamAV scan and write command output to report log.
  clamscan \
    --recursive \
    --infected \
    --exclude-dir='^\.git$' \
    --exclude-dir='^\.security-reports$' \
    --exclude-dir='^node_modules$' \
    --exclude-dir='^\.venv$' \
    --exclude-dir='^venv$' \
    --exclude-dir='^\.pytest_cache$' \
    --exclude-dir='^\.mypy_cache$' \
    --exclude-dir='^\.gomodcache$' \
    "${scan_target}" >"${report_path}" 2>&1 &
  local clamscan_pid=$!
  local start_epoch
  local next_heartbeat=0
  start_epoch="$(date +%s)"
  next_heartbeat="$heartbeat_seconds"

  #R025: Emit heartbeat progress while long-running scans execute.
  while kill -0 "$clamscan_pid" >/dev/null 2>&1; do
    local now elapsed
    now="$(date +%s)"
    elapsed=$((now - start_epoch))
    if [ "$elapsed" -ge "$next_heartbeat" ]; then
      echo "ℹ️  ClamAV scan in progress (${elapsed}s elapsed)"
      next_heartbeat=$((next_heartbeat + heartbeat_seconds))
    fi
    sleep "$poll_seconds"
  done

  wait "$clamscan_pid"
  clamscan_exit=$?

  cat "${report_path}"
  return "$clamscan_exit"
}

write_summary_json() {
  local report_path="$1"
  local summary_path="$2"
  local scan_exit="$3"
  local skipped="$4"
  local fail_on_high="$5"
  local allowlist="$6"
  #R030: Persist machine-readable ClamAV summary and optional gate result.
  python3 - "$report_path" "$summary_path" "$scan_exit" "$skipped" "$fail_on_high" "$allowlist" <<'PY'
import json
import re
import sys
from pathlib import Path

report_path = Path(sys.argv[1])
summary_path = Path(sys.argv[2])
scan_exit = int(sys.argv[3])
skipped = sys.argv[4].lower() == "true"
fail_on_high = sys.argv[5].lower() == "true"
allowlist = {value.strip() for value in sys.argv[6].split(",") if value.strip()}

scanned_files = 0
infected_files = 0
if report_path.exists():
    text = report_path.read_text(encoding="utf-8", errors="replace")
    scanned_match = re.search(r"Scanned files:\s*([0-9]+)", text)
    infected_match = re.search(r"Infected files:\s*([0-9]+)", text)
    if scanned_match:
        scanned_files = int(scanned_match.group(1))
    found_signatures = re.findall(r":\s*([^\s]+)\s+FOUND", text)
    if found_signatures:
        infected_files = sum(
            1 for signature in found_signatures if signature not in allowlist
        )
    elif infected_match:
        infected_files = int(infected_match.group(1))
    elif scan_exit == 1:
        infected_files = 1

execution_failed = (not skipped) and scanned_files == 0 and scan_exit == 0
gate_failed = (not skipped) and (
    execution_failed or (fail_on_high and infected_files > 0)
)
payload = {
    "scanned_files": scanned_files,
    "infected_files": infected_files,
    "exit_code": scan_exit,
    "skipped": skipped,
    "execution_failed": execution_failed,
    "gate_failed": gate_failed,
}
summary_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
print("Antivirus (ClamAV) summary")
print(json.dumps(payload, indent=2))
if execution_failed:
    print("❌ Antivirus (ClamAV) gate failed: scanner reported zero scanned files.")
    raise SystemExit(1)
if gate_failed:
    print("❌ Antivirus (ClamAV) gate failed: infected files detected.")
    raise SystemExit(1)
PY
}

run_clamav_lane() {
  #R010: Allow explicit skip behavior while still emitting deterministic artifacts.
  if [[ "$RUN_CLAMAV" != "true" ]]; then
    : > "$CLAMAV_LOG"
    write_summary_json "$CLAMAV_LOG" "$CLAMAV_SUMMARY" 0 true false "${CLAMAV_ALLOWLIST_SIGNATURES}"
    echo "ℹ️  ClamAV lane skipped."
    return 0
  fi

  require_command clamscan
  require_command python3

  CLAMAV_HEARTBEAT_SECONDS="$(normalize_positive_int "$CLAMAV_HEARTBEAT_SECONDS" 15)"
  CLAMAV_POLL_SECONDS="$(normalize_positive_int "$CLAMAV_POLL_SECONDS" 1)"

  local resolved_target
  resolved_target="$(python3 - "$CLAMAV_SCAN_TARGET" <<'PY'
import os
import sys
print(os.path.abspath(sys.argv[1]))
PY
)"
  #R035: Fail clearly when configured scan targets do not exist.
  if [ ! -e "$resolved_target" ]; then
    echo "❌ ClamAV scan target not found: ${resolved_target}"
    exit 1
  fi

  local db_dir
  db_dir="$(detect_clamav_db_dir)"
  echo "▶ Running ClamAV scan"
  echo "ℹ️  ClamAV scan target: ${resolved_target}"
  print_signature_freshness "$db_dir"

  local clamscan_exit
  set +e
  run_clamscan_once "$CLAMAV_LOG" "$resolved_target" "$CLAMAV_HEARTBEAT_SECONDS" "$CLAMAV_POLL_SECONDS"
  clamscan_exit=$?
  set -e

  #R040: Refresh signatures and retry once when ClamAV reports missing database files.
  if [ "$clamscan_exit" -gt 1 ] && python3 - "$CLAMAV_LOG" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
raise SystemExit(0 if "No supported database files found" in text else 1)
PY
  then
    require_command freshclam
    echo "⚠️  ClamAV database missing; attempting one-time database refresh with freshclam --stdout."
    set +e
    freshclam --stdout | tee "$FRESHCLAM_LOG"
    local freshclam_exit=${PIPESTATUS[0]}
    set -e
    if [ "$freshclam_exit" -ne 0 ]; then
      echo "❌ freshclam failed with exit code ${freshclam_exit}; signatures remain unavailable."
      exit 1
    fi
    echo "ℹ️  Retrying ClamAV repository scan after freshclam refresh."
    set +e
    run_clamscan_once "$CLAMAV_LOG" "$resolved_target" "$CLAMAV_HEARTBEAT_SECONDS" "$CLAMAV_POLL_SECONDS"
    clamscan_exit=$?
    set -e
  fi

  #R045: Treat ClamAV exit codes above 1 as execution errors.
  if [ "$clamscan_exit" -gt 1 ]; then
    write_summary_json "$CLAMAV_LOG" "$CLAMAV_SUMMARY" "$clamscan_exit" false false "${CLAMAV_ALLOWLIST_SIGNATURES}"
    echo "❌ ClamAV failed to execute."
    exit 1
  fi

  if [ "$clamscan_exit" -eq 1 ]; then
    echo "⚠️  ClamAV detected infected files; gate evaluation will determine pass/fail."
  fi

  write_summary_json "$CLAMAV_LOG" "$CLAMAV_SUMMARY" "$clamscan_exit" false "$FAIL_ON_HIGH_CRITICAL" "${CLAMAV_ALLOWLIST_SIGNATURES}"
  echo "✅ Antivirus (ClamAV) checks completed."
}

run_clamav_e2e() {
  #R055: Prove the real ClamAV toolchain detects the canonical EICAR test string.
  if [[ "${RUN_CLAMAV_E2E}" != "true" ]]; then
    return 0
  fi
  if ! command -v clamscan >/dev/null 2>&1; then
    echo "ℹ️  ClamAV E2E skipped: clamscan not available."
    return 0
  fi
  local eicar_dir="${SCRIPT_DIR}/tests/fixtures"
  local eicar_file="${eicar_dir}/eicar.txt"
  if [[ ! -f "${eicar_file}" ]]; then
    echo "❌ ClamAV E2E fixture missing: ${eicar_file}"
    exit 1
  fi
  echo "▶ Running ClamAV E2E against EICAR fixture"
  local eicar_log="${REPORT_DIR}/clamav-e2e.log"
  local eicar_exit=0
  set +e
  clamscan --infected "${eicar_file}" >"${eicar_log}" 2>&1
  eicar_exit=$?
  set -e
  python3 - "${eicar_log}" "${eicar_exit}" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
exit_code = int(sys.argv[2])
infected_match = re.search(r"Infected files:\s*([0-9]+)", text)
infected = int(infected_match.group(1)) if infected_match else 0
if exit_code != 1 or infected < 1:
    print("❌ ClamAV E2E failed: expected EICAR detection (exit 1, infected >= 1).")
    print(text)
    raise SystemExit(1)
print("✅ ClamAV E2E detected EICAR test file as expected.")
PY
}

run_clamav_lane
run_clamav_e2e

#R050: Emit deterministic completion output including report directory.
echo "✅ AV checks completed. Reports: ${REPORT_DIR}"
