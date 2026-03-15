#!/bin/bash
# ============================
# vscreen Integration Test Suite
# Version: 3.1.0
# ============================
# Scope:  Robustness and System Integration
# Target: root bin/vscreen symlink (local artifact)
# Output: spells/vscreen/logs/tests/integration/
# ============================

# TODO(test-safety): Add GDM/display-manager compatibility check
# Issue URL: https://github.com/vinnylg/sigils/issues/17
# See version 2.2.0 for full details on symptoms, root cause, and proposed solutions.
# Temporary workaround: Limit stress test to STRESS_MAX displays, always force_cleanup().

set -o pipefail

# Locates the script directory to find the project root regardless of CWD
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
SPELL_ROOT="$PROJECT_ROOT/spells/vscreen"

# We do not rely on global PATH. We test the linked root binary explicitly.
VSCREEN="$PROJECT_ROOT/bin/vscreen"

# Log Configuration
LOG_DIR="$SPELL_ROOT/logs/tests/integration"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date +"%Y%m%d%H%M%S")
LOGFILE="$LOG_DIR/${TIMESTAMP}.log"
LATEST_LINK="$LOG_DIR/latest.log"

ln -sf "$(basename "$LOGFILE")" "$LATEST_LINK"

# ============================
# Constants
# ============================
STRESS_MAX=10

# ============================
# Test Counters
# ============================
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0
FAILED_TESTS=()

# Last output captured by run_test (used by expect_output_* helpers)
LAST_OUTPUT=""
LAST_EXIT=0

# ============================
# Colors (only for terminal)
# ============================
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  CYAN='\033[0;36m'
  NC='\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' CYAN='' NC=''
fi

# ============================
# Logging Functions
# ============================
log_to_file() {
  echo "$*" | sed 's/\x1b\[[0-9;]*m//g; s/\\033\[[0-9;]*m//g' >> "$LOGFILE"
}

log() {
  echo -e "$*"
  log_to_file "$*"
}

log_section() {
  local msg="$1"
  log ""
  log "${CYAN}========================================${NC}"
  log "${CYAN}$msg${NC}"
  log "${CYAN}========================================${NC}"
}

log_test() {
  ((TEST_COUNT++))
  log ""
  log "${BLUE}[TEST $TEST_COUNT]${NC} $*"
}

log_pass() {
  ((PASS_COUNT++))
  log "${GREEN}✓ PASS${NC}: $*"
}

log_fail() {
  ((FAIL_COUNT++))
  FAILED_TESTS+=("$TEST_COUNT")
  log "${RED}✗ FAIL${NC}: $*"
}

log_info() {
  log "${YELLOW}ℹ INFO${NC}: $*"
}

log_cmd() {
  log "  $ $*"
}

# ============================
# Test Utilities
# ============================

# Runs a command, captures output, logs everything.
# Stores result in LAST_OUTPUT and LAST_EXIT for use by expect_output_* helpers.
# IMPORTANT: Uses "$@" (not "$*") to preserve argument quoting.
run_test() {
  local description="$1"
  shift

  log_test "$description"
  log_cmd "$*"

  LAST_OUTPUT=$("$@" 2>&1)
  LAST_EXIT=$?

  if [[ -n "$LAST_OUTPUT" ]]; then
    echo "$LAST_OUTPUT" | while IFS= read -r line; do
      log "    $line"
    done
  fi

  return $LAST_EXIT
}

# Expects command to succeed (exit 0).
expect_success() {
  local description="$1"
  shift

  if run_test "$description" "$@"; then
    log_pass "$description"
    return 0
  else
    log_fail "$description (exit code: $LAST_EXIT)"
    return 1
  fi
}

# Expects command to fail (exit != 0).
expect_failure() {
  local description="$1"
  shift

  if run_test "$description" "$@"; then
    log_fail "$description (should have failed but succeeded)"
    return 1
  else
    log_pass "$description (correctly failed)"
    return 0
  fi
}

# Expects command to succeed AND output to contain a fixed string.
expect_output_contains() {
  local description="$1" expected="$2"
  shift 2

  if ! run_test "$description" "$@"; then
    log_fail "$description (exit code: $LAST_EXIT)"
    return 1
  fi

  if echo "$LAST_OUTPUT" | grep -qF "$expected"; then
    log_pass "$description"
    return 0
  else
    log_fail "$description (expected output containing: $expected)"
    return 1
  fi
}

# Expects command to succeed AND output to match an extended regex.
expect_output_match() {
  local description="$1" pattern="$2"
  shift 2

  if ! run_test "$description" "$@"; then
    log_fail "$description (exit code: $LAST_EXIT)"
    return 1
  fi

  if echo "$LAST_OUTPUT" | grep -qE "$pattern"; then
    log_pass "$description"
    return 0
  else
    log_fail "$description (output did not match pattern: $pattern)"
    return 1
  fi
}

# Verifies the resolution of an active output by querying xrandr directly.
# Does NOT run vscreen — reads xrandr state independently.
verify_resolution() {
  local description="$1" output="$2" expected_wxh="$3"

  log_test "$description"

  local geom actual_wxh
  geom=$(xrandr 2>/dev/null | grep "^${output} connected" | grep -oE '[0-9]+x[0-9]+[+-][0-9]+[+-][0-9]+')

  if [[ -z "$geom" ]]; then
    log "  Expected: $expected_wxh"
    log "  Actual:   (output not active)"
    log_fail "$description ($output not active)"
    return 1
  fi

  actual_wxh="${geom%%[+-]*}"

  log "  Expected: $expected_wxh"
  log "  Actual:   $actual_wxh"

  if [[ "$actual_wxh" == "$expected_wxh" ]]; then
    log_pass "$description"
    return 0
  else
    log_fail "$description (expected $expected_wxh, got $actual_wxh)"
    return 1
  fi
}

