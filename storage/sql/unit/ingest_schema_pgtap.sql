BEGIN;
SELECT plan(8);
SELECT has_table('public', 'valve_credentials', 'valve_credentials table exists');
SELECT has_table('public', 'valve_audit_log', 'valve_audit_log table exists');
SELECT col_is_pk('public', 'valve_credentials', 'credential_id', 'valve_credentials.credential_id is primary key');
SELECT has_index('public', 'valve_credentials', 'idx_valve_credentials_tenant_install',
  'tenant/install index exists on valve_credentials');
SELECT has_index('public', 'valve_credentials', 'idx_valve_credentials_status',
  'status index exists on valve_credentials');
SELECT has_index('public', 'valve_credentials', 'idx_valve_credentials_tenant_status',
  'tenant/status index exists on valve_credentials');
SELECT col_type_is('public', 'valve_audit_log', 'metadata', 'jsonb', 'valve_audit_log.metadata is jsonb');
SELECT col_type_is('public', 'valve_credentials', 'hmac_secret_encrypted', 'bytea',
  'valve_credentials.hmac_secret_encrypted is bytea');
SELECT * FROM finish();
ROLLBACK;
