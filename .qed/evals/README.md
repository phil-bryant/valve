# Valve QED Evals

This directory contains recorded-only eval suites for Valve v0 bootstrapping.

## Files

- `api_recorded.yaml`: API lifecycle, security, and error-mapping contract checks.
- `scripts_recorded.yaml`: shell script operability and fail-fast contract checks.
- `repo_quality_recorded.yaml`: repo-level testing and testing-of-testing quality checks.
- `combined_recorded.yaml`: mixed API + scripts contract checks.
- `datasets/api_recorded.jsonl`: API recorded cases.
- `datasets/scripts_recorded.jsonl`: script recorded cases.
- `datasets/repo_quality_recorded.jsonl`: repo-quality recorded cases.
- `datasets/combined_recorded.jsonl`: mixed recorded cases.

## What Recorded-Only Means

Recorded-only evals do not execute live Valve services or Postgres.
They evaluate model outputs against curated contract cases sourced from:

- `internal/credentials/*_test.go`
- `internal/httpserver/server_test.go`
- `tests/sh/*.bats`
- `requirements/**/*.md`

## Baselines

Baselines are stored in:

- `.qed/baselines/api-recorded-baseline.json`
- `.qed/baselines/scripts-recorded-baseline.json`
- `.qed/baselines/repo-quality-recorded-baseline.json`
- `.qed/baselines/combined-recorded-baseline.json`

## Running

From repo root:

```bash
./11_run_llm_evals.sh run
```

Save baselines:

```bash
./11_run_llm_evals.sh save-baseline
```

Compare current results to baselines:

```bash
./11_run_llm_evals.sh compare
```

Run full cycle:

```bash
./11_run_llm_evals.sh all
```

Run only repo-level testing quality eval:

```bash
./11_run_llm_evals.sh repo-quality-only
```

If QED is not at `/Users/phil/local/src/qed`, set:

```bash
QED_REPO_PATH="/path/to/qed"
```

## Dataset Refresh Guidance

When behavior contracts change:

1. Update or add relevant recorded cases in `datasets/*.jsonl`.
2. Run `./11_run_llm_evals.sh run` and inspect report outputs under `.qed/evals/results/`.
3. If changes are intentional and quality is acceptable, run `./11_run_llm_evals.sh save-baseline`.
4. Keep case prompts specific to one behavior each (status code, security rule, or script failure path).
5. Keep references explicit and test-backed; avoid speculative expectations.
