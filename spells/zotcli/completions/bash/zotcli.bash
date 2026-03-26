#!/usr/bin/env bash
# Bash completion for zotcli (v2)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_zotcli_spell_dir() {
    local bin_path
    bin_path=$(command -v zotcli 2>/dev/null) || return 1
    bin_path=$(readlink -f "$bin_path" 2>/dev/null || realpath "$bin_path" 2>/dev/null) || return 1
    dirname "$(dirname "$bin_path")"
}

_zotcli_state_key() {
    local spell_dir state_file
    spell_dir=$(_zotcli_spell_dir) || return
    state_file="$spell_dir/data/state.json"
    [[ -f "$state_file" ]] || { echo "null"; return; }
    python3 -c "
import json, sys
try:
    with open('$state_file') as f:
        print(json.load(f).get('collection_key') or 'null')
except Exception:
    print('null')
" 2>/dev/null
}

# Emit collection names at the given parent_key level (null = top-level)
_zotcli_collections_at() {
    local spell_dir cache_file parent_key="$1"
    spell_dir=$(_zotcli_spell_dir) || return
    cache_file="$spell_dir/data/cache.json"
    [[ -f "$cache_file" ]] || return
    python3 -c "
import json, sys
parent = None if '$parent_key' in ('null', '') else '$parent_key'
try:
    with open('$cache_file') as f:
        cols = json.load(f).get('collections', [])
    for c in cols:
        d = c.get('data', c)
        p = d.get('parentCollection') or None
        if p == parent:
            print(d.get('name', ''))
except Exception:
    pass
" 2>/dev/null
}

# Resolve a partially-typed absolute path prefix (~/foo/bar) and return
# the collection key of the last fully resolved segment, plus the trailing
# partial name for prefix-match.
# Outputs: "<parent_key> <partial>" on one line.
_zotcli_resolve_partial_path() {
    local spell_dir cache_file path_so_far="$1"
    spell_dir=$(_zotcli_spell_dir) || return
    cache_file="$spell_dir/data/cache.json"
    [[ -f "$cache_file" ]] || return
    python3 -c "
import json, sys
path = '$path_so_far'
try:
    with open('$cache_file') as f:
        cols = json.load(f).get('collections', [])
except Exception:
    sys.exit(0)

# Strip leading ~/
if path.startswith('~/'):
    path = path[2:]
elif path.startswith('/'):
    path = path[1:]
else:
    sys.exit(0)

# Walk all but the last segment
parts = path.split('/')
resolved_parts = parts[:-1]
partial        = parts[-1]

parent = None
for part in resolved_parts:
    if not part:
        continue
    match = next((c for c in cols
                  if (c.get('data',c).get('parentCollection') or None) == parent
                  and c.get('data',c).get('name','') == part), None)
    if match is None:
        sys.exit(0)
    parent = match.get('data', match).get('key')

print(parent if parent is not None else 'null', partial)
" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Main completion function
# ---------------------------------------------------------------------------

_zotcli() {
    local cur prev words cword
    _init_completion 2>/dev/null || {
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        words=("${COMP_WORDS[@]}")
        cword=$COMP_CWORD
    }

    local subcommands="cd pwd ls tree cat get connect sync --fresh"

    # Find the subcommand (skip --fresh and the binary name)
    local subcmd=""
    local i
    for ((i = 1; i < cword; i++)); do
        case "${words[i]}" in
            --fresh|-*) continue ;;
            *)          subcmd="${words[i]}"; break ;;
        esac
    done

    # No subcommand yet
    if [[ -z "$subcmd" ]]; then
        COMPREPLY=($(compgen -W "$subcommands" -- "$cur"))
        return
    fi

    # ----------------------------------------------------------------
    # Subcommand-specific completions
    # ----------------------------------------------------------------
    case "$subcmd" in

        cd|ls)
            # Complete collection names.
            # Handle absolute paths (~/...) and relative paths.
            if [[ "$cur" == "~/"* ]]; then
                # Absolute path: resolve up to the last /
                local read result parent_key partial
                read -r parent_key partial < <(_zotcli_resolve_partial_path "$cur")
                if [[ -n "$parent_key" ]]; then
                    local names
                    names=$(_zotcli_collections_at "$parent_key")
                    # Build completions preserving the prefix up to last /
                    local prefix="${cur%/*}/"
                    local suggestions=()
                    while IFS= read -r name; do
                        [[ "$name" == "$partial"* ]] && suggestions+=("${prefix}${name}/")
                    done <<< "$names"
                    COMPREPLY=("${suggestions[@]}")
                fi
            elif [[ "$cur" == "~" ]]; then
                COMPREPLY=($(compgen -W "~/" -- "$cur"))
            elif [[ "$subcmd" == "cd" && "$cur" == "-" ]]; then
                COMPREPLY=("-")
            else
                # Relative: complete names at current state level
                local current_key
                current_key=$(_zotcli_state_key)
                local names
                names=$(_zotcli_collections_at "$current_key")
                # Append / to each to signal it's a directory-like path
                local suggestions=()
                while IFS= read -r name; do
                    [[ "$name" == "$cur"* ]] && suggestions+=("${name}/")
                done <<< "$names"
                COMPREPLY=("${suggestions[@]}")
                # Also offer special tokens for cd
                if [[ "$subcmd" == "cd" ]]; then
                    COMPREPLY+=($(compgen -W "~ .. -" -- "$cur"))
                fi
            fi
            ;;

        cat|get)
            # Complete item references from cache (citation keys).
            # Only offer top-level cache data since we don't cache per-collection.
            local spell_dir cache_file
            spell_dir=$(_zotcli_spell_dir) || return
            # No item cache in v2 — graceful fallback (no API call during completion)
            ;;

        tree|pwd|connect|sync)
            # No argument completion needed
            ;;

    esac
}

complete -F _zotcli zotcli
