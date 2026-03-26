#!/usr/bin/env bash
# Bash completion for zotcli

_zotcli_spell_dir() {
    local bin_path
    bin_path=$(command -v zotcli 2>/dev/null) || return 1
    bin_path=$(readlink -f "$bin_path" 2>/dev/null || realpath "$bin_path" 2>/dev/null) || return 1
    echo "$(dirname "$(dirname "$bin_path")")"
}

_zotcli_cache_collections() {
    local spell_dir cache_file
    spell_dir=$(_zotcli_spell_dir) || return
    cache_file="$spell_dir/data/cache.json"
    [[ -f "$cache_file" ]] || return
    python3 -c "
import json, sys
try:
    with open('$cache_file') as f:
        data = json.load(f)
    for col in data.get('collections', []):
        d = col.get('data', col)
        print(d.get('name', ''))
except Exception:
    pass
" 2>/dev/null
}

_zotcli_cache_item_keys() {
    local spell_dir cache_file
    spell_dir=$(_zotcli_spell_dir) || return
    cache_file="$spell_dir/data/cache.json"
    [[ -f "$cache_file" ]] || return
    python3 -c "
import json, sys
try:
    with open('$cache_file') as f:
        data = json.load(f)
    for item in data.get('items', []):
        d = item.get('data', item)
        k = d.get('key', '')
        if k:
            print(k)
except Exception:
    pass
" 2>/dev/null
}

_zotcli() {
    local cur prev words cword
    _init_completion 2>/dev/null || {
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        words=("${COMP_WORDS[@]}")
        cword=$COMP_CWORD
    }

    local subcommands="collections items info attachments connect sync"

    # Find the subcommand (skip --fresh and the binary name)
    local subcmd=""
    local i
    for ((i = 1; i < cword; i++)); do
        case "${words[i]}" in
            --fresh) continue ;;
            -*)      continue ;;
            *)       subcmd="${words[i]}"; break ;;
        esac
    done

    # No subcommand yet: complete subcommands and global flags
    if [[ -z "$subcmd" ]]; then
        COMPREPLY=($(compgen -W "$subcommands --fresh" -- "$cur"))
        return
    fi

    # Subcommand-specific completions
    case "$subcmd" in
        collections)
            COMPREPLY=($(compgen -W "--flat" -- "$cur"))
            ;;
        items)
            if [[ $cword -gt 1 && -z "${cur}" || "$cur" != "-"* ]]; then
                local names
                names=$(_zotcli_cache_collections)
                COMPREPLY=($(compgen -W "$names" -- "$cur"))
            fi
            ;;
        info|attachments)
            if [[ $cword -gt 1 && -z "${cur}" || "$cur" != "-"* ]]; then
                local keys
                keys=$(_zotcli_cache_item_keys)
                COMPREPLY=($(compgen -W "$keys" -- "$cur"))
            fi
            ;;
    esac
}

complete -F _zotcli zotcli
