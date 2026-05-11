#!/bin/sh
#R001: Enforce strict fail-fast execution semantics.
set -eu

#R005: Resolve valve credential from dedicated 1psa item.
VALVE_PSA_ITEM="${VALVE_PSA_ITEM:-localhost_postgres_valve}"
VALVE_PSA_FIELD="${VALVE_PSA_FIELD:-password}"
DB_USER="valve"

if ! command -v 1psa >/dev/null; then
  echo "❌ FAIL: 1psa is required but was not found on PATH."
  exit 1
fi

read_1psa_secret() {
  item="$1"
  field="$2"
  if [ "$field" = "password" ]; then
    1psa -p "$item"
  else
    1psa -f "$item" "$field"
  fi
}

DB_PASSWORD="$(read_1psa_secret "$VALVE_PSA_ITEM" "$VALVE_PSA_FIELD")"
if [ -z "$DB_PASSWORD" ]; then
  echo "❌ FAIL: Failed to resolve valve password from 1psa item: ${VALVE_PSA_ITEM}"
  exit 1
fi
DB_HOST="$(read_1psa_secret "$VALVE_PSA_ITEM" "host")"
if [ -z "$DB_HOST" ]; then
  echo "❌ FAIL: Failed to resolve valve host from 1psa item: ${VALVE_PSA_ITEM}"
  exit 1
fi
DB_PORT="$(read_1psa_secret "$VALVE_PSA_ITEM" "port")"
case "$DB_PORT" in
  ''|*[!0-9]*)
    echo "❌ FAIL: Failed to resolve valve port from 1psa item: ${VALVE_PSA_ITEM}"
    exit 1
    ;;
esac
DB_NAME="$(read_1psa_secret "$VALVE_PSA_ITEM" "database")"
if [ -z "$DB_NAME" ]; then
  echo "❌ FAIL: Failed to resolve valve database name from 1psa item: ${VALVE_PSA_ITEM}"
  exit 1
fi
DB_SCHEMA="$(read_1psa_secret "$VALVE_PSA_ITEM" "schema")"
if [ -z "$DB_SCHEMA" ]; then
  echo "❌ FAIL: Failed to resolve valve schema name from 1psa item: ${VALVE_PSA_ITEM}"
  exit 1
fi
case "$DB_SCHEMA" in
  [A-Za-z_]*)
    ;;
  *)
    echo "❌ FAIL: Failed to resolve valve schema name from 1psa item: ${VALVE_PSA_ITEM}"
    exit 1
    ;;
esac
case "$DB_SCHEMA" in
  *[!A-Za-z0-9_]*)
    echo "❌ FAIL: Failed to resolve valve schema name from 1psa item: ${VALVE_PSA_ITEM}"
    exit 1
    ;;
esac

#R010: Refuse verification when psql is unavailable.
if ! command -v psql >/dev/null; then
  echo "❌ FAIL: psql is required but was not found on PATH."
  exit 1
fi

#R035: Run all verification queries with fail-fast psql options.
db_lines() {
  PGPASSWORD="$DB_PASSWORD" \
    psql -w -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -At -c "$1"
}

#R035: Scalar helper shares fail-fast settings with line helper.
db_scalar() {
  db_lines "$1"
}

FAILURES=""
record_failure() {
  if [ -n "$FAILURES" ]; then
    FAILURES="${FAILURES}
$1"
  else
    FAILURES="$1"
  fi
}

comma_join_lines() {
  printf '%s' "$1" | tr '\n' ',' | sed 's/,$//'
}

echo "🔎 Verifying valve database schema on ${DB_HOST}:${DB_PORT}/${DB_NAME} schema ${DB_SCHEMA} as ${DB_USER}..."

#R015: Verify required valve credential tables exist.
echo "- checking required tables..."
missing_tables="$(
  db_lines "
    WITH expected(table_name) AS (
      VALUES ('valve_audit_log'), ('valve_credentials')
    )
    SELECT expected.table_name
    FROM expected
    LEFT JOIN information_schema.tables tables
      ON tables.table_schema = '${DB_SCHEMA}'
     AND tables.table_name = expected.table_name
     AND tables.table_type = 'BASE TABLE'
    WHERE tables.table_name IS NULL
    ORDER BY expected.table_name;
  "
)"
if [ -n "$missing_tables" ]; then
  record_failure "missing tables: $(comma_join_lines "$missing_tables")"
else
  echo "  ✓ tables present: valve_audit_log, valve_credentials"
fi

#R020: Verify required valve credential indexes exist.
echo "- checking required indexes..."
missing_indexes="$(
  db_lines "
    WITH expected(index_name) AS (
      VALUES
        ('idx_valve_credentials_status'),
        ('idx_valve_credentials_tenant_install'),
        ('idx_valve_credentials_tenant_status')
    )
    SELECT expected.index_name
    FROM expected
    LEFT JOIN pg_indexes idx
      ON idx.schemaname = '${DB_SCHEMA}'
     AND idx.tablename = 'valve_credentials'
     AND idx.indexname = expected.index_name
    WHERE idx.indexname IS NULL
    ORDER BY expected.index_name;
  "
)"
if [ -n "$missing_indexes" ]; then
  record_failure "missing indexes: $(comma_join_lines "$missing_indexes")"
else
  echo "  ✓ indexes present: tenant_install, status, tenant_status"
fi

#R025: Verify valve_credentials has expected uniqueness contract.
echo "- checking uniqueness contract..."
if [ "$(db_scalar "
  SELECT EXISTS (
    SELECT 1
    FROM pg_constraint con
    JOIN pg_class rel
      ON rel.oid = con.conrelid
    JOIN pg_namespace ns
      ON ns.oid = rel.relnamespace
    WHERE con.contype = 'u'
      AND ns.nspname = '${DB_SCHEMA}'
      AND rel.relname = 'valve_credentials'
      AND con.conname = 'valve_credentials_tenant_id_install_id_credential_id_key'
  );
")" != "t" ]; then
  record_failure "missing unique constraint: valve_credentials(tenant_id, install_id, credential_id)"
else
  echo "  ✓ unique constraint present: valve_credentials(tenant_id, install_id, credential_id)"
fi

#R030: Print explicit pass/fail verification result.
if [ -n "$FAILURES" ]; then
  echo "❌ FAIL: Valve database verification failed."
  old_ifs="$IFS"
  IFS='
'
  for failure in $FAILURES; do
    echo "- $failure"
  done
  IFS="$old_ifs"
  exit 1
fi
echo "✅ PASS: Valve database schema objects verified."
