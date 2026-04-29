#!/bin/bash
# bash completion for pamusb

_pamusb_complete() {
    local cur prev words cword
    _init_completion || return

    local subcommands="setup setup-pam setup-keyring partition status test recover devices rekey provision-host lock-disable lock-enable uninstall"
    local global_opts="--debug --log --help"

    if [[ "$cword" -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "$subcommands $global_opts" -- "$cur") )
        return
    fi

    case "${words[1]}" in
        devices)
            if [[ "$cword" -eq 2 ]]; then
                COMPREPLY=( $(compgen -W "list set forget" -- "$cur") )
            elif [[ "${words[2]}" == "set" ]]; then
                COMPREPLY=( $(compgen -W "--uuid --label --help" -- "$cur") )
            fi
            ;;
        setup|setup-pam|setup-keyring|partition|status|test|recover|rekey|provision-host|lock-disable|lock-enable|uninstall)
            COMPREPLY=( $(compgen -W "--help" -- "$cur") )
            ;;
        --log)
            COMPREPLY=( $(compgen -f -- "$cur") )
            ;;
    esac
}

complete -F _pamusb_complete pamusb
