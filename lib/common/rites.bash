#!/usr/bin/env bash

SIGILS_ROOT="${SIGILS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

sigils_iter_rites() {
    local rite_dir

    for rite_dir in "$SIGILS_ROOT"/rites/*; do
        [[ -d "$rite_dir" ]] || continue
        printf '%s\t%s\n' "$(basename "$rite_dir")" "$rite_dir"
    done
}

sigils_rite_dir() {
    local rite="$1"

    [[ -d "$SIGILS_ROOT/rites/$rite" ]] || return 1
    printf '%s\n' "$SIGILS_ROOT/rites/$rite"
}

sigils_rite_entrypoint() {
    local rite="$1"
    local rite_dir

    rite_dir="$(sigils_rite_dir "$rite")" || return 1
    [[ -x "$rite_dir/bin/$rite" ]] || return 1
    printf '%s\n' "$rite_dir/bin/$rite"
}

sigils_rite_doc_path() {
    local rite="$1"
    local rite_dir

    rite_dir="$(sigils_rite_dir "$rite")" || return 1
    [[ -f "$rite_dir/README.md" ]] || return 1
    printf '%s\n' "$rite_dir/README.md"
}
