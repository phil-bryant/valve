# Run All Checks Parallel Requirements

## Scope

Applies to `13_run_all_checks_parallel.sh`.

R001  Statement: Run in strict shell mode and fail fast.
Design: Use `set -euo pipefail` at script entry.
Tests:
- R001-T01: Cause command failure and verify script exits non-zero.

R005  Statement: Execute from repository root regardless of caller directory.
Design: Resolve script directory from `${BASH_SOURCE[0]}` and `cd` into it before invoking child check scripts.
Tests:
- R005-T01: Run from a non-root working directory and verify child scripts still resolve under repo root.

R010  Statement: Run a fixed checklist of nine numbered check scripts.
Design: Launch, in order: `00_verify_requirements_traceability.sh`, `02_run_dependency_freshness_checks.sh`, `04_verify_deploy_database.sh`, `05_run_unit_tests.sh`, `06_run_mutation_tests.sh`, `07_run_security_checks.sh`, `08_run_av_checks.sh`, `11_run_llm_evals.sh`, and `12_run_fuzz.sh`.
Design: Fail fast with an actionable error if any expected child script file is missing before background launch.
Tests:
- R010-T01: Omit one expected child script and verify non-zero exit with explicit missing-script message before parallel jobs start.

R015  Statement: Launch all check scripts concurrently.
Design: Start each child script as a background job and wait for all jobs to complete.
Tests:
- R015-T01: Use slow stubs and verify total wall time is well below sequential execution time.

R020  Statement: Capture each child exit code independently.
Design: Disable errexit while waiting for background jobs; record and evaluate each child exit code separately without aborting early on the first failure.
Tests:
- R020-T01: Stub one child to exit non-zero and others to exit zero; verify all nine results are reported.

R025  Statement: Print per-script pass/fail summary lines as each check completes.
Design: Emit exactly nine `✅ PASS:` or `❌ FAIL:` lines, one per checklist script basename, in completion order as soon as each background job finishes (before the overall summary line).
Tests:
- R025-T01: When all children succeed, verify nine PASS lines.
- R025-T02: When one child fails, verify the failing script FAIL line and remaining PASS lines.
- R025-T03: Use stubs with different runtimes and verify a fast-finishing check appears before a slow-finishing check in output.

R030  Statement: Print overall pass/fail gate and exit code.
Design: Exit `0` with an overall `✅ PASS:` line when all nine checks succeed; exit non-zero with an overall `❌ FAIL:` line when any check fails.
Tests:
- R030-T01: All-pass run verifies overall PASS line and exit code zero.
- R030-T02: Mixed run verifies overall FAIL line and non-zero exit code.

R035  Statement: Persist per-check stdout/stderr log artifacts.
Design: Write each child output to `${PARALLEL_CHECKS_REPORT_DIR:-./.parallel-checks-reports}/<script-stem>.log` and include the log path in FAIL summary lines.
Tests:
- R035-T01: Verify stub output appears in the expected log file and FAIL lines reference the log path.

R040  Statement: Remain a standalone meta-runner entrypoint.
Design: The nine child check scripts must not invoke or reference `13_run_all_checks_parallel.sh`; each child remains an independent numbered entrypoint.
Tests:
- R040-T01: Grep the nine child scripts for `run_all_checks_parallel` and verify no matches.

R045  Statement: Report continuous aggregate progress while checks are running.
Design: Render a textual progress bar with completed/total counts and percentage that starts at `0/9 (0%)`, updates periodically while child checks are still running, and reaches `9/9 (100%)` before the final overall summary line.
Design: Keep per-check completion lines intact; progress rendering must not suppress any `✅ PASS:` or `❌ FAIL:` check result line.
Tests:
- R045-T01: Use staggered child runtimes and verify progress output includes intermediate states before all nine checks complete.
- R045-T02: Verify final output includes `9/9 (100%)` before the overall PASS/FAIL summary line.

R046  Statement: Export outer lane count for nested parallel runners.
Design: Before launching child checks, export `PARALLEL_LANES="${#CHECKS[@]}"` so nested parallel runners (notably `05_run_unit_tests.sh`) divide inner job counts and keep total concurrency near `hw.ncpu`.
Tests:
- R046-T01: Stub `05_run_unit_tests.sh` to print `PARALLEL_LANES` and verify the exported value equals nine.

R050  Statement: Prevent concurrent orchestrator runs from the same repository root.
Design: Acquire a single-run lock file at repo-root scope before launching child checks and fail immediately if another live `13_run_all_checks_parallel.sh` process already owns the lock.
Design: If the lock file is stale (owner PID no longer exists), reclaim it and continue.
Tests:
- R050-T01: Start one long-running orchestrator process and verify a second invocation exits non-zero with an already-active lock message.
- R050-T02: Seed a stale lock PID and verify the run succeeds and clears lock ownership on exit.

R055  Statement: Terminate launched child checks on interrupt or termination.
Design: Launch each child check in a new session via `setsid` when available, otherwise via a portable `python3` `os.setsid()` wrapper on macOS.
Design: On SIGINT/SIGTERM, recursively terminate the full descendant tree for each launched lane (not just direct children), then fall back to `pgrep -f` matches for `${SCRIPT_DIR}/<check-script>` to catch re-parented workers such as Go fuzz workers, gremlins, and clamscan.
Design: When `PARALLEL_CHECKS_TEST_INTERRUPT=1`, invoke the same interrupt stop path immediately after launch so unit tests can verify child cleanup without relying on signal delivery quirks.
Tests:
- R055-T01: Launch long-running child stubs with `PARALLEL_CHECKS_TEST_INTERRUPT=1` and verify child processes terminate and interrupt messaging is emitted.
- R055-T02: Stub one lane with a deeply nested background worker and verify the worker PID is terminated when the interrupt stop path runs.

## Changelog

- 2026-05-20: Reswizzled from teller `18_run_all_checks_parallel.sh` for valve check scripts and `PARALLEL_LANES` composition.
- 2026-05-20: Launch lanes in `setsid` sessions and recursively terminate full child process trees on interrupt.
