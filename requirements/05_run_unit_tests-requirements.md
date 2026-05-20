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

R030  Statement: Execute SQL unit tests before Go, Bats, and Swift unit tests using non-interactive fail-fast commands, with a boxed header and progress line before each section.
Design: Before each stage, print a boxed `print_runner_header` (same border/width format as step-07 `print_tool_header`, labeled `Test Runner:`) with runner name, two explainer lines, and documentation URL; then print the existing `▶ Running ...` or `▶ Checking ...` progress line; then run the stage command. Stages in order: pgTAP SQL tests via `psql` with `-w -P pager=off -h localhost -p 5432 -d valve -v ON_ERROR_STOP=1 -v VALVE_SCHEMA=<1psa schema> -f <sql-test-file>` using credentials and schema from `R005`; `go test ./...`; Go coverage gate for `GO_COVERAGE_PACKAGES` against `GO_COVERAGE_THRESHOLD`; bats test files under `tests/sh` (per `R040`); `swift test --package-path <swift-package-dir>`. Each stage only runs after the previous succeeds.
Tests:
- R030-T01: Verify test invocation includes `ON_ERROR_STOP=1`, `-P pager=off`, VALVE_SCHEMA, and SQL test file path.
- R030-T02: Force SQL stage failure and verify `go test` is not attempted.
- R030-T03: Force `go test` failure and verify script exits non-zero.
- R030-T04: Verify bats runs only after `go test ./...` succeeds.
- R030-T05: Verify output includes header lines before each test section.
- R030-T06: Verify successful run output includes `Test Runner:` labels for all five runners and the `+====...====+` border.

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

R038  Statement: Enforce a minimum Go line coverage threshold after unit tests pass.
Design: After `go test ./...`, measure coverage for `GO_COVERAGE_PACKAGES` (default core internal packages) and fail when total statement coverage is below `GO_COVERAGE_THRESHOLD` (default 70); write `coverage-summary.json` under `.security-reports/`.
Tests:
- R038-T01: Emit coverage profile below threshold and verify explicit non-zero failure output.

R040  Statement: Run bats files in parallel by file with buffered per-file output, configurable via `BATS_JOBS`, `PARALLEL_LANES`, `BATS_FILTER`, `BATS_FILTER_STATUS`, and `BATS_USE_NATIVE_JOBS`.
Design: Discover `tests/sh/*.bats` via `find -maxdepth 1 -name '*.bats' -print0`; fail fast if the directory is missing or contains no `*.bats` files. Default mode invokes each file in parallel via `xargs -0 -P "$BATS_JOBS_RESOLVED"`, calling `bats --tap --print-output-on-failure --timing <file>` so the same per-test result lines, failure diagnostics, and per-test timings remain visible. Each file's stdout/stderr is buffered to a tempfile under `$(mktemp -d)` and dumped atomically once the file finishes, prefixed with a `===== <basename> =====` banner; the tempdir is cleaned up via `trap EXIT`. When `BATS_USE_NATIVE_JOBS=true` and GNU `parallel` is on PATH, the runner instead invokes `bats -j "$BATS_JOBS_RESOLVED" --no-parallelize-within-files --print-output-on-failure --timing "$BATS_DIR"`, delegating to bats's native parallel driver so future within-file parallelism is possible; when parallel is unavailable the runner prints a fallback notice and reverts to the xargs path. Default concurrency is `sysctl -n hw.ncpu`; when `PARALLEL_LANES` is set and > 1 (indicating an outer parallel meta-runner such as `12_run_all_checks_parallel.sh`), divide the default by `PARALLEL_LANES` (floor 1) so total inner+outer concurrency stays near `hw.ncpu`. `BATS_JOBS` overrides the resolved default. `BATS_FILTER` is forwarded as `-f <value>` and `BATS_FILTER_STATUS` as `--filter-status <value>` to every bats invocation, supporting the dev loop. Any non-zero bats exit propagates: the script exits with the bats / xargs failure status.
Tests:
- R040-T01: Verify parallel bats invocation forwards `--tap`, `--print-output-on-failure`, and `--timing` per file.
- R040-T02: Empty `tests/sh` directory verifies the runner fails fast with a clear message.
- R040-T03: Missing `tests/sh` directory verifies the runner fails fast with a clear message.
- R040-T04: `BATS_JOBS=1` verifies the resolved-jobs value flows through to the progress banner.
- R040-T05: `PARALLEL_LANES=99` with `BATS_JOBS` unset clamps the default to 1 so an outer meta-runner does not oversubscribe.
- R040-T06: `BATS_FILTER=foo` verifies `-f foo` is forwarded to every bats call.
- R040-T07: `BATS_FILTER_STATUS=failed` verifies `--filter-status failed` is forwarded to every bats call.
- R040-T08: Verify the per-file output dump is prefixed by `===== <basename> =====`.
- R040-T09: A failing bats stub verifies the meta-runner exits non-zero.
- R040-T10: `BATS_USE_NATIVE_JOBS=true` with no `parallel` on PATH verifies the runner prints a fallback notice and still runs the xargs path successfully.
- R040-T11: `BATS_USE_NATIVE_JOBS=true` with a stub `parallel` on PATH verifies bats is invoked once with `-j` and the tests directory (not once per file).

## Changelog

- 2026-05-20: Added `R040` parallel-by-file bats runner with `BATS_JOBS`, `PARALLEL_LANES`, `BATS_FILTER`, `BATS_FILTER_STATUS`, and `BATS_USE_NATIVE_JOBS` knobs.
- 2026-05-16: Numbered test bullets with R###-T## scheme.
- 2026-05-10: Added Bats execution to step-05 and required `bats` CLI presence before running tests.
- 2026-05-09: Renamed unit-test runner requirements to `05_run_unit_tests.sh`.
