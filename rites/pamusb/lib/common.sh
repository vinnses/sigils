#!/bin/bash
# lib/common.sh — shared utilities: logging, colors, confirmations, USB detection

# ─── Colors ──────────────────────────────────────────────────────────────────

_color_init() {
    if [[ -t 2 ]]; then
        C_RESET='\033[0m'
        C_BOLD='\033[1m'
        C_DIM='\033[2m'
        C_RED='\033[0;31m'
        C_GREEN='\033[0;32m'
        C_YELLOW='\033[0;33m'
        C_BLUE='\033[0;34m'
        C_CYAN='\033[0;36m'
        C_WHITE='\033[0;37m'
        C_BRED='\033[1;31m'
        C_BGREEN='\033[1;32m'
        C_BYELLOW='\033[1;33m'
        C_BBLUE='\033[1;34m'
        C_BCYAN='\033[1;36m'
    else
        C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW=''
        C_BLUE='' C_CYAN='' C_WHITE='' C_BRED='' C_BGREEN=''
        C_BYELLOW='' C_BBLUE='' C_BCYAN=''
    fi
}

_color_init

# ─── Logging ─────────────────────────────────────────────────────────────────

: "${LOG_FILE:="${SPELL_DIR}/logs/setup.log"}"
: "${LOG_LEVEL:="INFO"}"

_log_level_num() {
    case "$1" in
        DEBUG) echo 0 ;;
        INFO)  echo 1 ;;
        WARN)  echo 2 ;;
        ERROR) echo 3 ;;
        FATAL) echo 4 ;;
        *)     echo 1 ;;
    esac
}

_log() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')

    local current_num
    current_num=$(_log_level_num "$LOG_LEVEL")
    local msg_num
    msg_num=$(_log_level_num "$level")
    [[ "$msg_num" -lt "$current_num" ]] && return 0

    # Write to log file
    if [[ -n "$LOG_FILE" ]]; then
        mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
        printf '%s [%s] %s\n' "$ts" "$level" "$msg" >> "$LOG_FILE" 2>/dev/null
    fi

    # Write to stderr with color
    case "$level" in
        DEBUG) printf "${C_DIM}[debug]${C_RESET} %s\n" "$msg" >&2 ;;
        INFO)  printf "${C_BLUE}[info]${C_RESET}  %s\n" "$msg" >&2 ;;
        WARN)  printf "${C_BYELLOW}[warn]${C_RESET}  %s\n" "$msg" >&2 ;;
        ERROR) printf "${C_BRED}[error]${C_RESET} %s\n" "$msg" >&2 ;;
        FATAL) printf "${C_BRED}${C_BOLD}[fatal]${C_RESET} %s\n" "$msg" >&2 ;;
    esac
}

log_debug() { _log DEBUG "$@"; }
log_info()  { _log INFO  "$@"; }
log_warn()  { _log WARN  "$@"; }
log_error() { _log ERROR "$@"; }
log_fatal() { _log FATAL "$@"; }

# ─── UI helpers ──────────────────────────────────────────────────────────────

print_header() {
    local title="$1"
    echo >&2
    printf "${C_BCYAN}${C_BOLD}══ %s ══${C_RESET}\n" "$title" >&2
}

print_step() {
    local n="$1"; local total="$2"; local msg="$3"
    printf "${C_BBLUE}[%s/%s]${C_RESET} %s\n" "$n" "$total" "$msg" >&2
}

print_ok() {
    printf "  ${C_BGREEN}✓${C_RESET} %s\n" "$*" >&2
}

print_fail() {
    printf "  ${C_BRED}✗${C_RESET} %s\n" "$*" >&2
}

print_warn() {
    printf "  ${C_BYELLOW}!${C_RESET} %s\n" "$*" >&2
}

print_info() {
    printf "  ${C_BLUE}·${C_RESET} %s\n" "$*" >&2
}

print_section() {
    printf "\n${C_BOLD}%s${C_RESET}\n" "$*" >&2
    printf '%*s\n' "${#1}" '' | tr ' ' '─' >&2
}

# ─── Confirmation helpers ─────────────────────────────────────────────────────

