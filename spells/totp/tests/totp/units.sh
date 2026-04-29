#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPELL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TOTP_BIN="$SPELL_DIR/bin/totp"

TEST_COUNT=0
FAIL_COUNT=0

pass() {
  printf 'ok %s - %s\n' "$TEST_COUNT" "$1"
}

fail() {
  printf 'not ok %s - %s\n' "$TEST_COUNT" "$1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
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

assert_contains() {
  local actual="$1"
  local expected="$2"
  local message="$3"
  TEST_COUNT=$((TEST_COUNT + 1))
  if grep -Fq -- "$expected" <<<"$actual"; then
    pass "$message"
  else
    printf '  expected output containing: %s\n' "$expected"
    printf '  actual output: %s\n' "$actual"
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

run_cmd() {
  set +e
  CMD_OUTPUT="$("$@" 2>&1)"
  CMD_STATUS=$?
  set -e
}

make_fixture() {
  FIXTURE_DIR="$(mktemp -d)"
  export TOTP_DATA_DIR="$FIXTURE_DIR/data"
  export TOTP_TEST_CLIP_LOG="$FIXTURE_DIR/clipboard.log"
  mkdir -p "$FIXTURE_DIR/fakebin" "$TOTP_DATA_DIR"
  chmod 700 "$TOTP_DATA_DIR"

  cat >"$TOTP_DATA_DIR/keys" <<'EOF'
github	JBSWY3DPEHPK3PXP	sha1	6	30
email	JBSWY3DPEHPK3PXP	sha1	6	30
EOF

  cat >"$FIXTURE_DIR/fakebin/oathtool" <<'EOF'
#!/usr/bin/env bash
printf '123456\n'
EOF

  cat >"$FIXTURE_DIR/fakebin/xclip" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"-o"* ]]; then
  printf 'JBSWY3DPEHPK3PXP\n'
else
  cat >"$TOTP_TEST_CLIP_LOG"
fi
EOF

  cat >"$FIXTURE_DIR/fakebin/openssl" <<'EOF'
#!/usr/bin/env bash
cat
EOF

  cat >"$FIXTURE_DIR/fakebin/gpg" <<'EOF'
#!/usr/bin/env bash
output=""
decrypt=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --decrypt)
      decrypt=true
      shift
      ;;
    --output)
      output="$2"
      shift 2
      ;;
    --*)
      shift
      ;;
    -)
      shift
      ;;
    *)
      input="$1"
      shift
      ;;
  esac
done
if $decrypt; then
  cat "$input"
else
  cat >"$output"
fi
EOF

  chmod +x "$FIXTURE_DIR/fakebin/oathtool" "$FIXTURE_DIR/fakebin/xclip" "$FIXTURE_DIR/fakebin/openssl" "$FIXTURE_DIR/fakebin/gpg"
  export PATH="$FIXTURE_DIR/fakebin:$PATH"
}

cleanup_fixture() {
  rm -rf "$FIXTURE_DIR"
}

main() {
  make_fixture
  trap cleanup_fixture EXIT

  run_cmd "$TOTP_BIN" get github
  assert_status "$CMD_STATUS" "0" "get accepts positional account name"
  assert_contains "$CMD_OUTPUT" "github" "get prints the selected account"
  assert_contains "$CMD_OUTPUT" "123 456" "get prints the generated code"

  run_cmd "$TOTP_BIN" copy github
  assert_status "$CMD_STATUS" "0" "copy accepts positional account name"
  assert_eq "$(cat "$TOTP_TEST_CLIP_LOG")" "123456" "copy writes the raw code to clipboard"

  run_cmd "$TOTP_BIN" cp email
  assert_status "$CMD_STATUS" "0" "cp aliases copy"
  assert_eq "$(cat "$TOTP_TEST_CLIP_LOG")" "123456" "cp writes the raw code to clipboard"

  run_cmd "$TOTP_BIN" get github --xclip
  assert_status "$CMD_STATUS" "0" "get --xclip copies while printing"
  assert_eq "$(cat "$TOTP_TEST_CLIP_LOG")" "123456" "get --xclip writes the raw code to clipboard"

  run_cmd "$TOTP_BIN" ls
  assert_status "$CMD_STATUS" "0" "ls aliases list"
  assert_contains "$CMD_OUTPUT" "github" "ls lists account metadata without codes"

  run_cmd "$TOTP_BIN" get --all
  assert_status "$CMD_STATUS" "0" "get --all reveals all current codes"
  assert_contains "$CMD_OUTPUT" "github" "get --all includes github"
  assert_contains "$CMD_OUTPUT" "email" "get --all includes email"

  run_cmd "$TOTP_BIN" rm github
  assert_status "$CMD_STATUS" "1" "rm still requires encrypted storage for writes"
  assert_contains "$CMD_OUTPUT" "unencrypted storage" "rm aliases remove after parsing"

  run_cmd "$TOTP_BIN" init --backend gpg
  assert_status "$CMD_STATUS" "0" "init --backend gpg migrates plaintext storage"
  assert_contains "$(cat "$TOTP_DATA_DIR/backend")" "gpg" "gpg init records the backend"
  TEST_COUNT=$((TEST_COUNT + 1))
  if [[ -f "$TOTP_DATA_DIR/keys.gpg" && ! -f "$TOTP_DATA_DIR/keys" ]]; then
    pass "gpg init writes encrypted storage and removes plaintext"
  else
    printf '  expected keys.gpg present and legacy keys removed\n'
    find "$TOTP_DATA_DIR" -maxdepth 1 -type f -printf '  %f\n'
    fail "gpg init writes encrypted storage and removes plaintext"
  fi

  if [[ "$FAIL_COUNT" -ne 0 ]]; then
    printf '%s tests failed\n' "$FAIL_COUNT"
    exit 1
  fi

  printf '1..%s\n' "$TEST_COUNT"
}

main "$@"
