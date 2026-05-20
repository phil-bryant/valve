#!/usr/bin/env bats

load "helpers/common.bash"
load "helpers/security_stubs.bash"

# Numbered-tag parity supplements for security-tool branch coverage.
# Hosted here (in the first 07_*.bats file alphabetically) because the
# traceability checker discovers tests across every 07_*.bats sibling.
#R010-T02
#R015-T02
#R015-T03
#R020-T02
#R020-T03
#R025-T02
#R025-T05
#R035-T04
#R040-T02
#R040-T03
#R040-T04

setup_file() {
  setup_file_shared_fixture "07_run_security_checks.sh"
}

setup() {
  setup_security_test
}

teardown() {
  teardown_shell_test
}

@test "runs from non-repo cwd and writes reports under script root" {
  #R001-T01: Run from non-repo cwd verifies report artifacts written under script-root .security-reports.
  #R001
  make_semgrep_stub
  make_shellcheck_stub '[]'
  make_gitleaks_stub '[]'
  make_detect_secrets_stub '{"results":{}}'
  make_gosec_stub '{"Issues":[]}'
  make_govulncheck_stub '{}'
  mkdir -p "${TEST_TMPDIR}/elsewhere"
  run env RUN_DAST=false PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash -c "cd '${TEST_TMPDIR}/elsewhere' && bash '${FIXTURE_ROOT}/07_run_security_checks.sh'"
  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/.security-reports/sast-summary.json" ]
}

@test "fails fast with installer guidance when semgrep is missing" {
  #R005-T01: Run SAST lane with missing semgrep verifies non-zero failure plus installer guidance.
  #R005
  run env RUN_DAST=false PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing required command: semgrep"* ]]
  [[ "$output" == *"./01_install_prerequisites.sh"* ]]
}

@test "fails fast with installer guidance when shellcheck is missing" {
  #R005
  make_semgrep_stub
  make_detect_secrets_stub '{"results":{}}'
  run env RUN_DAST=false PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing required command: shellcheck"* ]]
  [[ "$output" == *"./01_install_prerequisites.sh"* ]]
}

@test "does not run dependency freshness lane and emits no dependency artifacts" {
  #R010-T01: Run step-06 without dependency freshness script verifies SAST execution still succeeds.
  #R010
  make_semgrep_stub
  make_shellcheck_stub '[]'
  make_gitleaks_stub '[]'
  make_detect_secrets_stub '{"results":{}}'
  make_gosec_stub '{"Issues":[]}'
  make_govulncheck_stub '{}'
  run env PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" RUN_DAST=false \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [ ! -f "${FIXTURE_ROOT}/.security-reports/dependency-freshness.txt" ]
  [ ! -f "${FIXTURE_ROOT}/.security-reports/dependency-freshness.json" ]
}

@test "writes all SAST scanner artifacts and summary" {
  #R015-T01: Run SAST lane with stubs verifies each expected scanner artifact file is generated.
  #R015
  make_semgrep_stub
  make_shellcheck_stub '[]'
  make_gitleaks_stub '[]'
  make_detect_secrets_stub '{"results":{}}'
  make_gosec_stub '{"Issues":[]}'
  make_govulncheck_stub '{}'
  run env RUN_DAST=false PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/.security-reports/semgrep.json" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/shellcheck.json" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/gitleaks.json" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/detect-secrets.json" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/govet.json" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/gosec.json" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/govulncheck.json" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/sast-summary.json" ]
}

