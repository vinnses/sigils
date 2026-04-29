#!/bin/bash
# lib/partition.sh — USB partition analysis, planning, and execution

# ─── Analysis ────────────────────────────────────────────────────────────────

# Detect partition table type: gpt|msdos|none
partition_table_type() {
    local dev="$1"
    parted -s "$dev" print 2>/dev/null | awk '/^Partition Table:/ {print $3}'
}

# List partitions as tab-separated: num start end size fstype label uuid
partition_list() {
    local dev="$1"
    parted -s -m "$dev" unit MiB print 2>/dev/null | tail -n +3 | while IFS=':' read -r num start end size fstype name flags; do
        # Strip trailing MiB from sizes
        start="${start%MiB}"
        end="${end%MiB}"
        size="${size%MiB}"
        local uuid=""
        local part_dev="${dev}${num}"
        # parted adds 'p' prefix for nvme/mmcblk devices
        [[ "$dev" =~ [0-9]$ ]] && part_dev="${dev}p${num}"
        uuid=$(blkid -s UUID -o value "$part_dev" 2>/dev/null)
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$num" "$start" "$end" "$size" "${fstype:-unknown}" "${name:-}" "${uuid:-}"
    done
}

# Get disk size in MiB
partition_disk_size_mib() {
    local dev="$1"
    parted -s -m "$dev" unit MiB print 2>/dev/null | grep "^${dev##*/}" | cut -d: -f2 | tr -d 'MiB'
}

# Check if ≥128MiB of unallocated space exists at the end of the disk
partition_free_at_end_mib() {
    local dev="$1"
    local disk_size_mib
    disk_size_mib=$(partition_disk_size_mib "$dev")

    local last_end=0
    while IFS=$'\t' read -r num start end size fstype name uuid; do
        # Use last partition's end as our reference
        last_end="$end"
    done < <(partition_list "$dev")

    if [[ -z "$disk_size_mib" || -z "$last_end" ]]; then
        echo "0"
        return
    fi

    local free_mib
    free_mib=$(awk "BEGIN { printf \"%.0f\", $disk_size_mib - $last_end - 1 }")
    echo "$free_mib"
}

# Print a human-readable partition layout table
partition_print_layout() {
    local dev="$1"
    local table_type
    table_type=$(partition_table_type "$dev")

    echo >&2
    printf "${C_BOLD}Device:${C_RESET} %s  |  ${C_BOLD}Table:${C_RESET} %s  |  ${C_BOLD}Size:${C_RESET} %s MiB\n" \
        "$dev" "${table_type:-none}" "$(partition_disk_size_mib "$dev")" >&2
    printf "\n%-4s  %-10s  %-10s  %-10s  %-10s  %-20s  %s\n" \
        "Num" "Start(MiB)" "End(MiB)" "Size(MiB)" "FS" "Label" "UUID" >&2
    printf '%s\n' "$(printf '─%.0s' {1..80})" >&2

    local count=0
    while IFS=$'\t' read -r num start end size fstype name uuid; do
        printf "%-4s  %-10s  %-10s  %-10s  %-10s  %-20s  %s\n" \
            "$num" "$start" "$end" "$size" "$fstype" "$name" "$uuid" >&2
        (( count++ ))
    done < <(partition_list "$dev")

    if [[ "$count" -eq 0 ]]; then
        printf "  (no partitions)\n" >&2
    fi

    local free_end
    free_end=$(partition_free_at_end_mib "$dev")
    (( free_end > 0 )) && printf "\n  ${C_DIM}%s MiB unallocated at end of disk${C_RESET}\n" "$free_end" >&2
    echo >&2
}

# ─── Planning ─────────────────────────────────────────────────────────────────

# Returns: virgin|has_free|needs_resize|has_luks|unknown
partition_assess() {
    local dev="$1"
    local luks_uuid="${2:-}"

    # Check if existing LUKS partition matches config
    if [[ -n "$luks_uuid" ]]; then
        local existing_luks_uuid
        while IFS=$'\t' read -r num start end size fstype name uuid; do
            if [[ "$uuid" == "$luks_uuid" ]]; then
                echo "has_luks"
                return 0
            fi
        done < <(partition_list "$dev")
    fi

    local table_type
    table_type=$(partition_table_type "$dev")

    if [[ -z "$table_type" || "$table_type" == "unknown" ]]; then
        echo "virgin"
        return 0
    fi

    local free_end
    free_end=$(partition_free_at_end_mib "$dev")
    if (( free_end >= 128 )); then
        echo "has_free"
        return 0
    fi

    echo "needs_resize"
}

