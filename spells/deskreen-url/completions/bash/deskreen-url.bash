# Bash completion for deskreen-url
# Source in ~/.bashrc or copy to /etc/bash_completion.d/

_deskreen_url_completion() {
    local cur prev
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    case "$prev" in
        --device)
            # Reuse gclip's device names
            local names
            names=$(gclip list 2>/dev/null | grep -v '^ ' | grep -v '^$')
            COMPREPLY=( $(compgen -W "$names" -- "$cur") )
            return 0
            ;;
        --iface)
            # Offer both enx interface names and USB device names
            local ifaces
            ifaces=$(ip -br -4 addr show 2>/dev/null | awk '/^enx/ {print $1}')

            local names=""
            local iface
            for iface in $ifaces; do
                local p="/sys/class/net/${iface}/device"
                [[ -L "$p" ]] || continue
                local r=$(readlink -f "$p")
                while [[ "$r" != "/" ]]; do
                    if [[ -f "$r/product" ]]; then
                        names+="$(cat "$r/product")"$'\n'
                        break
                    fi
                    r=$(dirname "$r")
                done
            done

            local IFS=$'\n'
            COMPREPLY=( $(compgen -W "${ifaces}"$'\n'"${names}" -- "$cur") )
            COMPREPLY=( "${COMPREPLY[@]// /\\ }" )
            return 0
            ;;
        --port)
            return 0
            ;;
    esac

    COMPREPLY=( $(compgen -W "--device --iface --port --help" -- "$cur") )
}

complete -F _deskreen_url_completion deskreen-url