# confirm_yn <prompt> — returns 0 for yes, 1 for no
confirm_yn() {
    local prompt="${1:-Continue?}"
    local reply
    while true; do
        printf "${C_BOLD}%s${C_RESET} [y/N] " "$prompt" >&2
        read -r reply
        case "${reply,,}" in
            y|yes) return 0 ;;
            n|no|"") return 1 ;;
            *) printf "Please answer y or n.\n" >&2 ;;
        esac
    done
}

# confirm_yes <prompt> — requires typing "yes" (for destructive ops)
confirm_yes() {
    local prompt="${1:-Type 'yes' to confirm}"
    local reply
    printf "${C_BYELLOW}${C_BOLD}%s:${C_RESET} " "$prompt" >&2
    read -r reply
    [[ "$reply" == "yes" ]]
}

# prompt_value <prompt> <varname> [default]
prompt_value() {
    local prompt="$1"
    local varname="$2"
    local default="${3:-}"
    local reply

    if [[ -n "$default" ]]; then
        printf "${C_BOLD}%s${C_RESET} [%s]: " "$prompt" "$default" >&2
    else
        printf "${C_BOLD}%s${C_RESET}: " "$prompt" >&2
    fi
    read -r reply
    if [[ -z "$reply" && -n "$default" ]]; then
        reply="$default"
    fi
    printf -v "$varname" '%s' "$reply"
}

# prompt_secret <prompt> <varname> — hidden input
prompt_secret() {
    local prompt="$1"
    local varname="$2"
    local reply
    printf "${C_BOLD}%s${C_RESET}: " "$prompt" >&2
    read -rs reply
    echo >&2
    printf -v "$varname" '%s' "$reply"
}

# prompt_secret_confirm <prompt> <varname> — hidden input with confirmation
prompt_secret_confirm() {
    local prompt="$1"
    local varname="$2"
    local a b
    while true; do
        prompt_secret "$prompt" a
        prompt_secret "Confirm $prompt" b
        if [[ "$a" == "$b" ]]; then
            printf -v "$varname" '%s' "$a"
            return 0
        fi
        log_warn "Passwords do not match, try again."
    done
}

