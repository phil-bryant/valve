# Run Security Checks Requirements

## Scope

Applies to `07_run_security_checks.sh`.

R001  Statement: Run security checks in strict fail-fast mode from repository root.
Design: Use `bash` strict mode (`set -euo pipefail`), resolve script directory from `${BASH_SOURCE[0]}`, and `cd` into that directory before lane execution.
Tests:
- R001-T01: Run from a non-repo working directory and verify report output still resolves relative to repository root.

R005  Statement: Fail fast when required tools are missing with actionable install guidance.
Design: Validate required commands before each lane and print `./01_install_prerequisites.sh` guidance when a command is unavailable.
Tests:
- R005-T01: Run SAST lane with missing `semgrep` and verify non-zero failure plus installer guidance output.

R010  Statement: Keep step-07 security checks independent from dependency freshness checks.
Design: Do not invoke `./02_run_dependency_freshness_checks.sh` from step-07; run only SAST and optional DAST lanes within `07_run_security_checks.sh`.
Tests:
- R010-T01: Run step-07 when `02_run_dependency_freshness_checks.sh` is absent and verify SAST execution still succeeds.
- R010-T02: Verify no dependency freshness artifacts are emitted by step-07.

R015  Statement: Run SAST scanners and persist machine-readable artifacts.
Design: Require `semgrep`, `shellcheck`, `gitleaks`, `detect-secrets`, `gosec`, `govulncheck`, and `go`; run `go vet -json` as part of SAST and persist `govet.json`; run `detect-secrets` with explicit file exclusion support; write scanner outputs to `semgrep.json`, `shellcheck.json`, `gitleaks.json`, `detect-secrets.json`, `govet.json`, `gosec.json`, and `govulncheck.json` under the report directory.
Tests:
- R015-T01: Run SAST lane with stubs and verify each expected scanner artifact file is generated.
- R015-T02: Run SAST lane with `go vet` findings and verify `sast-summary.json` includes non-zero `govet_findings`.
- R015-T03: Verify `detect-secrets` invocation includes the default `.gomodcache`, requirements-doc, `.cursor/plans/*.plan.md`, and `.qed/evals/results/*.json` exclusion regex.

R020  Statement: Aggregate SAST findings into a centralized gating summary.
Design: Build `sast-summary.json` from scanner outputs, include high/critical totals, count `detect-secrets` findings after applying the exclusion regex policy, and fail when `SECURITY_FAIL_ON_HIGH_CRITICAL=true` and findings are non-zero.
Tests:
- R020-T01: Seed finding-producing scanner outputs and verify gate fails with explicit SAST gate message.
- R020-T02: Run with clean scanner outputs and verify `sast-summary.json` indicates gate pass.
- R020-T03: Verify findings under `.gomodcache` are excluded from detect-secrets gate totals while in-scope findings still fail the gate.

R025  Statement: Enable DAST by default while allowing explicit opt-out and deterministic local target boot.
Design: Default `RUN_DAST` to `true` and execute the DAST lane unless `RUN_DAST=false`; default `DAST_AUTO_BOOT=true` to launch `go run ./cmd/valve`; resolve `DAST_BASE_URL` from `1psa` fields when unset; fail fast when none of those fields are available and `DAST_BASE_URL` is unset.
Tests:
- R025-T01: Run without setting `RUN_DAST` and verify DAST executes.
- R025-T02: Run with `RUN_DAST=false` and verify the lane is skipped with explicit skip output.
- R025-T03: Run with auto-boot enabled and no DAST endpoint fields in `1psa` and verify fail-fast output instructs operators to set `DAST_BASE_URL`.
- R025-T04: Run with auto-boot enabled and `dast_port` populated in `1psa` and verify the `VALVE_ADDR` bind address uses that port.
- R025-T05: Run with auto-boot enabled and explicit `DAST_BASE_URL` and verify the override controls `VALVE_ADDR`.
- R025-T06: Run with auto-boot enabled and explicit `VALVE_DATABASE_URL` set while `1psa` is unavailable and verify fail-fast output.

R030  Statement: Probe service health before launching DAST scanning and prevent auto-boot from leaking the bind address.
Design: Require a successful `curl` probe to `${DAST_BASE_URL}/healthz`; when `DAST_AUTO_BOOT=true`, wait up to `DAST_AUTO_BOOT_TIMEOUT_SECONDS` for service readiness; launch the auto-boot child in its own session via `setsid` and tear down the entire process group on cleanup.
Tests:
- R030-T01: Run DAST lane with failing `curl` stub and verify explicit non-zero failure output that includes the last health probe output.
- R030-T02: Run DAST lane with passing `curl` and verify `dast-health.log` is created and no transient curl errors are printed to the terminal.
- R030-T03: Run DAST lane with a crashing auto-boot stub and verify fail-fast output indicates pre-health process exit.
- R030-T04: Run DAST lane with a NUL-padded `dast-app.log` written before failure and verify the dump completes without aborting.
- R030-T05: Run DAST lane with the resolved bind address already held by another listener and verify fail-fast output names the offending PID/process.
- R030-T06: Run DAST lane with a long-running auto-boot stub that spawns a grandchild listener and verify cleanup terminates the grandchild.

