# Configuration Loading Requirements

## Scope

Applies to `internal/config/config.go`.

R001  Statement: Configuration must be loaded from environment variables with deterministic defaults for optional fields.
Design: `Load` populates `Addr` from `VALVE_ADDR` (default `:8090`), `DevAuthAllowAll` from `VALVE_DEV_AUTH_ALLOW_ALL` (default `false`), `HMACModeEnabled` from `VALVE_HMAC_MODE_ENABLED` (default `false`), `UploadTargetTTLSeconds` from `VALVE_UPLOAD_TARGET_TTL_SECONDS` (default `300`), and `UploadTargetRoutingVersion` from `VALVE_UPLOAD_TARGET_ROUTING_VERSION` (default `"v1"`).
Tests:
- R001-T01: Verify that when `VALVE_ADDR` is unset, `Addr` is `:8090`.
- R001-T02: Verify that when `VALVE_ADDR` is set to a custom value, `Addr` reflects that value.
- R001-T04: Verify that when `VALVE_UPLOAD_TARGET_TTL_SECONDS` is unset, `UploadTargetTTLSeconds` is `300`.

R005  Statement: Required environment variables must cause `Load` to return an explicit error when absent.
Design: `Load` returns an error when `VALVE_DATABASE_URL` is empty, when `VALVE_UPLOAD_ENDPOINT` is empty, when `VALVE_UPLOAD_TARGET_TTL_SECONDS` resolves to `<= 0`, or when `VALVE_UPLOAD_TARGET_ROUTING_VERSION` resolves to empty.
Tests:
- R005-T01: Verify that `Load` returns an error when `VALVE_DATABASE_URL` is unset.
- R005-T02: Verify that `Load` returns an error when `VALVE_UPLOAD_ENDPOINT` is unset.
- R005-T03: Verify that `Load` returns an error when `VALVE_UPLOAD_TARGET_TTL_SECONDS` is set to `0`.
- R005-T04: Verify that `Load` returns an error when `VALVE_UPLOAD_TARGET_ROUTING_VERSION` is set to an empty string.
- R005-T05: Verify that `Load` succeeds when all required variables are set.

R010  Statement: Boolean flags must be parsed safely, falling back to the default when the value is absent or unparseable.
Design: `parseBoolOrDefault` returns the fallback when the environment variable is unset or when `strconv.ParseBool` fails; it returns the parsed value otherwise.
Tests:
- R010-T01: Verify that an unset boolean env var returns the specified fallback.
- R010-T02: Verify that `"true"` parses to `true`.
- R010-T03: Verify that `"false"` parses to `false`.
- R010-T04: Verify that an invalid value (e.g. `"yes"`) returns the fallback rather than an error.

R015  Statement: CSV and tenant-route environment variables must be parsed into typed collections, ignoring blank entries.
Design: `VALVE_UPLOAD_TARGET_ALLOWED_HOSTS` is split on commas and trimmed into a `[]string`, omitting blank entries. `VALVE_UPLOAD_TARGET_TENANT_ROUTES` is split on commas, each entry split on the first `=` into a `map[string]string`, omitting entries with empty keys or values.
Tests:
- R015-T01: Verify that a CSV with trailing commas or spaces produces no blank entries in the slice.
- R015-T02: Verify that a tenant routes string `"t1=https://a.example.com,t2=https://b.example.com"` produces a map with two entries.
- R015-T03: Verify that a malformed entry (no `=`) is silently skipped.

## Changelog

- 2026-05-16: Numbered test bullets with R###-T## scheme.
- 2026-05-16: Rewrote with concrete acceptance criteria; added R015 for CSV and tenant-route parsing.
- 2026-05-10: Added requirements coverage for backend source traceability.
