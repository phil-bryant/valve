#!/usr/bin/env bash
umask 007
#R001: Run backend launcher in strict fail-fast mode from repository root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

#R005: Fail fast when Go toolchain is unavailable with install guidance.
if ! command -v go >/dev/null 2>&1; then
  echo "❌ Missing required command: go"
  echo "Install prerequisites with: ./01_install_prerequisites.sh"
  exit 1
fi
if ! command -v 1psa >/dev/null 2>&1; then
  echo "❌ Missing required command: 1psa"
  echo "Install prerequisites with: ./01_install_prerequisites.sh"
  exit 1
fi

VALVE_PSA_ITEM="${VALVE_PSA_ITEM:-localhost_postgres_valve}"
VALVE_ENDPOINT_1PSA_ITEM="${VALVE_ENDPOINT_1PSA_ITEM:-VALVE_SERVICE_ENDPOINT}"
VALVE_DATABASE_NAME="${VALVE_DATABASE_NAME:-valve}"
VALVE_DATABASE_SSLMODE="${VALVE_DATABASE_SSLMODE:-disable}"

read_1psa_field() {
  local item="$1"
  local field="$2"
  1psa -f "$item" "$field"
}

read_optional_1psa_field() {
  local item="$1"
  local field="$2"
  local value=""
  set +e
  value="$(1psa -f "$item" "$field" 2>/dev/null)"
  local read_exit=$?
  set -e
  if [ "${read_exit}" -ne 0 ]; then
    return 1
  fi
  value="${value//$'\r'/}"
  value="${value%$'\n'}"
  if [ -z "${value}" ]; then
    return 1
  fi
  printf '%s' "${value}"
}

resolve_bind_addr() {
  if [ -n "${VALVE_ADDR:-}" ]; then
    printf '%s' "${VALVE_ADDR}"
    return 0
  fi

  local endpoint_host=""
  local endpoint_port=""
  local field_name=""
  local -a endpoint_port_fields=("port" "service_port" "app_port" "http_port" "dast_port")

  if endpoint_host="$(read_optional_1psa_field "${VALVE_ENDPOINT_1PSA_ITEM}" "host")"; then
    :
  elif endpoint_host="$(read_optional_1psa_field "${VALVE_ENDPOINT_1PSA_ITEM}" "service_host")"; then
    :
  else
    endpoint_host="127.0.0.1"
  fi

  for field_name in "${endpoint_port_fields[@]}"; do
    if endpoint_port="$(read_optional_1psa_field "${VALVE_ENDPOINT_1PSA_ITEM}" "${field_name}")"; then
      if [[ ! "${endpoint_port}" =~ ^[0-9]+$ ]] || (( endpoint_port < 1 || endpoint_port > 65535 )); then
        echo "❌ Invalid VALVE service endpoint port in 1psa item/field: ${VALVE_ENDPOINT_1PSA_ITEM}/${field_name}"
        exit 1
      fi
      printf '%s:%s' "${endpoint_host}" "${endpoint_port}"
      return 0
    fi
  done

  # Preserve local-dev ergonomics when endpoint item is not populated.
  printf ':8090'
}

resolve_box_fqdn() {
  local resolver_source="/tmp/valve-upload-host-resolver-$$.go"
  printf '%s\n' \
    'package main' \
    '' \
    'import (' \
    '  "fmt"' \
    '  "net"' \
    '  "os"' \
    '  "strings"' \
    ')' \
    '' \
    'func main() {' \
    '  host, err := os.Hostname()' \
    '  if err != nil {' \
    '    fmt.Fprintf(os.Stderr, "resolver_debug stage=os.Hostname err=%v\n", err)' \
    '    os.Exit(1)' \
    '  }' \
    '  fmt.Fprintf(os.Stderr, "resolver_debug stage=os.Hostname host=%s\n", host)' \
    '' \
    '  addrs, err := net.LookupIP(host)' \
    '  if err != nil {' \
    '    fmt.Fprintf(os.Stderr, "resolver_debug stage=net.LookupIP host=%s err=%v\n", host, err)' \
    '    os.Exit(1)' \
    '  }' \
    '  if len(addrs) == 0 {' \
    '    fmt.Fprintf(os.Stderr, "resolver_debug stage=net.LookupIP host=%s err=no_results\n", host)' \
    '    os.Exit(1)' \
    '  }' \
    '  fmt.Fprintf(os.Stderr, "resolver_debug stage=net.LookupIP ip=%s\n", addrs[0].String())' \
    '' \
    '  names, err := net.LookupAddr(addrs[0].String())' \
    '  if err != nil {' \
    '    fmt.Fprintf(os.Stderr, "resolver_debug stage=net.LookupAddr ip=%s err=%v\n", addrs[0].String(), err)' \
    '    os.Exit(1)' \
    '  }' \
    '  if len(names) == 0 {' \
    '    fmt.Fprintf(os.Stderr, "resolver_debug stage=net.LookupAddr ip=%s err=no_results\n", addrs[0].String())' \
    '    os.Exit(1)' \
    '  }' \
    '  fmt.Fprintf(os.Stderr, "resolver_debug stage=net.LookupAddr fqdn=%s\n", strings.TrimSuffix(names[0], "."))' \
    '' \
    '  fmt.Println(strings.TrimSuffix(names[0], "."))' \
    '}' > "$resolver_source"
  go run "$resolver_source"
}