# Returns W H X Y for an active output by querying xrandr directly.
get_output_whxy() {
  local output="$1"
  local geom
  geom=$(xrandr 2>/dev/null | grep "^${output} connected" | grep -oE '[0-9]+x[0-9]+\+[0-9]+\+[0-9]+' | head -n1)

  if [[ -z "$geom" ]]; then
    return 1
  fi

  local wh rest w h x y
  wh="${geom%%+*}"
  rest="${geom#*+}"
  w="${wh%%x*}"
  h="${wh##*x}"
  x="${rest%%+*}"
  y="${rest##*+}"

  echo "$w $h $x $y"
}

# Verifies the X,Y position of an active output by querying xrandr directly.
verify_position() {
  local description="$1" output="$2" expected_x="$3" expected_y="$4"

  log_test "$description"

  local w h x y
  if ! read -r w h x y <<< "$(get_output_whxy "$output")"; then
    log "  Expected: ${expected_x}x${expected_y}"
    log "  Actual:   (output not active)"
    log_fail "$description ($output not active)"
    return 1
  fi

  log "  Expected: ${expected_x}x${expected_y}"
  log "  Actual:   ${x}x${y}"

  if [[ "$x" == "$expected_x" && "$y" == "$expected_y" ]]; then
    log_pass "$description"
    return 0
  else
    log_fail "$description (expected ${expected_x}x${expected_y}, got ${x}x${y})"
    return 1
  fi
}

# ============================
# System Helpers
# ============================
get_active_virtuals() {
  xrandr 2>/dev/null | grep -c "^VIRTUAL[0-9]* connected"
}

get_virtual_list() {
  xrandr 2>/dev/null | awk '/^VIRTUAL[0-9]+ connected/{print $1}'
}

wait_for_xrandr() {
  sleep 0.5
}

force_cleanup() {
  log_info "Force cleanup: purging all virtual displays"
  "$VSCREEN" --purge-all &>> "$LOGFILE" || true
  wait_for_xrandr
}

# ============================
# Test Setup
# ============================
log_section "TEST SUITE INITIALIZATION"
log "Starting vscreen integration test suite v3.1.0"
log "Date: $(date)"
log "Logfile: $LOGFILE"
log "vscreen location: $VSCREEN"

if [[ ! -f "$VSCREEN" ]]; then
  log_fail "vscreen script not found at $VSCREEN"
  exit 1
fi

chmod +x "$VSCREEN"

log_info "Force cleaning up any existing virtual displays"
force_cleanup

REMAINING=$(get_active_virtuals)
if [[ $REMAINING -gt 0 ]]; then
  log_fail "Could not clean up existing displays: $REMAINING remain active"
  get_virtual_list | while read -r v; do
    log_info "  Active: $v"
  done
  exit 1
fi

log_info "Cleanup successful, starting tests"

# ============================
# TEST SECTION 1: Basic Commands
# ============================
log_section "TEST SECTION 1: Basic Commands"

expect_output_contains "Display help" "USAGE:" "$VSCREEN" --help
expect_output_contains "Display version" "3.1.0" "$VSCREEN" --version
expect_success "List all virtual outputs" "$VSCREEN" --list all
expect_success "List active virtual outputs" "$VSCREEN" --list active
expect_success "List free virtual outputs" "$VSCREEN" --list free

# ============================
# TEST SECTION 2: Invalid Arguments
# ============================
log_section "TEST SECTION 2: Invalid Arguments"

expect_failure "Invalid resolution name" "$VSCREEN" -r NOTEXIST
expect_failure "Invalid size format (missing height)" "$VSCREEN" -s 1920
expect_failure "Invalid orientation" "$VSCREEN" -o VIRTUAL1 -r FHD --orientation INVALID
expect_failure "Invalid position format" "$VSCREEN" -o VIRTUAL1 -r FHD --pos 1920
expect_failure "Missing size argument" "$VSCREEN" -s
expect_failure "Output without resolution" "$VSCREEN" -o VIRTUAL1
expect_failure "Invalid output format" "$VSCREEN" -o ABC -r FHD
expect_failure "Invalid ratio format" "$VSCREEN" -o VIRTUAL1 -r FHD --ratio 16:9
expect_failure "Invalid per format" "$VSCREEN" -o VIRTUAL1 -r FHD --per abc
expect_failure "Deactivate non-existent VIRTUAL99" "$VSCREEN" --off VIRTUAL99
expect_failure "Change non-existent VIRTUAL99" "$VSCREEN" -c VIRTUAL99 -r FHD
expect_failure "Purge non-existent VIRTUAL99" "$VSCREEN" --purge VIRTUAL99

# ============================
# TEST SECTION 3: Resolution Presets
# ============================
log_section "TEST SECTION 3: Resolution Presets"

expect_output_contains "List resolution presets" "FHD" "$VSCREEN" -r

log_info "Testing predefined resolutions by name"
declare -a preset_names=("FHD" "HD+" "HD" "HD10" "HD+10" "SD")

for i in "${!preset_names[@]}"; do
  name="${preset_names[$i]}"
  vnum=$((i + 1))
  expect_success "Activate VIRTUAL${vnum} with preset $name" "$VSCREEN" -o "VIRTUAL${vnum}" -r "$name"
  wait_for_xrandr
done

log_info "Current active displays:"
get_virtual_list | tee -a "$LOGFILE"

expect_success "Deactivate all displays" "$VSCREEN" --off-all
wait_for_xrandr
force_cleanup

# ============================
# TEST SECTION 4: Custom Resolutions (--size)
# ============================
log_section "TEST SECTION 4: Custom Resolutions"

declare -a custom_resolutions=(
  "1920x1080"
  "2560x1440"
  "1024x768"
)

