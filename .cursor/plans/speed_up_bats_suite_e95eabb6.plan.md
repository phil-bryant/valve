---
name: speed up bats suite
overview: Speed up the 19-file bats suite from ~2:29 to roughly 25-45s wall time without losing any output that is currently visible, by adding parallelism, hoisting expensive fixture setup, and trimming a handful of artificial wait loops in tests.
todos:
  - id: tier1-xargs-parallel
    content: "Tier 1: replace serial `bats tests/sh` in 05_run_unit_tests.sh with xargs -P N per-file buffered runner (no new deps)."
    status: completed
  - id: tier5-shrink-waits
    content: "Tier 5: add DAST_HEALTH_PROBE_INTERVAL_SECS / _MAX_ATTEMPTS knobs to 07_run_security_checks.sh; have slow tests set them; replace any sleep-based assertions with argv assertions."
    status: completed
  - id: tier4-setup-file
    content: "Tier 4: extend tests/sh/helpers/common.bash with setup_file_shared_fixture; convert .bats files to call it from setup_file() and keep per-test setup minimal."
    status: completed
  - id: tier3-split-07
    content: "Tier 3: split tests/sh/07_run_security_checks.bats into sast/dast/schemathesis/misc files and extract stubs to tests/sh/helpers/security_stubs.bash."
    status: completed
  - id: tier2-bats-jobs
    content: "Tier 2 (optional): add `parallel` to 01_install_prerequisites.sh and switch invocation to `bats -j N --no-parallelize-within-files --print-output-on-failure --timing`."
    status: completed
  - id: devloop-niceties
    content: Add BATS_JOBS and BATS_FILTER env knobs and a --filter-status failed dev wrapper.
    status: completed
  - id: meta-runner-compat
    content: Make BATS_JOBS PARALLEL_LANES-aware in 05_run_unit_tests.sh so it composes safely if/when ../teller/18_run_all_checks_parallel.sh is ported to valve.
    status: completed
isProject: false
---

# Speed up the bats suite without losing output

## Baseline measurement

- `bats tests/sh` today: 221 tests, 19 files, **149s wall / 37s CPU (~25% utilization)** — heavily serial.
- Single-file outliers (`bats --timing`):
  - `tests/sh/07_run_security_checks.bats` — **~60s** (47 tests; several DAST/probe tests 2-5.6s)
  - `tests/sh/06_run_mutation_tests.bats` — ~23s
  - `tests/sh/01_install_prerequisites.bats` — ~8s
  - All others ≤ ~5s each.
- Invocation today: [`05_run_unit_tests.sh`](05_run_unit_tests.sh) line 185 calls `bats "${SCRIPT_DIR}/tests/sh"` with default pretty formatter, single job.

## Output-preservation contract

Every option below preserves the lines currently emitted by bats:

- "ok N test name" / "not ok N test name" per test
- Failure diagnostics (file+line, captured `$output` on failure)
- The header banner printed by `05_run_unit_tests.sh`

Parallel modes additionally either keep per-file output atomic (no interleaving) or render TAP, which is line-atomic by design. We add `--print-output-on-failure` so failures show `$output` even when buffered.

## Tier 1 — invocation-only changes (no new deps, no test edits)

Largest win for the least risk. Run files concurrently with `xargs -P` (BSD xargs ships on macOS), buffer each file's TAP output, and dump it as the file finishes.

Replace the single `bats` call in [05_run_unit_tests.sh](05_run_unit_tests.sh):

```bash
BATS_DIR="${SCRIPT_DIR}/tests/sh"
BATS_TMP="$(mktemp -d)"
trap 'rm -rf "$BATS_TMP"' EXIT
JOBS="${BATS_JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 8)}"
echo "▶ Running Bats shell tests (parallel by file, jobs=${JOBS})..."
status=0
find "$BATS_DIR" -maxdepth 1 -name '*.bats' -print0 \
  | xargs -0 -n1 -P "$JOBS" -I {} bash -c '
      f="$1"; out="'"$BATS_TMP"'/$(basename "$f").tap"
      bats --tap --print-output-on-failure --timing "$f" >"$out" 2>&1
      rc=$?
      printf "\n===== %s =====\n" "$(basename "$f")"
      cat "$out"
      exit $rc
    ' _ {} || status=$?
[ "$status" -eq 0 ] || exit "$status"
```

