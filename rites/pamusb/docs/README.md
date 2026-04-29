# pamusb — Technical Documentation

## Architecture overview

```
pamusb (bin/pamusb)
├── lib/common.sh      Logging, colors, confirmations, USB/system detection
├── lib/partition.sh   Partition analysis, planning, execution
├── lib/pam.sh         pam_usb registration, PAM file patching, lock/unlock scripts
├── lib/keyring.sh     LUKS lifecycle, keyring provisioning, unlock runtime
└── lib/sudoers.sh     sudoers drop-in generation and validation

templates/
├── udev-suppress.rules   Prevent udisks from prompting for LUKS passphrase
├── udev-lock.rules       Trigger lock/unlock on USB plug/unplug
├── sudoers.conf          NOPASSWD rules for cryptsetup and mount
├── autostart.desktop     XDG autostart for keyring unlock
├── guard.sh              Debounce wrapper for udev events
└── dispatch.sh           Session-aware lock/unlock executor
```

## Setup wizard steps

| Step | Description |
|------|-------------|
| 1 | Device detection — list removable devices, validate selection |
| 2 | Partition analysis — read table, list partitions, show layout |
| 3 | Partition plan — select strategy based on disk state |
| 4 | Partition execution — apply strategy, record UUID/LABEL identities |
| 5 | pam_usb setup — register device/user, patch PAM files, install lock/unlock |
| 6 | LUKS setup — generate keyfile, format LUKS2, create ext4 inside |
| 7 | Keyring provisioning — write password payload to LUKS container |
| 8 | System integration — sudoers, udev suppress, unlock script, autostart |
| 9 | Verification — pamusb-check, LUKS dry-run, sudoers validate |
| 10 | Summary — list all files, print next steps |

## Config file

`config/pamusb.conf` is shell-sourceable. Written incrementally by each step.

```bash
USB_DEVICE_PATH="/dev/sdb"
USB_DEVICE_SERIAL="1234567890"
USB_DEVICE_MODEL="Kingston DataTraveler"
USB_MAIN_PARTITION_UUID="1DA7-7194"
USB_MAIN_PARTITION_LABEL="AUTHKEY"
USB_MAIN_PARTITION_MATCH_KIND="uuid"
USB_MAIN_PARTITION_MATCH_VALUE="1DA7-7194"
USB_LUKS_PARTITION_UUID="abcd1234-..."
LUKS_KEYFILE="/root/usb-luks.key"
LUKS_MAPPER_NAME="usb-secret"
LUKS_MOUNT_BASE="/run/user"
PAM_DEVICE_NAME="authkey"
PAM_USER="alice"
SETUP_STEP_COMPLETED="10"
```

## Lock/unlock system

```
USB removed
  → udev ACTION=remove matches 90-usb-lock.rules (UUID or LABEL)
  → executes usb-pam-guard.sh remove
      → debounce check (3s window)
      → executes usb-pam-dispatch.sh remove USERNAME
          → finds active graphical session for USERNAME (x11/wayland, state=active)
          → loginctl lock-session <SESSION_ID>

USB reconnected
  → udev ACTION=add matches rule
  → same chain → loginctl unlock-session
```

## Keyring unlock flow (at session start)

```
XDG autostart → pamusb-unlock-keyring.sh
  → wait for LUKS UUID to appear (30s timeout)
  → sudo cryptsetup luksOpen (NOPASSWD via sudoers)
  → sudo mount (NOPASSWD via sudoers)
  → read /run/user/<UID>/usb-secret/keyring-pass/<hostname>
  → cat payload | gnome-keyring-daemon --unlock
  → sudo umount
  → sudo cryptsetup luksClose
```

## LUKS partition layout (128 MiB)

```
LUKS2 header          ~16 MiB
ext4 metadata          ~8 MiB
keyring-pass/
  └── <hostname>       tiny (password string)
Free space            ~104 MiB (headroom for additional hostnames)
```

## Error handling policy

| Phase | On failure |
|-------|-----------|
| Partitioning | Abort immediately, print diagnostics, no auto-recovery |
| PAM configuration | Revert changes in that step, abort |
| LUKS setup | Close any open containers, abort |
| System integration | List what succeeded, list what failed, print manual completion |

## Distro compatibility

The tool detects the distro via `/etc/os-release` and adjusts:
- PAM module paths (`/lib/x86_64-linux-gnu/security/` vs `/lib/security/`)
- Install hints (apt vs pacman)
- Dynamic path resolution avoids hardcoding Debian-specific locations

Tested primary target: **Pop!_OS 22.04** (Debian-based, GNOME, GDM, X11).
Secondary target: **Arch Linux** (future migration, supported in code paths).
