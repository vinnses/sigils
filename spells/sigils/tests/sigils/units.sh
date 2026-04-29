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

assert_eq() {
  local actual="$1"
  local expected="$2"
  local message="$3"
  TEST_COUNT=$((TEST_COUNT + 1))
  if [[ "$actual" == "$expected" ]]; then
    pass "$message"
  else
    printf '  expected: %s\n' "$expected"
    printf '  actual:   %s\n' "$actual"
    fail "$message"
  fi
}

assert_status() {
  local actual="$1"
  local expected="$2"
  local message="$3"
  TEST_COUNT=$((TEST_COUNT + 1))
  if [[ "$actual" == "$expected" ]]; then
    pass "$message"
  else
    printf '  expected status: %s\n' "$expected"
    printf '  actual status:   %s\n' "$actual"
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
           "$REPO_FIXTURE/spells/alpha/bin" \
           "$REPO_FIXTURE/rites/mail/bin"

  printf '#!/usr/bin/env bash\necho blocked\n' >"$REPO_FIXTURE/spells/blocked/bin/blocked"
  printf 'export BLOCKED_INIT_LOADED=1\n' >"$REPO_FIXTURE/spells/blocked/inits/bash/blocked.bash"
  printf 'export BLOCKED_COMPLETION_LOADED=1\n' >"$REPO_FIXTURE/spells/blocked/completions/bash/blocked.bash"
  printf '#!/usr/bin/env bash\necho alpha\n' >"$REPO_FIXTURE/spells/alpha/bin/alpha"
  printf '#!/usr/bin/env bash\nprintf "mail:%%s\\n" "${1:-noop}"\n' >"$REPO_FIXTURE/rites/mail/bin/mail"
  cat >"$REPO_FIXTURE/spells/alpha/README.md" <<'EOF'
# alpha

Alpha spell fixture documentation.
EOF
  cat >"$REPO_FIXTURE/rites/mail/README.md" <<'EOF'
# mail

Mail rite fixture documentation.
EOF
  cat >"$REPO_FIXTURE/spells/alpha/Makefile" <<'EOF'
SHELL := /bin/bash

.PHONY: install install-dev test check fmt clean

install:
	@printf 'install\n' >> install.log

install-dev:
	@printf 'install-dev\n' >> install-dev.log

test:
	@printf 'test\n' >> test.log

check:
	@printf 'check\n' >> check.log

fmt:
	@printf 'fmt\n' >> fmt.log

clean:
	@printf 'clean\n' >> clean.log
EOF
  chmod +x "$REPO_FIXTURE/spells/blocked/bin/blocked" "$REPO_FIXTURE/spells/alpha/bin/alpha" "$REPO_FIXTURE/rites/mail/bin/mail"

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
  if grep -Fq "usb-auth" <<<"$CMD_OUTPUT"; then
    TEST_COUNT=$((TEST_COUNT + 1))
    printf '  spell list unexpectedly included usb-auth\n'
    fail "usb-auth is no longer listed as a spell"
  else
    TEST_COUNT=$((TEST_COUNT + 1))
    pass "usb-auth is no longer listed as a spell"
  fi

  run_cmd env SIGILS_ROOT="$REPO_FIXTURE" "$REPO_FIXTURE/bin/sigils" rites
  assert_contains "$CMD_OUTPUT" "mail" "sigils rites lists discovered rites"
  assert_contains "$CMD_OUTPUT" "pamusb" "sigils rites lists pamusb as a rite"

  run_cmd env SIGILS_ROOT="$REPO_FIXTURE" "$REPO_FIXTURE/bin/sigils" rites path mail
  assert_status "$CMD_STATUS" "0" "sigils rites path resolves a rite directory"
  assert_eq "$CMD_OUTPUT" "$REPO_FIXTURE/rites/mail" "sigils rites path prints the absolute rite path"

  run_cmd env SIGILS_ROOT="$REPO_FIXTURE" "$REPO_FIXTURE/bin/sigils" rites docs mail
  assert_status "$CMD_STATUS" "0" "sigils rites docs resolves rite documentation"
  assert_contains "$CMD_OUTPUT" "Mail rite fixture documentation." "sigils rites docs renders the rite README"

  run_cmd env SIGILS_ROOT="$REPO_FIXTURE" "$REPO_FIXTURE/bin/sigils" rites status --all
  assert_status "$CMD_STATUS" "0" "sigils rites status --all aggregates rite status"
  assert_contains "$CMD_OUTPUT" "mail:status" "sigils rites status --all runs rite status"

  run_cmd env SIGILS_ROOT="$REPO_FIXTURE" "$REPO_FIXTURE/bin/sigils" rites doctor mail
  assert_status "$CMD_STATUS" "0" "sigils rites doctor accepts a rite selector"
  assert_contains "$CMD_OUTPUT" "mail:doctor" "sigils rites doctor forwards to the selected rite"

  run_cmd env SIGILS_ROOT="$REPO_FIXTURE" "$REPO_FIXTURE/bin/sigils" rite mail status
  assert_status "$CMD_STATUS" "0" "sigils rite dispatches to the rite entrypoint"
  assert_contains "$CMD_OUTPUT" "mail:status" "sigils rite forwards rite arguments"

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

  run_cmd env SIGILS_ROOT="$REPO_FIXTURE" "$REPO_FIXTURE/bin/sigils" install alpha
  assert_status "$CMD_STATUS" "0" "sigils install runs the spell install target"
  assert_contains "$(cat "$REPO_FIXTURE/spells/alpha/install.log")" "install" "sigils install delegates to the spell Makefile"

  run_cmd env SIGILS_ROOT="$REPO_FIXTURE" "$REPO_FIXTURE/bin/sigils" install --dev alpha
  assert_status "$CMD_STATUS" "0" "sigils install --dev runs the spell dev install target"
  assert_contains "$(cat "$REPO_FIXTURE/spells/alpha/install-dev.log")" "install-dev" "sigils install --dev delegates to install-dev"

  run_cmd env SIGILS_ROOT="$REPO_FIXTURE" "$REPO_FIXTURE/bin/sigils" check alpha
  assert_status "$CMD_STATUS" "0" "sigils check accepts a spell selector"
  assert_contains "$(cat "$REPO_FIXTURE/spells/alpha/check.log")" "check" "sigils check delegates to the requested spell"

  run_cmd env SIGILS_ROOT="$REPO_FIXTURE" "$REPO_FIXTURE/bin/sigils" man alpha
  assert_status "$CMD_STATUS" "0" "sigils man renders spell documentation"
  assert_contains "$CMD_OUTPUT" "Alpha spell fixture documentation." "sigils man prints the spell README"

  run_cmd env SIGILS_ROOT="$REPO_FIXTURE" "$REPO_FIXTURE/bin/sigils" cd alpha
  assert_status "$CMD_STATUS" "0" "sigils cd resolves the spell directory"
  assert_eq "$CMD_OUTPUT" "$REPO_FIXTURE/spells/alpha" "sigils cd prints the absolute spell path"

  if [[ "$FAIL_COUNT" -ne 0 ]]; then
    printf '%s tests failed\n' "$FAIL_COUNT"
    exit 1
  fi

  printf '1..%s\n' "$TEST_COUNT"
}

main "$@"