- Output: each file prints atomically with a header, including `--print-output-on-failure` and `--timing`. No interleaved lines.
- Empirically measured: **~80s wall** at `-P 19` on this machine vs 149s today (bounded by `07_run_security_checks.bats` at ~60s). With Tier 3 (split 07), drops to ~25-30s.
- Trade-off: order of files in output is completion order, not alphabetical. If alphabetical order matters more than streaming, append `| sort` and print at the end, but that loses live progress.

Add a `BATS_JOBS=1` override to fall back to serial for debugging.

## Tier 2 — true `bats -j N` (one-time `brew install parallel`)

Bats 1.13 supports `-j N` when GNU parallel is on PATH. Then:

```bash
bats -j "$JOBS" \
  --no-parallelize-within-files \
  --print-output-on-failure --timing \
  "${SCRIPT_DIR}/tests/sh"
```

- `--no-parallelize-within-files` keeps each file serial internally (safe default; preserves any per-file shared state via `setup_file`).
- Drop it to also parallelize the 47-test `07_*.bats` internally — fastest path, ~15-25s total. Needs Tier 4 fixture isolation review for `07`.
- Output: pretty formatter still works; bats serializes the result line of each test through its own driver, so the same lines appear (just in completion order).
- Add `parallel` to [`01_install_prerequisites.sh`](01_install_prerequisites.sh) so CI gets it too.

## Compatibility with a future top-level parallel meta-runner (`18_run_all_checks_parallel.sh`)

If valve later adopts the teller pattern at [`../teller/18_run_all_checks_parallel.sh`](../teller/18_run_all_checks_parallel.sh) — a meta-runner that backgrounds every check script and captures each child's stdout/stderr to `${REPORT_DIR}/${script%.sh}.log` — both Tier 1 and Tier 2 remain valid. Three adjustments are required so the two parallelism layers compose safely.

### 1. Cap `BATS_JOBS` so we don't oversubscribe the host

Outer (`18_`: ~9 lanes) × inner (`bats -j N`) can spike to dozens of concurrent test processes. Make the cap explicit in both places.

In [`05_run_unit_tests.sh`](05_run_unit_tests.sh) (Tier 1 / Tier 2 invocation):

```bash
default_jobs="$(sysctl -n hw.ncpu 2>/dev/null || echo 8)"
if [ -n "${PARALLEL_LANES:-}" ] && [ "${PARALLEL_LANES}" -gt 1 ]; then
  default_jobs=$(( default_jobs / PARALLEL_LANES ))
  [ "$default_jobs" -lt 1 ] && default_jobs=1
fi
JOBS="${BATS_JOBS:-$default_jobs}"
```

In the ported `18_run_all_checks_parallel.sh`, before launching children:

```bash
export PARALLEL_LANES="${#CHECKS[@]}"
```

This keeps total concurrency near `hw.ncpu` whether `05_*` runs alone or under `18_`.

### 2. Output model changes under `18_` (by design, not Tier 2's fault)

- Standalone `05_run_unit_tests.sh` (Tier 1/Tier 2): bats output streams live, per-file atomic, with `--print-output-on-failure --timing`.
- Under `18_`: every child script's full stdout/stderr is captured to `${REPORT_DIR}/${script%.sh}.log`; only the final `PASS/FAIL` line per child streams live. Bats output is fully preserved on disk, just not live.

Document this in the porting commit so reviewers know `.parallel-checks-reports/05_run_unit_tests.log` is the canonical view when `18_` is used.

### 3. Bats-internal collision risk is unchanged

- Per-test `setup_shell_test` uses `mktemp -d` + isolated `STUB_BIN` + isolated `HOME` → no FS collisions across concurrent tests or concurrent lanes.
- `07_*.bats` uses `allocate_free_port` for ephemeral 127.0.0.1 binds → no port collisions.
- Shared Go build cache (`GOCACHE`) is concurrency-safe by design.
- Cross-script (not cross-test) artifacts under `${SCRIPT_DIR}/.security-reports/` (e.g. `go-coverage.out` in [`05_run_unit_tests.sh`](05_run_unit_tests.sh) line 117) are only a concern between top-level scripts; each uses distinct filenames today, but it's worth a `PARALLEL_LANE_REPORT_SUBDIR` convention if more files are added.