for i in "${!custom_resolutions[@]}"; do
  res="${custom_resolutions[$i]}"
  vnum=$((i + 1))
  expect_success "Activate VIRTUAL${vnum} with custom size $res" "$VSCREEN" -o "VIRTUAL${vnum}" -s "$res"
  wait_for_xrandr
  verify_resolution "Verify VIRTUAL${vnum} resolution $res" "VIRTUAL${vnum}" "$res"
done

expect_success "Deactivate all displays" "$VSCREEN" --off-all
wait_for_xrandr
force_cleanup

# ============================
# TEST SECTION 5: Orientations
# ============================
log_section "TEST SECTION 5: Orientations"

# Format: mode:alias:expected_wxh
# right/left swap dimensions, normal/inverted keep them
declare -a orientations=(
  "normal:L:1920x1080"
  "right:PR:1080x1920"
  "left:PL:1080x1920"
  "inverted:LF:1920x1080"
)

for orient in "${orientations[@]}"; do
  IFS=':' read -r mode alias expected_wxh <<< "$orient"

  expect_success "Activate with orientation $mode" "$VSCREEN" -o VIRTUAL1 -r FHD --orientation "$mode"
  wait_for_xrandr
  verify_resolution "Verify orientation $mode → $expected_wxh" VIRTUAL1 "$expected_wxh"
  expect_success "Deactivate" "$VSCREEN" --off VIRTUAL1
  wait_for_xrandr

  expect_success "Activate with orientation alias $alias" "$VSCREEN" -o VIRTUAL1 -r FHD --orientation "$alias"
  wait_for_xrandr
  verify_resolution "Verify orientation $alias → $expected_wxh" VIRTUAL1 "$expected_wxh"
  expect_success "Deactivate" "$VSCREEN" --off VIRTUAL1
  wait_for_xrandr
done

force_cleanup

# ============================
# TEST SECTION 6: Change Command
# ============================
log_section "TEST SECTION 6: Change Command"

expect_success "Activate VIRTUAL1 with FHD" "$VSCREEN" -o VIRTUAL1 -r FHD
wait_for_xrandr

expect_success "Change VIRTUAL1 to HD" "$VSCREEN" -c VIRTUAL1 -r HD
wait_for_xrandr

expect_success "Change VIRTUAL1 orientation to right" "$VSCREEN" -c VIRTUAL1 --orientation right
wait_for_xrandr
verify_resolution "Verify change orientation right" VIRTUAL1 "768x1368"

expect_success "Change VIRTUAL1 orientation back to normal" "$VSCREEN" -c VIRTUAL1 --orientation normal
wait_for_xrandr

expect_failure "Change inactive VIRTUAL2" "$VSCREEN" -c VIRTUAL2 -r HD

# Auto-select with single active
expect_success "Change (auto-select) to HD+" "$VSCREEN" -c -r HD+
wait_for_xrandr

expect_success "Deactivate VIRTUAL1" "$VSCREEN" --off VIRTUAL1
wait_for_xrandr
force_cleanup

# ============================
# TEST SECTION 7: Positioning
# ============================
log_section "TEST SECTION 7: Positioning"

PRIMARY=$(xrandr 2>/dev/null | awk '/primary/ && /^[A-Z]/ {print $1; exit}')
log_info "Primary output detected: ${PRIMARY:-none}"

if [[ -n "$PRIMARY" && ! "$PRIMARY" =~ ^VIRTUAL ]]; then
  # Get primary geometry for position validation
  PRIMARY_GEOM=$(xrandr 2>/dev/null | grep "^${PRIMARY} connected" | grep -oE '[0-9]+x[0-9]+[+-][0-9]+[+-][0-9]+')
  PRIMARY_W="" PRIMARY_H="" PRIMARY_X="" PRIMARY_Y=""
  if [[ "$PRIMARY_GEOM" =~ ^([0-9]+)x([0-9]+)([+-][0-9]+)([+-][0-9]+)$ ]]; then
    PRIMARY_W="${BASH_REMATCH[1]}"
    PRIMARY_H="${BASH_REMATCH[2]}"
    PRIMARY_X="${BASH_REMATCH[3]#+}"
    PRIMARY_Y="${BASH_REMATCH[4]#+}"
  else
    log_info "Could not parse primary geometry: $PRIMARY_GEOM"
  fi
  log_info "Primary geometry: ${PRIMARY_W}x${PRIMARY_H}+${PRIMARY_X}+${PRIMARY_Y}"

  # right-of center
  expect_success "Position right-of $PRIMARY (default center)" \
    "$VSCREEN" -o VIRTUAL1 -r FHD --right-of "$PRIMARY"
  wait_for_xrandr
  expect_output_contains "Verify --get-pos shows VIRTUAL1" "VIRTUAL1" "$VSCREEN" --get-pos VIRTUAL1
  expect_success "Deactivate" "$VSCREEN" --off VIRTUAL1
  wait_for_xrandr

  # right-of top: X = PRIMARY_X + PRIMARY_W, Y = PRIMARY_Y
  expect_success "Position right-of $PRIMARY top" \
    "$VSCREEN" -o VIRTUAL1 -r FHD --right-of "$PRIMARY" top
  wait_for_xrandr
  EXPECTED_X=$((PRIMARY_X + PRIMARY_W))
  EXPECTED_Y=$PRIMARY_Y
  expect_output_match "Verify right-of top position" \
    "VIRTUAL1.*${EXPECTED_X}.*${EXPECTED_Y}" \
    "$VSCREEN" --get-pos VIRTUAL1
  expect_success "Deactivate" "$VSCREEN" --off VIRTUAL1
  wait_for_xrandr

  # right-of bottom: X = PRIMARY_X + PRIMARY_W, Y = PRIMARY_Y + PRIMARY_H - VH
  expect_success "Position right-of $PRIMARY bottom" \
    "$VSCREEN" -o VIRTUAL1 -r FHD --right-of "$PRIMARY" bottom
  wait_for_xrandr
  expect_output_contains "Verify right-of bottom shows VIRTUAL1" "VIRTUAL1" "$VSCREEN" --get-pos VIRTUAL1
  expect_success "Deactivate" "$VSCREEN" --off VIRTUAL1
  wait_for_xrandr

  # left-of center
  expect_success "Position left-of $PRIMARY center" \
    "$VSCREEN" -o VIRTUAL1 -r FHD --left-of "$PRIMARY" center
  wait_for_xrandr
  expect_output_contains "Verify left-of shows VIRTUAL1" "VIRTUAL1" "$VSCREEN" --get-pos VIRTUAL1
  expect_success "Deactivate" "$VSCREEN" --off VIRTUAL1
  wait_for_xrandr

  # above-of center
  expect_success "Position above-of $PRIMARY center" \
    "$VSCREEN" -o VIRTUAL1 -r HD+10 --above-of "$PRIMARY" center
  wait_for_xrandr
  expect_output_contains "Verify above-of shows VIRTUAL1" "VIRTUAL1" "$VSCREEN" --get-pos VIRTUAL1
  expect_success "Deactivate" "$VSCREEN" --off VIRTUAL1
  wait_for_xrandr

  # below-of right
  expect_success "Position below-of $PRIMARY right" \
    "$VSCREEN" -o VIRTUAL1 -r HD+10 --below-of "$PRIMARY" right
  wait_for_xrandr
  expect_output_contains "Verify below-of shows VIRTUAL1" "VIRTUAL1" "$VSCREEN" --get-pos VIRTUAL1
  expect_success "Deactivate" "$VSCREEN" --off VIRTUAL1
  wait_for_xrandr
