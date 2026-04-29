# pamusb

Internal Sigils rite for configuring a dedicated USB pendrive as a hardware
authentication token for Linux workstations.

Two independent but complementary subsystems unified under one tool:

1. **pam_usb** — session authentication via USB presence (OTP pads), automatic lock on removal, automatic unlock on reconnection.
2. **Keyring unlock** — automatic GNOME Keyring decryption at login via split-knowledge architecture (LUKS partition on USB + local keyfile).

## Quick start

```bash
sudo sigils rite pamusb setup
```

## Subcommands

| Command | Description |
|---------|-------------|
| `setup` | Full interactive wizard (all 10 steps) |
| `setup-pam` | pam_usb setup only |
| `setup-keyring` | Keyring LUKS setup only |
| `partition` | Partition analysis and modification only |
| `status` | Show state of all subsystems |
| `test` | Run diagnostics |
| `recover` | Reset pam_usb OTP pads |
| `devices list` | List removable partition UUID/LABEL identities |
| `devices set --uuid <uuid>` | Match the auth partition by UUID |
| `devices set --label <label>` | Match the auth partition by filesystem label |
| `devices forget` | Remove the configured auth partition association |
| `rekey` | Update keyring password in LUKS payload |
| `provision-host` | Add keyring payload for a new hostname |
| `lock-disable` | Temporarily disable session lock on USB removal |
| `lock-enable` | Re-enable session lock |
| `uninstall` | Full teardown |

## Prerequisites

- **pam_usb** — must be built from source: <https://github.com/aluzzardi/pam_usb>
- Runtime tools: `cryptsetup`, `parted`, `lsblk`, `blkid`, `mkfs.ext4`, `mkfs.vfat`, `jq`, `udevadm`, `loginctl`, `visudo`
- GNOME Keyring (`gnome-keyring-daemon`)

```bash
# Debian/Ubuntu/Pop!_OS
sudo apt install cryptsetup parted util-linux e2fsprogs dosfstools jq sudo systemd gnome-keyring

# Arch
sudo pacman -S cryptsetup parted util-linux e2fsprogs dosfstools jq sudo systemd gnome-keyring
```

## USB partition layout

| Partition | Size | Filesystem | Purpose |
|-----------|------|------------|---------|
| 1 (primary) | ~7.87 GB | vfat | pam_usb `.pad` files |
| 2 (end) | 128 MB | LUKS2 → ext4 | Keyring password payloads |

## USB identity

The setup records the main pam_usb partition by UUID by default:

```bash
sudo sigils rite pamusb devices set --uuid 1DA7-7194
```

For day-to-day usability, the lock/unlock udev rule can instead match a stable
filesystem label:

```bash
sudo sigils rite pamusb devices list
sudo sigils rite pamusb devices set --label AUTHKEY
sudo sigils rite pamusb setup-pam
```

Use `devices forget` when an old pendrive should stop being associated with the
workstation.

## Security model

- **pam_usb**: OTP-based. USB present → access granted. USB absent → fallback to password. USB removed → session locks.
- **Keyring split-knowledge**: LUKS encryption key lives on the host (`/root/usb-luks.key`). Encrypted keyring password lives on the USB. Neither alone is sufficient.
- Keyring does **not** re-lock on USB removal — the pam_usb session lock is sufficient.

## Multi-machine support

The same USB pendrive authenticates on multiple hosts. Keyring payloads are stored per hostname inside the LUKS partition: `/keyring-pass/<hostname>`. The LUKS keyfile (`/root/usb-luks.key`) must be identical across all machines.

On a second machine:
1. Copy `/root/usb-luks.key` from the first machine (secure transfer, e.g. `scp` over LAN).
2. Run `sudo sigils rite pamusb setup-keyring` → choose "Reuse existing keyfile" when prompted.

## Recovery

If the USB OTP pad is desynchronized (pam_usb rejects access after a failed auth):

```bash
sudo sigils rite pamusb recover
```

If locked out of the graphical session, use a TTY:

```
Ctrl+Alt+F2  →  login with password  →  sudo sigils rite pamusb recover
```

## Files created by setup

| Path | Purpose |
|------|---------|
| `config/pamusb.conf` | USB identity, device info, setup state |
| `/root/usb-luks.key` | LUKS keyfile (chmod 400) |
| `/etc/security/pam_usb.conf` | pam_usb device/user registration |
| `/etc/udev/rules.d/90-usb-lock.rules` | Session lock/unlock trigger |
| `/etc/udev/rules.d/91-pamusb-suppress.rules` | Suppress udisks LUKS prompt |
| `/etc/sudoers.d/99-pamusb` | NOPASSWD for cryptsetup/mount |
| `/usr/local/bin/usb-pam-guard.sh` | Udev debounce script |
| `/usr/local/bin/usb-pam-dispatch.sh` | Session lock/unlock dispatcher |
| `~/.local/bin/pamusb-unlock-keyring.sh` | Keyring unlock wrapper |
| `~/.config/autostart/pamusb-keyring.desktop` | XDG autostart entry |