### 4. Tier 5 becomes load-bearing under `18_`

The DAST readiness/probe tests in `07_*.bats` (5.6s, 4.5s, 3.0s) hit real retry timers; under high CPU contention from `18_` siblings they're the most likely to flake. Adding the `DAST_HEALTH_PROBE_INTERVAL_SECS` / `DAST_HEALTH_PROBE_MAX_ATTEMPTS` knobs in Tier 5 mitigates this and is recommended before enabling `18_`.

## Tier 3 — split `tests/sh/07_run_security_checks.bats`

This single file is the wall-clock floor for any parallel-by-file strategy. Split by lane:

- `07_run_security_checks_sast.bats` — semgrep / shellcheck / gitleaks / detect-secrets / gosec / govulncheck tests
- `07_run_security_checks_dast.bats` — DAST auto-boot, readiness probe, ZAP
- `07_run_security_checks_schemathesis.bats` — schemathesis tests
- `07_run_security_checks_misc.bats` — completion output, openapi, defaults

Move the shared `make_*_stub` helpers into a new `tests/sh/helpers/security_stubs.bash` and `load` it from each file.

After splitting, the longest file becomes ~20s and Tier 1 collapses to ~25-30s wall.

## Tier 4 — per-file fixture hoisting via `setup_file`

Every bats file calls `setup_shell_test` + `setup_fixture` per test today (`grep setup_shell_test tests/sh -r` → 14 files). Each does `mktemp -d`, several `mkdir`, and `cp` of the script under test. Bats supports `setup_file`/`teardown_file` (run once per file). Refactor the shared template in [`tests/sh/helpers/common.bash`](tests/sh/helpers/common.bash) to expose two layers:

- `setup_file_shared_fixture` (copies the script-under-test and openapi once into `BATS_FILE_TMPDIR`)
- `setup_shell_test` (per-test `STUB_BIN`, `CALLS_LOG`, `HOME`; cheap)

Then per `*.bats` file:

```bash
setup_file() { setup_file_shared_fixture "07_run_security_checks.sh"; }
setup()      { setup_shell_test; make_go_vet_stub '{}'; }
```

Estimated saving: ~10-15% wall time on top of parallelism (eliminates ~200 redundant cp/mkdir cycles).

Also cache `repo_root` once in `BATS_FILE_TMPDIR` instead of recomputing via `cd` + `pwd` on every call.

## Tier 5 — shrink artificial wait loops

A few tests dominate `07_*.bats` because they exercise real retry timers in [`07_run_security_checks.sh`](07_run_security_checks.sh):

- "readiness probe failure dumps captured health log for diagnostics" — 5.6s
- "fails DAST lane when health probe fails" — 4.5s
- "readiness probe suppresses transient curl noise…" — 3.0s

Add env-tunable knobs to the script (e.g. `DAST_HEALTH_PROBE_INTERVAL_SECS`, `DAST_HEALTH_PROBE_MAX_ATTEMPTS`) that already-existing tests can override (e.g. `0.1` / `5`). Default behavior unchanged. Cuts those tests from ~13s combined to ~1s.

Similarly, `06_run_mutation_tests.bats` "uses default timeout of 600 seconds" test (~2.4s) likely exercises a sleep; if it's just asserting a flag value, replace the time-based check with an argv assertion.

## Dev-loop niceties (free)

Add convenience wrappers in [`05_run_unit_tests.sh`](05_run_unit_tests.sh) (or a new `bin/bats-fast`):

- `--filter-status failed` for fast re-run after a red run.
- `BATS_FILTER` env passed through to `bats -f "$BATS_FILTER"` so a developer can iterate on one test by name.
- `--gather-test-outputs-in <dir>` for full archives in CI without changing console output.

## Implementation order / todos

Recommended sequencing: Tier 1 first (immediate, no risk), then Tier 5 (cheap, no infra), then Tier 4 (mechanical refactor), then Tier 3+2 together if we want sub-30s.

## Expected results

- Tier 1 alone: 149s → **~80s wall** (measured).
- Tier 1 + 5: → ~50-55s.
- Tier 1 + 5 + 3: → ~25-30s.
- Tier 2 + 3 + 4 + 5 (with `parallel` installed): → ~15-25s.

All variants preserve every line of test-result and failure-diagnostic output the current run produces.