fi

# Absolute position
expect_success "Absolute position 1920x0" "$VSCREEN" -o VIRTUAL1 -r FHD --pos 1920x0
wait_for_xrandr
verify_resolution "Verify absolute position resolution" VIRTUAL1 "1920x1080"
expect_success "Deactivate" "$VSCREEN" --off VIRTUAL1
wait_for_xrandr

# Auto-positioning with multiple displays
expect_success "Activate VIRTUAL1" "$VSCREEN" -o VIRTUAL1 -r FHD
wait_for_xrandr
expect_success "Activate VIRTUAL2 (auto-position)" "$VSCREEN" -o VIRTUAL2 -r HD+
wait_for_xrandr
expect_success "Activate VIRTUAL3 (auto-position)" "$VSCREEN" -o VIRTUAL3 -r HD
wait_for_xrandr

log_info "Current display layout:"
xrandr --listmonitors 2>/dev/null | tee -a "$LOGFILE"
"$VSCREEN" --get-pos 2>&1 | tee -a "$LOGFILE"

expect_success "Deactivate all" "$VSCREEN" --off-all
wait_for_xrandr
force_cleanup

# ============================
# TEST SECTION 8: --get-pos Validation
# ============================
log_section "TEST SECTION 8: --get-pos"

expect_success "Get all display positions (no virtuals)" "$VSCREEN" --get-pos

expect_success "Activate VIRTUAL1" "$VSCREEN" -o VIRTUAL1 -r FHD
wait_for_xrandr

expect_output_contains "Get position of VIRTUAL1" "VIRTUAL1" "$VSCREEN" --get-pos VIRTUAL1

if [[ -n "$PRIMARY" ]]; then
  expect_output_contains "Get position of $PRIMARY" "$PRIMARY" "$VSCREEN" --get-pos "$PRIMARY"
fi

expect_success "Deactivate" "$VSCREEN" --off VIRTUAL1
wait_for_xrandr
force_cleanup

# ============================
# TEST SECTION 9: --ratio Transform
# ============================
log_section "TEST SECTION 9: Ratio Transform"

# FHD 1920x1080 + 5:3x (fix width, H = 1920*3/5 = 1152)
expect_output_match "FHD with ratio 5:3x (fix width)" \
  "After ratio: 1920x1152" \
  "$VSCREEN" -o VIRTUAL1 -r FHD --ratio 5:3x --debug
wait_for_xrandr
verify_resolution "Verify 5:3x → 1920x1152" VIRTUAL1 "1920x1152"
expect_success "Deactivate" "$VSCREEN" --off VIRTUAL1
wait_for_xrandr

# FHD 1920x1080 + 5x:3 (fix height, W = 1080*5/3 = 1800)
expect_output_match "FHD with ratio 5x:3 (fix height)" \
  "After ratio: 1800x1080" \
  "$VSCREEN" -o VIRTUAL1 -r FHD --ratio 5x:3 --debug
wait_for_xrandr
verify_resolution "Verify 5x:3 → 1800x1080" VIRTUAL1 "1800x1080"
expect_success "Deactivate" "$VSCREEN" --off VIRTUAL1
wait_for_xrandr

# FHD 1920x1080 + 16:10x (fix width, H = 1920*10/16 = 1200)
expect_output_match "FHD with ratio 16:10x" \
  "After ratio: 1920x1200" \
  "$VSCREEN" -o VIRTUAL1 -r FHD --ratio 16:10x --debug
wait_for_xrandr
verify_resolution "Verify 16:10x → 1920x1200" VIRTUAL1 "1920x1200"
expect_success "Deactivate" "$VSCREEN" --off VIRTUAL1
wait_for_xrandr

expect_failure "Invalid ratio format W:H (no x marker)" \
  "$VSCREEN" -o VIRTUAL1 -r FHD --ratio 16:9

force_cleanup

# ============================
# TEST SECTION 10: --per Scale Transform
# ============================
log_section "TEST SECTION 10: Percentage Scale Transform"

# FHD * 80% = 1536x864
expect_output_match "FHD at 80 (scale)" \
  "After percentage: 1536x864" \
  "$VSCREEN" -o VIRTUAL1 -r FHD --per 80 --debug
wait_for_xrandr
verify_resolution "Verify 80% → 1536x864" VIRTUAL1 "1536x864"
expect_success "Deactivate" "$VSCREEN" --off VIRTUAL1
wait_for_xrandr

