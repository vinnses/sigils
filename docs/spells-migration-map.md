# Migration map: old path -> new path

## Command -> spell

- `vscreen`, `vscreen-reset` -> `vscreen`
- `netmon`, `netmon_v0.sh`, `netmon_v1.sh`, `netmon_v2.sh` -> `netmon`
- `gclip` -> `gclip`
- `enx` -> `enx`
- `deskreen-url` -> `deskreen-url`

## File moves

- `bin/vscreen` -> `spells/vscreen/bin/vscreen`
- `bin/vscreen-reset` -> `spells/vscreen/bin/vscreen-reset`
- `lib/vscreen/` -> `spells/vscreen/lib/vscreen/`
- `tests/vscreen/` -> `spells/vscreen/tests/vscreen/`
- `config/vscreen` -> `spells/vscreen/config/vscreen`
- `docs/vscreen/` -> `spells/vscreen/docs/vscreen/`
- `completions/bash/vscreen.bash` -> `spells/vscreen/completions/bash/vscreen.bash`

- `bin/netmon` -> `spells/netmon/bin/netmon`
- `bin/netmon_v0.sh` -> `spells/netmon/bin/netmon_v0.sh`
- `bin/netmon_v1.sh` -> `spells/netmon/bin/netmon_v1.sh`
- `bin/netmon_v2.sh` -> `spells/netmon/bin/netmon_v2.sh`
- `lib/netmon/` -> `spells/netmon/lib/netmon/`
- `config/netmon.json` -> `spells/netmon/config/netmon.json`
- `config/netmon copy.json` -> `spells/netmon/config/netmon copy.json`
- `rituals/netmon.service` -> `spells/netmon/services/systemd/system/netmon.service`
- `rituals/netmon.timer` -> `spells/netmon/services/systemd/system/netmon.timer`
- `docs/netmon/README.md` -> `spells/netmon/docs/README.md`

- `bin/gclip` -> `spells/gclip/bin/gclip`
- `completions/bash/gclip.bash` -> `spells/gclip/completions/bash/gclip.bash`

- `bin/enx` -> `spells/enx/bin/enx`
- `completions/bash/enx.bash` -> `spells/enx/completions/bash/enx.bash`

- `bin/deskreen-url` -> `spells/deskreen-url/bin/deskreen-url`
- `completions/bash/deskreen-url.bash` -> `spells/deskreen-url/completions/bash/deskreen-url.bash`
