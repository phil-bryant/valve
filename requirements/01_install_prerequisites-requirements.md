# Install Prerequisites Requirements

## Scope

Applies to `01_install_prerequisites.sh` and local macOS setup required before running this repository's Go/backend build and test targets.

R001  Statement: Run with `bash` in strict fail-fast mode.
Design: Use `set -euo pipefail` and exit non-zero on unrecoverable failures.
Tests:
- R001-T01: Force a failing command and verify installer exits non-zero.

R005  Statement: Verify Homebrew exists before Homebrew package actions.
Design: Check `brew` on `PATH`; print install guidance when missing.
Tests:
- R005-T01: Run with `brew` unavailable and verify clear failure guidance.

R010  Statement: Ensure Go toolchain is available for Valve development.
Design: Require `go` on `PATH`; install Homebrew formula `go` when missing, then verify command resolution.
Tests:
- R010-T01: Run without `go` and verify installer attempts `brew install go`.
- R010-T02: Rerun with `go` already installed and verify no reinstall.

R015  Statement: Enforce a minimum Go version required by this repository.
Design: Parse `go version` output and fail with actionable guidance when the detected version is below configured minimum.
Tests:
- R015-T01: Simulate lower-than-minimum version output and verify explicit failure.
- R015-T02: Simulate acceptable version output and verify pass.

R020  Statement: Ensure Postgres CLI tooling is available for local readiness and diagnostics.
Design: Require `psql`; when missing, install Homebrew formula `libpq` and accept either PATH-discoverable `psql` or `$(brew --prefix libpq)/bin/psql`.
Tests:
- R020-T01: Simulate missing `psql` and verify installer attempts `brew install libpq`.
- R020-T02: Simulate fallback `$(brew --prefix libpq)/bin/psql` and verify success.

R025  Statement: Ensure primary Go lint tooling is available.
Design: Require `golangci-lint`; install Homebrew formula `golangci-lint` when missing and fail when still unavailable.
Tests:
- R025-T01: Run without `golangci-lint` and verify installer attempts `brew install golangci-lint`.

R030  Statement: Ensure SAST/security tooling required by this repository is available.
Design: Verify/install `shellcheck`, `semgrep`, `gitleaks`, `detect-secrets`, `gosec`, `govulncheck`, and `clamscan` (via Homebrew `clamav`) before completion so SAST and AV lanes are runnable.
Tests:
- R030-T01: Run installer without those tools and verify each required formula install is attempted.
- R030-T02: Rerun installer and verify already-installed tools are not reinstalled.

R035  Statement: Print explicit status for each prerequisite phase.
Design: Emit clear checking/install/success/failure output for Homebrew, Go, Go version, Postgres CLI, lint toolchain, SAST/AV tools, DAST runtime tooling, mutation testing tooling, and `1psa`.
Tests:
- R035-T01: Run installer and verify phase status output appears for all major checks.

R040  Statement: Keep installer idempotent across reruns.
Design: Skip install/setup steps when dependencies are already satisfied.
Tests:
- R040-T01: Run installer twice and verify the second run performs no unnecessary installs.

R045  Statement: Print final readiness guidance for local development.
Design: End with success output that references repository commands (`go test ./...`, `go test -race ./...`, `golangci-lint run`).
Tests:
- R045-T01: On successful run, verify final guidance includes those commands.

R050  Statement: Ensure `1psa` is available for secure Postgres connection secret retrieval.
Design: Require `1psa` on `PATH`; fail with actionable setup guidance when missing.
Tests:
- R050-T01: Run without `1psa` and verify installer exits non-zero with explicit setup guidance.
- R050-T02: Run with `1psa` available and verify installer continues.

R055  Statement: Ensure DAST runtime tooling is available before completing prerequisites.
Design: Verify/install `schemathesis`, then accept `zap-baseline.py` from PATH, or discover ZAP CLI (`ZAP.sh`/`zap.sh`) under PATH or `ZAP_APP_PATH` (`/Applications/ZAP.app` by default); when missing, install Homebrew cask `zap` and re-verify command discovery.
Tests:
- R055-T01: Run installer without `schemathesis` and verify `brew install schemathesis` is attempted.
- R055-T02: Run installer without `zap-baseline.py`/`ZAP.sh` and verify `brew install --cask zap` is attempted.
- R055-T03: Run installer with `zap-baseline.py` or `ZAP.sh` available and verify cask install is skipped.

R060  Statement: Ensure mutation testing tooling is available for test quality gating.
Design: Resolve `gremlins` from `PATH` or Go bin (`$GOBIN` / `$(go env GOPATH)/bin`); when missing, install via `go install github.com/go-gremlins/gremlins/cmd/gremlins@latest` and verify command resolution.
Tests:
- R060-T01: Run installer without `gremlins` and verify `go install` is attempted for gremlins.
- R060-T02: Run with `gremlins` already available and verify no reinstall.

## Changelog

- 2026-05-16: Added R060 for mutation testing tooling (gremlins) prerequisite.
- 2026-05-16: Numbered test bullets with R###-T## scheme.
- 2026-05-10: Added explicit `1psa` prerequisite required for secure DB secret resolution in step-06 auto-boot.
- 2026-05-10: Added `detect-secrets` and `schemathesis` to prerequisite tooling coverage.
- 2026-05-10: Added explicit DAST runtime prerequisite coverage (`zap-baseline.py`).
- 2026-05-10: Switched DAST prerequisite installation to Homebrew cask `zap` with `ZAP_APP_PATH` discovery.
- 2026-05-09: Added ClamAV (`clamav`/`clamscan`) to prerequisite security tooling requirements.
- 2026-05-08: Reswizzled installer requirements for Valve Go backend prerequisites and strict dev tooling.
