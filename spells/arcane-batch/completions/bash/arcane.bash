#!/bin/bash
# arcane bash completion

_arcane() {
    local cur prev words cword
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    words=("${COMP_WORDS[@]}")
    cword=$COMP_CWORD

    local arcane_dir="${ARCANE_DIR:-$HOME/arcane}"
    local subcommands="up down pull restart clean status dump restore"

    # Complete subcommand at position 1
    if [[ $cword -eq 1 ]]; then
        COMPREPLY=($(compgen -W "$subcommands --help" -- "$cur"))
        return 0
    fi

    local subcmd="${words[1]}"

    # dump and restore have special completion
    if [[ "$subcmd" == "dump" ]]; then
        return 0
    fi
    if [[ "$subcmd" == "restore" ]]; then
        COMPREPLY=($(compgen -f -- "$cur"))
        return 0
    fi

    # After --device/-d: complete device names
    if [[ "$prev" == "--device" || "$prev" == "-d" ]]; then
        local devices=()
        if [[ -d "$arcane_dir" ]]; then
            local d
            for d in "$arcane_dir"/*/; do
                [[ ! -d "$d" ]] && continue
                local name
                name="$(basename "$d")"
                [[ "$name" == "archived" || "$name" == .* ]] && continue
                devices+=("$name")
            done
        fi
        COMPREPLY=($(compgen -W "${devices[*]}" -- "$cur"))
        return 0
    fi

    # Determine current device for project completion
    local device
    device="$(hostname)"
    local i
    for ((i=2; i<cword; i++)); do
        if [[ "${words[i]}" == "--device" || "${words[i]}" == "-d" ]]; then
            if [[ $((i+1)) -lt ${#words[@]} ]]; then
                device="${words[i+1]}"
            fi
            break
        fi
    done

    # Collect project names
    local device_dir="$arcane_dir/$device"
    local projects=()
    if [[ -d "$device_dir" ]]; then
        if [[ -f "$device_dir/compose.yaml" ]]; then
            projects+=("$device")
        fi
        local entry
        for entry in "$device_dir"/*/; do
            [[ ! -d "$entry" ]] && continue
            local name
            name="$(basename "$entry")"
            [[ "$name" == "archived" || "$name" == .* || "$name" == ".data" ]] && continue
            [[ -f "$entry/compose.yaml" ]] && projects+=("$name")
        done
    fi

    # After --exclude/-e: complete project names
    local in_exclude=false
    for ((i=2; i<cword; i++)); do
        if [[ "${words[i]}" == "--exclude" || "${words[i]}" == "-e" ]]; then
            in_exclude=true
            break
        fi
    done

    if $in_exclude || [[ "$prev" == "--exclude" || "$prev" == "-e" ]]; then
        COMPREPLY=($(compgen -W "${projects[*]}" -- "$cur"))
        return 0
    fi

    # Default: complete project names + options
    COMPREPLY=($(compgen -W "${projects[*]} --exclude --device -e -d" -- "$cur"))
    return 0
}

complete -F _arcane arcane
