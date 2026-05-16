---
name: Remediate shellcheck findings
overview: Fix the three SC2155 ShellCheck warnings causing the SAST gate failure by separating variable declaration and assignment in affected scripts, then verify behavior and tests remain unchanged.
todos:
  - id: fix-sc2155-mutation-script
    content: Refactor SC2155 pattern in 06_run_mutation_tests.sh to declaration then assignment
    status: pending
  - id: fix-sc2155-installer-script
    content: Refactor both SC2155 patterns in ensure_gremlins in 01_install_prerequisites.sh
    status: pending
  - id: update-requirements-docs
    content: Update requirement docs for step-01 and step-06 to capture the SC2155-compliant declaration/assignment pattern
    status: pending
  - id: update-shell-tests
    content: Update shell tests to assert the refactored command resolution behavior still works for both scripts
    status: pending
  - id: verify-tests-and-sast
    content: Run targeted bats suites and rerun security checks to confirm ShellCheck and SAST gate pass
    status: pending
isProject: false
---

# Remediate ShellCheck SC2155 Findings

## Goal
Clear the three ShellCheck `SC2155` warnings reported in `.security-reports/shellcheck.json` so SAST passes without weakening shell safety.

## Targeted Code Changes
- Update [`/Users/phil/local/src/valve/06_run_mutation_tests.sh`](/Users/phil/local/src/valve/06_run_mutation_tests.sh):
  - In the gremlins resolver branch, replace inline assignment in the `if` condition (`if resolved_gremlins="$(...)"; then`) with:
    - prior declaration/initialization, and
    - explicit assignment before a status check.
- Update [`/Users/phil/local/src/valve/01_install_prerequisites.sh`](/Users/phil/local/src/valve/01_install_prerequisites.sh):
  - In `ensure_gremlins()`, replace both inline command-substitution assignments in `if` conditions (pre-install and post-install checks) with declaration-then-assignment flow.

## Requirements + Tests Updates
- Update requirements docs to reflect the shell-style contract change:
  - [`/Users/phil/local/src/valve/requirements/06_run_mutation_tests-requirements.md`](/Users/phil/local/src/valve/requirements/06_run_mutation_tests-requirements.md)
  - [`/Users/phil/local/src/valve/requirements/01_install_prerequisites-requirements.md`](/Users/phil/local/src/valve/requirements/01_install_prerequisites-requirements.md)
- Update shell tests where necessary to preserve explicit coverage of command-resolution behavior after the SC2155 refactor:
  - [`/Users/phil/local/src/valve/tests/sh/06_run_mutation_tests.bats`](/Users/phil/local/src/valve/tests/sh/06_run_mutation_tests.bats)
  - [`/Users/phil/local/src/valve/tests/sh/01_install_prerequisites.bats`](/Users/phil/local/src/valve/tests/sh/01_install_prerequisites.bats)

## Verification
- Run focused shell tests for updated scripts and requirement-aligned behaviors:
  - [`/Users/phil/local/src/valve/tests/sh/06_run_mutation_tests.bats`](/Users/phil/local/src/valve/tests/sh/06_run_mutation_tests.bats)
  - [`/Users/phil/local/src/valve/tests/sh/01_install_prerequisites.bats`](/Users/phil/local/src/valve/tests/sh/01_install_prerequisites.bats)
- Re-run security lane to confirm shellcheck findings drop to zero and gate passes:
  - `./07_run_security_checks.sh` and verify `.security-reports/shellcheck.json` + `.security-reports/sast-summary.json`.

## Notes
- No behavior changes are expected; this is a lint-compliance refactor preserving existing control flow and output.