# ─── Execution — virgin disk ──────────────────────────────────────────────────

# Create GPT table with two partitions
partition_create_gpt() {
    local dev="$1"
    local luks_size_mib="${2:-128}"

    log_info "Creating GPT partition table on $dev"

    parted -s "$dev" mklabel gpt || {
        log_error "Failed to create GPT table on $dev"
        return 1
    }

    local disk_mib
    disk_mib=$(partition_disk_size_mib "$dev")
    local luks_start=$(( disk_mib - luks_size_mib - 1 ))
    local luks_end=$(( disk_mib - 1 ))

    log_info "Creating main partition (1 MiB → ${luks_start} MiB)"
    parted -s "$dev" mkpart primary fat32 1MiB "${luks_start}MiB" || {
        log_error "Failed to create main partition"
        return 1
    }

    log_info "Creating LUKS partition (${luks_start} MiB → ${luks_end} MiB)"
    parted -s "$dev" mkpart primary "${luks_start}MiB" "${luks_end}MiB" || {
        log_error "Failed to create LUKS partition"
        return 1
    }

    partprobe "$dev" 2>/dev/null
    sleep 1

    # Format main partition as vfat
    local main_part="${dev}1"
    [[ "$dev" =~ [0-9]$ ]] && main_part="${dev}p1"
    log_info "Formatting main partition as vfat"
    mkfs.vfat -F32 "$main_part" || {
        log_error "Failed to format main partition as vfat"
        return 1
    }

    print_ok "Partitions created successfully"
    return 0
}

# ─── Execution — use existing free space ─────────────────────────────────────

partition_create_in_free() {
    local dev="$1"
    local luks_size_mib="${2:-128}"

    local disk_mib
    disk_mib=$(partition_disk_size_mib "$dev")
    local luks_start=$(( disk_mib - luks_size_mib - 1 ))
    local luks_end=$(( disk_mib - 1 ))

    log_info "Creating LUKS partition in free space (${luks_start} MiB → ${luks_end} MiB)"
    parted -s "$dev" mkpart primary "${luks_start}MiB" "${luks_end}MiB" || {
        log_error "Failed to create LUKS partition in free space"
        return 1
    }

    partprobe "$dev" 2>/dev/null
    sleep 1
    print_ok "LUKS partition created in free space"
    return 0
}

# ─── Execution — resize last partition ───────────────────────────────────────

partition_resize_last() {
    local dev="$1"
    local luks_size_mib="${2:-128}"

    # Find last partition
    local last_num last_start last_end last_fstype
    while IFS=$'\t' read -r num start end size fstype name uuid; do
        last_num="$num"
        last_start="$start"
        last_end="$end"
        last_fstype="$fstype"
    done < <(partition_list "$dev")

    if [[ -z "$last_num" ]]; then
        log_error "No partitions found on $dev"
        return 1
    fi

    local last_part="${dev}${last_num}"
    [[ "$dev" =~ [0-9]$ ]] && last_part="${dev}p${last_num}"

    # Check if mounted
    if usb_is_mounted "$last_part"; then
        log_error "Partition $last_part is currently mounted — unmount first"
        return 1
    fi

    local new_end
    new_end=$(awk "BEGIN { printf \"%.0f\", $last_end - $luks_size_mib - 1 }")

    log_info "Shrinking partition $last_num: ${last_end} MiB → ${new_end} MiB"

    case "$last_fstype" in
        ext2|ext3|ext4)
            log_info "Checking filesystem integrity"
            e2fsck -f "$last_part" || {
                log_error "Filesystem check failed on $last_part"
                return 1
            }
            local new_size_blocks=$(( (new_end - last_start) * 1024 ))
            log_info "Resizing ext4 filesystem"
            resize2fs "$last_part" "${new_size_blocks}k" || {
                log_error "resize2fs failed on $last_part"
                return 1
            }
            ;;
        fat16|fat32|vfat)
            if ! command -v fatresize &>/dev/null; then
                log_error "fatresize not found — required for vfat resize"
                log_error "Install: sudo apt install fatresize   (Debian)"
                log_error "         yay -S fatresize             (Arch AUR)"
                return 1
            fi
            local new_size_bytes=$(( (new_end - last_start) * 1024 * 1024 ))
            log_info "Resizing vfat filesystem"
            fatresize -s "${new_size_bytes}" "$last_part" || {
                log_error "fatresize failed on $last_part"
                return 1
            }
            ;;
        *)
            log_error "Cannot resize filesystem of type: $last_fstype"
            log_error "Use Option D (manual) to prepare space with GParted"
            return 1
            ;;
    esac

    # Resize the partition itself in parted
    log_info "Resizing partition in partition table"
    parted -s "$dev" resizepart "$last_num" "${new_end}MiB" || {
        log_error "parted resizepart failed"
        return 1
    }

    # Create the new LUKS partition
    local disk_mib
    disk_mib=$(partition_disk_size_mib "$dev")
    local new_part_start=$(( new_end + 1 ))
    local new_part_end=$(( disk_mib - 1 ))

    log_info "Creating LUKS partition (${new_part_start} MiB → ${new_part_end} MiB)"
    parted -s "$dev" mkpart primary "${new_part_start}MiB" "${new_part_end}MiB" || {
        log_error "Failed to create LUKS partition after resize"
        return 1
    }

    partprobe "$dev" 2>/dev/null
    sleep 1
    print_ok "Partition resized and LUKS partition created"
    return 0
}

