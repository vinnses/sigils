# vscreen Test Fixtures

This directory will contain static test data for vscreen unit tests.

## Purpose

Fixtures provide controlled, reproducible test inputs that allow testing without requiring:
- A real X session
- Physical or virtual displays
- xrandr installed and working
- Root privileges or system modifications

## Planned Structure

```
fixtures/
├── xrandr_outputs/
│   ├── no_virtuals.txt        # xrandr with no VIRTUAL outputs
│   ├── one_virtual_free.txt   # One VIRTUAL available
│   ├── one_virtual_active.txt # One VIRTUAL connected
│   ├── multiple_mixed.txt     # Mix of active and free VIRTUALs
│   └── all_active.txt         # All VIRTUALs in use
├── cvt_outputs/
│   ├── 1920x1080.txt          # Standard FHD output
│   ├── 2560x1440.txt          # QHD output
│   ├── 800x450.txt            # Small resolution
│   ├── 7680x4320.txt          # 8K resolution
│   └── malformed.txt          # Invalid CVT output
└── xrandr_monitor_lists/
    ├── single_monitor.txt     # One monitor layout
    ├── dual_monitor.txt       # Two monitors side-by-side
    └── complex_layout.txt     # Multiple monitors arranged
```

## Usage in Tests

Fixtures will be loaded and injected into test functions:

```bash
# Example: Mock xrandr command
xrandr() {
    cat "$FIXTURE_DIR/xrandr_outputs/one_virtual_free.txt"
}

# Then test parsing logic
source spells/vscreen/lib/vscreen/core.sh
result=$(list_free_virtuals)
assert_equals "VIRTUAL1" "$result"
```

## Creating New Fixtures

To capture real xrandr output for a fixture:

```bash
# Capture current state
xrandr > fixtures/xrandr_outputs/my_scenario.txt

# Capture with specific display active
vscreen --output 1 -r FHD
xrandr > fixtures/xrandr_outputs/virtual1_fhd.txt
vscreen --off 1
```

---

<!-- TODO(test-fixtures): Create comprehensive test fixture collection
     Need to capture various xrandr outputs representing different system states.
     
     Priority fixtures needed:
     1. Edge cases:
        - Empty VIRTUAL list (driver not loaded)
        - Single VIRTUAL output
        - 20+ VIRTUAL outputs (stress test)
     
     2. Different display states:
        - All outputs disconnected
        - Mix of physical and virtual displays
        - Rotated displays (portrait/landscape)
        - Different positions (overlapping, gaps, negative coords)
     
     3. Error conditions:
        - Malformed xrandr output
        - Missing expected fields
        - Unexpected output names
     
     4. CVT edge cases:
        - Very small resolutions (320x240)
        - Very large resolutions (15360x8640)
        - Non-standard aspect ratios
        - Refresh rates other than 60Hz
     
     Collection method:
     - Run vscreen in various scenarios
     - Capture xrandr output before and after
     - Document what each fixture represents
     - Add comments explaining expected behavior
     
     labels: testing, test-fixtures, test-data -->