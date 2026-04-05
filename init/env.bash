#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
BASE_DIR="$(realpath "$SCRIPT_DIR/..")"
SPELL_HELPERS="$BASE_DIR/lib/common/spells.bash"

if [[ -d "$BASE_DIR/bin" ]]; then
  case ":$PATH:" in
    *":$BASE_DIR/bin:"*) ;;
    *) export PATH="$BASE_DIR/bin:$PATH" ;;
  esac
fi

if [[ -f "$SPELL_HELPERS" ]]; then
  SIGILS_ROOT="$BASE_DIR"
  source "$SPELL_HELPERS"
  while IFS=$'\t' read -r _spell spell_dir; do
    shopt -s nullglob
    for init in "$spell_dir"/inits/bash/*.bash; do
      [[ -f "$init" ]] && source "$init"
    done
    for completion in "$spell_dir"/completions/bash/*.bash; do
      [[ -f "$completion" ]] && source "$completion"
    done
  done < <(sigils_iter_enabled_spells)
else
  shopt -s nullglob
  for init in "$BASE_DIR"/spells/*/inits/bash/*.bash; do
    [[ -f "$init" ]] && source "$init"
  done
  for completion in "$BASE_DIR"/spells/*/completions/bash/*.bash; do
    [[ -f "$completion" ]] && source "$completion"
  done
fi
