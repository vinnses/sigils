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
  if grep -Fq -- "$expected" <<<"$actual"; then
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
  mkdir -p "$FIXTURE_DIR/fakebin" \
           "$FIXTURE_DIR/arcane/testbox/web" \
           "$FIXTURE_DIR/arcane/testbox/alpha" \
           "$FIXTURE_DIR/arcane/testbox/beta"
  : >"$ARCANE_TEST_LOG"

  cat >"$FIXTURE_DIR/arcane/testbox/compose.yaml" <<'EOF'
services:
  api:
    image: ghcr.io/example/device-root:latest
EOF

  cat >"$FIXTURE_DIR/arcane/testbox/web/compose.yaml" <<'EOF'
services:
  api:
    image: ghcr.io/example/web:latest
    env_file:
      - .secret
EOF

  cat >"$FIXTURE_DIR/arcane/testbox/web/.env" <<'EOF'
ARCANE_DEVICE=testbox
ARCANE_PROJECT=web
ARCANE_DIR=/srv/arcane/testbox/web
EOF

  cat >"$FIXTURE_DIR/arcane/testbox/web/.secret" <<'EOF'
WEB_SECRET=1
EOF

  cat >"$FIXTURE_DIR/arcane/testbox/alpha/compose.yaml" <<'EOF'
services:
  vibecode:
    image: ghcr.io/example/alpha:latest
EOF

  cat >"$FIXTURE_DIR/arcane/testbox/beta/compose.yaml" <<'EOF'
services:
  vibecode:
    image: ghcr.io/example/beta:latest
EOF

  cat >"$FIXTURE_DIR/fakebin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s|%s\n' "$PWD" "$*" >>"$ARCANE_TEST_LOG"

