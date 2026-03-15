#!/bin/bash
# ============================
# vscreen bash completion
# Version: 3.1.0
# ============================
# Installation:
#   1. Copy to /etc/bash_completion.d/vscreen
#   OR
#   2. Source in ~/.bashrc: source /path/to/vscreen.bash
# ============================

_vscreen() {
  local cur prev words cword
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"
  words=("${COMP_WORDS[@]}")
  cword=$COMP_CWORD

  # ── Helpers: dynamic data ──────────────────────────────
  _vscreen_outputs() {
    xrandr 2>/dev/null | awk '/ connected/{print $1}'
  }

  _vscreen_all_virtuals() {
    xrandr 2>/dev/null | awk '/^VIRTUAL[0-9]+/{print $1}' | sort -V
  }

  _vscreen_active_virtuals() {
    xrandr 2>/dev/null | awk '/^VIRTUAL[0-9]+ connected (primary )?[0-9]+/{print $1}' | sort -V
  }

  _vscreen_free_virtuals() {
    # NOTE: comm requires lexicographically sorted inputs. Our VIRTUAL list is
    # version-sorted (VIRTUAL2 after VIRTUAL11), so comm complains.
    # Use grep set-difference instead, then sort naturally for display.
    grep -vFxf <(_vscreen_active_virtuals) <(_vscreen_all_virtuals) | sort -V
  }

  _vscreen_resolution_names() {
    local config="${SIGILS:-$HOME/.local/sigils}/spells/vscreen/config/resolutions"
    if [[ -f "$config" ]]; then
      awk '!/^[[:space:]]*#/ && NF {print $1}' "$config"
    else
      echo "FHD HD+ HD HD10 HD+10 SD"
    fi
  }

  _vscreen_layout_names() {
    local ardir="$HOME/.config/autorandr"
    if [[ -d "$ardir" ]]; then
      for d in "$ardir"/*/; do
        [[ -d "$d" ]] && basename "$d"
      done
    fi
  }

  # ── Detect context from preceding words ────────────────
  local action="" has_resolution=false has_size=false has_output=false
  local has_layout=false has_save=false

  local i
  for ((i=1; i < cword; i++)); do
    case "${words[i]}" in
      --output|-o)        action="output"; has_output=true ;;
      -c|--change)        action="change" ;;
      --off)              action="off" ;;
      --off-all)          action="off-all" ;;
      --purge)            action="purge" ;;
      --purge-all)        action="purge-all" ;;
      --list)             action="list" ;;
      --get-pos)          action="get-pos" ;;
      --align)            action="align" ;;
      --tile)             action="tile" ;;
      --pack)             action="pack" ;;
      -r|--resolution)    has_resolution=true ;;
      -s|--size)          has_size=true ;;
      -l|--layout)        has_layout=true ;;
      --save)             has_save=true ;;
    esac
  done

  # Check if two words back was a position flag (completing alignment)
  local prev2=""
  local prev3=""
  [[ $cword -ge 2 ]] && prev2="${words[cword-2]}"
  [[ $cword -ge 3 ]] && prev3="${words[cword-3]}"

  # ── Completions by previous word ───────────────────────
  case "$prev" in
    -r|--resolution)
      local names
      names=$(_vscreen_resolution_names)
      COMPREPLY=( $(compgen -W "$names --del" -- "$cur") )
      return 0
      ;;

    -s|--size)
      COMPREPLY=( $(compgen -W "1920x1080 1600x900 1440x900 1366x768 1280x800 1024x768 800x450" -- "$cur") )
      return 0
      ;;

    --output|-o)
      local fv
      fv=$(_vscreen_free_virtuals)
      if [[ -n "$fv" ]]; then
        COMPREPLY=( $(compgen -W "$fv" -- "$cur") )
      else
        COMPREPLY=( $(compgen -W "$(_vscreen_all_virtuals)" -- "$cur") )
      fi
      return 0
      ;;

    -c|--change)
      local av
      av=$(_vscreen_active_virtuals)
      [[ -n "$av" ]] && COMPREPLY=( $(compgen -W "$av" -- "$cur") )
      return 0
      ;;

    --off|--purge)
      local av
      av=$(_vscreen_active_virtuals)
      [[ -n "$av" ]] && COMPREPLY=( $(compgen -W "$av" -- "$cur") )
      return 0
      ;;

    --orientation)
      COMPREPLY=( $(compgen -W "L PR PL LF normal right left inverted" -- "$cur") )
      return 0
      ;;

    --right-of|--left-of|--above-of|--below-of)
      COMPREPLY=( $(compgen -W "$(_vscreen_outputs)" -- "$cur") )
      return 0
      ;;

    --pos)
      COMPREPLY=( $(compgen -W "0x0 1920x0 3840x0 0x1080" -- "$cur") )
      return 0
      ;;

    --list)
      COMPREPLY=( $(compgen -W "all active free" -- "$cur") )
      return 0
      ;;

    --get-pos)
      COMPREPLY=( $(compgen -W "$(_vscreen_outputs)" -- "$cur") )
      return 0
      ;;

    --ratio)
      COMPREPLY=( $(compgen -W "16:9x 16:10x 5:3x 4:3x 3:2x 16x:9 16x:10 5x:3 4x:3 3x:2" -- "$cur") )
      return 0
      ;;

    --per)
      COMPREPLY=( $(compgen -W "50 60 70 75 80 90 100 110 120 125 150 1/100 1/150 1/200 1/300" -- "$cur") )
      return 0
      ;;

    --save)
      if $has_layout; then
        COMPREPLY=( $(compgen -W "$(_vscreen_layout_names)" -- "$cur") )
      fi
      return 0
      ;;

    --del)
      if $has_resolution; then
        COMPREPLY=( $(compgen -W "$(_vscreen_resolution_names)" -- "$cur") )
      elif $has_layout; then
        COMPREPLY=( $(compgen -W "$(_vscreen_layout_names)" -- "$cur") )
      fi
      return 0
      ;;

    --ascii)
      if $has_layout; then
        COMPREPLY=( $(compgen -W "$(_vscreen_layout_names)" -- "$cur") )
      fi
      return 0
      ;;

    -l|--layout)
      local layouts
      layouts=$(_vscreen_layout_names)
      COMPREPLY=( $(compgen -W "$layouts --save --del --ascii" -- "$cur") )
      return 0
      ;;

    --align)
  COMPREPLY=( $(compgen -W "$(_vscreen_outputs)" -- "$cur") )
  return 0
  ;;

    --tile)
  COMPREPLY=( $(compgen -W "x y" -- "$cur") )
  return 0
  ;;

    --pack)
  COMPREPLY=( $(compgen -W "$(_vscreen_outputs)" -- "$cur") )
  return 0
  ;;

    --desc)
      # User types their own description, no completion
      return 0
      ;;
  esac

  # ── Alignment after position ref ───────────────────────
  case "$prev2" in
    --right-of|--left-of)
      COMPREPLY=( $(compgen -W "top center bottom" -- "$cur") )
      return 0
      ;;
    --above-of|--below-of)
      COMPREPLY=( $(compgen -W "left center right" -- "$cur") )
      return 0
      ;;
  esac

# ── Modes/refs for layout actions ──────────────────────
if [[ "$prev2" == "--align" ]]; then
  COMPREPLY=( $(compgen -W "left right hcenter top bottom vcenter center" -- "$cur") )
  return 0
fi
if [[ "$prev3" == "--align" ]]; then
  COMPREPLY=( $(compgen -W "$(_vscreen_outputs)" -- "$cur") )
  return 0
fi

if [[ "$prev2" == "--tile" ]]; then
  COMPREPLY=( $(compgen -W "$(_vscreen_outputs)" -- "$cur") )
  return 0
fi
if [[ "$prev3" == "--tile" ]]; then
  COMPREPLY=( $(compgen -W "$(_vscreen_outputs)" -- "$cur") )
  return 0
fi

if [[ "$prev2" == "--pack" ]]; then
  COMPREPLY=( $(compgen -W "$(_vscreen_outputs)" -- "$cur") )
  return 0
fi
if [[ "$prev3" == "--pack" ]]; then
  COMPREPLY=( $(compgen -W "$(_vscreen_outputs)" -- "$cur") )
  return 0
fi

  # ── Context-aware options ──────────────────────────────
  case "$action" in
    output)
      local opts="-r --resolution -s --size --orientation --ratio --per --right-of --left-of --above-of --below-of --pos --save --desc --dry-run --debug --force"
      COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
      return 0
      ;;
    change)
      local opts="-r --resolution -s --size --orientation --ratio --per --right-of --left-of --above-of --below-of --pos --dry-run --debug"
      COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
      return 0
      ;;
    align)
      local opts="--dry-run --debug"
      COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
      return 0
      ;;
    tile)
      local opts="--dry-run --debug"
      COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
      return 0
      ;;
    pack)
      local opts="--dry-run --debug"
      COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
      return 0
      ;;
    list|get-pos|off|off-all|purge|purge-all)
      return 0
      ;;
  esac

  # ── Default: main options ──────────────────────────────
  if [[ "$cur" == -* ]]; then
    local main_opts="
      --output -o -c --change
      -r --resolution -s --size
      --off --off-all --purge --purge-all
      --list --get-pos
      --align --tile --pack
      -l --layout --save --desc
      --ratio --per --orientation
      --right-of --left-of --above-of --below-of --pos
      --force -f --dry-run --debug
      --help --version
    "
    COMPREPLY=( $(compgen -W "$main_opts" -- "$cur") )
  else
    local names
    names=$(_vscreen_resolution_names)
    COMPREPLY=( $(compgen -W "$names" -- "$cur") )
  fi

  return 0
}

complete -F _vscreen vscreen
