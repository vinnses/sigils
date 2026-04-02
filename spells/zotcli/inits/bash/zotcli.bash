#!/usr/bin/env bash
# zotcli shell init (v3)
# Provides: shell wrapper, __zotcli_ps1, prompt hook, zot() alias.
#
# Sourced automatically by the sigils init system (init/env.bash).
# This file is sourced BEFORE completions.

# ---------------------------------------------------------------------------
# Shell wrapper — captures __ZOTCLI_ENV__ exports, forces colors
# ---------------------------------------------------------------------------

zotcli() {
    # 'nav' is handled entirely in bash (interactive loop)
    if [[ "${1:-}" == "nav" ]]; then
        __zotcli_nav
        return $?
    fi

    # ZOTCLI_COLOR=1 forces ANSI codes even though stdout is a pipe
    local output exitcode
    output=$(ZOTCLI_COLOR=1 command zotcli "$@")
    exitcode=$?

    # Parse __ZOTCLI_ENV__ lines; print the rest
    local line var val
    while IFS= read -r line; do
        if [[ "$line" == __ZOTCLI_ENV__* ]]; then
            var="${line#__ZOTCLI_ENV__}"
            val="${var#*=}"
            var="${var%%=*}"
            if [[ -z "$val" ]]; then
                unset "$var"
            else
                export "$var=$val"
            fi
        else
            printf '%s\n' "$line"
        fi
    done <<< "$output"

    return $exitcode
}

zot() { zotcli "$@"; }

# ---------------------------------------------------------------------------
# PS1 helper — returns info string when zotcli visual mode is active
#
# Returns nothing (empty) when ZOTCLI_VISUAL != 1, so it naturally
# disappears when zotcli hasn't been used or prompt is off.
#
# Integration with _update_prompt style prompts:
#
#   _update_prompt() {
#       local EXIT_CODE=$?
#       ...
#       local zot_info="$(__zotcli_ps1)"
#       if [[ -n "$zot_info" ]]; then
#           local C_ZOT='\[\e[36m\]'
#           PS1+="${C_ZOT}${zot_info}${C_RESET} "
#       fi
#       ...
#   }
#
# Or inline in PS1 (simpler but runs a subshell each prompt):
#   PS1+='$(__zotcli_ps1 " [%s]")'
# ---------------------------------------------------------------------------

__zotcli_ps1() {
    [[ "${ZOTCLI_VISUAL:-}" != "1" ]] && return

    local fmt="${1:-%s}"
    local path="${ZOTCLI_PATH:-zot://}"
    printf -- "$fmt" "$path"
}

# ---------------------------------------------------------------------------
# Prompt hook — appends zotcli path info to PS1 when visual mode is active
# ---------------------------------------------------------------------------

__zotcli_prompt_apply() {
    local _prev=$?
    local _zot_info
    _zot_info="$(__zotcli_ps1)"
    [[ -z "$_zot_info" ]] && return $_prev

    local _color="${ZOTCLI_PROMPT_COLOR:-\e[36m}"
    local _reset='\e[0m'
    PS1="${PS1%\[\\e\[*m\]*\[\\e\[0m\] }\[${_color}\]${_zot_info}\[${_reset}\] "
    return $_prev
}

# ---------------------------------------------------------------------------
# Navigation mode — interactive loop where bare commands become zot commands
#
#   zot nav
#   zot://0.Inbox > ls
#   zot://0.Inbox > cd 1.Books
#   zot://1.Books > cat jurafsky2026
#   zot://1.Books > exit
#
# Known zot commands are intercepted. Anything else runs in normal shell.
# Exit with 'exit', 'quit', or Ctrl+D.
# ---------------------------------------------------------------------------

__zotcli_nav() {
    # Auto-activate visual mode
    if [[ "${ZOTCLI_VISUAL:-}" != "1" ]]; then
        zotcli visual --on
    fi

    local _nav_cmds="cd pwd ls tree cat get find sync config visual connect help"
    local _cyan=$'\033[36m' _dim=$'\033[2m' _nc=$'\033[0m'

    printf "%s\n" "${_dim}Entering zot navigation mode. Type 'exit' or Ctrl+D to leave.${_nc}"

    local _cmd _args
    while true; do
        local _path="${ZOTCLI_PATH:-zot://}"
        printf "${_cyan}%s${_nc} > " "$_path"

        if ! IFS= read -r -e _line; then
            echo
            break  # Ctrl+D
        fi

        # Strip leading/trailing whitespace
        _line="${_line#"${_line%%[![:space:]]*}"}"
        _line="${_line%"${_line##*[![:space:]]}"}"
        [[ -z "$_line" ]] && continue

        # Split into command and args
        _cmd="${_line%% *}"
        if [[ "$_line" == *" "* ]]; then
            _args="${_line#* }"
        else
            _args=""
        fi

        case "$_cmd" in
            exit|quit)
                break
                ;;
            *)
                # Check if it's a known zot command
                local _is_zot=0 _c
                for _c in $_nav_cmds; do
                    [[ "$_cmd" == "$_c" ]] && { _is_zot=1; break; }
                done

                if [[ $_is_zot -eq 1 ]]; then
                    zotcli "$_cmd" $_args
                else
                    # Pass through to normal shell
                    eval "$_line"
                fi
                ;;
        esac
    done
}

# Install hook (idempotent — no-op when ZOTCLI_VISUAL != 1)
case ";${PROMPT_COMMAND:-};" in
    *";__zotcli_prompt_apply;"*) ;;
    *) PROMPT_COMMAND="${PROMPT_COMMAND:+${PROMPT_COMMAND}; }__zotcli_prompt_apply" ;;
esac