case "$*" in
  "compose exec api echo hello")
    exit 0
    ;;
  "compose exec vibecode echo beta")
    exit 0
    ;;
  "compose exec api bash")
    exit 0
    ;;
  "compose exec vibecode bash")
    exit 0
    ;;
  "compose ps -aq --all")
    [[ "$PWD" == */web ]] && printf 'web-api-1\n'
    ;;
  "compose config --images")
    [[ "$PWD" == */web ]] && printf 'ghcr.io/example/web:latest\n'
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
  "rm web-api-1")
    exit 0
    ;;
  "image rm -f ghcr.io/example/web:latest")
    exit 0
    ;;
  "image rm ghcr.io/example/web:latest")
    exit 0
    ;;
  "network rm web_default")
    exit 0
    ;;
  "volume rm web_data")
    exit 0
    ;;
  "volume inspect web_data")
    exit 0
    ;;
  "volume create web_data")
    printf 'web_data\n'
    ;;
  "compose down --rmi all")
    exit 0
    ;;
  "compose down --rmi all --volumes")
    exit 0
    ;;
  run\ --rm\ -v\ web_data:/volume:ro\ -v\ *:/backup\ alpine\ tar\ -C\ /volume\ -cf\ /backup/*)
    backup_arg=""
    backup_mount=""
    prev=""
    for arg in "$@"; do
      case "$arg" in
        *:/backup) backup_mount="${arg%:/backup}" ;;
      esac
      if [[ "$prev" == "-cf" ]]; then
        backup_arg="$arg"
        break
      fi
      prev="$arg"
    done
    backup_arg="$backup_mount/${backup_arg#/backup/}"
    mkdir -p "$(dirname "$backup_arg")"
    printf 'volume backup\n' >"$backup_arg"
    ;;
  run\ --rm\ -v\ web_data:/volume\ -v\ *:/backup\ alpine\ tar\ -C\ /volume\ -xf\ /backup/*)
    exit 0
    ;;
esac
EOF

  cat >"$FIXTURE_DIR/fakebin/7z" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '7z|%s|%s\n' "$PWD" "$*" >>"$ARCANE_TEST_LOG"

case "$1" in
  a)
    archive=""
    for arg in "$@"; do
      case "$arg" in
        *.7z) archive="$arg" ;;
      esac
    done
    [[ -n "$archive" ]] || exit 1
    rm -rf "${archive}.contents"
    mkdir -p "${archive}.contents"
    cp -a . "${archive}.contents/"
    : >"$archive"
    ;;
  x)
    archive=""
    outdir=""
    for arg in "$@"; do
      case "$arg" in
        -o*) outdir="${arg#-o}" ;;
        *.7z) archive="$arg" ;;
      esac
    done
    [[ -n "$archive" && -n "$outdir" ]] || exit 1
    mkdir -p "$outdir"
    cp -a "${archive}.contents/." "$outdir/"
    ;;
esac
EOF

  chmod +x "$FIXTURE_DIR/fakebin/docker" "$FIXTURE_DIR/fakebin/7z"
}

cleanup_fixture() {
  rm -rf "$FIXTURE_DIR"
}

complete_arcane() {
  COMP_WORDS=("$@")
  COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
  _arcane
  printf '%s\n' "${COMPREPLY[@]}" | sort -u
}

main() {
  make_fixture
  trap cleanup_fixture EXIT

  export ARCANE_DIR="$FIXTURE_DIR/arcane"
  export PATH="$FIXTURE_DIR/fakebin:$PATH"
  export SIGILS_ROOT="$(cd "$SPELL_DIR/../.." && pwd)"

  run_cmd "$ARCANE_BIN" exec -d testbox api -- echo hello
  assert_status "$CMD_STATUS" "0" "exec resolves a unique service without requiring a project"
  assert_contains "$(cat "$ARCANE_TEST_LOG")" "$FIXTURE_DIR/arcane/testbox/web|compose exec api echo hello" "exec ignores device-root compose.yaml when resolving services"

  run_cmd "$ARCANE_BIN" exec -d testbox api echo hello
  assert_status "$CMD_STATUS" "1" "exec requires the separator before the command"
  assert_contains "$CMD_OUTPUT" "requires '--' before the command" "exec explains the separator requirement"

  run_cmd "$ARCANE_BIN" exec -d testbox vibecode -- echo hello
  assert_status "$CMD_STATUS" "1" "exec rejects ambiguous service names"
  assert_contains "$CMD_OUTPUT" "matches multiple projects" "exec explains the ambiguity"
  assert_contains "$CMD_OUTPUT" "alpha" "exec ambiguity lists the first matching project"
  assert_contains "$CMD_OUTPUT" "beta" "exec ambiguity lists the second matching project"
  assert_contains "$CMD_OUTPUT" "--project" "exec points to the project selector"

  run_cmd "$ARCANE_BIN" exec -d testbox --project beta vibecode -- echo beta
  assert_status "$CMD_STATUS" "0" "exec accepts command arguments with the separator"
  assert_contains "$(cat "$ARCANE_TEST_LOG")" "$FIXTURE_DIR/arcane/testbox/beta|compose exec vibecode echo beta" "exec targets the selected project"

  source "$SPELL_DIR/completions/bash/arcane.bash"
  assert_contains "$(complete_arcane arcane exec -d testbox "")" "api" "exec completion suggests services"
  if grep -Fxq -- "--" <<<"$(complete_arcane arcane exec -d testbox "")"; then
    TEST_COUNT=$((TEST_COUNT + 1))
    printf '  completion unexpectedly included -- before the service\n'
    fail "exec completion excludes separator before service"
  else
    TEST_COUNT=$((TEST_COUNT + 1))
    pass "exec completion excludes separator before service"
  fi
  if grep -Fxq "web" <<<"$(complete_arcane arcane exec -d testbox "")"; then
    TEST_COUNT=$((TEST_COUNT + 1))
    printf '  completion unexpectedly included project: web\n'
    fail "exec completion excludes project names"
  else
    TEST_COUNT=$((TEST_COUNT + 1))
    pass "exec completion excludes project names"
  fi
  assert_contains "$(ARCANE_DEVICE=testbox complete_arcane arcane exec "")" "api" "exec completion defaults to ARCANE_DEVICE"
  assert_contains "$(complete_arcane arcane exec -d testbox --project "")" "beta" "exec completion suggests projects after --project"
  assert_contains "$(complete_arcane arcane exec -d testbox --project beta "")" "vibecode" "exec completion suggests services after selected project"
  if grep -Fxq "api" <<<"$(complete_arcane arcane exec -d testbox --project beta "")"; then
    TEST_COUNT=$((TEST_COUNT + 1))
    printf '  completion unexpectedly included service outside selected project: api\n'
    fail "exec completion filters services by selected project"
  else
    TEST_COUNT=$((TEST_COUNT + 1))
    pass "exec completion filters services by selected project"
  fi
  assert_eq "$(complete_arcane arcane exec -d testbox api "")" "--" "exec completion suggests only separator after service"

  run_cmd "$ARCANE_BIN" list -d testbox
  assert_status "$CMD_STATUS" "0" "list replaces ls"
  assert_contains "$CMD_OUTPUT" "web" "list prints discovered projects"
  if grep -Fq "testbox" <<<"$CMD_OUTPUT"; then
    TEST_COUNT=$((TEST_COUNT + 1))
    printf '  list unexpectedly included device root as project: %s\n' "$CMD_OUTPUT"
    fail "list does not treat the device root as a project"
  else
    TEST_COUNT=$((TEST_COUNT + 1))
    pass "list does not treat the device root as a project"
  fi

  run_cmd "$ARCANE_BIN" list -d testbox web
  assert_status "$CMD_STATUS" "0" "list reports project resources when a project is selected"
  assert_contains "$CMD_OUTPUT" "containers: web-api-1" "list project resources includes containers"
  assert_contains "$CMD_OUTPUT" "images: ghcr.io/example/web:latest" "list project resources includes images"
  assert_contains "$CMD_OUTPUT" "networks: web_default" "list project resources includes networks"
  assert_contains "$CMD_OUTPUT" "volumes: web_data" "list project resources includes volumes"

  run_cmd "$ARCANE_BIN" list -d testbox web containers
  assert_status "$CMD_STATUS" "0" "list filters project resources by type"
  assert_contains "$CMD_OUTPUT" "containers: web-api-1" "list project resource filter prints selected type"
  if grep -Fq "images:" <<<"$CMD_OUTPUT"; then
    TEST_COUNT=$((TEST_COUNT + 1))
    printf '  filtered list unexpectedly included images: %s\n' "$CMD_OUTPUT"
    fail "list project resource filter excludes other types"
  else
    TEST_COUNT=$((TEST_COUNT + 1))
    pass "list project resource filter excludes other types"
  fi

  run_cmd "$ARCANE_BIN" list -d testbox beta containers
  assert_status "$CMD_STATUS" "0" "list handles projects without discovered resources"
  assert_contains "$CMD_OUTPUT" "containers: -" "list prints '-' for empty resource lists"

  run_cmd "$ARCANE_BIN" archive -d testbox web
  assert_status "$CMD_STATUS" "0" "archive moves a project out of the active device"
  if [[ -d "$FIXTURE_DIR/arcane/archived/testbox/web" && ! -d "$FIXTURE_DIR/arcane/testbox/web" ]]; then
    TEST_COUNT=$((TEST_COUNT + 1))
    pass "archive stores projects under archived/device/project"
  else
    TEST_COUNT=$((TEST_COUNT + 1))
    fail "archive stores projects under archived/device/project"
  fi

  run_cmd "$ARCANE_BIN" list -d testbox --archived
  assert_status "$CMD_STATUS" "0" "list --archived lists archived projects"
  assert_contains "$CMD_OUTPUT" "web" "list --archived includes archived project names"

  run_cmd "$ARCANE_BIN" unarchive -d testbox web
  assert_status "$CMD_STATUS" "0" "unarchive restores a project to the active device"
  if [[ -d "$FIXTURE_DIR/arcane/testbox/web" && ! -d "$FIXTURE_DIR/arcane/archived/testbox/web" ]]; then
    TEST_COUNT=$((TEST_COUNT + 1))
    pass "unarchive restores projects from archived/device/project"
  else
    TEST_COUNT=$((TEST_COUNT + 1))
    fail "unarchive restores projects from archived/device/project"
  fi

  run_cmd "$ARCANE_BIN" clone --from testbox --to asmodeus web --new webcopy
  assert_status "$CMD_STATUS" "0" "clone copies a project between devices"
  if [[ -f "$FIXTURE_DIR/arcane/asmodeus/webcopy/compose.yaml" ]]; then
    TEST_COUNT=$((TEST_COUNT + 1))
    pass "clone creates the target project directory"
  else
    TEST_COUNT=$((TEST_COUNT + 1))
    fail "clone creates the target project directory"
  fi
  assert_contains "$(cat "$FIXTURE_DIR/arcane/asmodeus/webcopy/.env")" "ARCANE_DEVICE=asmodeus" "clone rewrites env device values"
  assert_contains "$(cat "$FIXTURE_DIR/arcane/asmodeus/webcopy/.env")" "ARCANE_PROJECT=webcopy" "clone rewrites env project values"
  assert_contains "$(cat "$FIXTURE_DIR/arcane/asmodeus/webcopy/.env")" "/srv/arcane/asmodeus/webcopy" "clone rewrites source project paths"

  run_cmd "$ARCANE_BIN" dump --only-env -d testbox web --output "$FIXTURE_DIR/web-env.7z"
  assert_status "$CMD_STATUS" "0" "dump --only-env supports project scope"
  assert_contains "$(cat "$ARCANE_TEST_LOG")" "testbox/web/.env" "dump includes conventional .env files"
  assert_contains "$(cat "$ARCANE_TEST_LOG")" "testbox/web/.secret" "dump includes compose env_file entries"

  run_cmd "$ARCANE_BIN" dump --volumes -d testbox web --output "$FIXTURE_DIR/web-full.7z"
  assert_status "$CMD_STATUS" "0" "dump --volumes creates a full backup"
  assert_contains "$(cat "$ARCANE_TEST_LOG")" "web_data:/volume:ro" "dump --volumes exports project volumes"
  if [[ -f "$FIXTURE_DIR/web-full.7z.contents/manifest.tsv" ]]; then
    TEST_COUNT=$((TEST_COUNT + 1))
    pass "dump writes a restore manifest"
  else
    TEST_COUNT=$((TEST_COUNT + 1))
    fail "dump writes a restore manifest"
  fi

  rm -f "$FIXTURE_DIR/arcane/testbox/web/.env" "$FIXTURE_DIR/arcane/testbox/web/.secret"
  run_cmd "$ARCANE_BIN" restore "$FIXTURE_DIR/web-full.7z"
  assert_status "$CMD_STATUS" "1" "restore refuses to overwrite existing volumes without --force"
  assert_contains "$CMD_OUTPUT" "volume already exists" "restore explains existing volume refusal"

  run_cmd "$ARCANE_BIN" restore "$FIXTURE_DIR/web-full.7z" --force
  assert_status "$CMD_STATUS" "0" "restore --force restores files and volumes"
  assert_contains "$CMD_OUTPUT" "Restored volume: web_data" "restore --force reports restored volumes"
  assert_contains "$(cat "$FIXTURE_DIR/arcane/testbox/web/.secret")" "WEB_SECRET=1" "restore restores env_file contents"

  run_cmd "$ARCANE_BIN" ps -d testbox web
  assert_status "$CMD_STATUS" "0" "ps replaces status"
  assert_contains "$(cat "$ARCANE_TEST_LOG")" "$FIXTURE_DIR/arcane/testbox/web|compose ps" "ps delegates to docker compose ps"

  run_cmd "$ARCANE_BIN" remove -d testbox web containers web-api-1
  assert_status "$CMD_STATUS" "0" "remove deletes one named project resource"
  assert_contains "$(cat "$ARCANE_TEST_LOG")" "rm web-api-1" "remove named container does not force by default"

  run_cmd "$ARCANE_BIN" remove -d testbox --force web containers web-api-1
  assert_status "$CMD_STATUS" "0" "remove accepts --force"
  assert_contains "$(cat "$ARCANE_TEST_LOG")" "rm -f web-api-1" "remove --force forces container removal"

  run_cmd "$ARCANE_BIN" remove -d testbox web images,volumes
  assert_status "$CMD_STATUS" "0" "remove accepts comma-separated resource types"
  assert_contains "$(cat "$ARCANE_TEST_LOG")" "image rm ghcr.io/example/web:latest" "remove images removes discovered images without forcing"
  assert_contains "$(cat "$ARCANE_TEST_LOG")" "volume rm web_data" "remove volumes removes discovered volumes"

  run_cmd "$ARCANE_BIN" rm -d testbox web all
  assert_status "$CMD_STATUS" "0" "rm remains available for remove"
  assert_contains "$(cat "$ARCANE_TEST_LOG")" "network rm web_default" "rm all removes discovered networks"

  run_cmd "$ARCANE_BIN" clean -d testbox web
  assert_status "$CMD_STATUS" "0" "clean keeps docker compose down semantics"
  assert_contains "$(cat "$ARCANE_TEST_LOG")" "$FIXTURE_DIR/arcane/testbox/web|compose down --rmi all" "clean stops compose project and removes images"

  run_cmd "$ARCANE_BIN" purge -d testbox web
  assert_status "$CMD_STATUS" "0" "purge keeps docker compose down semantics"
  assert_contains "$(cat "$ARCANE_TEST_LOG")" "$FIXTURE_DIR/arcane/testbox/web|compose down --rmi all --volumes" "purge stops compose project and removes volumes"

  run_cmd "$ARCANE_BIN" nginx-urls --device testbox --output "$FIXTURE_DIR/bookmarks.html"
  assert_status "$CMD_STATUS" "0" "nginx-urls replaces favorites"

  for removed in ls status path bash cd favorites resources; do
    run_cmd "$ARCANE_BIN" "$removed"
    assert_status "$CMD_STATUS" "1" "$removed is no longer a public arcane subcommand"
    assert_contains "$CMD_OUTPUT" "unknown subcommand" "$removed reports unknown subcommand"
  done

  run_cmd "$ARCANE_BIN" run -d testbox -- docker compose ps
  assert_status "$CMD_STATUS" "1" "run is rejected explicitly"
  assert_contains "$CMD_OUTPUT" "run has been removed" "run tells the caller to use exec or lifecycle commands"

  if [[ "$FAIL_COUNT" -ne 0 ]]; then
    printf '%s tests failed\n' "$FAIL_COUNT"
    exit 1
  fi

  printf '1..%s\n' "$TEST_COUNT"
}

main "$@"
