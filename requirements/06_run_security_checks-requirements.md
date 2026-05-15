# Run Security Checks Requirements

## Scope

Applies to `06_run_security_checks.sh`.

R001  Statement: Run security checks in strict fail-fast mode from repository root.
Design: Use `bash` strict mode (`set -euo pipefail`), resolve script directory from `${BASH_SOURCE[0]}`, and `cd` into that directory before lane execution.
Tests:
- Run from a non-repo working directory and verify report output still resolves relative to repository root.

R005  Statement: Fail fast when required tools are missing with actionable install guidance.
Design: Validate required commands before each lane and print `./01_install_prerequisites.sh` guidance when a command is unavailable.
Tests:
- Run SAST lane with missing `semgrep` and verify non-zero failure plus installer guidance output.

R010  Statement: Keep step-06 security checks independent from dependency freshness checks.
Design: Do not invoke `./02_run_dependency_freshness_checks.sh` from step-06; run only SAST and optional DAST lanes within `06_run_security_checks.sh`.
Tests:
- Run step-06 when `02_run_dependency_freshness_checks.sh` is absent and verify SAST execution still succeeds.
- Verify no dependency freshness artifacts are emitted by step-06.

R015  Statement: Run SAST scanners (including shell script linting, Go vet analysis, and credential-pattern scanners) and persist machine-readable artifacts.
Design: Require `semgrep`, `shellcheck`, `gitleaks`, `detect-secrets`, `gosec`, `govulncheck`, and `go`; run `go vet -json` as part of SAST and persist `govet.json`; run `detect-secrets` with explicit file exclusion support (default excludes `.gomodcache`, requirements markdown, and generated `.cursor/plans/*.plan.md` artifacts via `DETECT_SECRETS_EXCLUDE_FILES_REGEX` to prevent deterministic non-source false positives); write scanner outputs to `semgrep.json`, `shellcheck.json`, `gitleaks.json`, `detect-secrets.json`, `govet.json`, `gosec.json`, and `govulncheck.json` under the report directory.
Tests:
- Run SAST lane with stubs and verify each expected scanner artifact file is generated.
- Run SAST lane with `go vet` findings and verify `sast-summary.json` includes non-zero `govet_findings`.
- Verify `detect-secrets` invocation includes the default `.gomodcache`, requirements-doc, and `.cursor/plans/*.plan.md` exclusion regex.

R020  Statement: Aggregate SAST findings into a centralized gating summary.
Design: Build `sast-summary.json` from scanner outputs, include high/critical totals, count `detect-secrets` findings after applying the same exclusion regex policy used during scan invocation, and fail when `SECURITY_FAIL_ON_HIGH_CRITICAL=true` and findings are non-zero.
Tests:
- Seed finding-producing scanner outputs and verify gate fails with explicit SAST gate message.
- Run with clean scanner outputs and verify `sast-summary.json` indicates gate pass.
- Verify findings under `.gomodcache` are excluded from detect-secrets gate totals while in-scope findings still fail the gate.

R025  Statement: Enable DAST by default while allowing explicit opt-out and deterministic local target boot.
Design: Default `RUN_DAST` to `true` and execute the DAST lane unless `RUN_DAST=false`; default `DAST_AUTO_BOOT=true` to launch `go run ./cmd/valve` with `VALVE_ADDR` derived from `DAST_BASE_URL`, and when `DAST_BASE_URL` is unset resolve the DAST HTTP target from `1psa` fields on `DAST_BASE_URL_1PSA_ITEM` (default `localhost_postgres_valve`) by preferring `dast_base_url`/`service_base_url`/`base_url`, then `dast_port`/`service_port`/`app_port`/`http_port` (paired with `service_host` or `DAST_DEFAULT_HOST`), and finally fallback to `http://${DAST_DEFAULT_HOST}:${DAST_DEFAULT_PORT}`; retrieve the proper Valve Postgres login information via `1psa` and construct runtime `VALVE_DATABASE_URL` directly from `localhost_postgres_valve` fields `username`, `password`, `host`, and `port` (plus default db name `valve`); and inject `VALVE_UPLOAD_ENDPOINT` from `DAST_UPLOAD_ENDPOINT` when not already set.
Tests:
- Run without setting `RUN_DAST` and verify DAST executes.
- Run with `RUN_DAST=false` and verify the lane is skipped with explicit skip output.
- Run with auto-boot enabled and verify `go run ./cmd/valve` is invoked with DB URL from `1psa` and DAST bind address fallback `http://${DAST_DEFAULT_HOST}:${DAST_DEFAULT_PORT}` when no DAST endpoint field is present.
- Run with auto-boot enabled and `dast_port` populated in `1psa` and verify the `VALVE_ADDR` bind address uses that port.
- Run with auto-boot enabled and explicit `DAST_BASE_URL` and verify the override controls `VALVE_ADDR`.
- Run with auto-boot enabled and explicit `VALVE_DATABASE_URL` set while `1psa` is unavailable and verify fail-fast `Missing required command: 1psa` output.

