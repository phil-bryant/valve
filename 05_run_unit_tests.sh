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

#R025: Ensure pgTAP extension exists in target database.
echo ""
echo "▶ Running SQL unit tests (pgTAP)..."
PGPASSWORD="$DB_PASSWORD" \
  psql "${PSQL_COMMON_ARGS[@]}" -c "CREATE EXTENSION IF NOT EXISTS pgtap;"

#R030: Execute SQL unit tests first with fail-fast psql settings.
PGPASSWORD="$DB_PASSWORD" \
  psql "${PSQL_COMMON_ARGS[@]}" -f "$SQL_TEST_FILE"

#R030: Run Go unit tests only after SQL unit tests pass.
echo ""
echo "▶ Running Go unit tests..."
GO_TEST_OUTPUT_FILE="$(mktemp)"
if ! go test ./... | tee "$GO_TEST_OUTPUT_FILE"; then
  exit 1
fi

#R030: Run Bats shell tests only after Go unit tests pass.
echo ""
echo "▶ Running Bats shell tests..."
bats "${SCRIPT_DIR}/tests/sh"

#R037: Run Swift package tests after Bats shell tests pass.
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
