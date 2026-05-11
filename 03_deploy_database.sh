#!/usr/bin/env bash
#R001: Enforce strict fail-fast execution semantics.
set -euo pipefail

#R005: Resolve admin and valve credentials from dedicated 1psa items.
POSTGRES_PSA_ITEM="${POSTGRES_PSA_ITEM:-localhost_postgres_postgres}"
POSTGRES_PSA_FIELD="${POSTGRES_PSA_FIELD:-password}"
VALVE_PSA_ITEM="${VALVE_PSA_ITEM:-localhost_postgres_valve}"
VALVE_PSA_FIELD="${VALVE_PSA_FIELD:-password}"
POSTGRES_USER="postgres"
VALVE_USER="valve"

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

POSTGRES_PASSWORD="$(read_1psa_secret "$POSTGRES_PSA_ITEM" "$POSTGRES_PSA_FIELD")"
if [ -z "$POSTGRES_PASSWORD" ]; then
  echo "Failed to resolve postgres password from 1psa item: ${POSTGRES_PSA_ITEM}"
  exit 1
fi

VALVE_PASSWORD="$(read_1psa_secret "$VALVE_PSA_ITEM" "$VALVE_PSA_FIELD")"
if [ -z "$VALVE_PASSWORD" ]; then
  echo "Failed to resolve valve password from 1psa item: ${VALVE_PSA_ITEM}"
  exit 1
fi
DB_HOST="$(read_1psa_secret "$VALVE_PSA_ITEM" "host")"
if [ -z "$DB_HOST" ]; then
  echo "Failed to resolve valve host from 1psa item: ${VALVE_PSA_ITEM}"
  exit 1
fi
DB_PORT="$(read_1psa_secret "$VALVE_PSA_ITEM" "port")"
if [[ ! "${DB_PORT}" =~ ^[0-9]+$ ]] || (( DB_PORT < 1 || DB_PORT > 65535 )); then
  echo "Failed to resolve valve port from 1psa item: ${VALVE_PSA_ITEM}"
  exit 1
fi
DB_NAME="$(read_1psa_secret "$VALVE_PSA_ITEM" "database")"
if [ -z "$DB_NAME" ]; then
  echo "Failed to resolve valve database name from 1psa item: ${VALVE_PSA_ITEM}"
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
VALVE_PASSWORD_SQL="${VALVE_PASSWORD//\'/\'\'}"

#R010: Fail fast when psql client is unavailable.
if ! command -v psql >/dev/null; then
  echo "psql is required but was not found on PATH."
  exit 1
fi

#R015: Resolve schema path relative to script location.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA_PATH="${SCRIPT_DIR}/storage/schema.sql"

#R020: Refuse deploy when schema file is missing.
if [ ! -f "$SCHEMA_PATH" ]; then
  echo "Schema file not found: ${SCHEMA_PATH}"
  exit 1
fi

run_psql_postgres() {
  PGPASSWORD="$POSTGRES_PASSWORD" \
    psql -w -h "$DB_HOST" -p "$DB_PORT" -U "$POSTGRES_USER" -v ON_ERROR_STOP=1 "$@"
}

#R025: Bootstrap valve role/database then apply schema as valve.
if [ "$(run_psql_postgres -d postgres -At -c "SELECT 1 FROM pg_roles WHERE rolname = '${VALVE_USER}'")" = "1" ]; then
  run_psql_postgres -d postgres \
    -c "ALTER ROLE ${VALVE_USER} WITH LOGIN PASSWORD '${VALVE_PASSWORD_SQL}';"
else
  run_psql_postgres -d postgres \
    -c "CREATE ROLE ${VALVE_USER} WITH LOGIN PASSWORD '${VALVE_PASSWORD_SQL}';"
fi

if [ "$(run_psql_postgres -d postgres -At -c "SELECT 1 FROM pg_database WHERE datname = '${DB_NAME}'")" != "1" ]; then
  run_psql_postgres -d postgres \
    -c "CREATE DATABASE ${DB_NAME} WITH OWNER = ${VALVE_USER} ENCODING = 'UTF8' TEMPLATE template0;"
else
  run_psql_postgres -d postgres -c "ALTER DATABASE ${DB_NAME} OWNER TO ${VALVE_USER};"
fi

run_psql_postgres -d "$DB_NAME" -c "CREATE SCHEMA IF NOT EXISTS ${DB_SCHEMA} AUTHORIZATION ${VALVE_USER};"
run_psql_postgres -d "$DB_NAME" -c "ALTER ROLE ${VALVE_USER} IN DATABASE ${DB_NAME} SET search_path TO ${DB_SCHEMA};"

PGPASSWORD="$VALVE_PASSWORD" \
  psql -w -h "$DB_HOST" -p "$DB_PORT" -U "$VALVE_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -c "SET search_path TO ${DB_SCHEMA};" -f "$SCHEMA_PATH"

#R030: Emit concise operator-readable success output.
echo "✅ PASS: Applied valve schema to target database."