# ─── Execution — delete and recreate ─────────────────────────────────────────

partition_delete_recreate_last() {
    local dev="$1"
    local luks_size_mib="${2:-128}"

    # Find last partition
    local last_num last_start last_end last_fstype
    while IFS=$'\t' read -r num start end size fstype name uuid; do
        last_num="$num"
        last_start="$start"
        last_end="$end"
        last_fstype="$fstype"
    done < <(partition_list "$dev")

    if [[ -z "$last_num" ]]; then
        log_error "No partitions found on $dev"
        return 1
    fi

    local last_part="${dev}${last_num}"
    [[ "$dev" =~ [0-9]$ ]] && last_part="${dev}p${last_num}"

    if usb_is_mounted "$last_part"; then
        log_error "Partition $last_part is mounted — unmount first"
        return 1
    fi

    log_warn "Deleting partition $last_num on $dev — all data on that partition will be lost"

    parted -s "$dev" rm "$last_num" || {
        log_error "Failed to delete partition $last_num"
        return 1
    }

    local disk_mib
    disk_mib=$(partition_disk_size_mib "$dev")
    local luks_start=$(( disk_mib - luks_size_mib - 1 ))
    local new_end=$(( luks_start - 1 ))

    log_info "Recreating partition $last_num (${last_start} MiB → ${new_end} MiB)"
    parted -s "$dev" mkpart primary "${last_start}MiB" "${new_end}MiB" || {
        log_error "Failed to recreate partition $last_num"
        return 1
    }

    log_info "Creating LUKS partition (${luks_start} MiB → $(( disk_mib - 1 )) MiB)"
    parted -s "$dev" mkpart primary "${luks_start}MiB" "$(( disk_mib - 1 ))MiB" || {
        log_error "Failed to create LUKS partition"
        return 1
    }

    partprobe "$dev" 2>/dev/null
    sleep 1
    print_ok "Partition deleted, recreated, and LUKS partition added"
    return 0
}

# ─── LUKS partition detection ─────────────────────────────────────────────────

# Find the LUKS partition on a device (last partition, by crypto_LUKS fstype)
partition_find_luks() {
    local dev="$1"
    local last_num=""
    while IFS=$'\t' read -r num start end size fstype name uuid; do
        last_num="$num"
    done < <(partition_list "$dev")

    [[ -z "$last_num" ]] && return 1

    local last_part="${dev}${last_num}"
    [[ "$dev" =~ [0-9]$ ]] && last_part="${dev}p${last_num}"

    echo "$last_part"
}

# ─── Backup helpers ───────────────────────────────────────────────────────────

partition_backup_contents() {
    local part="$1"
    local dest_dir="$2"
    local tmp_mount
    tmp_mount=$(mktemp -d)

    log_info "Mounting $part temporarily for backup"
    mount "$part" "$tmp_mount" || {
        rmdir "$tmp_mount"
        log_error "Failed to mount $part for backup"
        return 1
    }

    log_info "Copying contents to $dest_dir"
    mkdir -p "$dest_dir"
    cp -a "$tmp_mount/." "$dest_dir/" || {
        umount "$tmp_mount"
        rmdir "$tmp_mount"
        log_error "Backup copy failed"
        return 1
    }

    umount "$tmp_mount"
    rmdir "$tmp_mount"
    print_ok "Backup complete: $dest_dir"
}