R035  Statement: Execute OWASP ZAP baseline scans with deterministic runner fallback.
Design: Resolve host-native runner from PATH `zap-baseline.py` or ZAP CLI under PATH/`ZAP_APP_PATH`; execute against `DAST_ZAP_TARGET_URL` (defaulting to `${DAST_BASE_URL}/healthz`); scan the live log for `Failed to attack the URL` and fail fast when detected.
Tests:
- R035-T01: Run DAST lane with local `zap-baseline.py` stub and verify `dast-zap-report.json` is created.
- R035-T02: Run DAST lane without `zap-baseline.py` and without ZAP CLI and verify explicit missing-command failure output.
- R035-T03: Run DAST lane with ZAP CLI available only under `ZAP_APP_PATH` and verify scan invocation succeeds.
- R035-T04: Run DAST lane with a ZAP runner that prints `Failed to attack the URL` and verify the script fails fast with remediation guidance.

R040  Statement: Run Schemathesis contract testing and aggregate DAST findings into a centralized gating summary.
Design: When `RUN_SCHEMATHESIS=true`, execute `schemathesis run` against `SCHEMATHESIS_SCHEMA_PATH` and `${DAST_BASE_URL}`, emit `schemathesis.log` and `schemathesis-junit.xml`, forward `X-Valve-Service-Key` header, and include Schemathesis result state in `dast-summary.json`.
Tests:
- R040-T01: Run DAST lane with clean scanner output and verify `dast-summary.json` indicates gate pass.
- R040-T02: Run DAST lane with medium/high scanner findings and verify explicit DAST gate failure output.
- R040-T03: Run DAST lane with only suppressed medium alert refs and verify gate pass.
- R040-T04: Run DAST lane with off-target alert instances and verify they are excluded from gate evaluation.
- R040-T05: Run DAST lane with Schemathesis contract failures and verify gate failure output.
- R040-T06: Run DAST lane with auto-boot enabled and verify the auto-booted valve service receives the same `VALVE_SERVICE_AUTH_KEY` forwarded to Schemathesis.
- R040-T07: Run DAST lane with operator-provided `VALVE_SERVICE_AUTH_KEY` and verify the script reuses that value verbatim.

R045  Statement: Emit explicit completion status and report location.
Design: Print lane completion markers and final success output with resolved report directory path.
Tests:
- R045-T01: Run with enabled lanes passing and verify final completion line includes `Reports:`.

R050  Statement: Emit live DAST execution context and progress visibility in console output.
Design: Before running OWASP ZAP, print the resolved runner identity, DAST timeout value, report artifact path, and dedicated live log artifact path; stream ZAP command output to console while simultaneously persisting it to `dast-zap.log`.
Tests:
- R050-T01: Run DAST lane with stubs and verify console output includes runner resolution, timeout, report artifact, and live log artifact lines.
- R050-T02: Run DAST lane with ZAP CLI fallback and verify invocation includes `-quickprogress` and streamed output is captured in `dast-zap.log`.

R055  Statement: Enforce a strict Schemathesis schema contract with deterministic preflight validation.
Design: When `RUN_SCHEMATHESIS=true`, default `SCHEMATHESIS_SCHEMA_PATH` to `${SCRIPT_DIR}/openapi/valve.v1.yaml`; verify the schema path is readable before DAST auto-boot, health probing, and scanner execution; fail with explicit remediation guidance when the schema is missing or unreadable.
Tests:
- R055-T01: Run with default `RUN_SCHEMATHESIS=true` and no `SCHEMATHESIS_SCHEMA_PATH` override and verify Schemathesis runs using the canonical `openapi/valve.v1.yaml`.
- R055-T02: Run with `RUN_SCHEMATHESIS=true` and an unreadable/missing schema path and verify fail-fast output contains schema-path diagnostics.
- R055-T03: Run with `SCHEMATHESIS_SCHEMA_PATH` override to an alternate readable file and verify Schemathesis execution uses the override path.

R060  Statement: Emit a clear DAST startup marker immediately after SAST completion.
Design: When `RUN_DAST=true`, print an explicit DAST lane-start line before DAST preflight checks so operators can distinguish active progression from a perceived hang after the SAST completion marker.
Tests:
- R060-T01: Run with both lanes enabled and verify output contains SAST completion followed by the explicit DAST startup marker.

## Changelog

- 2026-05-16: Numbered test bullets with R###-T## scheme.
- 2026-05-15: Made DAST end-to-end actually pass on a healthy system.
- 2026-05-15: Hardened DAST auto-boot lifecycle.
- 2026-05-15: Added explicit DAST lane-start output requirement.
- 2026-05-10: Added strict Schemathesis schema preflight requirement.
- 2026-05-14: Added `go vet` to step-06 SAST tooling.
- 2026-05-09: Added Valve step-06 security checks requirements with SAST/DAST lane policy.
