# Credential Validation Requirements

## Scope

Applies to `internal/credentials/validation.go`.

R001  Statement: Register validation must reject missing required fields, unsupported modes, disabled HMAC, and invalid Ed25519 keys.
Design: `ValidateRegister` returns an error when `tenant_id`, `install_id`, or `app_bundle_id` are empty; when `actor_user_id` is empty and `allowEmptyActor` is false; when `platform` is not `macOS`; when `credential_mode` is not `ed25519` or `hmac_sha256`; when `credential_mode` is `hmac_sha256` and `hmacEnabled` is false; when `credential_mode` is `ed25519` and `public_key` is empty, not valid base64, or not exactly 32 bytes after decoding.
Tests:
- R001-T01: Verify that an empty `tenant_id` returns an error.
- R001-T02: Verify that an empty `actor_user_id` with `allowEmptyActor=false` returns an error.
- R001-T03: Verify that an empty `actor_user_id` with `allowEmptyActor=true` does not return an error.
- R001-T04: Verify that `platform != "macOS"` returns an error.
- R001-T05: Verify that an unknown `credential_mode` returns an error.
- R001-T06: Verify that `credential_mode=hmac_sha256` with `hmacEnabled=false` returns an error.
- R001-T07: Verify that `credential_mode=ed25519` with an empty `public_key` returns an error.
- R001-T08: Verify that `credential_mode=ed25519` with a non-base64 `public_key` returns an error.
- R001-T09: Verify that `credential_mode=ed25519` with a base64 key that decodes to fewer than 32 bytes returns an error.
- R001-T10: Verify that a fully valid Ed25519 request returns nil.
- R001-T11: Verify that a fully valid HMAC request with `hmacEnabled=true` returns nil.

R005  Statement: Revoke validation must reject missing tenant, credential ID, and actor when required.
Design: `ValidateRevoke` returns an error when `tenant_id` is empty, when `credential_id` is empty, or when `actor_user_id` is empty and `allowEmptyActor` is false.
Tests:
- R005-T01: Verify that an empty `tenant_id` returns an error.
- R005-T02: Verify that an empty `credential_id` returns an error.
- R005-T03: Verify that an empty `actor_user_id` with `allowEmptyActor=false` returns an error.
- R005-T04: Verify that a fully valid revoke request returns nil.

R010  Statement: Rotate validation must reject missing identifiers, unsupported modes, disabled HMAC, and invalid replacement Ed25519 keys.
Design: `ValidateRotate` returns an error when `tenant_id`, `old_credential_id`, or `install_id` are empty; when `actor_user_id` is empty and `allowEmptyActor` is false; when `credential_mode` is not `ed25519` or `hmac_sha256`; when `credential_mode` is `hmac_sha256` and `hmacEnabled` is false; when `credential_mode` is `ed25519` and `new_public_key` is empty, not valid base64, or not exactly 32 bytes after decoding.
Tests:
- R010-T01: Verify that an empty `old_credential_id` returns an error.
- R010-T02: Verify that an empty `install_id` returns an error.
- R010-T03: Verify that `credential_mode=ed25519` with a base64 key that decodes to the wrong length returns an error.
- R010-T04: Verify that a fully valid Ed25519 rotate request returns nil.
- R010-T05: Verify that `credential_mode=hmac_sha256` with `hmacEnabled=false` returns an error for rotate requests.
- R010-T06: Verify that an unknown rotate-mode service error maps to the generic validation failure path.

R015  Statement: Upload target request validation must reject missing tenant, install, and credential identifiers.
Design: `ValidateUploadTargetRequest` returns an error when `tenant_id`, `install_id`, or `credential_id` are empty.
Tests:
- R015-T01: Verify that an empty `tenant_id` returns an error.
- R015-T02: Verify that an empty `install_id` returns an error.
- R015-T03: Verify that an empty `credential_id` returns an error.
- R015-T04: Verify that a fully valid upload target request returns nil.
- R015-T05: Verify that successful upload-target lookup validation supports downstream audit recording behavior.

## Changelog

- 2026-05-16: Numbered test bullets with R###-T## scheme.
- 2026-05-16: Rewrote with concrete field-level acceptance criteria; added R015.
- 2026-05-10: Added requirements coverage for backend source traceability.
