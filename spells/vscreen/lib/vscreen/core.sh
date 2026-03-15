#!/bin/bash
# ============================
# vscreen - Reusable Functions Library
# ============================
# This file is a placeholder for future refactoring.
# Currently all logic lives in bin/vscreen, but should be split according to
# the project's separation of concerns principle.

# TODO(refactoring): Extract reusable logic from bin/vscreen to lib/vscreen/
# The main vscreen script currently contains all implementation details.
# This violates the project principle that bin/ should only contain entry points.
#
# Refactoring plan:
#
# 1. Create modular library files:
#    - lib/vscreen/core.sh: Main functions (enable_virtual, create_mode, etc)
#    - lib/vscreen/validation.sh: Argument and state validation
#    - lib/vscreen/output.sh: Logging and user messages
#    - lib/vscreen/xrandr.sh: All xrandr interaction wrappers
#    - lib/vscreen/positioning.sh: Smart positioning logic
#
# 2. Make functions testable:
#    - Accept parameters explicitly (no global state)
#    - Return status codes consistently
#    - Separate pure logic from side effects
#    - Allow mocking of external commands
#
# 3. Update bin/vscreen:
#    - Source all library files
#    - Parse arguments and delegate to library functions
#    - Handle only top-level orchestration
#    - Keep under 200 lines if possible
#
# 4. Create unit tests:
#    - Test each library function in isolation
#    - Mock xrandr outputs using fixtures
#    - Verify argument validation
#    - Test edge cases and error conditions
#
# Benefits:
# - Easier to test individual components
# - Better code organization and readability
# - Reusable functions for future tools
# - Follows project architecture guidelines
#
# labels: refactoring, architecture, technical-debt, testing



# TODO(improvements): Make available resolutions dynamic
# Instead of having a fixed table written directly in the code, making it separate allows for changes
# The creation of two distinct files is necessary, one for the created resolution history, 
# Another for saved resolutions. Or just a file, define it better.

# TODO(feature): Add --dpi to vscreen
#
# e.g.: 
#  vscreen --size 1200x2000 --dpi 212
#  vscreen -o 1 --dpi 212
