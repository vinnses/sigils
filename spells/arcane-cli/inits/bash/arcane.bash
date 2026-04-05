#!/usr/bin/env bash

arcane() {
    if [[ "${1:-}" == "cd" ]]; then
        shift
        local target
        target="$(command arcane path "$@")" || return $?
        builtin cd "$target"
        return 0
    fi

    command arcane "$@"
}
