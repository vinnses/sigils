#!/bin/bash

_arcane() {
    local cur prev words cword
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    words=("${COMP_WORDS[@]}")
    cword=$COMP_CWORD

    local arcane_dir="${ARCANE_DIR:-$HOME/arcane}"
    local subcommands="up down pull restart clean purge status ls cd path exec resources rm favorites dump restore"

    if [[ $cword -eq 1 ]]; then
        COMPREPLY=($(compgen -W "$subcommands --help" -- "$cur"))
        return 0
    fi

    local subcmd="${words[1]}"

    if [[ "$subcmd" == "restore" ]]; then
        COMPREPLY=($(compgen -f -- "$cur"))
        return 0
    fi

    if [[ "$prev" == "--device" || "$prev" == "-d" ]]; then
        local devices=()
        if [[ -d "$arcane_dir" ]]; then
            local d
            for d in "$arcane_dir"/*/; do
                [[ -d "$d" ]] || continue
                local name
                name="$(basename "$d")"
                [[ "$name" == "archived" || "$name" == .* ]] && continue
                devices+=("$name")
            done
        fi
        COMPREPLY=($(compgen -W "${devices[*]}" -- "$cur"))
        return 0
    fi

    local device
    device="$(hostname)"
    local i
    for ((i = 2; i < cword; i++)); do
        if [[ "${words[i]}" == "--device" || "${words[i]}" == "-d" ]]; then
            if [[ $((i + 1)) -lt ${#words[@]} ]]; then
                device="${words[i+1]}"
            fi
            break
        fi
    done

    local device_dir="$arcane_dir/$device"
    local projects=()
    if [[ -d "$device_dir" ]]; then
        if [[ -f "$device_dir/compose.yaml" ]]; then
            projects+=("$device")
        fi
        local entry
        for entry in "$device_dir"/*/; do
            [[ -d "$entry" ]] || continue
            local name
            name="$(basename "$entry")"
            [[ "$name" == "archived" || "$name" == .* || "$name" == ".data" ]] && continue
            [[ -f "$entry/compose.yaml" ]] && projects+=("$name")
        done
    fi

    case "$subcmd" in
        exec)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "--device -d" -- "$cur"))
                return 0
            fi
            for ((i = 2; i < cword; i++)); do
                [[ "${words[i]}" == "--" ]] && return 0
            done
            COMPREPLY=($(compgen -W "${projects[*]} --device -d --" -- "$cur"))
            return 0
            ;;
        rm)
            if [[ $cword -eq 2 ]]; then
                COMPREPLY=($(compgen -W "containers images networks volumes all" -- "$cur"))
                return 0
            fi
            COMPREPLY=($(compgen -W "${projects[*]} --exclude --device -e -d" -- "$cur"))
            return 0
            ;;
        ls)
            COMPREPLY=($(compgen -W "${projects[*]} --exclude --device -e -d --up --down" -- "$cur"))
            return 0
            ;;
        cd|path|resources|up|down|pull|restart|clean|purge|status)
            COMPREPLY=($(compgen -W "${projects[*]} --exclude --device -e -d" -- "$cur"))
            return 0
            ;;
        favorites)
            COMPREPLY=($(compgen -W "--device -d --output -o" -- "$cur"))
            return 0
            ;;
        dump)
            return 0
            ;;
    esac

    COMPREPLY=($(compgen -W "$subcommands --help" -- "$cur"))
}

complete -F _arcane arcane