R030  Statement: Probe service health before launching DAST scanning.
Design: Require a successful `curl` probe to `${DAST_BASE_URL}/healthz`; when `DAST_AUTO_BOOT=true`, wait up to `DAST_AUTO_BOOT_TIMEOUT_SECONDS` for service readiness, write `dast-health.log`, fail fast if the auto-booted PID exits before readiness, and print `dast-app.log` diagnostics for boot failures.
Tests:
- Run DAST lane with failing `curl` stub and verify explicit non-zero failure output.
- Run DAST lane with passing `curl` and verify `dast-health.log` is created.
- Run DAST lane with a crashing auto-boot stub and verify fail-fast output indicates pre-health process exit.

R035  Statement: Execute OWASP ZAP baseline scans with deterministic runner fallback.
Design: Resolve host-native runner from PATH `zap-baseline.py` or ZAP CLI (`ZAP.sh`/`zap.sh`) under PATH/`ZAP_APP_PATH` (`/Applications/ZAP.app` by default), execute against `DAST_ZAP_TARGET_URL` (defaulting to `DAST_BASE_URL`) with bounded runtime via `DAST_ZAP_TIMEOUT_SECONDS`, and fail clearly when runner discovery, scanner execution, timeout, or report generation fails.
Tests:
- Run DAST lane with local `zap-baseline.py` stub and verify `dast-zap-report.json` is created.
- Run DAST lane without `zap-baseline.py` and without ZAP CLI and verify explicit missing-command failure output.
- Run DAST lane with ZAP CLI available only under `ZAP_APP_PATH` and verify scan invocation succeeds.

R040  Statement: Run Schemathesis contract testing and aggregate DAST findings into a centralized gating summary.
Design: When `RUN_SCHEMATHESIS=true`, execute `schemathesis run` against `SCHEMATHESIS_SCHEMA_PATH` and `${DAST_BASE_URL}`, emit `schemathesis.log` and `schemathesis-junit.xml`, and include Schemathesis result state in `dast-summary.json`; aggregate OWASP ZAP alerts scoped to `DAST_ZAP_TARGET_URL` host/port instances, allow configurable alert-ref suppression via `DAST_IGNORED_ALERT_REFS` (default includes known API-noise `10055-13` and ZAP daemon UI noise `10062`), and fail when `SECURITY_FAIL_ON_HIGH_CRITICAL=true` and unsuppressed in-scope medium/high alerts or Schemathesis contract failures are present.
Tests:
- Run DAST lane with clean scanner output and verify `dast-summary.json` indicates gate pass.
- Run DAST lane with medium/high scanner findings and verify explicit DAST gate failure output.
- Run DAST lane with only suppressed medium alert refs and verify gate pass.
- Run DAST lane with off-target alert instances and verify they are excluded from gate evaluation.
- Run DAST lane with Schemathesis contract failures and verify gate failure output.

R045  Statement: Emit explicit completion status and report location.
Design: Print lane completion markers and final success output with resolved report directory path.
Tests:
- Run with enabled lanes passing and verify final completion line includes `Reports:`.

