#!/usr/bin/env bash
# Bash completion for zotcli (v2)
# Delegates path resolution to: zotcli _complete <typed_prefix>
# which reads the local cache — no API calls, no network latency.

_zotcli() {
    local cur prev words cword
    _init_completion 2>/dev/null || {
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        words=("${COMP_WORDS[@]}")
        cword=$COMP_CWORD
    }

    local subcommands="cd pwd ls tree cat get connect sync init"

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
            # Delegate entirely to zotcli _complete which reads the cache.
            # It understands relative names, ~/absolute paths, and prefix matching.
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
                COMPREPLY+=($(compgen -W "~ .. -" -- "$cur"))
            fi
            ;;

        get)
            # Complete flags; item refs have no cache in v2
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "--bibtex --json -o" -- "$cur"))
            fi
            ;;

        init)
            COMPREPLY=($(compgen -W "bash" -- "$cur"))
            ;;

        # pwd, tree, cat, connect, sync: no argument completions
    esac
}

complete -F _zotcli zotcli
