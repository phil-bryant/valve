# Credential Type Definitions Requirements

## Scope

Applies to `internal/credentials/types.go`.

R001  Statement: Canonical credential mode and lifecycle status constants must cover all supported values.
Design: String constants `ModeEd25519 = "ed25519"`, `ModeHMACSHA256 = "hmac_sha256"`, `StatusActive = "active"`, `StatusRevoked = "revoked"`, and `StatusRotated = "rotated"` are the only valid values accepted or produced by the service layer.
Tests:
- R001-T01: Verify that `ModeEd25519`, `ModeHMACSHA256`, `StatusActive`, `StatusRevoked`, and `StatusRotated` have the expected string values.
- R001-T02: Verify that `credential_mode` constants remain stable for register validation mode checks.
- R001-T03: Verify that status constants remain stable for lifecycle transition checks.
- R001-T04: Verify canonical register payloads using these type definitions validate successfully.
- R001-T05: Verify unknown credential mode payloads are rejected when decoded into these type definitions.
- R001-T06: Verify disabled-HMAC payloads are rejected when decoded into these type definitions.
- R001-T07: Verify missing Ed25519 key payloads are rejected when decoded into these type definitions.
- R001-T08: Verify non-base64 Ed25519 key payloads are rejected when decoded into these type definitions.
- R001-T09: Verify invalid-length Ed25519 key payloads are rejected when decoded into these type definitions.
- R001-T10: Verify valid Ed25519 payloads pass validation when decoded into these type definitions.
- R001-T11: Verify valid HMAC payloads pass validation when decoded into these type definitions and HMAC is enabled.

R005  Statement: API request and response payload models must carry JSON tags matching the wire contract for all credential operations.
Design: `RegisterRequest`, `RegisterResponse`, `RevokeRequest`, `RevokeResponse`, `RotateRequest`, `RotateResponse`, `UploadTargetRequest`, and `UploadTargetResponse` are defined with `json:` struct tags. `RegisterResponse.Secret` and `RotateResponse.Secret` use `omitempty` so the field is absent from Ed25519 responses. `UploadTargetResponse.RoutingVersion` uses `omitempty`.
Tests:
- R005-T01: Verify that JSON-marshalling a `RegisterResponse` with an empty `Secret` field omits the `secret` key.
- R005-T02: Verify that JSON-marshalling a `RegisterResponse` with a non-empty `Secret` field includes the `secret` key.
- R005-T03: Verify that JSON-marshalling an `UploadTargetResponse` with an empty `RoutingVersion` omits the `routing_version` key.
- R005-T04: Verify that JSON payload type definitions support valid revoke request/response validation round-trips.

R010  Statement: Persisted credential and audit data models must carry all fields required by the storage and API layers.
Design: `CredentialRecord` includes `CredentialID`, `TenantID`, `InstallID`, `ActorUserID`, `AppBundleID`, `AppVersion`, `AppBuild`, `Platform`, `CredentialMode`, `PublicKey`, `Status`, `ReplacedByCredentialID`, `DeviceLabel`, `CreatedAt`, `RevokedAt`, `RotatedAt`, and `LastSeenAt`. `AuditEntry` includes `ActorUserID`, `TenantID`, `InstallID`, `CredentialID`, `Action`, `Reason`, and `MetadataJSON`. `VerificationResponse` includes `CredentialID`, `TenantID`, `InstallID`, `AppBundleID`, `CredentialMode`, `PublicKey`, `Status`, and `RevokedAt`.
Tests:
- R010-T01: Verify that `CredentialRecord` round-trips through JSON without losing `RevokedAt` when it is non-nil.
- R010-T02: Verify that `VerificationResponse` omits `public_key` when the field is empty (HMAC mode).
- R010-T03: Verify that rotate payload types reject invalid replacement key sizes during validation flows.
- R010-T04: Verify that fully valid rotate payload types pass validation flows.
- R010-T05: Verify that rotate payloads preserve inherited bundle/platform fields in resulting type values.
- R010-T06: Verify that unknown rotate/handler errors still map to stable JSON error outputs for these type definitions.

## Changelog

- 2026-05-16: Numbered test bullets with R###-T## scheme.
- 2026-05-16: Rewrote with concrete field-level and JSON-serialization acceptance criteria.
- 2026-05-10: Added requirements coverage for backend source traceability.