# FHD * 120% = 2304x1296
expect_output_match "FHD at 120 (scale)" \
  "After percentage: 2304x1296" \
  "$VSCREEN" -o VIRTUAL1 -r FHD --per 120 --debug
wait_for_xrandr
verify_resolution "Verify 120% → 2304x1296" VIRTUAL1 "2304x1296"
expect_success "Deactivate" "$VSCREEN" --off VIRTUAL1
wait_for_xrandr

# 1920x1080 * 50% = 960x540
expect_output_match "Custom size at 50 (scale)" \
  "After percentage: 960x540" \
  "$VSCREEN" -o VIRTUAL1 -s 1920x1080 --per 50 --debug
wait_for_xrandr
verify_resolution "Verify 50% → 960x540" VIRTUAL1 "960x540"
expect_success "Deactivate" "$VSCREEN" --off VIRTUAL1
wait_for_xrandr

force_cleanup

# ============================
# TEST SECTION 11: --per Density Transform (1/N)
# ============================
log_section "TEST SECTION 11: Density Transform (--per 1/N)"

# 2000x1200 / 1.5 → 1334x800 (debug), xrandr may round width to multiple of 8
expect_output_match "2000x1200 with density 1/150 (tablet)" \
  "After percentage: 1334x800" \
  "$VSCREEN" -o VIRTUAL1 -s 2000x1200 --per 1/150 --debug
wait_for_xrandr
expect_output_contains "Verify density 1/150 active" "VIRTUAL1" "$VSCREEN" --get-pos VIRTUAL1
expect_success "Deactivate" "$VSCREEN" --off VIRTUAL1
wait_for_xrandr

# 2560x1600 / 2.0 → 1280x800
expect_output_match "2560x1600 with density 1/200 (hdpi tablet)" \
  "After percentage: 1280x800" \
  "$VSCREEN" -o VIRTUAL1 -s 2560x1600 --per 1/200 --debug
wait_for_xrandr
verify_resolution "Verify density 1/200 → 1280x800" VIRTUAL1 "1280x800"
expect_success "Deactivate" "$VSCREEN" --off VIRTUAL1
wait_for_xrandr

# 1920x1200 / 1.0 → 1920x1200 (no change)
expect_output_match "1920x1200 with density 1/100 (no change)" \
  "After percentage: 1920x1200" \
  "$VSCREEN" -o VIRTUAL1 -s 1920x1200 --per 1/100 --debug
wait_for_xrandr
verify_resolution "Verify density 1/100 → 1920x1200" VIRTUAL1 "1920x1200"
expect_success "Deactivate" "$VSCREEN" --off VIRTUAL1
wait_for_xrandr

expect_failure "Density 1/0 (division by zero)" \
  "$VSCREEN" -o VIRTUAL1 -s 1920x1080 --per 1/0

force_cleanup

# ============================
# TEST SECTION 12: Combined Transforms
# ============================
log_section "TEST SECTION 12: Combined Transforms (ratio + per)"

# FHD + 5:3x → 1920x1152, then * 80% → 1536x922
expect_output_match "FHD + ratio 5:3x + per 80" \
  "After percentage: 1536x922" \
  "$VSCREEN" -o VIRTUAL1 -r FHD --ratio 5:3x --per 80 --debug
wait_for_xrandr
expect_output_contains "Verify combined transform active" "VIRTUAL1" "$VSCREEN" --get-pos VIRTUAL1
expect_success "Deactivate" "$VSCREEN" --off VIRTUAL1
wait_for_xrandr

# Change with transforms from current resolution
# Activate FHD (1920x1080), then change --per 80 → 1536x864
expect_success "Activate VIRTUAL1 with FHD" "$VSCREEN" -o VIRTUAL1 -r FHD
wait_for_xrandr
expect_output_match "Change VIRTUAL1 --per 80" \
  "After percentage: 1536x864" \
  "$VSCREEN" -c VIRTUAL1 --per 80 --debug
wait_for_xrandr
verify_resolution "Verify change --per 80 → 1536x864" VIRTUAL1 "1536x864"
expect_success "Deactivate" "$VSCREEN" --off VIRTUAL1
wait_for_xrandr

force_cleanup

# ============================
# TEST SECTION 13: Resolution Management
# ============================
log_section "TEST SECTION 13: Resolution Management"

expect_success "Save custom resolution" "$VSCREEN" -s 1600x1000 --save TestRes -f
expect_output_contains "List presets (verify TestRes)" "TestRes" "$VSCREEN" -r

# Verify TestRes works
expect_success "Use saved resolution TestRes" "$VSCREEN" -o VIRTUAL1 -r TestRes
wait_for_xrandr
expect_success "Deactivate" "$VSCREEN" --off VIRTUAL1
wait_for_xrandr

# Save resolution from active output
expect_success "Activate VIRTUAL1 with FHD" "$VSCREEN" -o VIRTUAL1 -r FHD
wait_for_xrandr
expect_success "Save current resolution of VIRTUAL1" "$VSCREEN" -o VIRTUAL1 --save FromOutput -f
expect_output_contains "List presets (verify FromOutput)" "FromOutput" "$VSCREEN" -r
expect_success "Deactivate" "$VSCREEN" --off VIRTUAL1
wait_for_xrandr

# Save with transforms
expect_success "Save transformed resolution" "$VSCREEN" -s 1920x1080 --ratio 5:3x --per 80 --save TransRes -f
expect_output_contains "List presets (verify TransRes)" "TransRes" "$VSCREEN" -r

# Save with --desc
expect_success "Save with description" \
  "$VSCREEN" -s 2000x1200 --per 1/150 --save Tab10 --desc "Galaxy Tab S6 Lite" -f
