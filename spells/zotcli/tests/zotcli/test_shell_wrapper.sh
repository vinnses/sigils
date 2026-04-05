#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPELL_DIR="${SPELL_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
INIT_FILE="$SPELL_DIR/inits/bash/zotcli.bash"

TEST_COUNT=0
FAIL_COUNT=0

pass() {
  printf 'ok %s - %s\n' "$TEST_COUNT" "$1"
}

fail() {
  printf 'not ok %s - %s\n' "$TEST_COUNT" "$1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"
  TEST_COUNT=$((TEST_COUNT + 1))
  if grep -Fq -- "$needle" <<<"$haystack"; then
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

make_fixture() {
  FIXTURE_DIR="$(mktemp -d)"
  export FIXTURE_DIR
  mkdir -p "$FIXTURE_DIR/fakebin"

  cat >"$FIXTURE_DIR/fakebin/zotcli" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  off)
    printf '__ZOTCLI_ENV__ZOTCLI_VISUAL=\n'
    printf '__ZOTCLI_ENV__ZOTCLI_PATH=\n'
    printf '__ZOTCLI_ENV__ZOTCLI_SYNC_AGE=\n'
    ;;
  *)
    printf '__ZOTCLI_ENV__ZOTCLI_PATH=^/Papers\n'
    printf '__ZOTCLI_ENV__ZOTCLI_SYNC_AGE=5m ago\n'
    printf 'collections listed\n'
    ;;
esac
EOF
  chmod +x "$FIXTURE_DIR/fakebin/zotcli"
}

cleanup_fixture() {
  rm -rf "$FIXTURE_DIR"
}

main() {
  make_fixture
  trap cleanup_fixture EXIT

  export PATH="$FIXTURE_DIR/fakebin:$PATH"
  export PROMPT_COMMAND="existing_hook"
  unset ZOTCLI_VISUAL ZOTCLI_PATH ZOTCLI_SYNC_AGE ZOTCLI_PROMPT_COLOR

  # shellcheck disable=SC1090
  source "$INIT_FILE"

  local_output_file="$FIXTURE_DIR/output.txt"
  zotcli ls >"$local_output_file"
  output="$(cat "$local_output_file")"
  assert_contains "$output" "collections listed" "wrapper preserves display output"
  assert_eq "${ZOTCLI_PATH:-}" "^/Papers" "wrapper exports canonical zot path"
  assert_eq "${ZOTCLI_SYNC_AGE:-}" "5m ago" "wrapper exports sync age"
  assert_contains "$PROMPT_COMMAND" "__zotcli_prompt_apply" "prompt hook is installed on source"

  zotcli off >/dev/null
  assert_eq "${ZOTCLI_VISUAL:-}" "" "off clears visual flag"
  assert_eq "${ZOTCLI_PATH:-}" "" "off clears current path"
  assert_eq "${ZOTCLI_SYNC_AGE:-}" "" "off clears sync age"
  if grep -Fq "__zotcli_prompt_apply" <<<"$PROMPT_COMMAND"; then
    TEST_COUNT=$((TEST_COUNT + 1))
    fail "off removes zotcli hook from PROMPT_COMMAND"
  else
    TEST_COUNT=$((TEST_COUNT + 1))
    pass "off removes zotcli hook from PROMPT_COMMAND"
  fi

  if [[ "$FAIL_COUNT" -ne 0 ]]; then
    printf '%s tests failed\n' "$FAIL_COUNT"
    exit 1
  fi

  printf '1..%s\n' "$TEST_COUNT"
}

main "$@"
