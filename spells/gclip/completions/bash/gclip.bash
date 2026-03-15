# Bash completion for gclip
# Source in ~/.bashrc or copy to /etc/bash_completion.d/

_gclip_device_names() {
    gclip list 2>/dev/null | grep -v '^ ' | grep -v '^$'
}

_gclip_device_ids() {
    gclip list 2>/dev/null | awk '/id:/ {print $2}'
}

_gclip_completion() {
    local cur prev
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # First argument: subcommand
    if [[ $COMP_CWORD -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "list push pull --help" -- "$cur") )
        return 0
    fi

    case "$prev" in
        --name)
            COMPREPLY=( $(compgen -W "$(_gclip_device_names)" -- "$cur") )
            return 0
            ;;
        --id)
            COMPREPLY=( $(compgen -W "$(_gclip_device_ids)" -- "$cur") )
            return 0
            ;;
    esac

    local cmd="${COMP_WORDS[1]}"
    case "$cmd" in
        push) COMPREPLY=( $(compgen -W "--name --id --txt --help" -- "$cur") ) ;;
        pull) COMPREPLY=( $(compgen -W "--name --id --txt --help" -- "$cur") ) ;;
        list) COMPREPLY=() ;;
    esac
}

complete -F _gclip_completion gclip
