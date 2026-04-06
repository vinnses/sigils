#!/usr/bin/env bash

mail_pass_store_dir() {
    printf '%s\n' "${PASSWORD_STORE_DIR:-$HOME/.password-store}"
}

mail_pass_is_initialized() {
    local store_dir

    store_dir="$(mail_pass_store_dir)"
    [[ -d "$store_dir" && -f "$store_dir/.gpg-id" ]]
}
