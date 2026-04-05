#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPELL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ARCANE_BIN="$SPELL_DIR/bin/arcane"

TEST_COUNT=0
FAIL_COUNT=0

fail() {
  printf 'not ok %s - %s\n' "$TEST_COUNT" "$1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

pass() {
  printf 'ok %s - %s\n' "$TEST_COUNT" "$1"
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

assert_contains() {
  local actual="$1"
  local expected="$2"
  local message="$3"

  TEST_COUNT=$((TEST_COUNT + 1))
  if grep -Fq "$expected" <<<"$actual"; then
    pass "$message"
  else
    printf '  expected output containing: %s\n' "$expected"
    printf '  actual output: %s\n' "$actual"
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
  export FIXTURE_DIR
  export ARCANE_TEST_LOG="$FIXTURE_DIR/docker.log"
  mkdir -p "$FIXTURE_DIR/fakebin" "$FIXTURE_DIR/arcane/testbox/web"
  : >"$ARCANE_TEST_LOG"

  cat >"$FIXTURE_DIR/arcane/testbox/web/compose.yaml" <<'EOF'
services:
  api:
    image: ghcr.io/example/web:latest
EOF

  cat >"$FIXTURE_DIR/fakebin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s|%s\n' "$PWD" "$*" >>"$ARCANE_TEST_LOG"

case "$*" in
  "compose exec api echo hello")
    exit 0
    ;;
  "compose ps -aq --all")
    printf 'web-api-1\n'
    ;;
  "compose config --images")
    printf 'ghcr.io/example/web:latest\n'
    ;;
  "network ls --filter label=com.docker.compose.project=web --format {{.Name}}")
    printf 'web_default\n'
    ;;
  "volume ls --filter label=com.docker.compose.project=web --format {{.Name}}")
    printf 'web_data\n'
    ;;
  "rm -f web-api-1")
    exit 0
    ;;
  "image rm -f ghcr.io/example/web:latest")
    exit 0
    ;;
  "network rm web_default")
    exit 0
    ;;
  "volume rm web_data")
    exit 0
    ;;
esac
EOF

  chmod +x "$FIXTURE_DIR/fakebin/docker"
}

cleanup_fixture() {
  rm -rf "$FIXTURE_DIR"
}

main() {
  make_fixture
  trap cleanup_fixture EXIT

  export ARCANE_DIR="$FIXTURE_DIR/arcane"
  export PATH="$FIXTURE_DIR/fakebin:$PATH"
  export SIGILS_ROOT="$(cd "$SPELL_DIR/../.." && pwd)"

  run_cmd "$ARCANE_BIN" exec -d testbox web -- echo hello
  assert_status "$CMD_STATUS" "1" "exec requires an explicit service argument"
  assert_contains "$CMD_OUTPUT" "requires exactly one project and one service" "exec explains the missing service contract"

  run_cmd "$ARCANE_BIN" path -d testbox web
  assert_status "$CMD_STATUS" "0" "path prints a project path"
  assert_eq "$CMD_OUTPUT" "$FIXTURE_DIR/arcane/testbox/web" "path resolves the selected project"

  run_cmd "$ARCANE_BIN" resources -d testbox web
  assert_status "$CMD_STATUS" "0" "resources reports project resources"
  assert_contains "$CMD_OUTPUT" "containers: web-api-1" "resources lists project containers"
  assert_contains "$CMD_OUTPUT" "images: ghcr.io/example/web:latest" "resources lists project images"
  assert_contains "$CMD_OUTPUT" "networks: web_default" "resources lists project networks"
  assert_contains "$CMD_OUTPUT" "volumes: web_data" "resources lists project volumes"

  run_cmd "$ARCANE_BIN" rm containers -d testbox web
  assert_status "$CMD_STATUS" "0" "rm containers removes only project containers"
  assert_contains "$(cat "$ARCANE_TEST_LOG")" "rm -f web-api-1" "rm containers uses docker rm on discovered containers"

  run_cmd "$ARCANE_BIN" run -d testbox -- docker compose ps
  assert_status "$CMD_STATUS" "1" "run is rejected explicitly"
  assert_contains "$CMD_OUTPUT" "run has been removed" "run tells the caller to use exec or lifecycle commands"

  run_cmd bash -lc "export ARCANE_DIR='$FIXTURE_DIR/arcane'; export PATH='$FIXTURE_DIR/fakebin:$PATH'; source '$SIGILS_ROOT/init/env.bash'; cd /; arcane cd -d testbox web; pwd"
  assert_status "$CMD_STATUS" "0" "arcane cd works as a shell helper after init is sourced"
  assert_eq "$CMD_OUTPUT" "$FIXTURE_DIR/arcane/testbox/web" "arcane cd changes the current shell directory"

  if [[ "$FAIL_COUNT" -ne 0 ]]; then
    printf '%s tests failed\n' "$FAIL_COUNT"
    exit 1
  fi

  printf '1..%s\n' "$TEST_COUNT"
}

main "$@"