# menu_select <varname> <items...> — numbered menu, sets varname to chosen item
menu_select() {
    local varname="$1"; shift
    local items=("$@")
    local i reply

    for (( i=0; i<${#items[@]}; i++ )); do
        printf "  ${C_BOLD}%d)${C_RESET} %s\n" "$(( i + 1 ))" "${items[$i]}" >&2
    done

    while true; do
        printf "${C_BOLD}Select [1-%d]:${C_RESET} " "${#items[@]}" >&2
        read -r reply
        if [[ "$reply" =~ ^[0-9]+$ ]] && (( reply >= 1 && reply <= ${#items[@]} )); then
            printf -v "$varname" '%s' "${items[$(( reply - 1 ))]}"
            return 0
        fi
        printf "Invalid choice.\n" >&2
    done
}

# ─── Config file helpers ──────────────────────────────────────────────────────

: "${CONF_FILE:="${SPELL_DIR}/config/pamusb.conf"}"

conf_load() {
    [[ -f "$CONF_FILE" ]] && source "$CONF_FILE"
    return 0
}

conf_set() {
    local key="$1"
    local value="$2"

    mkdir -p "$(dirname "$CONF_FILE")"

    if [[ ! -f "$CONF_FILE" ]]; then
        printf '# Generated by pamusb setup — do not edit manually\n' > "$CONF_FILE"
    fi

    if grep -q "^${key}=" "$CONF_FILE" 2>/dev/null; then
        # Update existing
        local escaped_value
        escaped_value=$(printf '%s' "$value" | sed 's/[&/\]/\\&/g')
        sed -i "s|^${key}=.*|${key}=\"${escaped_value}\"|" "$CONF_FILE"
    else
        printf '%s="%s"\n' "$key" "$value" >> "$CONF_FILE"
    fi
}

conf_get() {
    local key="$1"
    local default="${2:-}"
    local val
    val=$(grep "^${key}=" "$CONF_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' || true)
    echo "${val:-$default}"
}

conf_unset() {
    local key="$1"
    [[ -f "$CONF_FILE" ]] || return 0
    sed -i "/^${key}=/d" "$CONF_FILE"
}

conf_mark_step() {
    local step="$1"
    conf_set "SETUP_STEP_COMPLETED" "$step"
    conf_set "SETUP_LAST_UPDATED" "$(date -Iseconds)"
}

# ─── USB device detection ─────────────────────────────────────────────────────

# List all removable block devices as JSON
usb_list_devices() {
    if ! command -v lsblk &>/dev/null; then
        log_error "lsblk not found (util-linux required)"
        return 1
    fi
    lsblk --json -o NAME,MODEL,SERIAL,SIZE,TYPE,RM,MOUNTPOINT,TRAN 2>/dev/null \
        | jq -r '.blockdevices[] | select(.rm == true and .type == "disk")'
}

# List removable block device names (/dev/sdX)
usb_list_device_names() {
    lsblk --json -o NAME,TYPE,RM 2>/dev/null \
        | jq -r '.blockdevices[] | select(.rm == true and .type == "disk") | "/dev/" + .name'
}

# Get device info fields for a given /dev path
usb_device_info() {
    local dev="$1"
    local devname="${dev#/dev/}"
    lsblk --json -o NAME,MODEL,SERIAL,SIZE,TYPE,RM,TRAN "$dev" 2>/dev/null \
        | jq -r --arg n "$devname" '.blockdevices[] | select(.name == $n)'
}

# Validate a device is safe to use
usb_validate_device() {
    local dev="$1"

    # Must be removable
    local rm_flag
    rm_flag=$(lsblk --nodeps --noheadings -o RM "$dev" 2>/dev/null | tr -d ' ')
    if [[ "$rm_flag" != "1" ]]; then
        log_error "$dev is not a removable device"
        return 1
    fi

    # Must not be root filesystem
    local root_dev
    root_dev=$(findmnt -n -o SOURCE / 2>/dev/null)
    if [[ "$root_dev" == "${dev}"* ]]; then
        log_error "$dev appears to be the root filesystem device — refusing"
        return 1
    fi

    # Must not be the boot device
    local boot_dev
    boot_dev=$(findmnt -n -o SOURCE /boot 2>/dev/null)
    if [[ -n "$boot_dev" && "$boot_dev" == "${dev}"* ]]; then
        log_error "$dev appears to be the boot device — refusing"
        return 1
    fi

    return 0
}

# Get partition UUIDs for a device
usb_get_partition_uuid() {
    local part="$1"
    blkid -s UUID -o value "$part" 2>/dev/null
}

usb_get_partition_label() {
    local part="$1"
    blkid -s LABEL -o value "$part" 2>/dev/null
}

# Get partition filesystem type
usb_get_partition_fstype() {
    local part="$1"
    blkid -s TYPE -o value "$part" 2>/dev/null
}

# Check if a partition is currently mounted
usb_is_mounted() {
    local dev="$1"
    findmnt -n "$dev" &>/dev/null
}

# Get mount point for a device
usb_get_mountpoint() {
    local dev="$1"
    findmnt -n -o TARGET "$dev" 2>/dev/null
}

# Wait for a block device by UUID to appear (with timeout)
# usb_wait_for_uuid <uuid> <timeout_seconds>
usb_wait_for_uuid() {
    local uuid="$1"
    local timeout="${2:-30}"
    local elapsed=0
    local dev_path="/dev/disk/by-uuid/${uuid}"

    while [[ ! -e "$dev_path" ]]; do
        if (( elapsed >= timeout )); then
            log_error "Timed out waiting for UUID $uuid to appear"
            return 1
        fi
        sleep 1
        (( elapsed++ ))
    done
    echo "$dev_path"
}

usb_match_kind_normalize() {
    case "${1:-uuid}" in
        uuid|UUID) echo "uuid" ;;
        label|LABEL) echo "label" ;;
        *)
            log_error "USB match kind must be 'uuid' or 'label'"
            return 1
            ;;
    esac
}

usb_match_env_name() {
    case "$(usb_match_kind_normalize "$1")" in
        uuid) echo "ID_FS_UUID" ;;
        label) echo "ID_FS_LABEL" ;;
    esac
}

usb_current_match_kind() {
    usb_match_kind_normalize "$(conf_get "USB_MAIN_PARTITION_MATCH_KIND" "uuid")"
}

usb_current_match_value() {
    local kind
    kind="$(usb_current_match_kind)" || return 1
    case "$kind" in
        uuid) conf_get "USB_MAIN_PARTITION_MATCH_VALUE" "$(conf_get "USB_MAIN_PARTITION_UUID" "")" ;;
        label) conf_get "USB_MAIN_PARTITION_MATCH_VALUE" "$(conf_get "USB_MAIN_PARTITION_LABEL" "")" ;;
    esac
}

