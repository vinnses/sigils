#!/usr/bin/env bash
# zotcli shell integration (v3)
# Provides: shell wrapper, __zotcli_ps1, tab completions, zot() alias.
#
# Sourced automatically by the sigils init system.

# ---------------------------------------------------------------------------
# Shell wrapper — captures env var exports, forces colors, activates visual mode
# ---------------------------------------------------------------------------

zotcli() {
    # 'off': reset state + clear visual env vars
    if [[ "${1:-}" == "off" ]]; then
        ZOTCLI_COLOR=1 command zotcli off "${@:2}"
        unset ZOTCLI_VISUAL ZOTCLI_PATH ZOTCLI_SYNC_AGE
        return 0
    fi

    # ZOTCLI_COLOR=1 forces ANSI codes even though stdout is a pipe
    local output exitcode
    output=$(ZOTCLI_COLOR=1 command zotcli "$@")
    exitcode=$?

    # Parse __ZOTCLI_ENV__ lines; print the rest
    local line
    while IFS= read -r line; do
        if [[ "$line" == __ZOTCLI_ENV__* ]]; then
            export "${line#__ZOTCLI_ENV__}"
        else
            printf '%s\n' "$line"
        fi
    done <<< "$output"

    # Mark visual mode as active on first use (sets ZOTCLI_VISUAL=1)
    if [[ -z "${ZOTCLI_VISUAL:-}" ]]; then
        export ZOTCLI_VISUAL=1
    fi

    return $exitcode
}

zot() { zotcli "$@"; }

# ---------------------------------------------------------------------------
# PS1 helper — like __git_ps1, outputs formatted string when active
#
# Usage in PS1:
#   PS1+='$(__zotcli_ps1 " [%s]")'
#
# Usage via PROMPT_COMMAND (updates a variable, zero subshell cost):
#   PROMPT_COMMAND+='PS1_ZOTCLI=$(__zotcli_ps1 " [%s]")'
#   PS1+='${PS1_ZOTCLI}'
# ---------------------------------------------------------------------------

__zotcli_ps1() {
    # Only output when zotcli has been used in this session
    [[ "${ZOTCLI_VISUAL:-}" != "1" ]] && return

    local fmt="${1:-%s}"
    local path="${ZOTCLI_PATH:-zot://}"
    local sync="${ZOTCLI_SYNC_AGE:-}"
    local info="$path"
    [[ -n "$sync" ]] && info+=" [${sync}]"
    printf -- "$fmt" "$info"
}

# ---------------------------------------------------------------------------
# Tab completions
# ---------------------------------------------------------------------------

_zotcli() {
    # Temporarily remove ':' from COMP_WORDBREAKS so zot:// isn't split
    local OLD_IFS="$COMP_WORDBREAKS"
    COMP_WORDBREAKS="${COMP_WORDBREAKS//:}"

    local cur prev words cword
    _init_completion 2>/dev/null || {
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        words=("${COMP_WORDS[@]}")
        cword=$COMP_CWORD
    }

    COMP_WORDBREAKS="$OLD_IFS"

    local subcommands="cd pwd ls tree cat get find sync connect config py off"

    # Find the subcommand (skip global flags)
    local subcmd=""
    local i
    for ((i = 1; i < cword; i++)); do
        case "${words[i]}" in
            --fresh|-*) continue ;;
            *)          subcmd="${words[i]}"; break ;;
        esac
    done

    if [[ -z "$subcmd" ]]; then
        COMPREPLY=($(compgen -W "$subcommands --fresh" -- "$cur"))
        return
    fi

    case "$subcmd" in

        cd|ls)
            if [[ "$cur" == -* ]]; then
                [[ "$subcmd" == "ls" ]] && \
                    COMPREPLY=($(compgen -W "--sort --reverse --unfiled" -- "$cur"))
            else
                compopt -o nospace 2>/dev/null
                local IFS=$'\n'
                local results
                results=$(SPELL_DIR="${SPELL_DIR:-}" command zotcli _complete "$cur" 2>/dev/null)
                COMPREPLY=()
                while IFS=$'\t' read -r completion _type; do
                    [[ -n "$completion" ]] && COMPREPLY+=("$completion")
                done <<< "$results"
                if [[ "$subcmd" == "cd" ]]; then
                    COMPREPLY+=($(compgen -W "zot:// .. -" -- "$cur"))
                fi
            fi
            ;;

        get)
            [[ "$cur" == -* ]] && \
                COMPREPLY=($(compgen -W "--bibtex --json --bib --style -o" -- "$cur"))
            ;;

        find)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "--field --scope --tag --type" -- "$cur"))
            elif [[ "$prev" == "--scope" ]]; then
                COMPREPLY=($(compgen -W "collection library" -- "$cur"))
            fi
            ;;

        tree)
            [[ "$cur" == -* ]] && \
                COMPREPLY=($(compgen -W "--depth --no-items" -- "$cur"))
            ;;

        config)
            COMPREPLY=($(compgen -W \
                "ls.default_sort ls.sort_reverse get.default_format get.bib_style cache.ttl_seconds visual.enabled visual.show_sync_age" \
                -- "$cur"))
            ;;

        py)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "-c" -- "$cur"))
            else
                COMPREPLY=($(compgen -f -X '!*.py' -- "$cur"))
            fi
            ;;

    esac
}

complete -F _zotcli zotcli
complete -F _zotcli zot
