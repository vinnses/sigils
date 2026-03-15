# vscreen - Installation and Usage Guide

## Project Structure

```
.
├── bin/
│   └── vscreen                 # Main executable
├── completions/
│   └── bash/
│       └── vscreen.bash        # Bash completion
├── docs/
│   └── vscreen/
│       ├── claude_steps.md
│       └── test_completion.md
├── tests/
│   └── integration/
│       └── vscreen/
│           └── exhaust.sh      # Comprehensive test suite
├── logs/
│   └── integration/
│       └── vscreen/            # Test logs stored here
├── Makefile
└── README.md
```

## Installation

### Option 1: Quick Install (Single User)

```bash
# 1. Make vscreen executable
chmod +x spells/vscreen/bin/vscreen

# 2. Add to your PATH (add to ~/.bashrc or ~/.zshrc)
export PATH="$HOME/.local/scripts/bin:$PATH"

# 3. Install bash completion
mkdir -p ~/.local/share/bash-completion/completions
cp spells/vscreen/completions/bash/vscreen.bash ~/.local/share/bash-completion/completions/vscreen

# 4. Reload shell
source ~/.bashrc
```

### Option 2: Using Makefile (if available)

```bash
# Install for current user
make install

# Or install system-wide (requires sudo)
sudo make install-system
```

### Option 3: Manual System-wide Install

```bash
# Copy executable
sudo cp spells/vscreen/bin/vscreen /usr/local/bin/
sudo chmod +x /usr/local/bin/vscreen

# Install bash completion
sudo cp spells/vscreen/completions/bash/vscreen.bash /etc/bash_completion.d/vscreen

# Reload completions
source /etc/bash_completion.d/vscreen
```

## Verify Installation

```bash
# Check if vscreen is in PATH
which vscreen

# Check version
vscreen --version

# Test bash completion
vscreen --<TAB><TAB>
```

## Running Tests

### Quick Test

```bash
# Run from project root
./spells/vscreen/tests/vscreen/integration.sh
```

### View Test Results

```bash
# Latest test log is symlinked
cat logs/integration/vscreen/exhaust_latest.log

# Or view specific test
ls -lt logs/integration/vscreen/
cat logs/integration/vscreen/exhaust_YYYYMMDD_HHMMSS.log
```

### Test What's Covered

The test suite (`exhaust.sh`) covers:
- ✅ Basic commands (help, version, list)
- ✅ Invalid argument validation
- ✅ All predefined resolutions
- ✅ Custom resolutions
- ✅ All orientations (landscape, portrait, inverted)
- ✅ Change command (modify existing displays)
- ✅ Positioning (relative and absolute)
- ✅ Stress test (10 virtual displays)
- ✅ Edge cases
- ✅ Complex multi-display scenarios
- ✅ Cleanup (--off-all, --purge-modes)

## Basic Usage

### Activate a Virtual Display

```bash
# Using predefined resolution (ID)
vscreen --output 1 -r 1

# Using predefined resolution (name)
vscreen --output 1 -r FHD

# Using custom resolution
vscreen --output 1 --size 1920x1080
```

### List Displays

```bash
# List all virtual outputs
vscreen --list all

# List active only
vscreen --list active

# List free (available) only
vscreen --list free
```

### Change Display Configuration

```bash
# Change resolution
vscreen --change 1 -r HD

# Change orientation
vscreen --change 1 -o right

# Change both
vscreen --change 1 -r FHD -o normal
```

### Position Displays

```bash
# Relative positioning
vscreen --output 2 -r 2 --right-of eDP1
vscreen --output 3 -r 3 --left-of VIRTUAL1
vscreen --output 4 -r 4 --above eDP1
vscreen --output 5 -r 5 --below VIRTUAL2

# Absolute positioning
vscreen --output 1 -r 1 --pos 1920x0
vscreen --output 2 -r 2 --pos 0x1080

# Disable auto-positioning
vscreen --output 1 -r 1 --no-auto
```

### Orientations

