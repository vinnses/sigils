#!/bin/bash
# totp bash completion

_totp() {
    local cur prev words cword
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    words=("${COMP_WORDS[@]}")
    cword=$COMP_CWORD

    _totp_account_names() {
        # Decrypt via the totp binary itself; safe in graphical sessions where
        # the keyring is unlocked. Returns nothing silently in TTY sessions.
        totp list 2>/dev/null | awk '/^[^ ]/ {print $0}'
    }

    # Complete commands at position 1
    if [[ $cword -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "init add list get remove export --help" -- "$cur") )
        return 0
    fi

    local command="${words[1]}"

    case "$prev" in
        --name)
            local names
            names=$(_totp_account_names)
            [[ -n "$names" ]] && COMPREPLY=( $(compgen -W "$names" -- "$cur") )
            return 0
            ;;
        --algo)
            COMPREPLY=( $(compgen -W "sha1 sha256 sha512" -- "$cur") )
            return 0
            ;;
        --digits)
            COMPREPLY=( $(compgen -W "6 7 8" -- "$cur") )
            return 0
            ;;
        --period)
            COMPREPLY=( $(compgen -W "30 60 90" -- "$cur") )
            return 0
            ;;
        --secret|--uri)
            # User types their own value, no completion
            return 0
            ;;
    esac

    case "$command" in
        add)
            COMPREPLY=( $(compgen -W "--name --secret --uri --clip --algo --digits --period --help" -- "$cur") )
            ;;
        get)
            COMPREPLY=( $(compgen -W "--name --clip --help" -- "$cur") )
            ;;
        remove|export)
            COMPREPLY=( $(compgen -W "--name --help" -- "$cur") )
            ;;
        list)
            COMPREPLY=( $(compgen -W "--help" -- "$cur") )
            ;;
    esac

    return 0
}

complete -F _totp totp
