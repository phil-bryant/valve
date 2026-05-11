# Valve

Valve is the credential-provisioning backend service for diagnostics uploads in the Fountain/Piston/Manifold pipeline.

Valve turns an authenticated user/account action into a tenant-bound upload credential. Piston later proves possession of that credential on every upload. Manifold derives `tenant_id` and `install_id` from the credential record created by Valve, not from event JSON, preventing cross-account contamination.

## How Valve Fits the System

- Fountain (C++) writes sanitized events to local SQLite with `tenant_scope`.
- Piston (Swift) claims batches and uploads over HTTPS.
- Valve (Go) provisions and manages per-tenant/per-install upload credentials.
- Manifold (Go) verifies upload signatures using Valve credential data and derives tenant/install identity.
- Vortex handles downstream storage, analytics, and UI.

Valve does **not** ingest event batches and does **not** store event logs.

## Features

- Register per-tenant/per-install credentials.
- Revoke active credentials.
- Rotate credentials transactionally.
- List credentials for tenant/install support/debug.
- Internal verification lookup endpoint for Manifold.
- Audit log for register/revoke/rotate/lookup/deny paths.
- Ed25519 mode (preferred v1).
- Optional HMAC fallback (`VALVE_HMAC_MODE_ENABLED=true`) with one-time secret return.

## Project Layout

- `cmd/valve/main.go`
- `internal/config/config.go`
- `internal/httpserver/server.go`
- `internal/credentials/*`
- `internal/storage/postgres.go`
- `internal/storage/schema.sql`
- `internal/auth/*`
- `internal/security/*`
- `internal/logging/logging.go`

## Environment Variables

- `VALVE_ADDR` (default `:8090`)
- `VALVE_DATABASE_URL` (required)
- `VALVE_UPLOAD_ENDPOINT` (required, e.g. `https://ingest.example.com/v1/events/batch`)
- `VALVE_DEV_AUTH_ALLOW_ALL` (default `false`)
- `VALVE_HMAC_MODE_ENABLED` (default `false`)
- `VALVE_SERVICE_AUTH_KEY` (optional, but required for internal verification endpoint access)

## Database Setup

Valve automatically applies `internal/storage/schema.sql` at startup.

To initialize manually:

```bash
psql "$VALVE_DATABASE_URL" -f internal/storage/schema.sql
```

## Run Locally

```bash
export VALVE_DATABASE_URL="postgres://localhost:5432/valve?sslmode=disable"
export VALVE_UPLOAD_ENDPOINT="https://ingest.example.com/v1/events/batch"
export VALVE_DEV_AUTH_ALLOW_ALL=true
export VALVE_SERVICE_AUTH_KEY="set-runtime-value-in-your-shell" # pragma: allowlist secret

go run ./cmd/valve
```

## API

### Register Credential

`POST /v1/valve/credentials/register`

Ed25519 example:

```bash
curl -X POST http://localhost:8090/v1/valve/credentials/register \
  -H 'Content-Type: application/json' \
  -d '{
    "tenant_id": "tenant_dev",
    "actor_user_id": "user_dev",
    "install_id": "install_dev_001",
    "app_bundle_id": "com.example.App",
    "app_version": "1.8.3",
    "app_build": "1842",
    "platform": "macOS",
    "device_label": "Dev Mac",
    "credential_mode": "ed25519",
    "public_key": "BASE64_ED25519_PUBLIC_KEY_HERE"
  }'
```

HMAC fallback example (feature-flagged):

```bash
curl -X POST http://localhost:8090/v1/valve/credentials/register \
  -H 'Content-Type: application/json' \
  -d '{
    "tenant_id": "tenant_dev",
    "actor_user_id": "user_dev",
    "install_id": "install_dev_001",
    "app_bundle_id": "com.example.App",
    "app_version": "1.8.3",
    "app_build": "1842",
    "platform": "macOS",
    "device_label": "Dev Mac",
    "credential_mode": "hmac_sha256"
  }'
```

### Revoke Credential

`POST /v1/valve/credentials/revoke`

```bash
curl -X POST http://localhost:8090/v1/valve/credentials/revoke \
  -H 'Content-Type: application/json' \
  -d '{
    "tenant_id": "tenant_dev",
    "actor_user_id": "user_dev",
    "credential_id": "cred_abc123",
    "reason": "device_lost"
  }'
```

### Rotate Credential

`POST /v1/valve/credentials/rotate`

```bash
curl -X POST http://localhost:8090/v1/valve/credentials/rotate \
  -H 'Content-Type: application/json' \
  -d '{
    "tenant_id": "tenant_dev",
    "actor_user_id": "user_dev",
    "old_credential_id": "cred_old",
    "install_id": "install_dev_001",
    "credential_mode": "ed25519",
    "new_public_key": "BASE64_ED25519_PUBLIC_KEY_HERE"
  }'
```

### List Credentials

`GET /v1/valve/credentials?tenant_id=tenant_dev&install_id=install_dev_001`

### Verification Lookup (Internal)

`GET /v1/valve/credentials/{credential_id}/verification`

