#!/usr/bin/env bash
# zotcli tab completions (v3)
# Shell wrapper, __zotcli_ps1, and prompt hook are in inits/bash/zotcli.bash.
#
# Sourced automatically by the sigils init system (after inits).

_zotcli() {
    # Temporarily remove ':' from COMP_WORDBREAKS so legacy zot:// isn't split
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

    local subcommands="cd pwd ls tree cat get find sync connect config off nav py help"

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
                    COMPREPLY=($(compgen -W "--sort --reverse --unfiled --fields" -- "$cur"))
            else
                compopt -o nospace 2>/dev/null
                local IFS=$'\n'
                local results
                results=$(SPELL_DIR="${SPELL_DIR:-}" command zotcli _complete "$cur" 2>/dev/null)
                COMPREPLY=()
                while IFS=$'\t' read -r completion _type; do
                    [[ -n "$completion" ]] && COMPREPLY+=("$completion")
                done <<< "$results"
                # Add item refs (citation key/item key) in current collection context.
                local item_results
                item_results=$(SPELL_DIR="${SPELL_DIR:-}" command zotcli _complete_items item "$cur" 2>/dev/null)
                while IFS=$'\t' read -r completion _type; do
                    [[ -n "$completion" ]] && COMPREPLY+=("$completion")
                done <<< "$item_results"
                if [[ "$subcmd" == "cd" ]]; then
                    COMPREPLY+=($(compgen -W "^ .. -" -- "$cur"))
                fi
            fi
            ;;

        get)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "--bibtex --json --bib --style -o" -- "$cur"))
            else
                local IFS=$'\n'
                local refs
                refs=$(SPELL_DIR="${SPELL_DIR:-}" command zotcli _complete_items ref "$cur" 2>/dev/null)
                COMPREPLY=()
                while IFS=$'\t' read -r completion _type; do
                    [[ -n "$completion" ]] && COMPREPLY+=("$completion")
                done <<< "$refs"
            fi
            ;;

        cat)
            if [[ "$cur" != -* ]]; then
                local IFS=$'\n'
                local refs
                refs=$(SPELL_DIR="${SPELL_DIR:-}" command zotcli _complete_items ref "$cur" 2>/dev/null)
                COMPREPLY=()
                while IFS=$'\t' read -r completion _type; do
                    [[ -n "$completion" ]] && COMPREPLY+=("$completion")
                done <<< "$refs"
            fi
            ;;

        find)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "--field --scope --tag --type --fields" -- "$cur"))
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
                "ls.default_sort ls.sort_reverse ls.default_fields get.default_format get.bib_style cache.ttl_seconds visual.auto visual.color visual.show_sync_age" \
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

# Completions can be disabled with: export ZOTCLI_COMPLETIONS=0
[[ "${ZOTCLI_COMPLETIONS:-1}" == "0" ]] && return 0

complete -F _zotcli zotcli
complete -F _zotcli zot