R050  Statement: Emit live DAST execution context and progress visibility in console output.
Design: Before running OWASP ZAP, print the resolved runner identity, DAST timeout value, report artifact path, and dedicated live log artifact path; stream ZAP command output to console while simultaneously persisting it to `dast-zap.log` so operators can observe scan progress during execution.
Tests:
- Run DAST lane with stubs and verify console output includes runner resolution, timeout, report artifact, and live log artifact lines.
- Run DAST lane with ZAP CLI fallback and verify invocation includes `-quickprogress` and streamed output is captured in `dast-zap.log`.

R055  Statement: Enforce a strict Schemathesis schema contract with deterministic preflight validation.
Design: When `RUN_SCHEMATHESIS=true`, default `SCHEMATHESIS_SCHEMA_PATH` to `${SCRIPT_DIR}/openapi/valve.v1.yaml`; verify the schema path is readable before DAST auto-boot, health probing, and scanner execution; fail with explicit remediation guidance when the schema is missing or unreadable.
Tests:
- Run with default `RUN_SCHEMATHESIS=true` and no `SCHEMATHESIS_SCHEMA_PATH` override, and verify Schemathesis runs successfully using the canonical `openapi/valve.v1.yaml`.
- Run with `RUN_SCHEMATHESIS=true` and an unreadable/missing schema path, and verify fail-fast output contains deterministic schema-path diagnostics and remediation guidance.
- Run with `SCHEMATHESIS_SCHEMA_PATH` override to an alternate readable file and verify Schemathesis execution uses the override path.

## Changelog

- 2026-05-15: Updated DAST auto-boot to derive `DAST_BASE_URL` from dedicated service endpoint fields in `1psa` and avoid using database host/port as HTTP target.
- 2026-05-10: Added strict Schemathesis schema preflight requirement with canonical `openapi/valve.v1.yaml` contract.
- 2026-05-14: Added `go vet` to step-06 SAST tooling, artifacts, and gating summary inputs.
- 2026-05-10: Added default DAST suppression for ZAP daemon UI alert `10062` to avoid deterministic host-runner false positives.
- 2026-05-10: Added live ZAP progress streaming and `dast-zap.log` artifact requirements for DAST observability.
- 2026-05-10: Removed `VALVE_DATABASE_URL_1PSA_REF` requirement for DAST auto-boot; DB URL is now composed directly from `localhost_postgres_valve` fields.
- 2026-05-10: Added default detect-secrets exclusions for requirements markdown to avoid deterministic documentation-only false positives.
- 2026-05-10: Removed host/port env references for DAST auto-boot; host/port now come directly from `localhost_postgres_valve` item fields.
- 2026-05-10: Updated DAST auto-boot to require dedicated `1psa` host/port references and apply them to the runtime Postgres DSN.
- 2026-05-10: Updated DAST auto-boot to require `1psa` + `VALVE_DATABASE_URL_1PSA_REF` and resolve DB URL exclusively through `1psa read`.
- 2026-05-10: Added DAST auto-boot lifecycle for `go run ./cmd/valve` and Schemathesis contract-testing integration.
- 2026-05-10: Added `detect-secrets` to step-06 SAST tooling, artifacts, and gate summary.
- 2026-05-10: Added explicit console observability requirement for live DAST execution context output.
- 2026-05-10: Added configurable DAST alert-ref suppression (`DAST_IGNORED_ALERT_REFS`) for known API-focused false positives.
- 2026-05-10: Added `ZAP_APP_PATH`-based discovery fallback for host-native `zap-baseline.py`.
- 2026-05-10: Split DAST requirements into granular execution, health-probe, scanner, and gate controls.
- 2026-05-09: Added `shellcheck` to step-06 SAST toolchain, artifacts, and gating summary inputs.
- 2026-05-09: Restored DAST lane in step-06 for server health probing and artifact generation.
- 2026-05-09: Updated step-06 requirements so DAST defaults to enabled with explicit `RUN_DAST=false` opt-out.
- 2026-05-09: Added Valve step-06 security checks requirements with SAST/DAST lane policy and centralized gating.
- 2026-05-09: Expanded DAST lane to run health probe plus OWASP ZAP baseline scan with scanner-backed gating artifacts.