```bash
# Landscape (default)
vscreen --output 1 -r 1 -o normal
vscreen --output 1 -r 1 -o L

# Portrait Right (90° clockwise)
vscreen --output 1 -r 1 -o right
vscreen --output 1 -r 1 -o PR

# Portrait Left (90° counter-clockwise)
vscreen --output 1 -r 1 -o left
vscreen --output 1 -r 1 -o PL

# Landscape Flipped (180°)
vscreen --output 1 -r 1 -o inverted
vscreen --output 1 -r 1 -o LF
```

### Deactivate Displays

```bash
# Deactivate specific display
vscreen --off 1

# Deactivate all virtual displays
vscreen --off-all
```

### Cleanup

```bash
# Remove custom mode associations
vscreen --purge-modes
```

## Advanced Usage

### Debug Mode

```bash
# See detailed execution
vscreen --output 1 -r 1 --debug
```

### Dry-Run Mode

```bash
# See what would be executed without running
vscreen --output 1 -r 1 --dry-run
```

### Complex Setup Example

```bash
# Activate 3 displays with different configs
vscreen --output 1 -r FHD -o normal --pos 1920x0
vscreen --output 2 -r HD -o right --right-of VIRTUAL1
vscreen --output 3 --size 2560x1440 -o normal --above VIRTUAL1

# Modify existing display
vscreen --change 2 -o normal

# Check layout
xrandr --listmonitors
```

## Available Resolutions

| ID | Name  | Resolution | Aspect Ratio | Description         |
|----|-------|------------|--------------|---------------------|
| 1  | FHD   | 1920x1080  | 16:9         | Desktop             |
| 2  | HD+   | 1600x900   | 16:9         | Tablet large UI     |
| 3  | HD    | 1366x768   | 16:9         | Tablet comfortable  |
| 4  | HD10  | 1280x800   | 16:10        | Tablet 16:10        |
| 5  | HD+10 | 1440x900   | 16:10        | Tablet large 16:10  |
| 6  | SD    | 800x450    | 16:9         | Phone               |

## Bash Completion

Bash completion is context-aware and dynamic:

- `vscreen --<TAB>` - Show all options
- `vscreen -r <TAB>` - Show available resolutions
- `vscreen --output <TAB>` - Show free virtual outputs
- `vscreen --change <TAB>` - Show active virtual outputs
- `vscreen --off <TAB>` - Show active virtual outputs
- `vscreen -o <TAB>` - Show orientations
- `vscreen --right-of <TAB>` - Show all connected outputs

See `docs/vscreen/test_completion.md` for comprehensive testing guide.

## Troubleshooting

### No VIRTUAL outputs available

```bash
# Check if Intel driver supports virtual outputs
xrandr | grep VIRTUAL

# If none appear, check your graphics driver
lspci | grep VGA
xrandr --version
```

### Display won't activate

```bash
# Run with debug to see what's happening
vscreen --output 1 -r 1 --debug

# Check xrandr directly
xrandr --output VIRTUAL1 --mode 1920x1080_60.00
```

### Can't deactivate displays

```bash
# Force deactivate with xrandr
xrandr --output VIRTUAL1 --off

# Or deactivate all
for v in $(xrandr | awk '/^VIRTUAL[0-9]+/{print $1}'); do
  xrandr --output "$v" --off
done
```

### Cleanup modes

```bash
# Remove all custom modes
vscreen --purge-modes

# Or manually with xrandr
xrandr --listmodes
xrandr --delmode VIRTUAL1 1920x1080_60.00
```

## Dependencies

Required packages:
- `xrandr` - X11 RandR extension
- `cvt` - Calculate VESA Coordinated Video Timings
- `awk` - Text processing

Install on Debian/Ubuntu:
```bash
sudo apt install x11-xserver-utils gawk
```

## Known Limitations

1. **Virtual outputs are GPU-dependent** - Number of available VIRTUAL outputs depends on your Intel GPU capabilities
2. **Performance** - Many virtual displays (15+) may impact performance
3. **Extreme resolutions** - Very high resolutions (8K+) may fail due to GPU memory limits
4. **No persistence** - Virtual displays don't survive reboot/logout

## Contributing

See `CONTRIBUTING.md` for development guidelines.

## License

[Your License Here]

## Support

For issues, questions, or contributions:
- Check logs in `logs/integration/vscreen/`
- Run test suite to verify functionality
- Report issues with debug output: `vscreen --debug [your command]`