---
name: Resolve detect-secrets false positive
overview: Refactor the failing backend test assertion to avoid embedding a credential-shaped URL literal while preserving the behavior guarantee that `08_run_backend.sh` composes the database URL correctly. Update security-check tests/docs only if required by the changed assertion style.
todos:
  - id: refactor-08-backend-assert
    content: Rewrite the flagged URL assertion in tests/sh/08_run_backend.bats into non-credential-shaped checks with equivalent intent.
    status: completed
  - id: verify-security-check-tests
    content: Run targeted bats tests for backend fixture and security-check harness to ensure no regressions.
    status: completed
  - id: verify-sast-gate
    content: Run ./06_run_security_checks.sh and confirm detect-secrets findings drop to zero and gate passes.
    status: completed
isProject: false
---

# Eliminate detect-secrets false positive in backend fixture test

## Goal
Make `./06_run_security_checks.sh` pass by removing the credential-shaped literal from the backend fixture assertion, without reducing `detect-secrets` coverage.

## Planned changes
- Update [`tests/sh/08_run_backend.bats`](/Users/phil/local/src/valve/tests/sh/08_run_backend.bats) to replace the single `grep -F "VALVE_DATABASE_URL=postgres://user_a:pw_a@db.local:6543/valve?sslmode=disable"` assertion with equivalent checks that validate URL composition but do not contain a `scheme://user:pass@...` literal in one string.
- Keep behavior coverage intact by asserting the same components are present in `${CALLS_LOG}` (prefix, host/port/db path, sslmode, and credential fragments) through split checks or a safer pattern that avoids triggering the Basic Auth detector.
- Validate that this change does not require policy changes in [`06_run_security_checks.sh`](/Users/phil/local/src/valve/06_run_security_checks.sh); leave exclusion logic untouched unless tests prove otherwise.
- Run and confirm the relevant tests/security flow after implementation:
  - backend fixture test file: [`tests/sh/08_run_backend.bats`](/Users/phil/local/src/valve/tests/sh/08_run_backend.bats)
  - SAST harness tests if impacted: [`tests/sh/06_run_security_checks.bats`](/Users/phil/local/src/valve/tests/sh/06_run_security_checks.bats)
  - full gate: `./06_run_security_checks.sh`

## Key rationale
- This approach resolves the current false positive at the source fixture line while preserving scanner signal on test files.
- It avoids adding permanent suppressions (`pragma`) or broad file exclusions that could hide future real leaks.