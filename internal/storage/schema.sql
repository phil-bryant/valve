-- #R001: Credential table with lifecycle state and integrity constraints.
CREATE TABLE IF NOT EXISTS valve_credentials (
    credential_id TEXT PRIMARY KEY,

    tenant_id TEXT NOT NULL,
    install_id TEXT NOT NULL,
    actor_user_id TEXT,
    app_bundle_id TEXT NOT NULL,
    app_version TEXT,
    app_build TEXT,
    platform TEXT NOT NULL,

    credential_mode TEXT NOT NULL CHECK (credential_mode IN ('ed25519', 'hmac_sha256')),

    public_key_base64 TEXT,
    hmac_secret_encrypted BYTEA,
    hmac_secret_hash TEXT,

    status TEXT NOT NULL CHECK (status IN ('active', 'revoked', 'rotated')),
    replaced_by_credential_id TEXT,

    device_label TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at TIMESTAMPTZ,
    rotated_at TIMESTAMPTZ,
    last_seen_at TIMESTAMPTZ,

    UNIQUE (tenant_id, install_id, credential_id)
);

-- #R005: Query indexes for tenant/install and status lookups.
CREATE INDEX IF NOT EXISTS idx_valve_credentials_tenant_install
ON valve_credentials(tenant_id, install_id);

CREATE INDEX IF NOT EXISTS idx_valve_credentials_status
ON valve_credentials(status);

CREATE INDEX IF NOT EXISTS idx_valve_credentials_tenant_status
ON valve_credentials(tenant_id, status);

-- #R010: Audit log table for credential operation events and metadata.
CREATE TABLE IF NOT EXISTS valve_audit_log (
    id BIGSERIAL PRIMARY KEY,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    actor_user_id TEXT,
    tenant_id TEXT NOT NULL,
    install_id TEXT,
    credential_id TEXT,
    action TEXT NOT NULL,
    reason TEXT,
    metadata JSONB NOT NULL DEFAULT '{}'
);
