#!/usr/bin/env python3
import os
import sys
import json
import subprocess
import time
import logging
import random
import platform
import re
from datetime import datetime, timezone

# --- Path Configuration ---
SCRIPT_PATH = os.path.realpath(__file__)
SCRIPT_DIR = os.path.dirname(SCRIPT_PATH)
SIGILS_ROOT = os.environ.get("SIGILS_ROOT", os.path.dirname(SCRIPT_DIR))

CONFIG_FILE = os.path.join(SIGILS_ROOT, "config", "netmon.json")
DATA_DIR = os.path.join(SIGILS_ROOT, "data")
RESULTS_DIR = os.path.join(DATA_DIR, "netmon", "results")
LOG_FILE = os.path.join(SIGILS_ROOT, "logs", "netmon", "netmon.log")

os.makedirs(RESULTS_DIR, exist_ok=True)
os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)

# --- Logger ---
logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S%z",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger()


class SystemInfo:
    """Helper to gather hardware info. Returns None for unavailable fields."""
    @staticmethod
    def get_info(interface_name):
        info = {
            "os": f"{platform.system()} {platform.release()}",
            "hostname": platform.node(),
            "cpu": None,
            "memory": None,
            "interface": interface_name,
            "local_ip": None
        }

        # CPU Model (Linux)
        try:
            with open("/proc/cpuinfo", "r") as f:
                for line in f:
                    if "model name" in line:
                        info["cpu"] = line.split(":")[1].strip()
                        break
        except:
            pass

        # Total Memory (Linux)
        try:
            with open("/proc/meminfo", "r") as f:
                for line in f:
                    if "MemTotal" in line:
                        kb = int(line.split()[1])
                        info["memory"] = f"{kb // 1024}MB"
                        break
        except:
            pass

        # IP
        try:
            if interface_name and interface_name != "unknown":
                out = subprocess.check_output(
                    ["ip", "addr", "show", interface_name], text=True
                )
                ip_match = re.search(r"inet\s+(\d+\.\d+\.\d+\.\d+)", out)
                if ip_match:
                    info["local_ip"] = ip_match.group(1)
        except:
            pass

        return info