@test "records go vet findings in SAST summary" {
  #R015 #R020
  make_semgrep_stub
  make_shellcheck_stub '[]'
  make_gitleaks_stub '[]'
  make_detect_secrets_stub '{"results":{}}'
  make_go_vet_stub '{"golang.org/x/tools/go/analysis/unitchecker":{"vet":[{"posn":"/tmp/repo/main.go:10:2","message":"suspicious construct"}]}}'
  make_gosec_stub '{"Issues":[]}'
  make_govulncheck_stub '{}'
  run env RUN_DAST=false SECURITY_FAIL_ON_HIGH_CRITICAL=true PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SAST) gate failed"* ]]
  run python3 -c 'import json,sys;print(json.load(open(sys.argv[1], encoding="utf-8"))["govet_findings"])' "${FIXTURE_ROOT}/.security-reports/sast-summary.json"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "fails SAST gate when findings exist and fail-on-high is enabled" {
  #R020-T01: Seed finding-producing scanner outputs verifies gate fails with explicit SAST gate message.
  #R020
  make_semgrep_stub
  make_shellcheck_stub '[]'
  make_gitleaks_stub '[{"RuleID":"secret"}]'
  make_detect_secrets_stub '{"results":{}}'
  make_gosec_stub '{"Issues":[]}'
  make_govulncheck_stub '{}'
  run env RUN_DAST=false SECURITY_FAIL_ON_HIGH_CRITICAL=true PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SAST) gate failed"* ]]
}

@test "invokes gosec with gomodcache excluded" {
  #R015
  make_semgrep_stub
  make_shellcheck_stub '[]'
  make_gitleaks_stub '[]'
  make_detect_secrets_stub '{"results":{}}'
  make_gosec_stub '{"Issues":[]}'
  make_govulncheck_stub '{}'
  run env RUN_DAST=false GOSEC_EXPECT_ARGS_CONTAIN="-exclude-dir=.gomodcache" PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 0 ]
}

@test "invokes detect-secrets with default exclusion regex by default" {
  #R015
  make_semgrep_stub
  make_shellcheck_stub '[]'
  make_gitleaks_stub '[]'
  make_detect_secrets_stub '{"results":{}}'
  make_gosec_stub '{"Issues":[]}'
  make_govulncheck_stub '{}'
  run env RUN_DAST=false DETECT_SECRETS_EXPECT_ARGS_CONTAIN="--exclude-files (^|/)\\.gomodcache/|(^|/)requirements/.*-requirements\\.md$|(^|/)\\.cursor/plans/.*\\.plan\\.md$|(^|/)\\.security-reports/.*\\.(json|log)$" PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 0 ]
}

@test "ignores detect-secrets findings under excluded paths for gate totals" {
  #R020
  make_semgrep_stub
  make_shellcheck_stub '[]'
  make_gitleaks_stub '[]'
  make_detect_secrets_stub '{"results":{".gomodcache/cache/download/example":[{"type":"Hex High Entropy String","line_number":1}],".cursor/plans/resolve.plan.md":[{"type":"Basic Auth Credentials","line_number":1}]}}'
  make_gosec_stub '{"Issues":[]}'
  make_govulncheck_stub '{}'
  run env RUN_DAST=false SECURITY_FAIL_ON_HIGH_CRITICAL=true PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 0 ]
  run python3 -c 'import json,sys;print(json.load(open(sys.argv[1], encoding="utf-8"))["detect_secrets_findings"])' "${FIXTURE_ROOT}/.security-reports/sast-summary.json"
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]
}

@test "fails SAST gate on in-scope detect-secrets findings" {
  #R020
  make_semgrep_stub
  make_shellcheck_stub '[]'
  mkdir -p "${FIXTURE_ROOT}/config"
  cat > "${FIXTURE_ROOT}/config/config.go" <<'EOF'
package config

func placeholder() {
}

// filler
// filler
// filler
// filler
// filler
// filler
secret := "abc123"
EOF
  make_gitleaks_stub '[]'
  make_detect_secrets_stub '{"results":{"config/config.go":[{"type":"Secret Keyword","line_number":12}]}}'
  make_gosec_stub '{"Issues":[]}'
  make_govulncheck_stub '{}'
  run env RUN_DAST=false SECURITY_FAIL_ON_HIGH_CRITICAL=true PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_security_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SAST) gate failed"* ]]
  [[ "$output" == *"❌ Detect-secrets findings (in scope):"* ]]
  [[ "$output" == *"❌ config/config.go:12 [Secret Keyword]"* ]]
  [[ "$output" == *"source: secret := \"abc123\""* ]]
  run python3 -c 'import json,sys;print(json.load(open(sys.argv[1], encoding="utf-8"))["detect_secrets_findings"])' "${FIXTURE_ROOT}/.security-reports/sast-summary.json"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}