usb_set_main_match() {
    local kind="$1"
    local value="$2"
    kind="$(usb_match_kind_normalize "$kind")" || return 1
    [[ -n "$value" ]] || {
        log_error "USB match value cannot be empty"
        return 1
    }

    conf_set "USB_MAIN_PARTITION_MATCH_KIND" "$kind"
    conf_set "USB_MAIN_PARTITION_MATCH_VALUE" "$value"
    case "$kind" in
        uuid) conf_set "USB_MAIN_PARTITION_UUID" "$value" ;;
        label) conf_set "USB_MAIN_PARTITION_LABEL" "$value" ;;
    esac
}

usb_clear_main_match() {
    conf_unset "USB_MAIN_PARTITION_MATCH_KIND"
    conf_unset "USB_MAIN_PARTITION_MATCH_VALUE"
    conf_unset "USB_MAIN_PARTITION_UUID"
    conf_unset "USB_MAIN_PARTITION_LABEL"
}

# ─── System detection ─────────────────────────────────────────────────────────

# Detect distro: outputs debian|arch|unknown
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        local id
        id=$(. /etc/os-release && echo "${ID:-unknown}")
        case "$id" in
            ubuntu|debian|linuxmint|pop) echo "debian" ;;
            arch|manjaro|endeavouros|garuda) echo "arch" ;;
            *) echo "$id" ;;
        esac
    else
        echo "unknown"
    fi
}

# Find pam_usb.so path
find_pam_usb_so() {
    local candidates=(
        "/lib/x86_64-linux-gnu/security/pam_usb.so"
        "/lib/aarch64-linux-gnu/security/pam_usb.so"
        "/lib/security/pam_usb.so"
        "/usr/lib/security/pam_usb.so"
        "/usr/lib/x86_64-linux-gnu/security/pam_usb.so"
    )
    for path in "${candidates[@]}"; do
        [[ -f "$path" ]] && echo "$path" && return 0
    done
    # Try find as last resort
    find /lib /usr/lib -name 'pam_usb.so' 2>/dev/null | head -1
}

# Detect display manager PAM file
detect_display_manager_pam() {
    local dm_pam_files=(
        "/etc/pam.d/gdm-password"
        "/etc/pam.d/gdm-autologin"
        "/etc/pam.d/sddm"
        "/etc/pam.d/lightdm"
        "/etc/pam.d/ly"
    )
    for f in "${dm_pam_files[@]}"; do
        [[ -f "$f" ]] && echo "$f"
    done
}

# ─── Command checks ───────────────────────────────────────────────────────────

require_root() {
    if [[ "$EUID" -ne 0 ]]; then
        log_fatal "This operation requires root privileges. Run with sudo."
        exit 1
    fi
}

require_cmd() {
    local cmd="$1"
    local hint="${2:-}"
    if ! command -v "$cmd" &>/dev/null; then
        log_error "Required command not found: $cmd"
        [[ -n "$hint" ]] && log_error "  $hint"
        return 1
    fi
}

check_dependencies() {
    local -a missing=()
    local -A pkgs_debian=(
        [cryptsetup]="cryptsetup"
        [lsblk]="util-linux"
        [blkid]="util-linux"
        [parted]="parted"
        [jq]="jq"
        [mkfs.ext4]="e2fsprogs"
        [mkfs.vfat]="dosfstools"
        [udevadm]="udev"
        [visudo]="sudo"
        [loginctl]="systemd"
    )

    for cmd in "${!pkgs_debian[@]}"; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        local distro
        distro=$(detect_distro)
        log_error "Missing required tools: ${missing[*]}"
        if [[ "$distro" == "debian" ]]; then
            log_error "Install with: sudo apt install ${missing[*]}"
        elif [[ "$distro" == "arch" ]]; then
            log_error "Install with: sudo pacman -S ${missing[*]}"
        fi
        return 1
    fi
    return 0
}
