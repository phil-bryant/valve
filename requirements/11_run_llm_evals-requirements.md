# Run LLM Evals Requirements

## Scope

Applies to `11_run_llm_evals.sh`.

R001  Statement: Run QED LLM eval workflows in strict fail-fast mode from repository root.
Design: Use `set -euo pipefail`, resolve `SCRIPT_DIR` from `${BASH_SOURCE[0]}`, and `cd` into that directory before invoking QED.
Tests:
- R001-T01: Run from a non-repo working directory with stubs and verify the script exits successfully.

R005  Statement: Fail fast when required host tools are unavailable.
Design: Require `go` and `1psa` on PATH before reading secrets or invoking QED.
Tests:
- R005-T01: Run with `go` missing from PATH and verify non-zero failure output.
- R005-T02: Run with `1psa` missing from PATH and verify non-zero failure output.

R010  Statement: Fail fast when the local QED repository entrypoint is unavailable.
Design: Default `QED_REPO_PATH` to `/Users/phil/local/src/qed`, resolve `${QED_REPO_PATH}/cmd/qed`, and exit with remediation guidance when that directory is missing.
Tests:
- R010-T01: Run with `QED_REPO_PATH` pointing at a path without `cmd/qed` and verify non-zero failure output.

R015  Statement: Validate the mode argument and print usage for unsupported values.
Design: Accept `run`, `save-baseline`, `compare`, `all`, `repo-quality-only`, and `live-only`; default to `run`; print usage and exit non-zero for any other value.
Tests:
- R015-T01: Run with an invalid mode argument and verify usage output plus non-zero exit.

R020  Statement: Read OpenAI and Anthropic API keys from 1psa before invoking QED.
Design: Call `1psa -p openai_api_key` and `1psa -p anthropic_api_key`; fail with explicit item names when either secret is empty.
Tests:
- R020-T01: Run with an empty OpenAI key from 1psa and verify non-zero failure output.
- R020-T02: Run with an empty Anthropic key from 1psa and verify non-zero failure output.

R025  Statement: Default to recorded eval execution across all bundled suites.
Design: When mode is `run` (default), invoke QED `eval run --ci` for api, scripts, repo-quality, and combined recorded specs under `.qed/evals`.
Tests:
- R025-T01: Run default mode with stubs and verify all four recorded suite spec paths appear in QED invocation logs.

R030  Statement: Support baseline, compare, and selective suite modes.
Design: Implement `save-baseline`, `compare`, `all`, and `repo-quality-only` modes that call the corresponding QED eval subcommands against the recorded suite artifacts.
Tests:
- R030-T01: Run `repo-quality-only` with stubs and verify only the repo-quality recorded spec is invoked.
- R030-T02: Run `compare` with stubs and verify QED `eval compare --ci` is invoked.

R035  Statement: Support optional live eval mode with graceful skip and health preflight.
Design: In `live-only` mode, exit success with an informational skip message when neither `VALVE_DATABASE_URL` nor `VALVE_TEST_DATABASE_URL` is set; default `VALVE_BASE_URL` to `http://127.0.0.1:8090`; probe `${VALVE_BASE_URL}/healthz` and fail when the service is unreachable.
Tests:
- R035-T01: Run `live-only` without database URL environment variables and verify success with skip output.
- R035-T02: Run `live-only` with database URL set but failing health probe and verify non-zero failure output referencing the expected service URL.

## Changelog

- 2026-05-19: Initial requirements for QED LLM eval runner traceability.
