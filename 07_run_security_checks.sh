#!/usr/bin/env bash
umask 007
#R001: Run in strict fail-fast mode from repository root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

REPORT_DIR="${SECURITY_REPORT_DIR:-./.security-reports}"
RUN_SAST="${RUN_SAST:-true}"
RUN_DAST="${RUN_DAST:-true}"
FAIL_ON_HIGH_CRITICAL="${SECURITY_FAIL_ON_HIGH_CRITICAL:-true}"
DETECT_SECRETS_EXCLUDE_FILES_REGEX="${DETECT_SECRETS_EXCLUDE_FILES_REGEX:-(^|/)\\.gomodcache/|(^|/)requirements/.*-requirements\\.md$|(^|/)\\.cursor/plans/.*\\.plan\\.md$|(^|/)\\.qed/evals/results/.*\\.json$|(^|/)\\.security-reports/.*\\.(json|log)$}"
DETECT_SECRETS_FORCE_ALL_PLUGINS="${DETECT_SECRETS_FORCE_ALL_PLUGINS:-false}"
DAST_BASE_URL="${DAST_BASE_URL:-}"
DAST_ZAP_TARGET_URL="${DAST_ZAP_TARGET_URL:-}"
DAST_UPLOAD_ENDPOINT="${DAST_UPLOAD_ENDPOINT:-http://127.0.0.1:8081/v1/events/batch}"
ZAP_APP_PATH="${ZAP_APP_PATH:-/Applications/ZAP.app}"
#R040: Default suppression list:
#   10055-13  Known API-noise false positive (CSP missing on JSON APIs).
#   10062     ZAP daemon UI noise that surfaces when scanning the ZAP CLI itself.
#   10106     "HTTP Only Site" — by-design when DAST auto-boots a local http://
#             dev service. Operators running DAST against a real HTTPS deployment
#             should remove 10106 from DAST_IGNORED_ALERT_REFS.
DAST_IGNORED_ALERT_REFS="${DAST_IGNORED_ALERT_REFS:-10055-13,10062,10106}"
DAST_HEALTH_PROBE_TIMEOUT_SECONDS="${DAST_HEALTH_PROBE_TIMEOUT_SECONDS:-5}"
DAST_ZAP_TIMEOUT_SECONDS="${DAST_ZAP_TIMEOUT_SECONDS:-180}"
DAST_AUTO_BOOT="${DAST_AUTO_BOOT:-true}"
DAST_AUTO_BOOT_TIMEOUT_SECONDS="${DAST_AUTO_BOOT_TIMEOUT_SECONDS:-30}"
RUN_SCHEMATHESIS="${RUN_SCHEMATHESIS:-true}"
SCHEMATHESIS_SCHEMA_PATH="${SCHEMATHESIS_SCHEMA_PATH:-${SCRIPT_DIR}/openapi/valve.v1.yaml}"
SCHEMATHESIS_TIMEOUT_SECONDS="${SCHEMATHESIS_TIMEOUT_SECONDS:-180}"
SCHEMATHESIS_SEED="${SCHEMATHESIS_SEED:-424242}"
SCHEMATHESIS_MODE="${SCHEMATHESIS_MODE:-all}"
SCHEMATHESIS_MAX_EXAMPLES="${SCHEMATHESIS_MAX_EXAMPLES:-200}"
SCHEMATHESIS_CHECKS="${SCHEMATHESIS_CHECKS:-not_a_server_error,status_code_conformance,content_type_conformance,response_headers_conformance,response_schema_conformance,negative_data_rejection,missing_required_header,unsupported_method}"
DAST_ZAP_TARGET_URLS="${DAST_ZAP_TARGET_URLS:-}"
DAST_RUN_ID="${DAST_RUN_ID:-}"
DAST_CLEANUP_TENANT_PREFIX="${DAST_CLEANUP_TENANT_PREFIX:-dast_run_}"
VALVE_DATABASE_1PSA_ITEM="${VALVE_DATABASE_1PSA_ITEM:-localhost_postgres_valve}"
VALVE_DATABASE_NAME="${VALVE_DATABASE_NAME:-valve}"
VALVE_DATABASE_SSLMODE="${VALVE_DATABASE_SSLMODE:-disable}"
DAST_BASE_URL_1PSA_ITEM="${DAST_BASE_URL_1PSA_ITEM:-VALVE_SERVICE_ENDPOINT}"

DAST_APP_PID=""
#R030: Track the auto-boot session/process group leader so cleanup can reap
# both `go run` and the spawned valve binary (the binary is a grandchild that
# would otherwise be reparented to init and keep holding the listen port).
DAST_APP_PGID=""
DAST_DATABASE_URL=""