expect_output_contains "List presets (verify Tab10)" "Tab10" "$VSCREEN" -r
expect_output_contains "Verify Tab10 description" "Galaxy Tab S6 Lite" "$VSCREEN" -r

# Delete
expect_success "Delete TestRes" "$VSCREEN" -r --del TestRes
expect_success "Delete FromOutput" "$VSCREEN" -r --del FromOutput
expect_success "Delete TransRes" "$VSCREEN" -r --del TransRes
expect_success "Delete Tab10" "$VSCREEN" -r --del Tab10
expect_failure "Delete non-existent preset" "$VSCREEN" -r --del NOPE

force_cleanup

# ============================
# TEST SECTION 14: Layout Management
# ============================
log_section "TEST SECTION 14: Layout Management"

if command -v autorandr &>/dev/null; then
  # Create a multi-display setup
  expect_success "Activate VIRTUAL1 with FHD" "$VSCREEN" -o VIRTUAL1 -r FHD
  wait_for_xrandr
  expect_success "Activate VIRTUAL2 with HD+10" "$VSCREEN" -o VIRTUAL2 -r HD+10
  wait_for_xrandr

  log_info "Layout to save:"
  "$VSCREEN" --get-pos 2>&1 | tee -a "$LOGFILE"

  # Save layout
  expect_success "Save layout" "$VSCREEN" -l --save test-layout -f

  # List layouts
  expect_output_contains "List layouts (verify test-layout)" "test-layout" "$VSCREEN" -l

  # Purge and reload
  expect_success "Purge all" "$VSCREEN" --purge-all
  wait_for_xrandr

  expect_success "Load layout" "$VSCREEN" -l test-layout
  wait_for_xrandr

  log_info "Layout after load:"
  "$VSCREEN" --get-pos 2>&1 | tee -a "$LOGFILE"
  xrandr --listmonitors 2>/dev/null | tee -a "$LOGFILE"

  # Cleanup layout
  expect_success "Delete layout" "$VSCREEN" -l --del test-layout
  expect_failure "Delete non-existent layout" "$VSCREEN" -l --del NOPE

  force_cleanup
else
  log_info "autorandr not installed, skipping layout tests"
fi

# ============================
# TEST SECTION 15: --save as layout shortcut
# ============================
log_section "TEST SECTION 15: --save Shortcut"

if command -v autorandr &>/dev/null; then
  expect_success "Activate VIRTUAL1" "$VSCREEN" -o VIRTUAL1 -r FHD
  wait_for_xrandr

  expect_success "Save layout via --save shortcut" "$VSCREEN" --save shortcut-test -f
  expect_success "Deactivate" "$VSCREEN" --off VIRTUAL1
  wait_for_xrandr

  expect_output_contains "List layouts (verify shortcut-test)" "shortcut-test" "$VSCREEN" -l

  expect_success "Delete shortcut-test layout" "$VSCREEN" -l --del shortcut-test
  force_cleanup
else
  log_info "autorandr not installed, skipping --save shortcut test"
fi

# ============================
# TEST SECTION 16: Auto-select output
# ============================
log_section "TEST SECTION 16: Auto-select Output"

expect_success "Auto-select with -r FHD" "$VSCREEN" -r FHD
wait_for_xrandr

log_info "Auto-selected output:"
get_virtual_list | tee -a "$LOGFILE"

expect_success "Auto-select with -s 1280x800" "$VSCREEN" -s 1280x800
wait_for_xrandr

log_info "Active displays:"
get_virtual_list | tee -a "$LOGFILE"

expect_success "Deactivate all" "$VSCREEN" --off-all
wait_for_xrandr
force_cleanup

# ============================
# TEST SECTION 17: Stress Test
# ============================
log_section "TEST SECTION 17: Stress Test - $STRESS_MAX Displays"

log_info "Attempting to activate $STRESS_MAX virtual displays"

preset_cycle=("FHD" "HD+" "HD" "HD10" "HD+10" "SD")

for i in $(seq 1 $STRESS_MAX); do
  res_name="${preset_cycle[$(( (i - 1) % ${#preset_cycle[@]} ))]}"
  expect_success "Stress: activate VIRTUAL${i} with $res_name" \
    "$VSCREEN" -o "VIRTUAL${i}" -r "$res_name"
  wait_for_xrandr
done

ACTIVE_COUNT=$(get_active_virtuals)
log_info "Total active displays: $ACTIVE_COUNT"

log_test "Stress verification: active count = $STRESS_MAX"
if [[ $ACTIVE_COUNT -eq $STRESS_MAX ]]; then
  log_pass "Active count matches ($ACTIVE_COUNT)"
else
  log_fail "Active count mismatch: expected $STRESS_MAX, got $ACTIVE_COUNT"
fi

force_cleanup

# ============================
# TEST SECTION 18: Edge Cases
# ============================
log_section "TEST SECTION 18: Edge Cases"

# Activate one for reactivation test
"$VSCREEN" -o VIRTUAL1 -r FHD &>> "$LOGFILE"
wait_for_xrandr

expect_failure "Activate already active VIRTUAL1" "$VSCREEN" -o VIRTUAL1 -r HD

# Dry-run should succeed without side effects
expect_output_contains "Dry-run activate" "[dry-run]" "$VSCREEN" -o VIRTUAL2 -r FHD --dry-run

# Debug output should contain debug markers
expect_output_contains "Debug mode" "[debug]" "$VSCREEN" -o VIRTUAL2 -r FHD --debug
wait_for_xrandr

force_cleanup

# ============================
# TEST SECTION 19: Layout Commands (--align/--tile/--pack)
# ============================
log_section "TEST SECTION 19: Layout Commands (--align/--tile/--pack)"

