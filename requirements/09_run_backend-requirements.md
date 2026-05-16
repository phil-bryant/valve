# Run Backend Requirements

## Scope

Applies to `09_run_backend.sh`.

R001  Statement: Run backend launcher in strict fail-fast mode from repository root.
Design: Use strict bash mode (`set -euo pipefail`), resolve script directory from `${BASH_SOURCE[0]}`, and `cd` into script directory before startup flow.
Tests:
- R001-T01: Run script from a non-repo working directory and verify backend launch invocation still resolves from script-root.

R005  Statement: Fail fast when Go toolchain is unavailable with actionable install guidance.
Design: Validate `go` and `1psa` on PATH before backend startup and print `./01_install_prerequisites.sh` guidance when unavailable.
Tests:
- R005-T01: Run with `go` missing from PATH and verify explicit non-zero failure with installer guidance output.
- R005-T02: Run with `1psa` missing from PATH and verify explicit non-zero failure with installer guidance output.

R010  Statement: Resolve backend database connection info from 1psa.
Design: Read `username`, `password`, `host`, and `port` from `VALVE_PSA_ITEM` (default `localhost_postgres_valve`), validate required fields and port range, and compose `VALVE_DATABASE_URL` when explicit override is not provided.
Tests:
- R010-T01: Run without `VALVE_DATABASE_URL` and verify backend receives composed DSN values from 1psa lookup.
- R010-T02: Run with invalid port from 1psa and verify explicit non-zero failure output.

R015  Statement: Require explicit upload endpoint before startup.
Design: When `VALVE_UPLOAD_ENDPOINT` is unset, derive same-box manifold upload endpoint by resolving host identity via Go network lookup flow (`os.Hostname` -> `net.LookupIP` -> `net.LookupAddr`), then combine with `MANIFOLD_UPLOAD_SCHEME` (default `http`), `MANIFOLD_UPLOAD_PORT` (default `8081`), and `MANIFOLD_UPLOAD_PATH` (default `/v1/events/batch`); fail when hostname lookup or derived upload port validation fails.
Tests:
- R015-T01: Run without `VALVE_UPLOAD_ENDPOINT` and verify derived endpoint is passed to backend launch.
- R015-T02: Run with invalid `MANIFOLD_UPLOAD_PORT` and verify explicit non-zero failure output.
- R015-T03: Run with resolver command failure and verify explicit non-zero failure output includes resolver debug stage/error context.

R020  Statement: Launch backend in foreground with explicit bind address configuration.
Design: Require explicit `VALVE_ADDR` before startup, default `VALVE_DEV_AUTH_ALLOW_ALL` to `true` for local bootstrap, and execute `go run ./cmd/valve` in foreground with `VALVE_ADDR`, `VALVE_DATABASE_URL`, `VALVE_UPLOAD_ENDPOINT`, and `VALVE_DEV_AUTH_ALLOW_ALL`.
Tests:
- R020-T01: Run without `VALVE_ADDR` and verify explicit non-zero failure output.
- R020-T02: Run with explicit `VALVE_ADDR` override and verify override is passed to `go run`.
- R020-T03: Run with `VALVE_DEV_AUTH_ALLOW_ALL` unset and verify `true` default is passed to backend launch.
- R020-T04: Run with explicit `VALVE_DEV_AUTH_ALLOW_ALL=false` and verify override is passed to backend launch.

## Changelog

- 2026-05-16: Numbered test bullets with R###-T## scheme.
- 2026-05-15: Removed implicit `VALVE_ADDR` default and now require explicit backend bind address configuration.
- 2026-05-11: Added step-08 backend launcher workflow requirements.
