# Bash completion for enx
# Source in ~/.bashrc or copy to /etc/bash_completion.d/

_enx_interfaces() {
    ip -br -4 addr show 2>/dev/null | awk '/^enx/ {print $1}'
}

_enx_device_names() {
    local iface
    for iface in $(_enx_interfaces); do
        local path="/sys/class/net/${iface}/device"
        [[ -L "$path" ]] || continue
        local real=$(readlink -f "$path")
        while [[ "$real" != "/" ]]; do
            if [[ -f "$real/product" ]]; then
                cat "$real/product"
                break
            fi
            real=$(dirname "$real")
        done
    done
}

_enx_completion() {
    local cur prev
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    if [[ $COMP_CWORD -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "list ip pin-onboard metric --help" -- "$cur") )
        return 0
    fi

    case "$prev" in
        --name)
            local IFS=$'\n'
            COMPREPLY=( $(compgen -W "$(_enx_device_names)" -- "$cur") )
            # Escape spaces for readline
            COMPREPLY=( "${COMPREPLY[@]// /\\ }" )
            return 0
            ;;
        --iface)
            COMPREPLY=( $(compgen -W "$(_enx_interfaces)" -- "$cur") )
            return 0
            ;;
        --id|--value)
            return 0
            ;;
    esac

    local cmd="${COMP_WORDS[1]}"
    case "$cmd" in
        ip)     COMPREPLY=( $(compgen -W "--name --id --iface --help" -- "$cur") ) ;;
        metric) COMPREPLY=( $(compgen -W "--name --id --iface --value --permanent --help" -- "$cur") ) ;;
        list|pin-onboard) COMPREPLY=() ;;
    esac
}

complete -F _enx_completion enx
