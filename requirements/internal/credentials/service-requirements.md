# Credential Service Requirements

## Scope

Applies to `internal/credentials/service.go`.

R001  Statement: Registration flow must validate inputs, authorize the actor, persist the credential, and emit audit records.
Design: `Register` calls `ValidateRegister`, checks `CanProvisionIngestCredential`, generates a new credential ID, persists the record via `CreateCredential`, and writes an audit entry. When authorization is denied, a `credential_registration_denied` audit entry is written before returning `ErrUnauthorized`. HMAC mode generates a 32-byte random secret server-side; the plaintext secret is returned once in the response and never stored in plaintext. Ed25519 mode stores the caller-supplied public key and returns no secret.
Tests:
- R001-T01: Verify a valid Ed25519 register request returns a response with a non-empty `credential_id`, `status: active`, and empty `secret`.
- R001-T02: Verify a valid HMAC register request returns a response with a non-empty `credential_id`, `status: active`, and a non-empty `secret`.
- R001-T03: Verify that when the authorizer denies the request, `Register` returns `ErrUnauthorized` and a `credential_registration_denied` audit entry is written.
- R001-T04: Verify that a validation failure (e.g. missing `tenant_id`) returns `ErrInvalidInput` without calling the authorizer or store.

R005  Statement: Revoke flow must enforce tenant ownership, active credential lifecycle transitions, and emit audit records.
Design: `Revoke` calls `ValidateRevoke`, checks `CanRevokeIngestCredential`, fetches the credential, asserts `record.TenantID == req.TenantID`, calls `RevokeCredential`, and writes a `credential_revoked` audit entry. When authorization is denied, a `credential_revoke_denied` audit entry is written before returning `ErrUnauthorized`. A tenant mismatch returns `ErrTenantMismatch`. A missing credential returns `ErrNotFound`.
Tests:
- R005-T01: Verify a valid revoke request returns a response with `status: revoked` and a non-nil `revoked_at`.
- R005-T02: Verify that revoking a credential belonging to a different tenant returns `ErrTenantMismatch`.
- R005-T03: Verify that revoking a non-existent credential returns `ErrNotFound`.
- R005-T04: Verify that when the authorizer denies the request, `Revoke` returns `ErrUnauthorized` and a `credential_revoke_denied` audit entry is written.

R010  Statement: Rotation flow must atomically replace an active credential, enforce tenant and install ownership, carry forward metadata, and emit audit records.
Design: `Rotate` calls `ValidateRotate`, checks `CanRevokeIngestCredential` on the old credential, fetches the old record, asserts `TenantID`, `InstallID`, and `Status == active`, generates a new credential ID, builds the replacement record (inheriting `AppBundleID`, `Platform`; preferring request values for `AppVersion`, `AppBuild`, `DeviceLabel`), calls `RotateCredential`, and writes a `credential_rotated` audit entry with `new_credential_id` and `credential_mode` in metadata. A non-active old credential returns `ErrInvalidState`. An install mismatch returns `ErrInvalidInput`.
Tests:
- R010-T01: Verify a valid rotation returns `old_status: rotated`, a new non-empty `new_credential_id`, and `status: active`.
- R010-T02: Verify that rotating a non-active credential returns `ErrInvalidState`.
- R010-T03: Verify that rotating with a mismatched `install_id` returns `ErrInvalidInput`.
- R010-T04: Verify that rotating a credential belonging to a different tenant returns `ErrTenantMismatch`.
- R010-T05: Verify that `AppBundleID` and `Platform` are inherited from the old record in the replacement.

R015  Statement: Read-only endpoints must enforce required arguments and normalize not-found behavior.
Design: `List` requires non-empty `tenant_id` and `install_id`, returning `ErrInvalidInput` otherwise. `VerificationLookup` requires a non-empty `credential_id`, returning `ErrInvalidInput` otherwise; storage misses are mapped to `ErrNotFound`. A successful `VerificationLookup` writes a `credential_lookup_for_verification` audit entry.
Tests:
- R015-T01: Verify `List` with empty `tenant_id` returns `ErrInvalidInput`.
- R015-T02: Verify `List` with empty `install_id` returns `ErrInvalidInput`.
- R015-T03: Verify `VerificationLookup` with empty `credential_id` returns `ErrInvalidInput`.
- R015-T04: Verify `VerificationLookup` for a missing credential returns `ErrNotFound`.
- R015-T05: Verify a successful `VerificationLookup` writes a `credential_lookup_for_verification` audit entry.

R020  Statement: Upload target discovery must validate inputs, enforce active credential ownership, resolve the upload URL from the allowlist, and emit an audit record.
Design: `UploadTarget` calls `ValidateUploadTargetRequest`, fetches the credential, asserts `InstallID` and `TenantID` match the request, asserts `Status == active`, resolves the upload URL via `resolveUploadEndpoint` (preferring tenant-specific routes), and writes an `upload_target_discovered` audit entry. A missing or mismatched credential returns `ErrNotFound`. An inactive credential returns `ErrUnauthorized`. A resolved host not in the allowlist returns `ErrInvalidInput`.
Tests:
- R020-T01: Verify a valid request returns a response with a non-empty `upload_url`, a future `expires_at`, and a positive `ttl_seconds`.
- R020-T02: Verify that a request for an inactive credential returns `ErrUnauthorized`.
- R020-T03: Verify that a request with a mismatched `install_id` returns `ErrNotFound`.
- R020-T04: Verify that a tenant-specific route overrides the default upload endpoint when configured.

R025  Statement: Upload target discovery configuration must validate TTL, routing version, tenant routes, and allowlist membership before applying.
Design: `ConfigureUploadTargetDiscovery` rejects `TTLSeconds <= 0`, empty `RoutingVersion`, empty tenant route keys, non-HTTPS (non-local) route URLs, and any route host not present in `AllowedUploadTargetHosts`. The default upload endpoint host must also be present in the allowlist. All fields are applied atomically only after all validations pass.
Tests:
- R025-T01: Verify that `TTLSeconds <= 0` returns `ErrInvalidInput`.
- R025-T02: Verify that an empty `RoutingVersion` returns `ErrInvalidInput`.
- R025-T03: Verify that a tenant route with a host not in `AllowedUploadTargetHosts` returns `ErrInvalidInput`.
- R025-T04: Verify that the default upload endpoint host not in `AllowedUploadTargetHosts` returns `ErrInvalidInput`.
- R025-T05: Verify that a valid configuration is applied and subsequent `UploadTarget` calls use the new TTL and routing version.

## Changelog

- 2026-05-16: Numbered test bullets with R###-T## scheme.
- 2026-05-16: Rewrote with concrete acceptance criteria; added R020 and R025.
- 2026-05-10: Added requirements coverage for backend source traceability.