Requires:

- Header: `X-Valve-Service-Key: <VALVE_SERVICE_AUTH_KEY>`

## Health and Readiness

- `GET /healthz` -> process liveness
- `GET /readyz` -> database reachability

## Security Model

- Per-tenant/per-install credential model only (no global shared app credential).
- Ed25519 public-key registration preferred.
- HMAC fallback behind feature flag only.
- HMAC secret is generated server-side and returned once on register/rotate.
- HMAC secret is never returned by list/get/verification APIs.
- No secret-bearing fields are logged by the service.
- Service-to-service verification endpoint is protected by constant-time key comparison.
- Unauthorized responses are generic.

## Piston -> Manifold Signed Request Contract

Required headers:

- `X-Manifold-Credential-ID`
- `X-Manifold-Timestamp` (RFC3339 UTC)
- `X-Manifold-Batch-ID` (UUID)
- `X-Manifold-Body-SHA256` (`base64url(sha256(body))`)
- `X-Manifold-Signature` (`base64url(signature)`)

Canonical string:

```text
METHOD + "\n" +
PATH + "\n" +
TIMESTAMP + "\n" +
BATCH_ID + "\n" +
BODY_SHA256
```

Example:

```text
POST
/v1/events/batch
2026-05-10T20:00:00Z
018f4f25-2f94-7a79-bbb0-588948272bc3
base64urlsha256body
```

Verification rules for Manifold:

1. Credential exists.
2. Credential status is active.
3. Timestamp is within skew window (default 5 minutes).
4. Body hash matches.
5. Signature verifies for credential mode.
6. `tenant_id` and `install_id` are derived from credential record.
7. Payload tenant/install fields (if present) are mismatch checks only.
8. Persisted identity uses credential-derived tenant/install values.

## Tests

Run all tests:

```bash
go test ./...
```

Integration tests use a real Postgres when one of these env vars is set:

- `VALVE_TEST_DATABASE_URL`
- `VALVE_DATABASE_URL`

If neither is set, integration tests are skipped.

## Production TODOs

- Replace dev authorizer with primary backend authorization integration.
- Replace placeholder HMAC secret storage with KMS envelope encryption.
- Restrict verification endpoint network exposure and require mTLS/service identity.
- Add request rate limiting and abuse controls.
- Add database migrations framework and rollout strategy.
- Add robust tracing/metrics dashboards and alerting.

## Architecture Diagram

```text
BACKEND
┌──────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│  ┌────────────────────────────┐        ┌──────────────────────────────────┐  │
│  │           Valve            │        │             Manifold             │  │
│  │                            │        │                                  │  │
│  │ - runs after user sign-in  │        │ - verifies signature / credential│  │
│  │ - verifies Account A access│        │ - derives tenant_id + install_id │  │
│  │ - provisions per-tenant /  │        │   from credential                │  │
│  │   per-install credential   │        │ - stores tenant-scoped events    │  │
│  │ - rotates / revokes creds  │        │ - rejects tenant mismatches      │  │
│  └─────────────┬──────────────┘        │                                  │  │
│                │                       │  ┌───────────────────────┐       │  │
│                │                       │  │ Ingest Endpoint       │       │  │
│                │                 ┌─────┼─►│ POST /v1/events/batch │       │  │
│                │                 │     │  └───────────────────────┘       │  │
│                │                 │     │                                  │  │
│                │                 │     └──────────────────────┬───────────┘  │
│                │                 │                            │              │
└────────────────┼─────────────────┼────────────────────────────┼──────────────┘
                 │                 │                            │
                 │                 │                            │ tenant-scoped
                 │                 │                            │ events
                 │ credential      │             NOC/SOC        ▼
                 │ for Account A   │             ┌──────────────────────────┐
                 │ + Install 123   │             │          Vortex          │
                 │                 │             │                          │
                 │                 │             │ - downstream all-in-one  │
                 │                 │             │ - storage / analytics    │
                 │                 │             │ - dashboards / alerts    │
                 │                 │             │ - incident review        │
    credential   │                 │             │ - strict tenant_id reads │
    provisioned  │                 │             └──────────────────────────┘
   after sign-in │                 │
                 │                 │ HTTPS + signed batch
                 │                 │ credential proves Account A + Install 123
CUSTOMER DEVICE  ▼                 │
┌──────────────────────────────────┼─────────┐
│                                  │         │
│  ┌────────────────────┐   ┌─────────────┐  │
│  │      Fountain      │   │   Piston    │  │
│  │                    │   │             │  │
│  │ - C++ event logger │   │ - Swift     │  │
│  │ - SQLite queue     │   │   uploader  │  │
│  │ - tags events with │   │ - stores    │  │
│  │   tenant_scope     │   │   credential│  │
│  └─────────┬──────────┘   │ - claims    │  │
│            │              │   matching  │  │
│            │ Account A    │   scope     │  │
│            │ events       │ - signs     │  │
│            └─────────────►│   uploads   │  │
│                           └─────────────┘  │
│                                            │
└────────────────────────────────────────────┘
```
