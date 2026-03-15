#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
BASE_DIR="$(realpath "$SCRIPT_DIR/..")"

if [[ -d "$BASE_DIR/bin" ]]; then
  case ":$PATH:" in
    *":$BASE_DIR/bin:"*) ;;
    *) export PATH="$BASE_DIR/bin:$PATH" ;;
  esac
fi

shopt -s nullglob
for completion in "$BASE_DIR"/spells/*/completions/bash/*.bash; do
  [[ -f "$completion" ]] && source "$completion"
done