class NetMon:
    def __init__(self):
        self.config = self.load_config()
        self.interface = self.get_interface()
        self.sys_info = SystemInfo.get_info(self.interface)
        self.execution_id = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.current_cycle = 0

    def load_config(self):
        if not os.path.exists(CONFIG_FILE):
            logger.error(f"Config file not found: {CONFIG_FILE}")
            sys.exit(1)

        try:
            with open(CONFIG_FILE, 'r') as f:
                config = json.load(f)

            def clean_speed(val):
                if isinstance(val, (int, float)):
                    return float(val)
                if isinstance(val, str):
                    cleaned = ''.join(c for c in val if c.isdigit() or c == '.')
                    return float(cleaned) if cleaned else 0.0
                return 0.0

            c_down = config.get('contracted', {}).get('download_mbps', 0)
            c_up = config.get('contracted', {}).get('upload_mbps', 0)

            config['contracted']['download_mbps'] = clean_speed(c_down)
            config['contracted']['upload_mbps'] = clean_speed(c_up)

            return config
        except Exception as e:
            logger.error(f"Config Error: {e}")
            sys.exit(1)

    def get_interface(self):
        try:
            res = subprocess.check_output(
                ["ip", "route", "get", "8.8.8.8"], text=True
            )
            parts = res.split()
            if "dev" in parts:
                return parts[parts.index("dev") + 1]
        except:
            pass
        return "unknown"

    def get_server_id(self, server_type):
        servers = self.config.get('servers', {})
        cfg = servers.get(server_type)

        if isinstance(cfg, list):
            valid = [s for s in cfg if isinstance(s, dict) and s.get('id')]
            return random.choice(valid).get('id') if valid else None
        elif isinstance(cfg, dict):
            return cfg.get('id')
        return None

    def get_server_label(self, server_type, server_id):
        servers = self.config.get('servers', {})
        cfg = servers.get(server_type)

        if isinstance(cfg, dict):
            return cfg.get('label', server_type)
        if isinstance(cfg, list):
            for s in cfg:
                if str(s.get('id')) == str(server_id):
                    return s.get('label', f"{server_type}_auto")
            return f"{server_type}_auto"
        return server_type

    def get_level(self, pct):
        """Returns severity level based on percentage."""
        if pct < 20:
            return "critical"
        elif pct < 40:
            return "degraded"
        elif pct < 60:
            return "low"
        elif pct < 80:
            return "ok"
        else:
            return "healthy"

    def get_diagnosis(self, dl_pct, up_pct):
        """Generate diagnosis string based on thresholds."""
        dl_level = self.get_level(dl_pct)
        up_level = self.get_level(up_pct)

        # Both healthy
        if dl_level == "healthy" and up_level == "healthy":
            return "healthy"

        # Priority order: critical > degraded > low > ok > healthy
        priority = ["critical", "degraded", "low", "ok", "healthy"]
        dl_pri = priority.index(dl_level)
        up_pri = priority.index(up_level)

        # Both have same issue level
        if dl_level == up_level:
            return f"both_{dl_level}"

        # Different levels - report the worse one with direction
        if dl_pri < up_pri:
            return f"download_{dl_level}"
        else:
            return f"upload_{up_level}"

    def create_result(self, output, duration, server_type):
        timestamp = datetime.now(timezone.utc).isoformat()

        # Parse JSON
        data = {}
        valid_json = False
        try:
            data = json.loads(output)
            valid_json = True
            if "error" in data:
                valid_json = False
        except:
            valid_json = False

        # Extract Metrics
        dl_mbps = 0.0
        up_mbps = 0.0
        ping = 0.0
        jitter = 0.0
        pkt_loss = 0.0

        if valid_json:
            dl_mbps = (data.get('download', {}).get('bandwidth', 0) or 0) * 8 / 1_000_000
            up_mbps = (data.get('upload', {}).get('bandwidth', 0) or 0) * 8 / 1_000_000
            ping = data.get('ping', {}).get('latency', 0) or 0
            jitter = data.get('ping', {}).get('jitter', 0) or 0
            pkt_loss = data.get('packetLoss', 0) or 0

        # Calculate Thresholds
        c_down = self.config['contracted']['download_mbps']
        c_up = self.config['contracted']['upload_mbps']
        dl_pct = (dl_mbps * 100 / c_down) if c_down > 0 else 0
        up_pct = (up_mbps * 100 / c_up) if c_up > 0 else 0

        # Diagnosis
        if not valid_json:
            diagnosis = "error"
        elif dl_pct <= 1 and up_pct <= 1:
            diagnosis = "no_internet"
        else:
            diagnosis = self.get_diagnosis(dl_pct, up_pct)

        # Server Metadata
        srv_id = None
        srv_label = "unknown"
        srv_name = None
        srv_loc = None
        srv_country = None
        srv_host = None

        if valid_json:
            srv = data.get('server', {})
            srv_id = srv.get('id')
            srv_label = self.get_server_label(server_type, srv_id)
            srv_name = srv.get('name')
            srv_loc = srv.get('location')
            srv_country = srv.get('country')
            srv_host = srv.get('host')

        # Network Metadata
        pub_ip = None
        isp = None
        if valid_json:
            pub_ip = data.get('interface', {}).get('externalIp')
            isp = data.get('isp')

        # Construct result in specified order
        return {
            "execution_id": self.execution_id,
            "cycle": self.current_cycle,
            "timestamp": timestamp,
            "diagnosis": diagnosis,
            "thresholds": {
                "upload_pct": round(up_pct, 1),
                "download_pct": round(dl_pct, 1)
            },
            "results": {
                "download_mbps": round(dl_mbps, 2),
                "upload_mbps": round(up_mbps, 2),
                "ping_ms": round(ping, 1),
                "jitter_ms": round(jitter, 1),
                "packet_loss": round(pkt_loss, 2),
                "test_duration": duration
            },
            "server": {
                "type": server_type,
                "id": srv_id,
                "label": srv_label,
                "name": srv_name,
                "location": srv_loc,
                "country": srv_country,
                "host": srv_host
            },
            "network": {
                "public_ip": pub_ip,
                "isp": isp
            },
            "meta": {
                "os": self.sys_info.get("os"),
                "hostname": self.sys_info.get("hostname"),
                "cpu": self.sys_info.get("cpu"),
                "memory": self.sys_info.get("memory"),
                "interface": self.sys_info.get("interface"),
                "local_ip": self.sys_info.get("local_ip")
            }
        }

    def run_speedtest(self, server_id, server_type):
        cmd = ["speedtest", "--format=json", "--accept-license", "--accept-gdpr"]
        if server_id:
            cmd.append(f"--server-id={server_id}")

        logger.info(f"Running test: {server_type}")
        start = time.time()

        try:
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
            output = res.stdout
        except subprocess.TimeoutExpired:
            logger.error("Speedtest timeout (120s)")
            output = ""
        except Exception as e:
            logger.error(f"Exec Error: {e}")
            output = ""

        duration = int(time.time() - start)
        return self.create_result(output, duration, server_type)

    def save_data(self, data):
        day_str = datetime.now().strftime("%Y-%m-%d")
        filename = os.path.join(RESULTS_DIR, f"{day_str}.jsonl")
        try:
            with open(filename, 'a') as f:
                f.write(json.dumps(data) + "\n")
        except Exception as e:
            logger.error(f"Save Error: {e}")

    def run_cycle(self):
        targets = list(self.config.get('servers', {}).keys())
        cycle_results = []

        for i, target in enumerate(targets):
            sid = self.get_server_id(target)
            res = self.run_speedtest(sid, target)

            self.save_data(res)
            cycle_results.append(res)

            dl = res['thresholds']['download_pct']
            up = res['thresholds']['upload_pct']
            diag = res['diagnosis']

            logger.info(f"Result [{target}]: D={dl}% U={up}% [{diag}]")

            # Wait between servers (except last)
            if i < len(targets) - 1:
                logger.info("Waiting 1 minute...")
                time.sleep(60)

        return cycle_results

    def get_worst_diagnosis(self, cycle_results):
        """Get the worst diagnosis from a cycle."""
        priority = ["no_internet", "error", "critical", "degraded", "low", "ok", "healthy"]

        worst = "healthy"
        for res in cycle_results:
            diag = res['diagnosis']
            # Extract level from diagnosis (e.g., "download_critical" -> "critical")
            level = diag.split('_')[-1] if '_' in diag else diag

            if level in priority:
                if priority.index(level) < priority.index(worst.split('_')[-1] if '_' in worst else worst):
                    worst = diag

        return worst

    def should_retry(self, diagnosis):
        """Check if we should retry based on diagnosis."""
        level = diagnosis.split('_')[-1] if '_' in diagnosis else diagnosis
        return level in ["critical", "degraded", "low", "ok", "no_internet", "error"]

    def get_retry_interval(self, diagnosis):
        """Get retry interval in minutes based on diagnosis."""
        intervals = self.config.get('intervals', {})
        level = diagnosis.split('_')[-1] if '_' in diagnosis else diagnosis

        mapping = {
            "no_internet": intervals.get('no_internet', 10),
            "error": intervals.get('no_internet', 10),
            "critical": intervals.get('retry_20', 1),
            "degraded": intervals.get('retry_40', 5),
            "low": intervals.get('retry_60', 10),
            "ok": intervals.get('retry_80', 15)
        }

        return mapping.get(level, 15)

    def start(self):
        logger.info("=== Starting Session ===")
        logger.info(f"Execution ID: {self.execution_id}")

        max_cycles = self.config.get('retry', {}).get('max_cycles', 1)
        logger.info(f"Max cycles: {max_cycles}")

        while self.current_cycle < max_cycles:
            self.current_cycle += 1
            logger.info(f"--- Cycle {self.current_cycle}/{max_cycles} ---")

            cycle_results = self.run_cycle()
            worst = self.get_worst_diagnosis(cycle_results)

            logger.info(f"Cycle {self.current_cycle} worst diagnosis: {worst}")

            # Check if we've reached max cycles
            if self.current_cycle >= max_cycles:
                logger.info(f"Max cycles reached ({max_cycles}). Finishing.")
                break

            # Check if healthy - no need to retry
            if worst == "healthy":
                logger.info("All healthy. Finishing.")
                break

            # Calculate retry wait
            wait_min = self.get_retry_interval(worst)
            logger.info(f"Retrying in {wait_min} minutes...")
            time.sleep(wait_min * 60)

        logger.info("=== Session Complete ===")


def main():
    if len(sys.argv) > 1:
        cmd = sys.argv[1]
        if cmd == "servers":
            subprocess.run(["speedtest", "-L"])
            sys.exit(0)
        elif cmd == "test":
            # Single test without retry logic
            nm = NetMon()
            nm.current_cycle = 1
            targets = list(nm.config.get('servers', {}).keys())
            if targets:
                sid = nm.get_server_id(targets[0])
                res = nm.run_speedtest(sid, targets[0])
                nm.save_data(res)
                print(json.dumps(res, indent=2))
            sys.exit(0)
        elif cmd == "run":
            pass  # Continue to normal run
        else:
            print(f"Unknown command: {cmd}")
            print("Usage: netmon [run|test|servers]")
            sys.exit(1)

    # Unbuffer stdout for proper logging in systemd
    sys.stdout.reconfigure(line_buffering=True)
    NetMon().start()


if __name__ == "__main__":
    main()
