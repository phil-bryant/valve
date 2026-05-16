# Run Mutation Tests Requirements

## Scope

Applies to `06_run_mutation_tests.sh`.

R001  Statement: Run in strict fail-fast mode from repository root.
Design: Use `umask 007`, `set -euo pipefail`, and resolve `SCRIPT_DIR` for path-independent execution.
Tests:
- R001-T01: Run from a non-repo working directory and verify execution succeeds.

R005  Statement: Fail fast when required commands are unavailable.
Design: Verify `go` exists on PATH and resolve `gremlins` from PATH or Go bin (`$GOBIN` / `$(go env GOPATH)/bin`) before mutation testing begins. Use declaration-then-assignment for command-substitution lookups so resolver exit codes are preserved explicitly. Emit installer guidance referencing `./01_install_prerequisites.sh` on failure.
Tests:
- R005-T01: Run with `gremlins` missing from PATH and verify explicit non-zero failure output with installer guidance.
- R005-T02: Run with `go` missing from PATH and verify explicit non-zero failure output.
- R005-T03: Run with `gremlins` absent from PATH but present in `GOBIN` and verify resolution succeeds.
- R005-T04: Run with empty `GOBIN` and `gremlins` available in `GOPATH/bin` and verify fallback resolution succeeds.

R010  Statement: Require unit tests to pass before mutation testing begins.
Design: Run `go test ./...` as a preflight gate. If any test fails, abort with a clear message directing the operator to fix tests first via `./05_run_unit_tests.sh`.
Tests:
- R010-T01: Force `go test` failure and verify script exits non-zero with guidance to run step-05 first.
- R010-T02: Verify `gremlins` is not invoked when preflight `go test` fails.

R012  Statement: Warm Go build and test caches before invoking gremlins.
Design: Between preflight and the gremlins invocation, run `go build ./...` followed by `go test -count=1 -run '^$' ./...` to populate `GOCACHE` with build artifacts and test binaries for every package. Mutation workers share that cache across their temp working directories, so per-mutation rebuilds become single-file recompiles rather than full cold compiles. If warm-up fails (e.g. a compile error), abort with a clear failure message; gremlins must not run.
Tests:
- R012-T01: Verify `go build ./...` is invoked between preflight and gremlins.
- R012-T02: Verify `go test -count=1 -run '^$' ./...` is invoked between preflight and gremlins.
- R012-T03: Force the warm-up `go build` to fail and verify the script exits non-zero with a warm-up-specific message and that gremlins is not invoked.

R015  Statement: Run gremlins mutation testing across the Go module.
Design: Invoke `gremlins unleash --tags ''` from the module root (no path argument; `./...` is Go-tool syntax that gremlins does not expand) and direct machine-readable results to `${REPORT_DIR}/gremlins.json` via `-o`. Capture stdout and stderr to a log for diagnostics. If gremlins writes no JSON (e.g. "No results to report.") or exits with a non-recoverable error, fail loudly with the captured output rather than reporting `0.0%`.
Tests:
- R015-T01: Verify `gremlins unleash` is invoked from the module root after preflight passes and that no `./...` argument is passed.
- R015-T02: Verify gremlins JSON output is written to `${REPORT_DIR}/gremlins.json`.
- R015-T03: Simulate gremlins exiting without writing a JSON file and verify the script fails with diagnostics referencing the captured gremlins output.

R020  Statement: Gate on a configurable minimum mutation score threshold.
Design: Read `test_efficacy` from the gremlins JSON output as the mutation score. Compare against `MUTATION_SCORE_THRESHOLD` (default `80`). Fail when the score is below the threshold.
Tests:
- R020-T01: Simulate gremlins JSON with `test_efficacy` below threshold and verify explicit non-zero failure.
- R020-T02: Simulate gremlins JSON with `test_efficacy` at or above threshold and verify pass.
- R020-T03: Verify custom `MUTATION_SCORE_THRESHOLD` environment variable overrides the default.

R022  Statement: Gate on a configurable minimum mutator coverage threshold.
Design: Read `mutations_coverage` from the gremlins JSON output. Compare against `MUTATOR_COVERAGE_THRESHOLD` (default `70`). Fail when the coverage is below the threshold, even if `test_efficacy` is above its threshold. This prevents low-signal runs (many `TIMED OUT` or `NOT COVERED` mutants resolving to a tiny pool of meaningful verdicts) from masquerading as a passing gate. Emit a dedicated `❌ FAIL: Mutator coverage ...` line in addition to (or instead of) the score line.
Tests:
- R022-T01: Simulate gremlins JSON with `mutations_coverage` below threshold (and `test_efficacy` above) and verify explicit non-zero failure citing mutator coverage.
- R022-T02: Simulate gremlins JSON with `mutations_coverage` at or above threshold and verify pass.
- R022-T03: Verify custom `MUTATOR_COVERAGE_THRESHOLD` environment variable overrides the default.

