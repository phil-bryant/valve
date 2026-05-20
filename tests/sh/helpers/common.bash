#!/usr/bin/env bash

# Memoize repo_root so the many per-test callers don't each spawn a `cd ... && pwd`
# subshell. The result is invariant across tests in a single bats process.
__REPO_ROOT_CACHED=""
repo_root() {
  if [[ -z "${__REPO_ROOT_CACHED}" ]]; then
    __REPO_ROOT_CACHED="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
  fi
  printf '%s' "${__REPO_ROOT_CACHED}"
}

# Optional per-file setup hook for files that want to amortize source-file
# copies across their tests. Bats calls `setup_file` once per file before the
# first `setup`. This helper pre-stages script-under-test source files and
# openapi schemas under BATS_FILE_TMPDIR (also created once per file) so
# per-test `setup` can copy from a local cache without re-reading the repo
# tree. Per-test isolation is preserved because each test still gets its own
# FIXTURE_ROOT under TEST_TMPDIR (per `setup_shell_test`).
#
# Usage in a *.bats file:
#   setup_file() { setup_file_shared_fixture "12_run_fuzz.sh"; }
#   setup()      { setup_shell_test; setup_fixture; }
# where `setup_fixture` calls `copy_script_to_fixture "12_run_fuzz.sh"`.
setup_file_shared_fixture() {
  : "${BATS_FILE_TMPDIR:?BATS_FILE_TMPDIR is unset; bats >=1.7 required}"
  export SHARED_SOURCE_DIR="${BATS_FILE_TMPDIR}/shared-source"
  mkdir -p "$SHARED_SOURCE_DIR"
  local script_name
  for script_name in "$@"; do
    cp "$(repo_root)/${script_name}" "${SHARED_SOURCE_DIR}/${script_name}"
    chmod +x "${SHARED_SOURCE_DIR}/${script_name}"
  done
  local schema_file
  if [[ -d "$(repo_root)/openapi" ]]; then
    mkdir -p "${SHARED_SOURCE_DIR}/openapi"
    for schema_file in "$(repo_root)/openapi"/*.yaml; do
      [[ -f "${schema_file}" ]] || continue
      cp "${schema_file}" "${SHARED_SOURCE_DIR}/openapi/"
    done
  fi
}

setup_shell_test() {
  export TEST_TMPDIR
  TEST_TMPDIR="$(mktemp -d)"
  export HOME="${TEST_TMPDIR}/home"
  mkdir -p "$HOME"
  export STUB_BIN="${TEST_TMPDIR}/test-bin"
  mkdir -p "$STUB_BIN"
  export CALLS_LOG="${TEST_TMPDIR}/calls.log"
  : > "$CALLS_LOG"
  export PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin"
}

teardown_shell_test() {
  if [[ -n "${TEST_TMPDIR:-}" && -d "${TEST_TMPDIR}" ]]; then
    mv "${TEST_TMPDIR}" "${TEST_TMPDIR}.trash.$$"
  fi
}

create_repo_fixture() {
  export FIXTURE_ROOT="${TEST_TMPDIR}/fixture"
  mkdir -p "$FIXTURE_ROOT"
}

# Resolve the source for a script-under-test. Prefer SHARED_SOURCE_DIR (set by
# setup_file_shared_fixture) when present; fall back to the live repo tree.
_resolve_source_path() {
  local rel="$1"
  if [[ -n "${SHARED_SOURCE_DIR:-}" && -e "${SHARED_SOURCE_DIR}/${rel}" ]]; then
    printf '%s' "${SHARED_SOURCE_DIR}/${rel}"
  else
    printf '%s' "$(repo_root)/${rel}"
  fi
}

copy_script_to_fixture() {
  local script_name="$1"
  local src
  src="$(_resolve_source_path "${script_name}")"
  cp "${src}" "${FIXTURE_ROOT}/${script_name}"
  chmod +x "${FIXTURE_ROOT}/${script_name}"
}

copy_openapi_to_fixture() {
  local source_dir
  local schema_file
  local copied_any=false
  if [[ -n "${SHARED_SOURCE_DIR:-}" && -d "${SHARED_SOURCE_DIR}/openapi" ]]; then
    source_dir="${SHARED_SOURCE_DIR}/openapi"
  else
    source_dir="$(repo_root)/openapi"
  fi
  if [[ -d "${source_dir}" ]]; then
    mkdir -p "${FIXTURE_ROOT}/openapi"
    for schema_file in "${source_dir}"/*.yaml; do
      if [[ -f "${schema_file}" ]]; then
        cp "${schema_file}" "${FIXTURE_ROOT}/openapi/"
        copied_any=true
      fi
    done
    if [[ "${copied_any}" != "true" ]]; then
      return 0
    fi
  fi
}

stub_cmd() {
  local name="$1"
  shift
  local target="${STUB_BIN}/${name}"
  {
    echo "#!/usr/bin/env bash"
    echo "echo ${name} \"\$*\" >> \"${CALLS_LOG}\""
    printf "%s\n" "$@"
  } > "$target"
  chmod +x "$target"
}

file_mode() {
  stat -f "%Lp" "$1"
}