#R010: Resolve backend database connection info from 1psa.
set +e
VALVE_DB_USER="$(read_1psa_field "$VALVE_PSA_ITEM" "username" 2>/dev/null)"
VALVE_DB_USER_EXIT=$?
set -e
if [ "${VALVE_DB_USER_EXIT}" -ne 0 ] || [ -z "${VALVE_DB_USER}" ]; then
  VALVE_DB_USER="valve"
fi
VALVE_DB_PASSWORD="$(read_1psa_field "$VALVE_PSA_ITEM" "password")"
VALVE_DB_HOST="$(read_1psa_field "$VALVE_PSA_ITEM" "host")"
VALVE_DB_PORT="$(read_1psa_field "$VALVE_PSA_ITEM" "port")"
if [ -z "$VALVE_DB_PASSWORD" ] || [ -z "$VALVE_DB_HOST" ]; then
  echo "❌ Failed to read valve database connection fields from 1psa item: ${VALVE_PSA_ITEM}"
  exit 1
fi
if [[ ! "$VALVE_DB_PORT" =~ ^[0-9]+$ ]] || (( VALVE_DB_PORT < 1 || VALVE_DB_PORT > 65535 )); then
  echo "❌ Failed to read valve database port from 1psa item: ${VALVE_PSA_ITEM}"
  exit 1
fi
if [ -z "${VALVE_DATABASE_URL:-}" ]; then
  VALVE_DATABASE_URL="postgres://${VALVE_DB_USER}:${VALVE_DB_PASSWORD}@${VALVE_DB_HOST}:${VALVE_DB_PORT}/${VALVE_DATABASE_NAME}?sslmode=${VALVE_DATABASE_SSLMODE}"
fi

#R015: Resolve upload endpoint from same-box defaults when not explicitly provided.
if [ -z "${VALVE_UPLOAD_ENDPOINT:-}" ]; then
  MANIFOLD_UPLOAD_SCHEME="${MANIFOLD_UPLOAD_SCHEME:-http}"
  MANIFOLD_UPLOAD_PORT="${MANIFOLD_UPLOAD_PORT:-8081}"
  MANIFOLD_UPLOAD_PATH="${MANIFOLD_UPLOAD_PATH:-/v1/events/batch}"
  RESOLVER_DEBUG_LOG="$(mktemp)"
  set +e
  MANIFOLD_UPLOAD_HOST="$(resolve_box_fqdn 2>"${RESOLVER_DEBUG_LOG}")"
  MANIFOLD_UPLOAD_HOST_EXIT=$?
  set -e
  if [[ ! "${MANIFOLD_UPLOAD_PORT}" =~ ^[0-9]+$ ]] || (( MANIFOLD_UPLOAD_PORT < 1 || MANIFOLD_UPLOAD_PORT > 65535 )); then
    echo "❌ Invalid MANIFOLD_UPLOAD_PORT: ${MANIFOLD_UPLOAD_PORT}"
    exit 1
  fi
  if [ "${MANIFOLD_UPLOAD_HOST_EXIT}" -ne 0 ] || [ -z "${MANIFOLD_UPLOAD_HOST}" ]; then
    echo "❌ Failed to resolve same-box upload hostname from local network identity."
    if [ -s "${RESOLVER_DEBUG_LOG}" ]; then
      echo "ℹ️  Resolver debug:"
      sed 's/^/   /' "${RESOLVER_DEBUG_LOG}"
    fi
    exit 1
  fi
  VALVE_UPLOAD_ENDPOINT="${MANIFOLD_UPLOAD_SCHEME}://${MANIFOLD_UPLOAD_HOST}:${MANIFOLD_UPLOAD_PORT}${MANIFOLD_UPLOAD_PATH}"
fi

VALVE_ADDR="$(resolve_bind_addr)"
VALVE_DEV_AUTH_ALLOW_ALL="${VALVE_DEV_AUTH_ALLOW_ALL:-true}"
#R020: Launch backend in foreground with explicit bind address.
echo "▶ Launching Valve backend on ${VALVE_ADDR}"
echo "ℹ️  Upload endpoint: ${VALVE_UPLOAD_ENDPOINT}"
echo "ℹ️  Dev authorizer allow-all: ${VALVE_DEV_AUTH_ALLOW_ALL}"
VALVE_ADDR="${VALVE_ADDR}" VALVE_DATABASE_URL="${VALVE_DATABASE_URL}" VALVE_UPLOAD_ENDPOINT="${VALVE_UPLOAD_ENDPOINT}" VALVE_DEV_AUTH_ALLOW_ALL="${VALVE_DEV_AUTH_ALLOW_ALL}" go run ./cmd/valve
