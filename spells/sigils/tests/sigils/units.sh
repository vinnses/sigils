#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPELL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_ROOT="$(cd "$SPELL_DIR/../.." && pwd)"

TEST_COUNT=0
FAIL_COUNT=0

pass() {
  printf 'ok %s - %s\n' "$TEST_COUNT" "$1"
}

fail() {
  printf 'not ok %s - %s\n' "$TEST_COUNT" "$1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

assert_file_exists() {
  local path="$1"
  local message="$2"
  TEST_COUNT=$((TEST_COUNT + 1))
  if [[ -e "$path" ]]; then
    pass "$message"
  else
    printf '  missing: %s\n' "$path"
    fail "$message"
  fi
}

assert_file_missing() {
  local path="$1"
  local message="$2"
  TEST_COUNT=$((TEST_COUNT + 1))
  if [[ ! -e "$path" ]]; then
    pass "$message"
  else
    printf '  unexpected path: %s\n' "$path"
    fail "$message"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"
  TEST_COUNT=$((TEST_COUNT + 1))
  if grep -Fq "$needle" <<<"$haystack"; then
    pass "$message"
  else
    printf '  expected output containing: %s\n' "$needle"
    printf '  actual output: %s\n' "$haystack"
    fail "$message"
  fi
}

run_cmd() {
  set +e
  CMD_OUTPUT="$("$@" 2>&1)"
  CMD_STATUS=$?
  set -e
}

make_fixture() {
  FIXTURE_DIR="$(mktemp -d)"
  cp -R "$PROJECT_ROOT" "$FIXTURE_DIR/repo"
  export REPO_FIXTURE="$FIXTURE_DIR/repo"

  mkdir -p "$REPO_FIXTURE/spells/blocked/bin" \
           "$REPO_FIXTURE/spells/blocked/inits/bash" \
           "$REPO_FIXTURE/spells/blocked/completions/bash" \
           "$REPO_FIXTURE/spells/alpha/bin"

  printf '#!/usr/bin/env bash\necho blocked\n' >"$REPO_FIXTURE/spells/blocked/bin/blocked"
  printf 'export BLOCKED_INIT_LOADED=1\n' >"$REPO_FIXTURE/spells/blocked/inits/bash/blocked.bash"
  printf 'export BLOCKED_COMPLETION_LOADED=1\n' >"$REPO_FIXTURE/spells/blocked/completions/bash/blocked.bash"
  printf '#!/usr/bin/env bash\necho alpha\n' >"$REPO_FIXTURE/spells/alpha/bin/alpha"
  chmod +x "$REPO_FIXTURE/spells/blocked/bin/blocked" "$REPO_FIXTURE/spells/alpha/bin/alpha"

  mkdir -p "$REPO_FIXTURE/config"
  printf 'blocked\nzotcli\n' >"$REPO_FIXTURE/config/spells.disabled"
}

cleanup_fixture() {
  rm -rf "$FIXTURE_DIR"
}

main() {
  make_fixture
  trap cleanup_fixture EXIT

  run_cmd make -C "$REPO_FIXTURE" link
  assert_file_exists "$REPO_FIXTURE/bin/alpha" "make link keeps enabled spell entrypoints"
  assert_file_missing "$REPO_FIXTURE/bin/blocked" "make link skips disabled spell entrypoints"

  run_cmd bash -lc "source '$REPO_FIXTURE/init/env.bash'; printf '%s:%s' \"\${BLOCKED_INIT_LOADED:-0}\" \"\${BLOCKED_COMPLETION_LOADED:-0}\""
  assert_contains "$CMD_OUTPUT" "0:0" "init/env.bash does not source disabled spell init or completion"

  run_cmd "$REPO_FIXTURE/bin/sigils" list
  assert_contains "$CMD_OUTPUT" "enabled alpha" "sigils list shows enabled spells"
  assert_contains "$CMD_OUTPUT" "disabled blocked" "sigils list shows disabled spells"

  run_cmd env SIGILS_ROOT="$REPO_FIXTURE" "$REPO_FIXTURE/bin/sigils" disable alpha
  assert_contains "$(cat "$REPO_FIXTURE/config/spells.disabled")" "alpha" "sigils disable records the spell in config"

  run_cmd env SIGILS_ROOT="$REPO_FIXTURE" "$REPO_FIXTURE/bin/sigils" enable blocked
  if grep -Fxq "blocked" "$REPO_FIXTURE/config/spells.disabled"; then
    TEST_COUNT=$((TEST_COUNT + 1))
    fail "sigils enable removes the spell from config"
  else
    TEST_COUNT=$((TEST_COUNT + 1))
    pass "sigils enable removes the spell from config"
  fi

  if [[ "$FAIL_COUNT" -ne 0 ]]; then
    printf '%s tests failed\n' "$FAIL_COUNT"
    exit 1
  fi

  printf '1..%s\n' "$TEST_COUNT"
}

main "$@"
