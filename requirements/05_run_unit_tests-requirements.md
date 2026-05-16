# Run Unit Tests Requirements

## Scope

Applies to `05_run_unit_tests.sh`.

R001  Statement: Run SQL unit-test script in strict fail-fast mode.
Design: Use `bash` strict mode (`set -euo pipefail`) and abort on first command failure.
Tests:
- R001-T01: Force `psql` to fail and verify script exits non-zero.

R005  Statement: Resolve SQL unit-test credentials and schema exclusively from `1psa`.
Design: Read valve password from `1psa` item `localhost_postgres_valve` (default field `password`), read schema name from the same item `schema` field, validate schema identifier safety, and connect only to local `localhost:5432/valve` as user `valve`.
Tests:
- R005-T01: Run with `1psa` unavailable and verify explicit non-zero failure output.
- R005-T02: Return empty valve credential from `1psa` and verify explicit non-zero failure output.
- R005-T03: Return empty valve schema from `1psa` and verify explicit non-zero failure output.
- R005-T04: Return invalid valve schema from `1psa` and verify explicit non-zero failure output.

R010  Statement: Refuse unit-test execution when required CLIs are unavailable.
Design: Verify `psql`, `go`, `bats`, and `swift` exist on PATH before any SQL, Go, shell, or Swift unit-test invocation.
Tests:
- R010-T01: Run with `psql` missing from PATH and verify explicit non-zero failure output.
- R010-T02: Run with `go` missing from PATH and verify explicit non-zero failure output.
- R010-T03: Run with `bats` missing from PATH and verify explicit non-zero failure output.
- R010-T04: Run with `swift` missing from PATH and verify explicit non-zero failure output.

R015  Statement: Resolve SQL unit-test file path relative to script location.
Design: Build SQL test file path from script directory so execution is independent of caller working directory.
Tests:
- R015-T01: Run script from a non-repo working directory and verify SQL unit-test path resolves correctly.

R020  Statement: Refuse SQL unit-test execution when SQL test file is missing.
Design: Validate required SQL unit-test file exists before running `psql`.
Tests:
- R020-T01: Move SQL test file out of place in fixture and verify explicit non-zero failure output.

R025  Statement: Ensure pgTAP extension exists before running SQL unit tests.
Design: Execute `CREATE EXTENSION IF NOT EXISTS pgtap;` via local `psql` using credentials resolved from `R005`.
Tests:
- R025-T01: Verify script invokes extension-create SQL before test-file execution.

R030  Statement: Execute SQL unit tests before Go, Bats, and Swift unit tests using non-interactive fail-fast commands, with a header line before each section.
Design: Print `▶ Running SQL unit tests (pgTAP)...` then run SQL test file with `-w -P pager=off -h localhost -p 5432 -d valve -v ON_ERROR_STOP=1 -v VALVE_SCHEMA=<1psa schema> -f <sql-test-file>` using credentials and schema from `R005`; print `▶ Running Go unit tests...` then run `go test ./...`; print `▶ Running Bats shell tests...` then run `bats tests/sh`; print `▶ Running Swift package tests...` then run `swift test --package-path <swift-package-dir>`. Each stage only runs after the previous succeeds.
Tests:
- R030-T01: Verify test invocation includes `ON_ERROR_STOP=1`, `-P pager=off`, VALVE_SCHEMA, and SQL test file path.
- R030-T02: Force SQL stage failure and verify `go test` is not attempted.
- R030-T03: Force `go test` failure and verify script exits non-zero.
- R030-T04: Verify `bats tests/sh` runs only after `go test ./...` succeeds.
- R030-T05: Verify output includes header lines before each test section.

R032  Statement: Fail when any Go package has no associated `_test.go` files.
Design: After `go test ./...` succeeds, parse output for `[no test files]` package rows and fail with an explicit list when any are present.
Tests:
- R032-T01: Emit simulated `go test` output with `[no test files]` entries and verify explicit non-zero failure output.
- R032-T02: Emit simulated `go test` output with no `[no test files]` entries and verify run can complete.

R035  Statement: Emit concise operator-readable pass output.
Design: Print one `✅ PASS:` line only after SQL, Go, Bats, and Swift unit-test execution succeeds.
Tests:
- R035-T01: Verify successful run emits a single `✅ PASS:` line.

R037  Statement: Run Swift package tests after Bats shell tests pass.
Design: Print `▶ Running Swift package tests...`, validate `macos/ValveProvisioningApp/Package.swift` exists, then run `swift test --package-path <dir>`. Fail when the package directory or manifest is missing.
Tests:
- R037-T01: Verify Swift test invocation uses `swift test --package-path` with the correct package directory.
- R037-T02: Force missing Swift package directory and verify explicit non-zero failure output.

## Changelog

- 2026-05-16: Numbered test bullets with R###-T## scheme.
- 2026-05-10: Added Bats execution to step-05 and required `bats` CLI presence before running tests.
- 2026-05-09: Renamed unit-test runner requirements to `05_run_unit_tests.sh`.
