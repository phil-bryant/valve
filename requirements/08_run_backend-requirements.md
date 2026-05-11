# Run Backend Requirements

## Scope

Applies to `08_run_backend.sh`.

R001  Statement: Run backend launcher in strict fail-fast mode from repository root.
Design: Use strict bash mode (`set -euo pipefail`), resolve script directory from `${BASH_SOURCE[0]}`, and `cd` into script directory before startup flow.
Tests:
- Run script from a non-repo working directory and verify backend launch invocation still resolves from script-root.

R005  Statement: Fail fast when Go toolchain is unavailable with actionable install guidance.
Design: Validate `go` and `1psa` on PATH before backend startup and print `./01_install_prerequisites.sh` guidance when unavailable.
Tests:
- Run with `go` missing from PATH and verify explicit non-zero failure with installer guidance output.
- Run with `1psa` missing from PATH and verify explicit non-zero failure with installer guidance output.

R010  Statement: Resolve backend database connection info from 1psa.
Design: Read `username`, `password`, `host`, and `port` from `VALVE_PSA_ITEM` (default `localhost_postgres_valve`), validate required fields and port range, and compose `VALVE_DATABASE_URL` when explicit override is not provided.
Tests:
- Run without `VALVE_DATABASE_URL` and verify backend receives composed DSN values from 1psa lookup.
- Run with invalid port from 1psa and verify explicit non-zero failure output.

R015  Statement: Require explicit upload endpoint before startup.
Design: When `VALVE_UPLOAD_ENDPOINT` is unset, derive same-box manifold upload endpoint by resolving host identity via Go network lookup flow (`os.Hostname` -> `net.LookupIP` -> `net.LookupAddr`), then combine with `MANIFOLD_UPLOAD_SCHEME` (default `http`), `MANIFOLD_UPLOAD_PORT` (default `8081`), and `MANIFOLD_UPLOAD_PATH` (default `/v1/events/batch`); fail when hostname lookup or derived upload port validation fails.
Tests:
- Run without `VALVE_UPLOAD_ENDPOINT` and verify derived endpoint is passed to backend launch.
- Run with invalid `MANIFOLD_UPLOAD_PORT` and verify explicit non-zero failure output.
- Run with resolver command failure and verify explicit non-zero failure output includes resolver debug stage/error context.

R020  Statement: Launch backend in foreground with deterministic default bind address.
Design: Default `VALVE_ADDR` to `:8090` and execute `go run ./cmd/valve` in foreground with `VALVE_ADDR`, `VALVE_DATABASE_URL`, and `VALVE_UPLOAD_ENDPOINT`.
Tests:
- Run with valid env values and verify `go run ./cmd/valve` invocation and `VALVE_ADDR=:8090` default.
- Run with explicit `VALVE_ADDR` override and verify override is passed to `go run`.

## Changelog

- 2026-05-11: Added step-08 backend launcher workflow requirements.
- 2026-05-11: Updated step-08 to resolve Valve DB connection info from 1psa defaults.
- 2026-05-11: Updated step-08 same-box upload endpoint derivation to use hostname/ip/reverse-lookup flow.
- 2026-05-11: Added resolver debug-output requirement for same-box hostname lookup failures.