R025  Statement: Support file-level exclusions for infrastructure-only code.
Design: Accept `MUTATION_EXCLUDE_FILES` as a comma-separated list of file-path regexes to skip. Pass each as `--exclude-files <regex>` to gremlins.
Tests:
- R025-T01: Set `MUTATION_EXCLUDE_FILES` and verify each regex appears as a `--exclude-files <regex>` flag in the gremlins invocation.
- R025-T02: Verify default (empty) exclusion list passes no `--exclude-files` flags.

R030  Statement: Persist machine-readable mutation testing report.
Design: Write a normalized summary to `${REPORT_DIR}/mutation-summary.json` derived from the gremlins JSON, containing at minimum: total mutants, killed mutants, lived mutants, not-covered mutants, not-viable mutants, timed-out mutants, score (test efficacy), mutator coverage, score threshold, coverage threshold, excluded files, per-gate pass/fail flags (`score_failed`, `coverage_failed`), and the overall `gate_failed` status.
Tests:
- R030-T01: Verify `${REPORT_DIR}/mutation-summary.json` is written after a successful run.
- R030-T02: Verify the JSON contains required fields: `total`, `killed`, `lived`, `not_covered`, `not_viable`, `timed_out`, `score`, `mutator_coverage`, `threshold`, `coverage_threshold`, `excluded_files`, `score_failed`, `coverage_failed`, `gate_failed`.

R035  Statement: Emit concise operator-readable pass or fail output.
Design: Print one `✅ PASS:` line with the mutation score when the gate passes. Print one `❌ FAIL:` line with the score and threshold when the gate fails.
Tests:
- R035-T01: Verify successful run emits a single `✅ PASS:` line including the score.
- R035-T02: Verify failed run emits a single `❌ FAIL:` line including score and threshold.

R040  Statement: Support a timeout to prevent runaway mutation runs.
Design: Accept `MUTATION_TIMEOUT_SECONDS` (default `600`). Kill gremlins if it exceeds the timeout and fail with a timeout-specific message.
Tests:
- R040-T01: Simulate gremlins exceeding timeout and verify explicit timeout failure message.
- R040-T02: Verify default timeout is 600 seconds when not overridden.

R045  Statement: Make gremlins' per-mutation `go test` budget configurable.
Design: Accept `MUTATION_TIMEOUT_COEFFICIENT` (default `20`) and pass it as `--timeout-coefficient <int>` to `gremlins unleash`. Gremlins multiplies the coverage-gathering elapsed time by this coefficient to set each mutation's `go test` timeout. Gremlins' built-in default (`3`) is too aggressive even with R012 warm-up on this repo's heavier packages (e.g. `internal/credentials`), producing spurious `TIMED OUT` verdicts that gremlins excludes from `test_efficacy`, in turn yielding a misleadingly high score on a handful of fast mutations.
Tests:
- R045-T01: Verify `gremlins unleash` is invoked with `--timeout-coefficient <int>`.
- R045-T02: Verify the default coefficient is `20` when `MUTATION_TIMEOUT_COEFFICIENT` is not set.
- R045-T03: Verify a custom `MUTATION_TIMEOUT_COEFFICIENT` value is forwarded.

## Changelog

- 2026-05-16: Clarified R005 command-resolution style to require declaration-then-assignment (ShellCheck SC2155-safe) and added R005-T04 for `GOPATH/bin` fallback.
- 2026-05-16: Initial requirements for mutation testing gate (step-06).
- 2026-05-16: Fix gremlins invocation (drop `./...`, invoke from module root). Switch to gremlins JSON via `-o` and gate on `test_efficacy`. Treat missing JSON as a hard failure instead of `0.0%`. Rename `MUTATION_EXCLUDE_PACKAGES` to `MUTATION_EXCLUDE_FILES` and map to `--exclude-files <regex>`. Expand the persisted summary fields (`lived`, `not_viable`, `mutator_coverage`, `excluded_files`).
- 2026-05-16: Add R022 mutator-coverage gate (`MUTATOR_COVERAGE_THRESHOLD`, default `70`) so that low-signal runs (e.g. mostly `TIMED OUT` or `NOT COVERED`) cannot pass on the strength of a tiny number of fast verdicts. Summary now records `coverage_threshold`, `score_failed`, and `coverage_failed`.
- 2026-05-16: Add R045 `MUTATION_TIMEOUT_COEFFICIENT` (default `20`) and forward it to gremlins as `--timeout-coefficient`. Replaces gremlins' built-in default of `3`, which on this repo gives ~7.5s per-mutation budgets and produces large `TIMED OUT` storms on cold Go build caches.
- 2026-05-16: Add R012 cache warm-up step (`go build ./...` + `go test -count=1 -run '^$' ./...`) between preflight and gremlins so that per-mutation rebuilds become single-file recompiles. Bumped R045 default coefficient from `10` to `20` for slower packages like `internal/credentials`.
