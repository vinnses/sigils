#!/usr/bin/env bash

SIGILS_ROOT="${SIGILS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SIGILS_DISABLED_FILE="${SIGILS_DISABLED_FILE:-$SIGILS_ROOT/config/spells.disabled}"

sigils_iter_spells() {
    local spell_dir
    for spell_dir in "$SIGILS_ROOT"/spells/*; do
        [[ -d "$spell_dir" ]] || continue
        local spell
        spell="$(basename "$spell_dir")"
        local status="enabled"
        if [[ -f "$SIGILS_DISABLED_FILE" ]] && grep -Fxq "$spell" "$SIGILS_DISABLED_FILE"; then
            status="disabled"
        fi
        printf '%s\t%s\t%s\n' "$spell" "$status" "$spell_dir"
    done
}

sigils_iter_enabled_spells() {
    while IFS=$'\t' read -r spell status spell_dir; do
        [[ "$status" == "enabled" ]] || continue
        printf '%s\t%s\n' "$spell" "$spell_dir"
    done < <(sigils_iter_spells)
}

sigils_spell_exists() {
    [[ -d "$SIGILS_ROOT/spells/$1" ]]
}

sigils_write_disabled_file() {
    local values=("$@")
    mkdir -p "$(dirname "$SIGILS_DISABLED_FILE")"

    if [[ ${#values[@]} -eq 0 ]]; then
        : >"$SIGILS_DISABLED_FILE"
        return 0
    fi

    printf '%s\n' "${values[@]}" | awk 'NF' | sort -u >"$SIGILS_DISABLED_FILE"
}

sigils_disable_spell() {
    local spell="$1"
    local values=()

    if [[ -f "$SIGILS_DISABLED_FILE" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && values+=("$line")
        done <"$SIGILS_DISABLED_FILE"
    fi

    values+=("$spell")
    sigils_write_disabled_file "${values[@]}"
}

sigils_enable_spell() {
    local spell="$1"
    local values=()

    if [[ -f "$SIGILS_DISABLED_FILE" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" && "$line" != "$spell" ]] && values+=("$line")
        done <"$SIGILS_DISABLED_FILE"
    fi

    sigils_write_disabled_file "${values[@]}"
}
