# Run Fuzz Tests Requirements

## Scope

Applies to `12_run_fuzz.sh`.

R001  Statement: Run fuzz tests in strict fail-fast mode from repository root.
Design: Use `set -euo pipefail`, `cd` to script directory, and execute `go test` with `-fuzz=.` and configurable `-fuzztime`.
Tests:
- R001-T01: Run from non-repo cwd and verify fuzz invocation still targets repository packages.

R005  Statement: Fail fast when go is unavailable.
Design: Print actionable error when `go` is missing from PATH.
Tests:
- R005-T01: Run with `go` missing from PATH and verify non-zero failure.

R010  Statement: Fuzz credential validation and service auth packages by default.
Design: Default `GO_FUZZ_PACKAGES` to `./internal/credentials ./internal/security` and `GO_FUZZ_TIME` to `30s`.
Tests:
- R010-T01: Run with go stub and verify fuzz packages and fuzztime appear in invocation log.

R015  Statement: Emit concise success output on completion.
Design: Print pass marker after all configured fuzz packages complete.
Tests:
- R015-T01: Run successful fuzz stub path and verify pass output line.

R020  Statement: Clarify that `new interesting` is coverage metadata, not failure criteria.
Design: Document that `new interesting: 0` can occur after corpus/cache warmup and does not fail the lane; only explicit fuzz target failures are gate-fail conditions.
Tests:
- R020-T01: Review README fuzz guidance and verify it states `new interesting` is non-failing metadata.
- R020-T02: Run fuzz targets with no failures and `new interesting: 0`; verify script exits successfully.

## Changelog

- 2026-05-19: Documented interpretation of `new interesting` and non-failing zero values.
- 2026-05-18: Added fuzz runner requirements for validation and service-auth packages.
