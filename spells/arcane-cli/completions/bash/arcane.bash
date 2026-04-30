#!/bin/bash

_arcane() {
    local cur prev words cword
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    words=("${COMP_WORDS[@]}")
    cword=$COMP_CWORD

    local arcane_dir="${ARCANE_DIR:-$HOME/arcane}"
    local subcommands="up down pull restart clean purge ps list exec remove rm archive unarchive clone nginx-urls dump restore"
    local resource_types="containers images networks volumes all"

    if [[ $cword -eq 1 ]]; then
        COMPREPLY=($(compgen -W "$subcommands --help" -- "$cur"))
        return 0
    fi

    local subcmd="${words[1]}"

    if [[ "$subcmd" == "restore" ]]; then
        if [[ "$cur" == -* ]]; then
            COMPREPLY=($(compgen -W "--force -f" -- "$cur"))
        else
            COMPREPLY=($(compgen -f -- "$cur"))
        fi
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
    device="${ARCANE_DEVICE:-$(hostname)}"
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
        local entry
        for entry in "$device_dir"/*/; do
            [[ -d "$entry" ]] || continue
            local name
            name="$(basename "$entry")"
            [[ "$name" == "archived" || "$name" == .* || "$name" == ".data" ]] && continue
            [[ -f "$entry/compose.yaml" ]] && projects+=("$name")
        done
    fi

    local services=()
    if [[ -d "$device_dir" ]]; then
        local project
        for project in "${projects[@]}"; do
            local compose_path
            compose_path="$device_dir/$project/compose.yaml"
            [[ -f "$compose_path" ]] || continue
            while IFS= read -r service; do
                [[ -n "$service" ]] || continue
                services+=("$service")
            done < <(awk '
                /^services:[[:space:]]*$/ { in_services=1; next }
                in_services && /^[^[:space:]]/ { in_services=0 }
                in_services && /^[[:space:]][[:space:]][A-Za-z0-9_.-]+:[[:space:]]*$/ {
                    line=$0
                    sub(/^[[:space:]]+/, "", line)
                    sub(/:[[:space:]]*$/, "", line)
                    print line
                }
            ' "$compose_path")
        done
    fi

    local selected_project=""
    local selected_project_path=""
    local skip_next_for_project=false
    for ((i = 2; i < cword; i++)); do
        if $skip_next_for_project; then
            skip_next_for_project=false
            continue
        fi
        case "${words[i]}" in
            --project|-p)
                if [[ $((i + 1)) -lt ${#words[@]} ]]; then
                    selected_project="${words[i+1]}"
                fi
                skip_next_for_project=true
                ;;
            --)
                break
                ;;
        esac
    done
    if [[ -n "$selected_project" ]]; then
        if [[ -f "$device_dir/$selected_project/compose.yaml" ]]; then
            selected_project_path="$device_dir/$selected_project"
        fi
    fi

    local project_services=()
    if [[ -n "$selected_project_path" ]]; then
        while IFS= read -r service; do
            [[ -n "$service" ]] || continue
            project_services+=("$service")
        done < <(awk '
            /^services:[[:space:]]*$/ { in_services=1; next }
            in_services && /^[^[:space:]]/ { in_services=0 }
            in_services && /^[[:space:]][[:space:]][A-Za-z0-9_.-]+:[[:space:]]*$/ {
                line=$0
                sub(/^[[:space:]]+/, "", line)
                sub(/:[[:space:]]*$/, "", line)
                print line
            }
        ' "$selected_project_path/compose.yaml")
    fi

    case "$subcmd" in
        exec)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "--device -d --project -p --" -- "$cur"))
                return 0
            fi
            if [[ "$prev" == "--project" || "$prev" == "-p" ]]; then
                COMPREPLY=($(compgen -W "${projects[*]}" -- "$cur"))
                return 0
            fi
            for ((i = 2; i < cword; i++)); do
                [[ "${words[i]}" == "--" ]] && return 0
            done
            local service_arg_count=0
            local skip_next=false
            for ((i = 2; i < cword; i++)); do
                if $skip_next; then
                    skip_next=false
                    continue
                fi
                case "${words[i]}" in
                    --device|-d|--project|-p)
                        skip_next=true
                        ;;
                    --)
                        return 0
                        ;;
                    -*)
                        ;;
                    *)
                        service_arg_count=$((service_arg_count + 1))
                        ;;
                esac
            done
            if [[ $service_arg_count -eq 0 ]]; then
                if [[ -n "$selected_project" ]]; then
                    COMPREPLY=($(compgen -W "${project_services[*]} --device -d --project -p" -- "$cur"))
                else
                    COMPREPLY=($(compgen -W "${services[*]} --device -d --project -p" -- "$cur"))
                fi
            else
                COMPREPLY=($(compgen -W "--" -- "$cur"))
            fi
            return 0
            ;;
        remove|rm)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "--device -d --force -f" -- "$cur"))
                return 0
            fi

            local remove_positionals=()
            local remove_skip_next=false
            for ((i = 2; i < cword; i++)); do
                if $remove_skip_next; then
                    remove_skip_next=false
                    continue
                fi
                case "${words[i]}" in
                    --device|-d)
                        remove_skip_next=true
                        ;;
                    --force|-f)
                        ;;
                    -*)
                        ;;
                    *)
                        remove_positionals+=("${words[i]}")
                        ;;
                esac
            done

            case "${#remove_positionals[@]}" in
                0) COMPREPLY=($(compgen -W "${projects[*]} --device -d --force -f" -- "$cur")) ;;
                1) COMPREPLY=($(compgen -W "$resource_types" -- "$cur")) ;;
                *) COMPREPLY=() ;;
            esac
            return 0
            ;;
        list)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "--exclude --device -e -d --up --down --archived" -- "$cur"))
                return 0
            fi

            local list_positionals=()
            local list_skip_next=false
            for ((i = 2; i < cword; i++)); do
                if $list_skip_next; then
                    list_skip_next=false
                    continue
                fi
                case "${words[i]}" in
                    --device|-d)
                        list_skip_next=true
                        ;;
                    --exclude|-e)
                        list_skip_next=true
                        ;;
                    --up|--down|-*)
                        ;;
                    *)
                        list_positionals+=("${words[i]}")
                        ;;
                esac
            done

            case "${#list_positionals[@]}" in
                0) COMPREPLY=($(compgen -W "${projects[*]} --exclude --device -e -d --up --down --archived" -- "$cur")) ;;
                1) COMPREPLY=($(compgen -W "$resource_types" -- "$cur")) ;;
                *) COMPREPLY=() ;;
            esac
            return 0
            ;;
        archive|unarchive)
            COMPREPLY=($(compgen -W "${projects[*]} --device -d" -- "$cur"))
            return 0
            ;;
        clone)
            COMPREPLY=($(compgen -W "${projects[*]} --from --to --new" -- "$cur"))
            return 0
            ;;
        up|down|pull|restart|clean|purge|ps)
            COMPREPLY=($(compgen -W "${projects[*]} --exclude --device -e -d" -- "$cur"))
            return 0
            ;;
        nginx-urls)
            COMPREPLY=($(compgen -W "--device -d --output -o" -- "$cur"))
            return 0
            ;;
        dump)
            COMPREPLY=($(compgen -W "${projects[*]} --only-env --device -d --output -o --volumes" -- "$cur"))
            return 0
            ;;
    esac

    COMPREPLY=($(compgen -W "$subcommands --help" -- "$cur"))
}

complete -F _arcane arcane
