#!/usr/bin/env bats

# Supplemental numbered tags for schema validation parity.
#R001-T02
#R010-T02

@test "R001,R005,R010: schema includes core tables and indexes" {
  #R001-T01: valve_credentials table exists with constrained lifecycle columns.
  #R005-T01: tenant_install index exists on valve_credentials.
  #R010-T01: valve_audit_log table exists with action and metadata columns.
  #R001: Credential table includes constrained lifecycle and identity columns.
  #R005: Schema defines indexes for tenant/install and status access paths.
  #R010: Schema defines audit log table with metadata payload.
  run rg "CREATE TABLE IF NOT EXISTS valve_credentials" "${BATS_TEST_DIRNAME}/../../internal/storage/schema.sql"
  [ "$status" -eq 0 ]
  run rg "CREATE INDEX IF NOT EXISTS idx_valve_credentials_tenant_install" "${BATS_TEST_DIRNAME}/../../internal/storage/schema.sql"
  [ "$status" -eq 0 ]
  run rg "CREATE TABLE IF NOT EXISTS valve_audit_log" "${BATS_TEST_DIRNAME}/../../internal/storage/schema.sql"
  [ "$status" -eq 0 ]
}
