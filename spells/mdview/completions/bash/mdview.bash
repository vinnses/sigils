#!/usr/bin/env bash

_mdview() {
    local cur prev
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    local subcommands="serve list stop open"
    local serve_flags="--background -b --port -p --theme -t --open --no-watch"
    local themes="github vscode"

    if [[ $COMP_CWORD -eq 1 ]]; then
        COMPREPLY=($(compgen -W "$subcommands" -- "$cur"))
        return 0
    fi

    case "${COMP_WORDS[1]}" in
        serve)
            if [[ "$prev" == "--theme" || "$prev" == "-t" ]]; then
                COMPREPLY=($(compgen -W "$themes" -- "$cur"))
                return 0
            fi
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "$serve_flags" -- "$cur"))
                return 0
            fi
            COMPREPLY=($(compgen -f -- "$cur"))
            ;;
        stop|open)
            COMPREPLY=($(compgen -W "$(find "${SPELL_DIR:-${PWD%/}/spells/mdview}"/data -maxdepth 1 -name '*.json' -printf '%f\n' 2>/dev/null | sed 's/\.json$//')" -- "$cur"))
            ;;
    esac
}

complete -F _mdview mdview