if [[ "${REPORT_DIR}" != /* ]]; then
  REPORT_DIR="${SCRIPT_DIR}/${REPORT_DIR#./}"
fi

mkdir -p "$REPORT_DIR"

cleanup_dast_app() {
  if [[ -n "${DAST_APP_PGID}" ]]; then
    #R030: Negative PID signals the entire process group, killing `go run` and
    # the actual valve listener it spawned in one shot. Errors are tolerated
    # because individual members of the group may already have exited.
    kill -TERM -- "-${DAST_APP_PGID}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${DAST_APP_PID}" ]] && kill -0 "${DAST_APP_PID}" >/dev/null 2>&1; then
    kill -TERM "${DAST_APP_PID}" >/dev/null 2>&1 || true
    wait "${DAST_APP_PID}" >/dev/null 2>&1 || true
  fi
}

trap cleanup_dast_app EXIT

resolve_dast_ignored_alert_refs() {
  local base_url="$1"
  local refs="${DAST_IGNORED_ALERT_REFS}"
  if [[ "${base_url}" == https://* ]]; then
    refs="$(python3 - "${refs}" <<'PY'
import sys
refs = [value.strip() for value in sys.argv[1].split(",") if value.strip()]
refs = [value for value in refs if value != "10106"]
print(",".join(refs))
PY
)"
  fi
  printf '%s' "${refs}"
}

cleanup_dast_tenant_data() {
  local database_url="$1"
  local tenant_prefix="$2"
  if [[ -z "${database_url}" ]] || [[ -z "${tenant_prefix}" ]]; then
    return 0
  fi
  if ! command -v psql >/dev/null 2>&1; then
    echo "ℹ️  DAST tenant cleanup skipped: psql not available."
    return 0
  fi
  echo "▶ Cleaning DAST tenant rows with prefix: ${tenant_prefix}"
  if ! psql "${database_url}" -v ON_ERROR_STOP=1 \
    -c "DELETE FROM valve_audit_log WHERE tenant_id LIKE '${tenant_prefix}%';" \
    -c "DELETE FROM valve_credentials WHERE tenant_id LIKE '${tenant_prefix}%';" \
    >/dev/null 2>&1; then
    echo "⚠️  DAST tenant cleanup failed; audit/credential rows may remain."
  fi
}

require_command() {
  local command_name="$1"
  #R005: Fail fast with installer guidance when a required command is missing.
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "❌ Missing required command: ${command_name}"
    echo "Install prerequisites with: ./01_install_prerequisites.sh"
    exit 1
  fi
}

print_tool_header() {
  local tool_name="$1"
  local explainer_line_1="$2"
  local explainer_line_2="$3"
  local tool_url="$4"
  local border="+==============================================================================+"
  printf '%s\n' "$border"
  printf '| %-76s |\n' "Security Tool: ${tool_name}"
  printf '| %-76s |\n' "${explainer_line_1}"
  printf '| %-76s |\n' "${explainer_line_2}"
  printf '| %-76s |\n' "URL: ${tool_url}"
  printf '%s\n' "$border"
}

resolve_zap_baseline() {
  if command -v zap-baseline.py >/dev/null 2>&1; then
    echo "zap-baseline.py"
    return 0
  fi
  if [[ ! -d "${ZAP_APP_PATH}" ]]; then
    return 1
  fi
  python3 - "${ZAP_APP_PATH}" <<'PY'
import os
import sys

zap_app_path = sys.argv[1]
candidates = [
    os.path.join(zap_app_path, "Contents", "Resources", "zap-baseline.py"),
    os.path.join(zap_app_path, "Contents", "Java", "zap-baseline.py"),
    os.path.join(zap_app_path, "Contents", "Java", "scripts", "zap-baseline.py"),
]
for candidate in candidates:
    if os.path.isfile(candidate):
        print(candidate)
        raise SystemExit(0)
for root, _dirs, files in os.walk(zap_app_path):
    if "zap-baseline.py" in files:
        print(os.path.join(root, "zap-baseline.py"))
        raise SystemExit(0)
raise SystemExit(1)
PY
}

resolve_zap_cli() {
  local candidate=""
  if command -v ZAP.sh >/dev/null 2>&1; then
    echo "ZAP.sh"
    return 0
  fi
  if command -v zap.sh >/dev/null 2>&1; then
    echo "zap.sh"
    return 0
  fi
  candidate="${ZAP_APP_PATH}/Contents/MacOS/ZAP.sh"
  if [[ -x "${candidate}" ]]; then
    echo "${candidate}"
    return 0
  fi
  candidate="${ZAP_APP_PATH}/Contents/Java/zap.sh"
  if [[ -x "${candidate}" ]]; then
    echo "${candidate}"
    return 0
  fi
  return 1
}

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

resolve_dast_bind_address() {
  python3 - "$1" <<'PY'
import sys
from urllib.parse import urlparse

parsed = urlparse(sys.argv[1])
host = parsed.hostname or ""
if not host:
    raise SystemExit(1)
port = parsed.port or (443 if parsed.scheme.lower() == "https" else 80)
print(f"{host}:{port}")
PY
}

#R030: Print a diagnostic log file with each line indented, robust to NUL bytes.
# macOS BSD sed aborts ("Assertion failed: (advance > 0)") when an input file
# contains NUL bytes, which can happen when an orphan auto-boot child kept the
# old fd open across our `>` truncate and wrote past the new logical EOF.
# Strip NULs defensively so diagnostic dumps never crash the script.
print_indented_log() {
  local log_path="$1"
  if [[ ! -f "${log_path}" ]]; then
    return 0
  fi
  tr -d '\0' < "${log_path}" | sed 's/^/  /' || true
}

#R030: Detect if the DAST bind address is already in use before auto-boot.
# When the port is taken (most often by a leaked auto-boot child from a prior
# run), surface the holding process so the operator gets actionable remediation
# instead of a confusing post-failure log dump from `go run`.
preflight_dast_bind_address() {
  local bind_addr="$1"
  python3 - "${bind_addr}" <<'PY'
import socket
import sys

bind_addr = sys.argv[1]
host, _, port = bind_addr.rpartition(":")
host = host or "127.0.0.1"
try:
    port_num = int(port)
except ValueError:
    sys.exit(2)

last_err = None
for family, _, _, _, sockaddr in socket.getaddrinfo(
    host, port_num, type=socket.SOCK_STREAM
):
    sock = socket.socket(family, socket.SOCK_STREAM)
    try:
        sock.bind(sockaddr)
    except OSError as exc:
        last_err = exc
        continue
    finally:
        sock.close()
    sys.exit(0)

if last_err is not None:
    sys.exit(1)
sys.exit(2)
PY
}

#R030: Best-effort identification of the process holding a TCP port for diagnostics.
describe_port_holder() {
  local bind_addr="$1"
  local port="${bind_addr##*:}"
  if [[ -z "${port}" || ! "${port}" =~ ^[0-9]+$ ]]; then
    return 0
  fi
  if ! command -v lsof >/dev/null 2>&1; then
    echo "  (install lsof for PID-level diagnostics)"
    return 0
  fi
  local lsof_out=""
  lsof_out="$(lsof -nP -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null || true)"
  if [[ -z "${lsof_out}" ]]; then
    echo "  (no listener reported by lsof; the conflict may be transient)"
    return 0
  fi
  printf '%s\n' "${lsof_out}" | sed 's/^/  /'
}

wait_for_healthz() {
  local base_url="$1"
  local timeout_seconds="$2"
  local app_pid="${3:-}"
  local start_ts
  start_ts="$(date +%s)"
  while true; do
    if [[ -n "${app_pid}" ]] && ! kill -0 "${app_pid}" >/dev/null 2>&1; then
      return 2
    fi
    #R030: Capture curl stderr alongside stdout so transient "connection
    # refused" messages while the auto-boot is still warming up do not appear
    # as scary noise on the operator's terminal. The last iteration's output
    # remains in dast-health.log so we can dump it on a real timeout failure.
    #
    # The `|| health_exit=$?` pattern captures the non-zero curl exit without
    # tripping the caller's `set -e`. We intentionally avoid toggling global
    # `set +e`/`set -e` here because shell options leak across the function
    # boundary, which previously made wait_for_healthz's non-zero return value
    # silently kill the script before the post-failure diagnostic dump could
    # print.
    local health_exit=0
    run_with_timeout 2 curl -fsS --max-time 2 "${base_url}/healthz" \
      > "${REPORT_DIR}/dast-health.log" 2>&1 || health_exit=$?
    if [[ "$health_exit" -eq 0 ]]; then
      return 0
    fi
    if (( "$(date +%s)" - start_ts >= timeout_seconds )); then
      return 1
    fi
    sleep 1
  done
}

read_database_field_from_1psa() {
  local field="$1"
  local value=""
  set +e
  value="$(1psa -f "${VALVE_DATABASE_1PSA_ITEM}" "${field}" 2>/dev/null)"
  local read_exit=$?
  set -e
  if [[ "${read_exit}" -ne 0 ]]; then
    echo "❌ Failed to read VALVE_DATABASE_${field^^} from 1psa item/field: ${VALVE_DATABASE_1PSA_ITEM}/${field}"
    exit 1
  fi
  value="${value//$'\r'/}"
  value="${value%$'\n'}"
  if [[ -z "${value}" ]]; then
    echo "❌ 1psa returned an empty VALVE_DATABASE_${field^^} for item/field: ${VALVE_DATABASE_1PSA_ITEM}/${field}"
    exit 1
  fi
  printf '%s' "${value}"
}

compose_database_url_from_1psa() {
  local database_user=""
  local database_password=""
  local database_host=""
  local database_port=""
  # Prefer explicit username when present, but keep the historical valve default.
  if database_user="$(read_optional_1psa_field "${VALVE_DATABASE_1PSA_ITEM}" "username")"; then
    :
  else
    database_user="valve"
  fi
  database_password="$(read_database_field_from_1psa "password")"
  database_host="$(read_database_field_from_1psa "host")"
  database_port="$(read_database_field_from_1psa "port")"
  if [[ ! "${database_port}" =~ ^[0-9]+$ ]] || (( database_port < 1 || database_port > 65535 )); then
    echo "❌ 1psa returned an invalid VALVE_DATABASE_PORT for item/field: ${VALVE_DATABASE_1PSA_ITEM}/port"
    exit 1
  fi
  python3 - "${database_user}" "${database_password}" "${database_host}" "${database_port}" "${VALVE_DATABASE_NAME}" "${VALVE_DATABASE_SSLMODE}" <<'PY'
import sys
from urllib.parse import quote

user, password, host, port, dbname, sslmode = sys.argv[1:]
print(
    "postgres://"
    + quote(user, safe="")
    + ":"
    + quote(password, safe="")
    + "@"
    + host
    + ":"
    + port
    + "/"
    + dbname
    + "?sslmode="
    + sslmode
)
PY
}

read_optional_1psa_field() {
  local item="$1"
  local field="$2"
  local value=""
  set +e
  value="$(1psa -f "${item}" "${field}" 2>/dev/null)"
  local read_exit=$?
  set -e
  if [[ "${read_exit}" -ne 0 ]]; then
    return 1
  fi
  value="${value//$'\r'/}"
  value="${value%$'\n'}"
  if [[ -z "${value}" ]]; then
    return 1
  fi
  printf '%s' "${value}"
}

resolve_auto_boot_dast_base_url() {
  if [[ -n "${DAST_BASE_URL}" ]]; then
    printf '%s' "${DAST_BASE_URL}"
    return 0
  fi
  local base_url=""
  local service_port=""
  local service_host=""
  local service_protocol=""
  local field_name=""
  local -a base_url_fields=("dast_base_url" "service_base_url" "base_url")
  local -a port_fields=("dast_port" "service_port" "app_port" "http_port" "port")

  for field_name in "${base_url_fields[@]}"; do
    if base_url="$(read_optional_1psa_field "${DAST_BASE_URL_1PSA_ITEM}" "${field_name}")"; then
      if ! resolve_dast_bind_address "${base_url}" >/dev/null 2>&1; then
        echo "❌ 1psa returned an invalid DAST base URL for item/field: ${DAST_BASE_URL_1PSA_ITEM}/${field_name}"
        exit 1
      fi
      printf '%s' "${base_url}"
      return 0
    fi
  done

  for field_name in "${port_fields[@]}"; do
    if service_port="$(read_optional_1psa_field "${DAST_BASE_URL_1PSA_ITEM}" "${field_name}")"; then
      if [[ ! "${service_port}" =~ ^[0-9]+$ ]] || (( service_port < 1 || service_port > 65535 )); then
        echo "❌ 1psa returned an invalid DAST service port for item/field: ${DAST_BASE_URL_1PSA_ITEM}/${field_name}"
        exit 1
      fi
      service_host="127.0.0.1"
      if service_host="$(read_optional_1psa_field "${DAST_BASE_URL_1PSA_ITEM}" "service_host")"; then
        :
      elif service_host="$(read_optional_1psa_field "${DAST_BASE_URL_1PSA_ITEM}" "host")"; then
        :
      else
        service_host="127.0.0.1"
      fi
      if service_protocol="$(read_optional_1psa_field "${DAST_BASE_URL_1PSA_ITEM}" "protocol")"; then
        if [[ "${service_protocol}" != "http" && "${service_protocol}" != "https" ]]; then
          echo "❌ 1psa returned an invalid DAST protocol for item/field: ${DAST_BASE_URL_1PSA_ITEM}/protocol"
          exit 1
        fi
      else
        service_protocol="http"
      fi
      printf '%s://%s:%s' "${service_protocol}" "${service_host}" "${service_port}"
      return 0
    fi
  done

  return 1
}

run_sast_lane() {
  #R015: Run Go-focused SAST scanners and persist machine-readable artifacts.
  if [[ "$RUN_SAST" != "true" ]]; then
    echo "ℹ️  SAST lane skipped."
    return 0
  fi

  require_command semgrep
  require_command shellcheck
  require_command gitleaks
  require_command detect-secrets
  require_command gosec
  require_command govulncheck
  require_command go
  require_command python3

  echo "▶ Running SAST lane"

  print_tool_header \
    "Semgrep" \
    "Static pattern-based scanning for security and correctness issues." \
    "Uses curated security and Go rules against the repository source tree." \
    "https://semgrep.dev/docs/"
  echo "▶ Running Semgrep"
  semgrep scan \
    --config "p/security-audit" \
    --config "p/golang" \
    --json \
    --output "${REPORT_DIR}/semgrep.json" \
    .

  print_tool_header \
    "ShellCheck" \
    "Static linting for shell scripts with security and reliability checks." \
    "Flags risky shell patterns, quoting bugs, and execution pitfalls." \
    "https://www.shellcheck.net/"
  echo "▶ Running ShellCheck"
  set +e
  shellcheck \
    --format json \
    --external-sources \
    --source-path SCRIPTDIR \
    ./*.sh > "${REPORT_DIR}/shellcheck.json"
  SHELLCHECK_EXIT=$?
  set -e
  if [[ "$SHELLCHECK_EXIT" -gt 1 ]]; then
    echo "❌ shellcheck failed to execute."
    exit 1
  fi

  print_tool_header \
    "Gitleaks" \
    "Scans repository content for hard-coded secrets and credentials." \
    "Detects leaked tokens, keys, and other sensitive data patterns." \
    "https://github.com/gitleaks/gitleaks"
  echo "▶ Running Gitleaks"
  set +e
  gitleaks detect \
    --no-banner \
    --report-format json \
    --report-path "${REPORT_DIR}/gitleaks.json"
  GITLEAKS_EXIT=$?
  set -e
  if [[ "$GITLEAKS_EXIT" -gt 1 ]]; then
    echo "❌ gitleaks failed to execute."
    exit 1
  fi

  print_tool_header \
    "detect-secrets" \
    "Scans repository files for high-entropy and known secret formats." \
    "Helps catch accidentally committed credentials before release." \
    "https://github.com/Yelp/detect-secrets"
  echo "▶ Running detect-secrets"
  local -a detect_secrets_args=(
    scan
    --all-files
    --exclude-files "${DETECT_SECRETS_EXCLUDE_FILES_REGEX}"
  )
  if [[ "${DETECT_SECRETS_FORCE_ALL_PLUGINS}" == "true" ]]; then
    detect_secrets_args+=(--force-use-all-plugins)
  fi
  detect-secrets "${detect_secrets_args[@]}" > "${REPORT_DIR}/detect-secrets.json"
  python3 - <<'PY' "${REPORT_DIR}/detect-secrets.json" "${DETECT_SECRETS_EXCLUDE_FILES_REGEX}"
import json
import re
import sys
from pathlib import Path
from typing import List, Optional, Tuple

report_path = Path(sys.argv[1])
exclude_pattern = sys.argv[2]
repo_root = Path.cwd()
exclude_regex = None
if exclude_pattern:
    try:
        exclude_regex = re.compile(exclude_pattern)
    except re.error:
        print(f"Invalid DETECT_SECRETS_EXCLUDE_FILES_REGEX: {exclude_pattern}")
        raise SystemExit(1)

try:
    payload = json.loads(report_path.read_text(encoding="utf-8", errors="replace"))
except json.JSONDecodeError:
    payload = {}
results = payload.get("results", {}) if isinstance(payload, dict) else {}

def read_source_line(filename: str, line_number: object) -> Optional[str]:
    try:
        line_idx = int(str(line_number))
    except (TypeError, ValueError):
        return None
    if line_idx <= 0:
        return None
    source_path = Path(filename)
    if not source_path.is_absolute():
        source_path = repo_root / source_path
    try:
        with source_path.open(encoding="utf-8", errors="replace") as fh:
            for idx, line in enumerate(fh, start=1):
                if idx == line_idx:
                    return line.rstrip("\r\n")
    except OSError:
        return None
    return None

details: List[Tuple[str, object, str, Optional[str]]] = []
if isinstance(results, dict):
    for filename, findings in results.items():
        if exclude_regex and exclude_regex.search(str(filename)):
            continue
        if not isinstance(findings, list):
            continue
        for finding in findings:
            if not isinstance(finding, dict):
                continue
            line_number = finding.get("line_number", "?")
            finding_type = str(finding.get("type", "Unknown"))
            source_line = read_source_line(str(filename), line_number)
            details.append((str(filename), line_number, finding_type, source_line))

if details:
    print("❌ Detect-secrets findings (in scope):")
    for filename, line_number, finding_type, source_line in details:
        print(f"❌ {filename}:{line_number} [{finding_type}]")
        if source_line is None:
            print("   source: <unavailable>")
        else:
            print(f"   source: {source_line}")
PY

  print_tool_header \
    "go vet" \
    "Go static analyzer for suspicious constructs and correctness issues." \
    "Checks packages for likely bugs before runtime and release." \
    "https://pkg.go.dev/cmd/vet"
  echo "▶ Running go vet"
  set +e
  go vet -json ./... > "${REPORT_DIR}/govet.json"
  GOVET_EXIT=$?
  set -e
  if [[ "$GOVET_EXIT" -gt 1 ]]; then
    echo "❌ go vet failed to execute."
    exit 1
  fi

  print_tool_header \
    "gosec" \
    "Static security analyzer focused on vulnerable Go code patterns." \
    "Surfaces risky API usage and common implementation weaknesses." \
    "https://github.com/securego/gosec"
  echo "▶ Running gosec"
  set +e
  gosec \
    -fmt=json \
    -exclude-dir=.gomodcache \
    -out "${REPORT_DIR}/gosec.json" \
    ./...
  GOSEC_EXIT=$?
  set -e
  if [[ "$GOSEC_EXIT" -gt 1 ]]; then
    echo "❌ gosec failed to execute."
    exit 1
  fi

  print_tool_header \
    "govulncheck" \
    "Go vulnerability scanner mapped to known ecosystem advisories." \
    "Evaluates project modules and reachable vulnerable symbols." \
    "https://pkg.go.dev/golang.org/x/vuln/cmd/govulncheck"
  echo "▶ Running govulncheck"
  set +e
  govulncheck -json ./... > "${REPORT_DIR}/govulncheck.json"
  GOVULNCHECK_EXIT=$?
  set -e
  if [[ "$GOVULNCHECK_EXIT" -gt 1 ]] && [[ ! -s "${REPORT_DIR}/govulncheck.json" ]]; then
    echo "❌ govulncheck failed to execute."
    exit 1
  fi

  #R020: Aggregate SAST findings into a centralized gate summary.
  python3 - <<'PY' "${REPORT_DIR}" "${FAIL_ON_HIGH_CRITICAL}" "${SHELLCHECK_EXIT}" "${GITLEAKS_EXIT}" "${GOVET_EXIT}" "${GOSEC_EXIT}" "${GOVULNCHECK_EXIT}" "${DETECT_SECRETS_EXCLUDE_FILES_REGEX}"
import json
import re
import sys
from pathlib import Path
from typing import Any

report_dir = Path(sys.argv[1])
fail_on_high = sys.argv[2].lower() == "true"
shellcheck_exit = int(sys.argv[3])
gitleaks_exit = int(sys.argv[4])
govet_exit = int(sys.argv[5])
gosec_exit = int(sys.argv[6])
govulncheck_exit = int(sys.argv[7])
detect_secrets_exclude_pattern = sys.argv[8]

semgrep_path = report_dir / "semgrep.json"
shellcheck_path = report_dir / "shellcheck.json"
gitleaks_path = report_dir / "gitleaks.json"
gosec_path = report_dir / "gosec.json"
govulncheck_path = report_dir / "govulncheck.json"
govet_path = report_dir / "govet.json"
detect_secrets_path = report_dir / "detect-secrets.json"

for required in [semgrep_path, shellcheck_path, gitleaks_path, govet_path, gosec_path, govulncheck_path, detect_secrets_path]:
    if not required.exists():
        print(f"Missing report file: {required}")
        sys.exit(1)

def load_first_json(path: Path, fallback: Any) -> Any:
    text = path.read_text(encoding="utf-8", errors="replace").strip()
    if not text:
        return fallback
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        decoder = json.JSONDecoder()
        try:
            parsed, _idx = decoder.raw_decode(text)
            return parsed
        except json.JSONDecodeError:
            return fallback

semgrep = load_first_json(semgrep_path, {"results": []})
semgrep_results = semgrep.get("results", []) if isinstance(semgrep, dict) else []
semgrep_high = sum(
    1
    for item in semgrep_results
    if str(item.get("extra", {}).get("severity", "")).upper() in {"CRITICAL", "ERROR", "HIGH"}
)

shellcheck = load_first_json(shellcheck_path, [])
if isinstance(shellcheck, list):
    shellcheck_high = sum(
        1
        for issue in shellcheck
        if str(issue.get("level", "")).lower() in {"error", "warning"}
    )
elif isinstance(shellcheck, dict) and isinstance(shellcheck.get("comments"), list):
    shellcheck_high = sum(
        1
        for issue in shellcheck.get("comments", [])
        if str(issue.get("level", "")).lower() in {"error", "warning"}
    )
else:
    shellcheck_high = 0

gitleaks = load_first_json(gitleaks_path, [])
if isinstance(gitleaks, list):
    gitleaks_findings = len(gitleaks)
elif isinstance(gitleaks, dict) and isinstance(gitleaks.get("findings"), list):
    gitleaks_findings = len(gitleaks.get("findings", []))
else:
    gitleaks_findings = 0

gosec = load_first_json(gosec_path, {"Issues": []})
issues = gosec.get("Issues", []) if isinstance(gosec, dict) else []
gosec_high = sum(1 for issue in issues if str(issue.get("severity", "")).upper() in {"HIGH", "MEDIUM"})

govulncheck_text = govulncheck_path.read_text(encoding="utf-8", errors="replace")
govulncheck_findings = len(re.findall(r'"finding"\s*:', govulncheck_text))

govet_payload = load_first_json(govet_path, {})
govet_findings = 0
if isinstance(govet_payload, dict):
    for package_result in govet_payload.values():
        if not isinstance(package_result, dict):
            continue
        diagnostics = package_result.get("vet")
        if isinstance(diagnostics, list):
            govet_findings += len(diagnostics)

detect_secrets = load_first_json(detect_secrets_path, {})
detect_secrets_results = detect_secrets.get("results", {}) if isinstance(detect_secrets, dict) else {}
detect_secrets_findings = 0
detect_secrets_exclude_regex = None
if detect_secrets_exclude_pattern:
    try:
        detect_secrets_exclude_regex = re.compile(detect_secrets_exclude_pattern)
    except re.error:
        print(f"Invalid DETECT_SECRETS_EXCLUDE_FILES_REGEX: {detect_secrets_exclude_pattern}")
        sys.exit(1)
if isinstance(detect_secrets_results, dict):
    for filename, findings in detect_secrets_results.items():
        if detect_secrets_exclude_regex and detect_secrets_exclude_regex.search(str(filename)):
            continue
        if isinstance(findings, list):
            detect_secrets_findings += len(findings)

high_critical_total = (
    shellcheck_high + semgrep_high + gitleaks_findings + govet_findings + gosec_high + govulncheck_findings + detect_secrets_findings
)
summary = {
    "shellcheck_high_critical": shellcheck_high,
    "semgrep_high_critical": semgrep_high,
    "gitleaks_findings": gitleaks_findings,
    "detect_secrets_findings": detect_secrets_findings,
    "govet_findings": govet_findings,
    "gosec_high_critical": gosec_high,
    "govulncheck_findings": govulncheck_findings,
    "shellcheck_exit_code": shellcheck_exit,
    "gitleaks_exit_code": gitleaks_exit,
    "govet_exit_code": govet_exit,
    "gosec_exit_code": gosec_exit,
    "govulncheck_exit_code": govulncheck_exit,
    "high_critical_total": high_critical_total,
    "gate_failed": fail_on_high and high_critical_total > 0,
}

summary_path = report_dir / "sast-summary.json"
with summary_path.open("w", encoding="utf-8") as fh:
    json.dump(summary, fh, indent=2)
    fh.write("\n")

print("Static Application Security Testing (SAST) summary")
print(json.dumps(summary, indent=2))
if fail_on_high and high_critical_total > 0:
    print("❌ Static Application Security Testing (SAST) gate failed: High/Critical findings detected.")
    sys.exit(1)
PY
  echo "✅ Static Application Security Testing (SAST) checks completed."
}

run_dast_lane() {
  #R025: Run DAST lane by default unless explicitly opted out.
  if [[ "$RUN_DAST" != "true" ]]; then
    echo "ℹ️  DAST lane skipped."
    return 0
  fi
  #R060: Emit explicit lane-start marker after SAST completion to prevent hang ambiguity.
  echo "▶ Starting Dynamic Application Security Testing (DAST) lane..."

  local effective_dast_base_url="${DAST_BASE_URL:-http://127.0.0.1:8080}"
  #R040: Track the service auth key used by both valve and Schemathesis. When
  # auto-boot is enabled the key may be generated below; for non-auto-boot
  # runs the operator-provided VALVE_SERVICE_AUTH_KEY is the source of truth.
  local DAST_SERVICE_AUTH_KEY="${VALVE_SERVICE_AUTH_KEY:-}"
  require_command curl
  require_command python3
  if [[ "${RUN_SCHEMATHESIS}" == "true" ]]; then
    #R055: Validate Schemathesis schema contract before DAST boot/health/scan work.
    require_command schemathesis
    if [[ ! -f "${SCHEMATHESIS_SCHEMA_PATH}" ]]; then
      echo "❌ Schemathesis schema file not found: ${SCHEMATHESIS_SCHEMA_PATH}"
      echo "Set SCHEMATHESIS_SCHEMA_PATH or add openapi/valve.v1.yaml."
      exit 1
    fi
    if [[ ! -r "${SCHEMATHESIS_SCHEMA_PATH}" ]]; then
      echo "❌ Schemathesis schema file is not readable: ${SCHEMATHESIS_SCHEMA_PATH}"
      echo "Set SCHEMATHESIS_SCHEMA_PATH or fix schema file permissions."
      exit 1
    fi
  fi
  if [[ "${DAST_AUTO_BOOT}" == "true" ]]; then
    require_command go
    require_command 1psa
    if ! effective_dast_base_url="$(resolve_auto_boot_dast_base_url)"; then
      echo "❌ Unable to resolve DAST endpoint."
      echo "Set DAST_BASE_URL or populate one of these 1psa fields on '${DAST_BASE_URL_1PSA_ITEM}':"
      echo "  dast_base_url, service_base_url, base_url, dast_port, service_port, app_port, http_port, port"
      echo "  optional companion fields: service_host or host, protocol"
      exit 1
    fi
    local database_url=""
    if ! database_url="$(compose_database_url_from_1psa)"; then
      echo "❌ Failed to compose VALVE_DATABASE_URL from 1psa fields."
      exit 1
    fi
    DAST_DATABASE_URL="${database_url}"
    if [[ -z "${DAST_RUN_ID}" ]]; then
      DAST_RUN_ID="${DAST_CLEANUP_TENANT_PREFIX}$(python3 -c 'import uuid; print(uuid.uuid4().hex[:12])')"
    fi
    echo "ℹ️  DAST run id (tenant cleanup prefix): ${DAST_RUN_ID}"
    local dast_bind_addr=""
    if ! dast_bind_addr="$(resolve_dast_bind_address "${effective_dast_base_url}")"; then
      echo "❌ Unable to derive bind address from DAST_BASE_URL: ${effective_dast_base_url}"
      exit 1
    fi
    local upload_endpoint="${VALVE_UPLOAD_ENDPOINT:-${DAST_UPLOAD_ENDPOINT}}"
    #R040: Provision a service auth key so DAST contract testing can pass the
    # `X-Valve-Service-Key` header and exercise authenticated endpoints. When
    # the operator already set VALVE_SERVICE_AUTH_KEY we reuse it; otherwise
    # we mint an ephemeral random key for the lifetime of this run only and
    # propagate the same value to Schemathesis below.
    if [[ -z "${VALVE_SERVICE_AUTH_KEY:-}" ]]; then
      VALVE_SERVICE_AUTH_KEY="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
      export VALVE_SERVICE_AUTH_KEY
    fi
    DAST_SERVICE_AUTH_KEY="${VALVE_SERVICE_AUTH_KEY}"
    print_tool_header \
      "go run ./cmd/valve" \
      "Auto-boots the local service so DAST has a deterministic target." \
      "Uses VALVE_ADDR from DAST_BASE_URL plus DB and upload endpoint wiring." \
      "https://go.dev/"
    #R030: Preflight the bind address; a leftover orphan from a prior crashed
    # run is a common cause of "address already in use" and would otherwise
    # leave the operator chasing a misleading post-boot error.
    set +e
    preflight_dast_bind_address "${dast_bind_addr}"
    local preflight_status=$?
    set -e
    if [[ "${preflight_status}" -ne 0 ]]; then
      echo "❌ DAST bind address already in use: ${dast_bind_addr}"
      echo "▶ Listener currently holding the port:"
      describe_port_holder "${dast_bind_addr}"
      echo "Free the port (e.g. \`kill <PID>\`) or override DAST_BASE_URL/dast_port and rerun."
      exit 1
    fi
    echo "▶ Auto-booting valve service for DAST at ${effective_dast_base_url}"
    #R030: Run the auto-boot child inside its own session via os.setsid() so
    # `cleanup_dast_app` can SIGTERM the whole tree (`go run` + spawned binary)
    # using the negative-PID syntax. Without this, killing `go run` would
    # orphan the actual valve listener and leak the bind address.
    VALVE_ADDR="${dast_bind_addr}" \
    VALVE_DATABASE_URL="${database_url}" \
    VALVE_UPLOAD_ENDPOINT="${upload_endpoint}" \
    VALVE_DEV_AUTH_ALLOW_ALL="${VALVE_DEV_AUTH_ALLOW_ALL:-true}" \
    VALVE_SERVICE_AUTH_KEY="${VALVE_SERVICE_AUTH_KEY}" \
      python3 -c '
import os, sys
os.setsid()
os.execvp(sys.argv[1], sys.argv[1:])
' go run ./cmd/valve > "${REPORT_DIR}/dast-app.log" 2>&1 &
    DAST_APP_PID="$!"
    DAST_APP_PGID="${DAST_APP_PID}"
  fi
  #R035: Default the ZAP entry URL to a documented 2xx route (`/healthz`) so
  # ZAP CLI's quick scan, which refuses entries that do not return 2xx, has a
  # valid starting point even when the service has no `/` handler. Operators
  # can override DAST_ZAP_TARGET_URL to point at a richer crawl surface.
  local effective_zap_target_url="${DAST_ZAP_TARGET_URL:-}"
  if [[ -z "${effective_zap_target_url}" ]]; then
    if [[ -n "${DAST_ZAP_TARGET_URLS}" ]]; then
      effective_zap_target_url="${DAST_ZAP_TARGET_URLS%%,*}"
    else
      effective_zap_target_url="${effective_dast_base_url%/}/healthz"
    fi
  fi
  local -a zap_target_urls=("${effective_zap_target_url}")
  if [[ -n "${DAST_ZAP_TARGET_URLS}" ]]; then
    IFS=',' read -r -a zap_target_urls <<< "${DAST_ZAP_TARGET_URLS}"
  fi
  local effective_dast_ignored_refs
  effective_dast_ignored_refs="$(resolve_dast_ignored_alert_refs "${effective_dast_base_url}")"
  local zap_runner_cmd=""
  local zap_runner_mode=""
  if zap_runner_cmd="$(resolve_zap_baseline)"; then
    zap_runner_mode="baseline"
  elif zap_runner_cmd="$(resolve_zap_cli)"; then
    zap_runner_mode="cli"
  else
    echo "❌ Missing required command: zap-baseline.py or ZAP.sh"
    echo "Install prerequisites with: ./01_install_prerequisites.sh"
    echo "If ZAP.app is installed elsewhere, set ZAP_APP_PATH and rerun."
    exit 1
  fi

  #R030: Probe /healthz before launching dynamic scanning.
  print_tool_header \
    "curl" \
    "HTTP health probe to validate target service availability." \
    "Confirms /healthz is reachable before dynamic scanning starts." \
    "https://curl.se/"
  echo "▶ Running DAST lane health probe against ${effective_dast_base_url}"
  local health_timeout_seconds="${DAST_HEALTH_PROBE_TIMEOUT_SECONDS}"
  if [[ "${DAST_AUTO_BOOT}" == "true" ]]; then
    health_timeout_seconds="${DAST_AUTO_BOOT_TIMEOUT_SECONDS}"
  fi
  #R030: Capture wait_for_healthz's exit status via `||` rather than toggling
  # `set -e`, so a non-zero return cannot abort the script before the
  # diagnostic dump below has a chance to run.
  local health_status=0
  wait_for_healthz "${effective_dast_base_url}" "${health_timeout_seconds}" "${DAST_APP_PID}" \
    || health_status=$?
  if [[ "${health_status}" -ne 0 ]]; then
    if [[ "${health_status}" -eq 2 ]]; then
      echo "❌ Auto-booted valve service exited before DAST health probe succeeded."
      echo "▶ Auto-boot log:"
      print_indented_log "${REPORT_DIR}/dast-app.log"
    else
      echo "❌ DAST health probe failed: ${effective_dast_base_url}/healthz"
      echo "▶ Last health probe output:"
      print_indented_log "${REPORT_DIR}/dast-health.log"
    fi
    exit 1
  fi
  if [[ -n "${DAST_APP_PID}" ]] && ! kill -0 "${DAST_APP_PID}" >/dev/null 2>&1; then
    echo "❌ Auto-booted valve service exited before DAST scans began."
    echo "▶ Auto-boot log:"
    print_indented_log "${REPORT_DIR}/dast-app.log"
    exit 1
  fi
  if [[ -n "${DAST_APP_PID}" ]]; then
    sleep 1
    if ! kill -0 "${DAST_APP_PID}" >/dev/null 2>&1; then
      echo "❌ Auto-booted valve service exited during DAST readiness checks."
      echo "▶ Auto-boot log:"
      print_indented_log "${REPORT_DIR}/dast-app.log"
      exit 1
    fi
  fi

  local schemathesis_exit=0
  if [[ "${RUN_SCHEMATHESIS}" == "true" ]]; then
    print_tool_header \
      "Schemathesis" \
      "Property-based API testing driven by the OpenAPI specification." \
      "Finds contract mismatches by generating and exercising request scenarios." \
      "https://schemathesis.readthedocs.io/"
    echo "▶ Running Schemathesis against ${SCHEMATHESIS_SCHEMA_PATH}"
    #R040: Forward the service auth header to Schemathesis so authenticated
    # operations (e.g. POST /v1/piston/upload-target) reach their documented
    # response codes instead of being uniformly rejected with 401. When no
    # key is available (e.g. operator opted out of auto-boot and did not set
    # VALVE_SERVICE_AUTH_KEY) we skip the header so the request still mirrors
    # whatever the external service expects.
    local -a schemathesis_extra_args=()
    if [[ -n "${DAST_SERVICE_AUTH_KEY}" ]]; then
      schemathesis_extra_args+=(--header "X-Valve-Service-Key: ${DAST_SERVICE_AUTH_KEY}")
    fi
    set +e
    #R040: Use the `${arr[@]+...}` pattern so bash's `set -u` does not trip on
    # an empty extra-args array when no service key is available.
    local -a schemathesis_cmd=(
      schemathesis run "${SCHEMATHESIS_SCHEMA_PATH}"
      --url "${effective_dast_base_url}"
      --mode "${SCHEMATHESIS_MODE}"
      --seed "${SCHEMATHESIS_SEED}"
      --max-examples "${SCHEMATHESIS_MAX_EXAMPLES}"
      --checks "${SCHEMATHESIS_CHECKS}"
      --report junit
      --report-junit-path "${REPORT_DIR}/schemathesis-junit.xml"
    )
    run_with_timeout "${SCHEMATHESIS_TIMEOUT_SECONDS}" \
      "${schemathesis_cmd[@]}" \
      ${schemathesis_extra_args[@]+"${schemathesis_extra_args[@]}"} \
      > "${REPORT_DIR}/schemathesis.log" 2>&1
    schemathesis_exit=$?
    set -e
    if [[ "$schemathesis_exit" -eq 124 ]]; then
      echo "❌ Schemathesis run timed out after ${SCHEMATHESIS_TIMEOUT_SECONDS}s."
      exit 1
    fi
    if [[ "$schemathesis_exit" -gt 1 ]]; then
      echo "❌ Schemathesis failed to execute."
      exit 1
    fi
  else
    echo "ℹ️  Schemathesis skipped."
  fi

  #R035: Execute OWASP ZAP baseline via host-native zap-baseline.py.
  local zap_target_url="${effective_zap_target_url}"

  print_tool_header \
    "OWASP ZAP Baseline" \
    "Dynamic web scanner for common HTTP application vulnerabilities." \
    "Runs baseline scan mode and emits JSON alert report artifacts." \
    "https://www.zaproxy.org/"
  local zap_report_path="${REPORT_DIR}/dast-zap-report.json"
  local zap_log_path="${REPORT_DIR}/dast-zap.log"
  #R050: Print DAST execution context so operators can observe live scan behavior.
  echo "▶ DAST runner resolved to: ${zap_runner_cmd} (${zap_runner_mode})"
  echo "▶ DAST timeout: ${DAST_ZAP_TIMEOUT_SECONDS}s"
  echo "▶ DAST report artifact: ${zap_report_path}"
  echo "▶ DAST live log artifact: ${zap_log_path}"
  local zap_exit=0
  local zap_target_url=""
  : > "${zap_log_path}"
  for zap_target_url in "${zap_target_urls[@]}"; do
    zap_target_url="${zap_target_url#"${zap_target_url%%[![:space:]]*}"}"
    zap_target_url="${zap_target_url%"${zap_target_url##*[![:space:]]}"}"
    [[ -z "${zap_target_url}" ]] && continue
    echo "▶ Running real DAST scan with OWASP ZAP baseline against ${zap_target_url}"
    local zap_iteration_exit=0
    set +e
    if [[ "${zap_runner_mode}" == "baseline" && "${zap_runner_cmd}" == "zap-baseline.py" ]]; then
      PYTHONUNBUFFERED=1 run_with_timeout "${DAST_ZAP_TIMEOUT_SECONDS}" \
        zap-baseline.py \
        -t "${zap_target_url}" \
        -J "${zap_report_path}" \
        -m 1 2>&1 | tee -a "${zap_log_path}"
      zap_iteration_exit=${PIPESTATUS[0]}
    elif [[ "${zap_runner_mode}" == "baseline" ]]; then
      run_with_timeout "${DAST_ZAP_TIMEOUT_SECONDS}" \
        python3 -u "${zap_runner_cmd}" \
        -t "${zap_target_url}" \
        -J "${zap_report_path}" \
        -m 1 2>&1 | tee -a "${zap_log_path}"
      zap_iteration_exit=${PIPESTATUS[0]}
    else
      run_with_timeout "${DAST_ZAP_TIMEOUT_SECONDS}" \
        "${zap_runner_cmd}" \
        -cmd \
        -quickurl "${zap_target_url}" \
        -quickout "${zap_report_path}" \
        -quickprogress 2>&1 | tee -a "${zap_log_path}"
      zap_iteration_exit=${PIPESTATUS[0]}
    fi
    set -e
    if [[ "${zap_iteration_exit}" -gt "${zap_exit}" ]]; then
      zap_exit="${zap_iteration_exit}"
    fi
    if [[ "${zap_iteration_exit}" -eq 124 ]]; then
      echo "❌ OWASP ZAP baseline scan timed out after ${DAST_ZAP_TIMEOUT_SECONDS}s."
      exit 1
    fi
    if [[ "${zap_iteration_exit}" -eq 3 ]]; then
      echo "❌ OWASP ZAP baseline scan failed to execute."
      exit 1
    fi
    if grep -q "Failed to attack the URL" "${zap_log_path}" 2>/dev/null; then
      echo "❌ OWASP ZAP could not scan ${zap_target_url}: entry URL did not return 2xx."
      echo "▶ ZAP output:"
      print_indented_log "${zap_log_path}"
      echo "Set DAST_ZAP_TARGET_URL to a path that returns 200 (e.g. \${DAST_BASE_URL}/healthz) and rerun."
      exit 1
    fi
  done
  zap_target_url="${effective_zap_target_url}"

  if [[ ! -s "${zap_report_path}" ]]; then
    echo "❌ OWASP ZAP baseline report was not generated."
    exit 1
  fi

  #R040: Summarize DAST findings and enforce medium/high gate policy.
  python3 - <<'PY' "${REPORT_DIR}/dast-summary.json" "${effective_dast_base_url}" "${zap_target_url}" "${zap_report_path}" "${FAIL_ON_HIGH_CRITICAL}" "${zap_exit}" "${effective_dast_ignored_refs}" "${schemathesis_exit}" "${RUN_SCHEMATHESIS}"
import json
import sys
from urllib.parse import urlparse

summary_path = sys.argv[1]
base_url = sys.argv[2]
zap_target = sys.argv[3]
zap_report_path = sys.argv[4]
fail_on_high = sys.argv[5].lower() == "true"
zap_exit = int(sys.argv[6])
ignored_alert_refs = {value.strip() for value in sys.argv[7].split(",") if value.strip()}
schemathesis_exit = int(sys.argv[8])
run_schemathesis = sys.argv[9].lower() == "true"

def load_first_json(path: str):
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        text = fh.read().strip()
    if not text:
        return {}
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        decoder = json.JSONDecoder()
        parsed, _idx = decoder.raw_decode(text)
        return parsed

zap_report = load_first_json(zap_report_path)

sites = zap_report.get("site", []) if isinstance(zap_report, dict) else []
alerts = []
for site in sites:
    if isinstance(site, dict):
        site_alerts = site.get("alerts", [])
        if isinstance(site_alerts, list):
            alerts.extend(site_alerts)

target = urlparse(zap_target)
target_host = (target.hostname or "").lower()
target_port = target.port or (443 if target.scheme.lower() == "https" else 80)

def is_target_scoped(alert):
    instances = alert.get("instances", [])
    if not isinstance(instances, list) or not instances:
        return True
    for instance in instances:
        if not isinstance(instance, dict):
            continue
        uri = str(instance.get("uri", "")).strip()
        if not uri:
            continue
        parsed = urlparse(uri)
        host = (parsed.hostname or "").lower()
        port = parsed.port or (443 if parsed.scheme.lower() == "https" else 80)
        if host == target_host and port == target_port:
            return True
    return False

scoped_alerts = [alert for alert in alerts if is_target_scoped(alert)]

filtered_alerts = [
    alert for alert in scoped_alerts
    if str(alert.get("alertRef", "")).strip() not in ignored_alert_refs
]

high_count = sum(1 for alert in filtered_alerts if str(alert.get("riskcode", "")) == "3")
medium_count = sum(1 for alert in filtered_alerts if str(alert.get("riskcode", "")) == "2")
low_count = sum(1 for alert in filtered_alerts if str(alert.get("riskcode", "")) == "1")
info_count = sum(1 for alert in filtered_alerts if str(alert.get("riskcode", "")) == "0")
total_alerts = len(alerts)
scoped_total = len(scoped_alerts)
ignored_alerts = scoped_total - len(filtered_alerts)
out_of_scope_alerts = total_alerts - scoped_total
gate_failed = fail_on_high and (high_count + medium_count > 0 or (run_schemathesis and schemathesis_exit == 1))

payload = {
    "health_probe_target": base_url,
    "zap_target": zap_target,
    "zap_report": zap_report_path,
    "zap_exit_code": zap_exit,
    "schemathesis_enabled": run_schemathesis,
    "schemathesis_exit_code": schemathesis_exit,
    "schemathesis_gate_failed": run_schemathesis and schemathesis_exit == 1,
    "zap_alerts": {
        "high": high_count,
        "medium": medium_count,
        "low": low_count,
        "info": info_count,
        "total": total_alerts,
        "scoped_total": scoped_total,
        "ignored": ignored_alerts,
        "out_of_scope_ignored": out_of_scope_alerts,
    },
    "ignored_alert_refs": sorted(ignored_alert_refs),
    "healthz_passed": True,
    "gate_failed": gate_failed,
}
with open(summary_path, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, indent=2)
    fh.write("\n")
print("Dynamic Application Security Testing (DAST) summary")
print(json.dumps(payload, indent=2))
if gate_failed:
    print("❌ Dynamic Application Security Testing (DAST) gate failed: Medium/High alerts or Schemathesis contract failures detected.")
    sys.exit(1)
PY
  if [[ -n "${DAST_DATABASE_URL}" ]] && [[ -n "${DAST_RUN_ID}" ]]; then
    cleanup_dast_tenant_data "${DAST_DATABASE_URL}" "${DAST_RUN_ID}"
  fi
  if [[ -n "${DAST_APP_PID}" ]] && kill -0 "${DAST_APP_PID}" >/dev/null 2>&1; then
    echo "▶ Stopping auto-booted valve service after DAST"
    #R030: Tear down the entire auto-boot process group so the spawned valve
    # binary can never outlive this script and leak the bind address.
    if [[ -n "${DAST_APP_PGID}" ]]; then
      kill -TERM -- "-${DAST_APP_PGID}" >/dev/null 2>&1 || true
    fi
    kill -TERM "${DAST_APP_PID}" >/dev/null 2>&1 || true
    wait "${DAST_APP_PID}" >/dev/null 2>&1 || true
    DAST_APP_PID=""
    DAST_APP_PGID=""
  fi
  echo "✅ Dynamic Application Security Testing (DAST) checks completed."
}

#R010: Keep security checks scoped to SAST/DAST so step-02 remains independent.
run_sast_lane
run_dast_lane

#R045: Emit explicit completion status and report location.
echo "✅ Security checks completed. Reports: ${REPORT_DIR}"
