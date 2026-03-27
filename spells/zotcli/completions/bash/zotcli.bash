#!/usr/bin/env bash
# zotcli shell integration (v3)
# Provides: shell wrapper function, PS1 hook, tab completions, zot() alias.
#
# Sourced automatically by the sigils init system from:
#   spells/*/completions/bash/*.bash

# ---------------------------------------------------------------------------
# Shell wrapper — captures env var exports, manages visual mode
# ---------------------------------------------------------------------------

zotcli() {
    # Special handling for 'off': deactivate everything, then reset state
    if [[ "${1:-}" == "off" ]]; then
        command zotcli off "${@:2}"
        unset ZOTCLI_VISUAL ZOTCLI_PATH ZOTCLI_SYNC_AGE
        if [[ -n "${PROMPT_COMMAND:-}" ]]; then
            PROMPT_COMMAND="${PROMPT_COMMAND//__zotcli_hook;/}"
            PROMPT_COMMAND="${PROMPT_COMMAND//;__zotcli_hook/}"
        fi
        return 0
    fi

    # Capture stdout; stderr flows through to terminal naturally
    local output exitcode
    output=$(command zotcli "$@")
    exitcode=$?

    # Separate __ZOTCLI_ENV__ lines from display output
    local line
    while IFS= read -r line; do
        if [[ "$line" == __ZOTCLI_ENV__* ]]; then
            export "${line#__ZOTCLI_ENV__}"
        else
            printf '%s\n' "$line"
        fi
    done <<< "$output"

    # Auto-activate visual mode on first command
    if [[ -z "${ZOTCLI_VISUAL:-}" ]]; then
        export ZOTCLI_VISUAL=1
        if [[ ";${PROMPT_COMMAND[*]:-};" != *";__zotcli_hook;"* ]]; then
            PROMPT_COMMAND="__zotcli_hook;${PROMPT_COMMAND:-}"
        fi
    fi

    return $exitcode
}

zot() { zotcli "$@"; }

# ---------------------------------------------------------------------------
# PS1 hook — prints Zotero context line above the prompt
# ---------------------------------------------------------------------------

__zotcli_hook() {
    local prev=$?
    if [[ "${ZOTCLI_VISUAL:-}" == "1" ]]; then
        local path="${ZOTCLI_PATH:-^}"
        local sync="${ZOTCLI_SYNC_AGE:-}"
        local info="\033[2m(zot)\033[0m $path"
        [[ -n "$sync" ]] && info+="  \033[2m[synced $sync]\033[0m"
        echo -e "$info" >&2
    fi
    return $prev
}

# ---------------------------------------------------------------------------
# Tab completions
# ---------------------------------------------------------------------------

_zotcli() {
    local cur prev words cword
    _init_completion 2>/dev/null || {
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        words=("${COMP_WORDS[@]}")
        cword=$COMP_CWORD
    }

    local subcommands="cd pwd ls tree cat get find sync connect config py off"

    # Find the subcommand (skip --fresh and other flags)
    local subcmd=""
    local i
    for ((i = 1; i < cword; i++)); do
        case "${words[i]}" in
            --fresh|-*) continue ;;
            *)          subcmd="${words[i]}"; break ;;
        esac
    done

    # No subcommand yet — complete subcommand names and global flags
    if [[ -z "$subcmd" ]]; then
        COMPREPLY=($(compgen -W "$subcommands --fresh" -- "$cur"))
        return
    fi

    # -----------------------------------------------------------------------
    # Subcommand-specific completions
    # -----------------------------------------------------------------------
    case "$subcmd" in

        cd|ls)
            # Delegate to zotcli _complete which reads the cache (no API calls)
            if [[ "$cur" == -* ]]; then
                if [[ "$subcmd" == "ls" ]]; then
                    COMPREPLY=($(compgen -W "--sort --reverse --unfiled" -- "$cur"))
                fi
            else
                compopt -o nospace 2>/dev/null
                local IFS=$'\n'
                local results
                results=$(command zotcli _complete "$cur" 2>/dev/null)
                COMPREPLY=()
                while IFS=$'\t' read -r completion _type; do
                    [[ -n "$completion" ]] && COMPREPLY+=("$completion")
                done <<< "$results"

                # cd-only special tokens
                if [[ "$subcmd" == "cd" ]]; then
                    COMPREPLY+=($(compgen -W "^ .. -" -- "$cur"))
                fi
            fi
            ;;

        get)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "--bibtex --json --bib --style -o" -- "$cur"))
            fi
            ;;

        find)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "--field --scope --tag --type" -- "$cur"))
            elif [[ "$prev" == "--scope" ]]; then
                COMPREPLY=($(compgen -W "collection library" -- "$cur"))
            fi
            ;;

        tree)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "--depth" -- "$cur"))
            fi
            ;;

        config)
            # Complete known config keys
            COMPREPLY=($(compgen -W \
                "ls.default_sort ls.sort_reverse get.default_format get.bib_style cache.ttl_seconds visual.enabled visual.show_sync_age" \
                -- "$cur"))
            ;;

        py)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "-c" -- "$cur"))
            else
                # Complete .py files
                COMPREPLY=($(compgen -f -X '!*.py' -- "$cur"))
            fi
            ;;

        # pwd, tree, cat, connect, sync, off: no argument completions
    esac
}

complete -F _zotcli zotcli
complete -F _zotcli zot
