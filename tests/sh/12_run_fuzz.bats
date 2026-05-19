#!/usr/bin/env bats

load "helpers/common.bash"

setup_fixture() {
  create_repo_fixture
  copy_script_to_fixture "12_run_fuzz.sh"
}

setup() {
  setup_shell_test
  setup_fixture
}

teardown() {
  teardown_shell_test
}

make_go_fuzz_stub() {
  cat > "${STUB_BIN}/go" <<EOF
#!/usr/bin/env bash
echo "go \$*" >> "${CALLS_LOG}"
if [[ "\$1" == "test" ]] && [[ "\$*" == *"-fuzz=Fuzz"* ]] && [[ "\$*" == *"-fuzztime=30s"* ]]; then
  exit 0
fi
if [[ "\$1" == "test" ]] && [[ "\$*" == *"-list=Fuzz"* ]] && [[ "\$*" == *"./internal/credentials"* ]]; then
  printf '%s\n' FuzzValidateRegister
  exit 0
fi
if [[ "\$1" == "test" ]] && [[ "\$*" == *"-list=Fuzz"* ]] && [[ "\$*" == *"./internal/security"* ]]; then
  printf '%s\n' FuzzIsServiceAuthorized
  exit 0
fi
exit 1
EOF
  chmod +x "${STUB_BIN}/go"
}

@test "runs fuzz tests from non-repo cwd" {
  #R001-T01: Run from non-repo cwd verifies fuzz invocation still targets repository packages.
  #R001
  make_go_fuzz_stub
  mkdir -p "${TEST_TMPDIR}/elsewhere"
  run env PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash -c "cd '${TEST_TMPDIR}/elsewhere' && bash '${FIXTURE_ROOT}/12_run_fuzz.sh'"
  [ "$status" -eq 0 ]
}

@test "fails when go is missing" {
  #R005-T01: Run with go missing verifies non-zero failure.
  #R005
  run env PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/12_run_fuzz.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"go is required"* ]]
}

@test "invokes default fuzz packages and fuzztime" {
  #R010-T01: Run with go stub verifies fuzz packages and fuzztime in invocation log.
  #R010
  make_go_fuzz_stub
  run env PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/12_run_fuzz.sh"
  [ "$status" -eq 0 ]
  run grep -F "internal/credentials" "${CALLS_LOG}"
  [ "$status" -eq 0 ]
  run grep -e '-fuzztime=30s' "${CALLS_LOG}"
  [ "$status" -eq 0 ]
  run grep -e '-fuzz=Fuzz' "${CALLS_LOG}"
  [ "$status" -eq 0 ]
}

@test "prints pass output on success" {
  #R015-T01: Run successful fuzz stub path and verify pass output line.
  #R015
  make_go_fuzz_stub
  run env PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/12_run_fuzz.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: Go fuzz tests completed"* ]]
}