# Pick an anchor position safely to the right of all non-virtual connected outputs
ANCHOR_X=$(
  xrandr 2>/dev/null | awk '
    /^VIRTUAL[0-9]+/ {next}
    / connected/ {
      if (match($0, /([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+)/, a)) {
        r = a[3] + a[1]
        if (r > max) max = r
      }
    }
    END { if (max < 1) max = 2000; print max + 50 }
  '
)
ANCHOR_Y=0
log_info "Layout-test anchor: ${ANCHOR_X}x${ANCHOR_Y}"

# ---- A) --align (with perpendicular push on overlap) ----
force_cleanup

expect_success "Activate VIRTUAL1 (FHD) at anchor" "$VSCREEN" -o VIRTUAL1 -r FHD --pos "${ANCHOR_X}x${ANCHOR_Y}"
wait_for_xrandr

V2_X=$((ANCHOR_X + 2200))
expect_success "Activate VIRTUAL2 (HD) offset from anchor" "$VSCREEN" -o VIRTUAL2 -r HD --pos "${V2_X}x200"
wait_for_xrandr

read -r W1 H1 X1 Y1 <<< "$(get_output_whxy VIRTUAL1)"
read -r W2 H2 X2 Y2 <<< "$(get_output_whxy VIRTUAL2)"

expect_success "Align top: VIRTUAL1,VIRTUAL2" "$VSCREEN" --align VIRTUAL1,VIRTUAL2 top
wait_for_xrandr
verify_position "Verify VIRTUAL2 aligned to top of VIRTUAL1" VIRTUAL2 "$X2" "$Y1"

# Non-overlapping left align (VIRTUAL2 below VIRTUAL1)
V2_BELOW_Y=$((Y1 + H1 + 120))
expect_success "Move VIRTUAL2 below VIRTUAL1" "$VSCREEN" -c VIRTUAL2 --pos "${X2}x${V2_BELOW_Y}"
wait_for_xrandr
expect_success "Align left: VIRTUAL1,VIRTUAL2 (no overlap)" "$VSCREEN" --align VIRTUAL1,VIRTUAL2 left
wait_for_xrandr
verify_position "Verify VIRTUAL2 aligned to left of VIRTUAL1 (Y preserved)" VIRTUAL2 "$X1" "$V2_BELOW_Y"

# Overlap case: left-align should push along Y (perpendicular) to resolve collision
expect_success "Move VIRTUAL2 to overlap VIRTUAL1 in Y" "$VSCREEN" -c VIRTUAL2 --pos "${X2}x${Y1}"
wait_for_xrandr
expect_success "Align left: VIRTUAL1,VIRTUAL2 (forces perpendicular push)" "$VSCREEN" --align VIRTUAL1,VIRTUAL2 left
wait_for_xrandr
EXPECTED_PUSH_Y=$((Y1 + H1))
verify_position "Verify VIRTUAL2 pushed down to avoid overlap" VIRTUAL2 "$X1" "$EXPECTED_PUSH_Y"

force_cleanup

# ---- B) --tile ----
expect_success "Activate VIRTUAL1 (FHD) at anchor" "$VSCREEN" -o VIRTUAL1 -r FHD --pos "${ANCHOR_X}x${ANCHOR_Y}"
wait_for_xrandr
expect_success "Activate VIRTUAL2 (HD)" "$VSCREEN" -o VIRTUAL2 -r HD --pos "$((ANCHOR_X + 2600))x0"
wait_for_xrandr
expect_success "Activate VIRTUAL3 (SD)" "$VSCREEN" -o VIRTUAL3 -r SD --pos "$((ANCHOR_X + 3600))x0"
wait_for_xrandr

read -r W1 H1 X1 Y1 <<< "$(get_output_whxy VIRTUAL1)"
read -r W2 H2 X2 Y2 <<< "$(get_output_whxy VIRTUAL2)"
read -r W3 H3 X3 Y3 <<< "$(get_output_whxy VIRTUAL3)"

expect_success "Tile horizontally (x): VIRTUAL1,VIRTUAL2,VIRTUAL3" "$VSCREEN" --tile x VIRTUAL1,VIRTUAL2,VIRTUAL3
wait_for_xrandr

EXPECTED_X2=$((X1 + W1))
EXPECTED_X3=$((EXPECTED_X2 + W2))
verify_position "Verify tile-x: VIRTUAL1 position preserved" VIRTUAL1 "$X1" "$Y1"
verify_position "Verify tile-x: VIRTUAL2 placed after VIRTUAL1" VIRTUAL2 "$EXPECTED_X2" "$Y1"
verify_position "Verify tile-x: VIRTUAL3 placed after VIRTUAL2" VIRTUAL3 "$EXPECTED_X3" "$Y1"

force_cleanup

# Vertical tile with explicit reference: stack VIRTUAL2,VIRTUAL3 below VIRTUAL1
expect_success "Activate VIRTUAL1 (FHD) at anchor" "$VSCREEN" -o VIRTUAL1 -r FHD --pos "${ANCHOR_X}x${ANCHOR_Y}"
wait_for_xrandr
expect_success "Activate VIRTUAL2 (SD)" "$VSCREEN" -o VIRTUAL2 -r SD --pos "$((ANCHOR_X + 2600))x0"
wait_for_xrandr
expect_success "Activate VIRTUAL3 (SD)" "$VSCREEN" -o VIRTUAL3 -r SD --pos "$((ANCHOR_X + 3600))x0"
wait_for_xrandr

read -r W1 H1 X1 Y1 <<< "$(get_output_whxy VIRTUAL1)"
read -r W2 H2 X2 Y2 <<< "$(get_output_whxy VIRTUAL2)"

expect_success "Tile vertically (y) VIRTUAL2,VIRTUAL3 starting at VIRTUAL1" "$VSCREEN" --tile y VIRTUAL2,VIRTUAL3 VIRTUAL1
wait_for_xrandr

EXPECTED_V2_Y=$((Y1 + H1))
EXPECTED_V3_Y=$((EXPECTED_V2_Y + H2))
verify_position "Verify tile-y: VIRTUAL2 stacked below VIRTUAL1" VIRTUAL2 "$X1" "$EXPECTED_V2_Y"
verify_position "Verify tile-y: VIRTUAL3 stacked below VIRTUAL2" VIRTUAL3 "$X1" "$EXPECTED_V3_Y"

force_cleanup

# ---- C) --pack (shelf pack with obstacle) ----
expect_success "Activate VIRTUAL1 (FHD) at anchor" "$VSCREEN" -o VIRTUAL1 -r FHD --pos "${ANCHOR_X}x${ANCHOR_Y}"
wait_for_xrandr
read -r W1 H1 X1 Y1 <<< "$(get_output_whxy VIRTUAL1)"
SLOT_X=$((X1 + W1))

# Obstacle occupies the first pack slot
expect_success "Activate obstacle VIRTUAL2 (HD) at first pack slot" "$VSCREEN" -o VIRTUAL2 -r HD --pos "${SLOT_X}x${Y1}"
wait_for_xrandr

# VIRTUAL3 will be packed relative to VIRTUAL1 and must avoid VIRTUAL2
expect_success "Activate VIRTUAL3 (SD)" "$VSCREEN" -o VIRTUAL3 -r SD --pos "$((SLOT_X + 2400))x${Y1}"
wait_for_xrandr

read -r _ H_OBST _ _ <<< "$(get_output_whxy VIRTUAL2)"
read -r _ H_ITEM _ _ <<< "$(get_output_whxy VIRTUAL3)"

expect_success "Pack VIRTUAL3 relative to VIRTUAL1 (must avoid obstacle)" "$VSCREEN" --pack VIRTUAL1,VIRTUAL3
wait_for_xrandr

# Expected: same slot X, and Y bumped in steps of H_ITEM until >= obstacle height
K=$(((H_OBST + H_ITEM - 1) / H_ITEM))
EXPECTED_PACK_Y=$((Y1 + K * H_ITEM))
verify_position "Verify pack: VIRTUAL3 placed at slot X and bumped below obstacle" VIRTUAL3 "$SLOT_X" "$EXPECTED_PACK_Y"

force_cleanup

# ============================
# TEST SECTION 20: Complex Scenarios
# ============================
log_section "TEST SECTION 20: Complex Scenarios"

log_info "Scenario: Multiple displays with different configs"

expect_success "VIRTUAL1: FHD landscape" "$VSCREEN" -o VIRTUAL1 -r FHD --orientation normal
wait_for_xrandr
verify_resolution "Verify VIRTUAL1 FHD landscape" VIRTUAL1 "1920x1080"

expect_success "VIRTUAL2: HD portrait right" "$VSCREEN" -o VIRTUAL2 -r HD --orientation right
wait_for_xrandr
# HD creates mode ~1368x768, rotated right → 768xH
# Width and height swap on rotation; verify via get-pos that it's active
expect_output_contains "Verify VIRTUAL2 portrait active" "VIRTUAL2" "$VSCREEN" --get-pos VIRTUAL2

expect_success "VIRTUAL3: Custom 2560x1440" "$VSCREEN" -o VIRTUAL3 -s 2560x1440 --orientation normal
wait_for_xrandr
verify_resolution "Verify VIRTUAL3 2560x1440" VIRTUAL3 "2560x1440"

log_info "Current complex setup:"
xrandr --listmonitors 2>/dev/null | tee -a "$LOGFILE"
"$VSCREEN" --get-pos 2>&1 | tee -a "$LOGFILE"

expect_success "Change VIRTUAL2 to landscape" "$VSCREEN" -c VIRTUAL2 --orientation normal
wait_for_xrandr

expect_success "Change VIRTUAL1 to HD+" "$VSCREEN" -c VIRTUAL1 -r HD+
wait_for_xrandr

log_info "After changes:"
xrandr --listmonitors 2>/dev/null | tee -a "$LOGFILE"
"$VSCREEN" --get-pos 2>&1 | tee -a "$LOGFILE"

# ============================
# FINAL CLEANUP
# ============================
log_section "FINAL CLEANUP"

log_info "Final force cleanup"
force_cleanup

log_info "Purging all custom modes"
expect_success "Purge all" "$VSCREEN" --purge-all

log_info "Final state verification"
FINAL_ACTIVE=$(get_active_virtuals)
log_info "Active virtual displays after cleanup: $FINAL_ACTIVE"

log_test "All displays successfully deactivated"
if [[ $FINAL_ACTIVE -eq 0 ]]; then
  log_pass "All displays successfully deactivated"
else
  log_fail "Some displays remain active: $FINAL_ACTIVE"
  get_virtual_list | while read -r v; do
    log_info "  Still active: $v"
  done
fi

# ============================
# TEST SUMMARY
# ============================
log_section "TEST SUMMARY"

log ""
log "Total tests run: $TEST_COUNT"
log "${GREEN}Passed: $PASS_COUNT${NC}"
log "${RED}Failed: $FAIL_COUNT${NC}"

if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
  log "Failed tests: $(printf '%s, ' "${FAILED_TESTS[@]}" | sed 's/, $//')"
fi

if [[ $FAIL_COUNT -eq 0 ]]; then
  log ""
  log "${GREEN}========================================${NC}"
  log "${GREEN}   ALL TESTS PASSED SUCCESSFULLY! ✓${NC}"
  log "${GREEN}========================================${NC}"
  log ""
  log "Full log available at: $LOGFILE"
  exit 0
else
  PASS_RATE=$((PASS_COUNT * 100 / TEST_COUNT))
  log ""
  log "${YELLOW}========================================${NC}"
  log "${YELLOW}   SOME TESTS FAILED${NC}"
  log "${YELLOW}   Pass rate: ${PASS_RATE}%${NC}"
  log "${YELLOW}========================================${NC}"
  log ""
  log "Full log available at: $LOGFILE"
  exit 1
fi
