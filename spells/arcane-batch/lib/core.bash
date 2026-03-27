#!/usr/bin/env bash
# arcane-batch core library

set -euo pipefail

readonly ARCANE_DIR="${ARCANE_DIR:-$HOME/arcane}"
readonly ARCANE_IGNORED_DIRS="archived .data"

# --- Colors ---

_arcane_bold_cyan()  { printf '\033[1;36m%s\033[0m' "$*"; }
_arcane_red()        { printf '\033[0;31m%s\033[0m' "$*"; }
_arcane_green()      { printf '\033[0;32m%s\033[0m' "$*"; }

# --- Arg parsing ---

# Sets: ARCANE_DEVICE, ARCANE_INCLUDES(), ARCANE_EXCLUDES()
_arcane_parse_args() {
    ARCANE_DEVICE="$(hostname)"
    ARCANE_INCLUDES=()
    ARCANE_EXCLUDES=()

    local mode="include"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --device|-d)
                [[ $# -lt 2 ]] && { echo "error: --device requires a value" >&2; return 1; }
                ARCANE_DEVICE="$2"
                shift 2
                ;;
            --exclude|-e)
                mode="exclude"
                shift
                ;;
            -*)
                echo "error: unknown option: $1" >&2
                return 1
                ;;
            *)
                if [[ "$mode" == "include" ]]; then
                    ARCANE_INCLUDES+=("$1")
                else
                    ARCANE_EXCLUDES+=("$1")
                fi
                shift
                ;;
        esac
    done

    if [[ ${#ARCANE_INCLUDES[@]} -gt 0 && ${#ARCANE_EXCLUDES[@]} -gt 0 ]]; then
        echo "error: cannot specify both projects and --exclude" >&2
        return 1
    fi
}

# --- Project discovery ---

# Prints "name\tpath" lines for all projects in a device
_arcane_discover() {
    local device="$1"
    local device_dir="$ARCANE_DIR/$device"

    if [[ ! -d "$device_dir" ]]; then
        echo "error: device directory not found: $device_dir" >&2
        return 1
    fi

    # Device root project
    if [[ -f "$device_dir/compose.yaml" ]]; then
        printf '%s\t%s\n' "$device" "$device_dir"
    fi

    # Subdirectory projects
    local entry
    for entry in "$device_dir"/*/; do
        [[ ! -d "$entry" ]] && continue
        local name
        name="$(basename "$entry")"

        # Skip hidden dirs and ignored dirs
        [[ "$name" == .* ]] && continue
        local ignored=false
        local ign
        for ign in $ARCANE_IGNORED_DIRS; do
            [[ "$name" == "$ign" ]] && { ignored=true; break; }
        done
        $ignored && continue

        [[ -f "$entry/compose.yaml" ]] && printf '%s\t%s\n' "$name" "$entry"
    done
}

# --- Core iterator ---

_arcane_each() {
    local action="$1"
    shift

    _arcane_parse_args "$@" || return 1

    local projects
    projects="$(_arcane_discover "$ARCANE_DEVICE")" || return 1

    if [[ -z "$projects" ]]; then
        echo "no projects found for device: $ARCANE_DEVICE" >&2
        return 1
    fi

    # Apply filters
    local filtered=()
    while IFS=$'\t' read -r name path; do
        if [[ ${#ARCANE_INCLUDES[@]} -gt 0 ]]; then
            local found=false
            local inc
            for inc in "${ARCANE_INCLUDES[@]}"; do
                [[ "$name" == "$inc" ]] && { found=true; break; }
            done
            $found || continue
        elif [[ ${#ARCANE_EXCLUDES[@]} -gt 0 ]]; then
            local excluded=false
            local exc
            for exc in "${ARCANE_EXCLUDES[@]}"; do
                [[ "$name" == "$exc" ]] && { excluded=true; break; }
            done
            $excluded && continue
        fi
        filtered+=("$name"$'\t'"$path")
    done <<< "$projects"

    if [[ ${#filtered[@]} -eq 0 ]]; then
        echo "no projects matched the filter" >&2
        return 1
    fi

    # Validate requested includes exist
    if [[ ${#ARCANE_INCLUDES[@]} -gt 0 ]]; then
        local inc
        for inc in "${ARCANE_INCLUDES[@]}"; do
            local found=false
            local entry
            for entry in "${filtered[@]}"; do
                local ename="${entry%%$'\t'*}"
                [[ "$ename" == "$inc" ]] && { found=true; break; }
            done
            if ! $found; then
                echo "warning: project not found: $inc" >&2
            fi
        done
    fi

    local ok=0 fail=0
    local entry
    for entry in "${filtered[@]}"; do
        local name="${entry%%$'\t'*}"
        local path="${entry#*$'\t'}"

        printf '%s %s\n' "$(_arcane_bold_cyan "$name")" "$action"
        if (cd "$path" && eval "$action"); then
            ((ok++))
        else
            printf '%s %s\n' "$(_arcane_red "$name")" "FAILED"
            ((fail++))
        fi
    done

    if [[ $((ok + fail)) -gt 1 ]]; then
        echo ""
        printf 'Done: %s ok, %s failed\n' "$(_arcane_green "$ok")" "$(_arcane_red "$fail")"
    fi

    [[ $fail -eq 0 ]]
}

# --- Dump ---

_arcane_dump() {
    if ! command -v 7z >/dev/null 2>&1; then
        echo "error: 7z not found. Install p7zip-full." >&2
        return 1
    fi

    local stamp
    stamp="$(date +%Y-%m-%d)"
    local output="$ARCANE_DIR/arcane-env-dump-${stamp}.7z"

    # Collect .env files
    local env_files=()
    while IFS= read -r -d '' f; do
        env_files+=("$f")
    done < <(find "$ARCANE_DIR" -name '.env' \
        -not -path '*/archived/*' \
        -not -path '*/.data/*' \
        -not -path '*/node_modules/*' \
        -print0)

    if [[ ${#env_files[@]} -eq 0 ]]; then
        echo "no .env files found" >&2
        return 1
    fi

    echo "Found ${#env_files[@]} .env file(s):"
    local f
    for f in "${env_files[@]}"; do
        echo "  ${f#"$ARCANE_DIR/"}"
    done

    # Build relative path list
    local rel_paths=()
    for f in "${env_files[@]}"; do
        rel_paths+=("${f#"$ARCANE_DIR/"}")
    done

    (cd "$ARCANE_DIR" && 7z a -p -mhe=on "$output" "${rel_paths[@]}")

    echo ""
    echo "Archive: $output"

    # Ensure gitignore entry
    local gitignore="$ARCANE_DIR/.gitignore"
    local pattern="arcane-env-dump-*.7z"
    if [[ -f "$gitignore" ]]; then
        if ! grep -qF "$pattern" "$gitignore"; then
            echo "$pattern" >> "$gitignore"
            echo "Added $pattern to .gitignore"
        fi
    else
        echo "$pattern" > "$gitignore"
        echo "Created .gitignore with $pattern"
    fi
}

# --- Restore ---

_arcane_restore() {
    local archive="$1"

    if ! command -v 7z >/dev/null 2>&1; then
        echo "error: 7z not found. Install p7zip-full." >&2
        return 1
    fi

    if [[ ! -f "$archive" ]]; then
        echo "error: archive not found: $archive" >&2
        return 1
    fi

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT

    # Extract to temp dir to preview
    if ! 7z x -o"$tmpdir" "$archive"; then
        echo "error: failed to extract archive" >&2
        return 1
    fi

    # List files and check for overwrites
    local env_files=()
    while IFS= read -r -d '' f; do
        env_files+=("$f")
    done < <(find "$tmpdir" -name '.env' -print0)

    if [[ ${#env_files[@]} -eq 0 ]]; then
        echo "no .env files found in archive" >&2
        return 1
    fi

    echo "Files to restore:"
    local has_overwrites=false
    local f
    for f in "${env_files[@]}"; do
        local rel="${f#"$tmpdir/"}"
        local target="$ARCANE_DIR/$rel"
        if [[ -f "$target" ]]; then
            echo "  $rel (overwrite)"
            has_overwrites=true
        else
            echo "  $rel (new)"
        fi
    done

    if $has_overwrites; then
        echo ""
        read -r -p "Some files will be overwritten. Continue? [y/N] " confirm
        case "$confirm" in
            [yY]|[yY][eE][sS]) ;;
            *)
                echo "Aborted."
                return 1
                ;;
        esac
    fi

    # Copy files to target
    for f in "${env_files[@]}"; do
        local rel="${f#"$tmpdir/"}"
        local target="$ARCANE_DIR/$rel"
        mkdir -p "$(dirname "$target")"
        cp "$f" "$target"
        echo "Restored: $rel"
    done

    echo "Done."
}
