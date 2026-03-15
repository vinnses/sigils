# netmon

Automated network speed monitoring with retry logic for degraded connections.

## Requirements

- `speedtest` (Ookla official CLI)
- `jq`
- `bc`

## Installation

```bash
cd ~/.local/sigils
make netmon
```

This will:
1. Install dependencies (speedtest, jq, bc)
2. Link systemd units
3. Enable and start the timer

## Configuration

Edit `spells/netmon/config/netmon.json`:

```json
{
  "contracted": {
    "download_mbps": 800,
    "upload_mbps": 400
  },
  "intervals": {
    "normal_min": 15,
    "retry_75_min": 10,
    "retry_50_min": 5,
    "retry_25_min": 1
  },
  "retry": {
    "max_retry_25": 3
  },
  "servers": {
    "curitiba": { "id": 12345, "label": "curitiba_copel" },
    "sao_paulo": { "id": 23456, "label": "sao_paulo_claro" },
    "international": [
      { "id": 34567, "label": "miami_att" }
    ]
  },
  "interface": "eth0"
}
```

### Finding Server IDs

```bash
bin/netmon servers
# or
speedtest -L | grep -i curitiba
```

## Usage

```bash
# Run manually
bin/netmon run

# List servers
bin/netmon servers

# Single test (auto server)
bin/netmon test
```

### Systemd Commands

```bash
# Status
systemctl --user status netmon.timer
systemctl --user list-timers netmon.timer

# Logs
journalctl --user -u netmon.service -f

# Disable
make netmon-disable

# Re-enable
make netmon-enable

# Uninstall (removes systemd links)
make netmon-unlink
```

## Retry Logic

| Condition | Retry Interval | Max Retries |
|-----------|----------------|-------------|
| < 75%     | 10 min         | unlimited   |
| < 50%     | 5 min          | unlimited   |
| < 25%     | 1 min          | 3           |

Retry timer counts from the last test, not the original scheduled time.

## Test Cycle

Each cycle tests three servers sequentially:
1. Curitiba (local)
2. São Paulo (regional)
3. International (random from list)

If any test falls below thresholds, retries occur before moving to the next server.

## Output

Results stored as JSON Lines in `data/netmon/results/YYYY-MM.jsonl`:

```json
{
  "timestamp": "2026-01-04T14:30:00-03:00",
  "test_type": "scheduled",
  "retry_reason": null,
  "retry_of": null,
  "server": {
    "id": 12345,
    "name": "Copel Telecom",
    "label": "curitiba_copel",
    "location": "Curitiba",
    "country": "Brazil",
    "host": "speedtest.copel.com",
    "type": "curitiba"
  },
  "network": {
    "interface": "eth0",
    "public_ip": "189.x.x.x",
    "isp": "Claro"
  },
  "results": {
    "ping_ms": 8.5,
    "jitter_ms": 1.2,
    "download_mbps": 756.32,
    "upload_mbps": 385.21,
    "packet_loss_percent": 0.0
  },
  "thresholds": {
    "download_percent": 94.5,
    "upload_percent": 96.3,
    "triggered_retry": false
  },
  "meta": {
    "hostname": "desktop",
    "test_duration_sec": 45
  }
}
```

## File Locations

| File | Location |
|------|----------|
| Executable | `bin/netmon` |
| Config | `spells/netmon/config/netmon.json` |
| Results | `data/netmon/results/YYYY-MM.jsonl` |
| Logs | `logs/netmon/netmon.log` |
| Service | `spells/netmon/services/systemd/system/netmon.service` |
| Timer | `spells/netmon/services/systemd/system/netmon.timer` |

## Useful Queries

```bash
# Today's average download
cat data/netmon/results/$(date +%Y-%m).jsonl | \
  jq -s '[.[] | select(.timestamp | startswith("'$(date +%Y-%m-%d)'"))] | 
         (map(.results.download_mbps) | add / length)'

# Tests that triggered retry
cat data/netmon/results/$(date +%Y-%m).jsonl | \
  jq -s '[.[] | select(.thresholds.triggered_retry == true)]'

# Average by server type
cat data/netmon/results/$(date +%Y-%m).jsonl | \
  jq -s 'group_by(.server.type) | 
         map({
           type: .[0].server.type, 
           avg_down: (map(.results.download_mbps) | add / length),
           avg_up: (map(.results.upload_mbps) | add / length),
           count: length
         })'
```

## Troubleshooting

### Speedtest license

On first run, Ookla speedtest requires license acceptance. Run manually once:

```bash
speedtest
```

### No servers configured

If all server IDs are null, speedtest auto-selects the nearest server. For consistent measurements, configure specific servers after running `bin/netmon servers`.
