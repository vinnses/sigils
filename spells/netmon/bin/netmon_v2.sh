#!/usr/bin/env python3
"""
netmon - Network speed monitoring with structured diagnostics.

Usage:
    netmon run      Run full test cycle
    netmon test     Single test (first server only)
    netmon servers  List available speedtest servers
"""
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
from pathlib import Path

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
    """Gather comprehensive system information for diagnostics."""

    @staticmethod
    def _run_cmd(cmd, default=""):
        try:
            return subprocess.check_output(cmd, shell=True, text=True, stderr=subprocess.DEVNULL).strip()
        except:
            return default

    @staticmethod
    def _read_file(path, default=""):
        try:
            return Path(path).read_text().strip()
        except:
            return default

    @classmethod
    def get_distro(cls):
        """Get distribution name and version."""
        try:
            with open("/etc/os-release") as f:
                data = {}
                for line in f:
                    if "=" in line:
                        k, v = line.strip().split("=", 1)
                        data[k] = v.strip('"')
                name = data.get("PRETTY_NAME") or data.get("NAME", "Linux")
                return name
        except:
            pass
        
        result = cls._run_cmd("lsb_release -d 2>/dev/null | cut -f2")
        return result if result else "Linux"

    @classmethod
    def get_kernel(cls):
        return platform.release()

    @classmethod
    def get_hostname(cls):
        return platform.node()

    @classmethod
    def get_cpu_info(cls):
        """Get CPU model, cores, and current usage."""
        info = {"model": None, "cores": None, "usage_pct": None}

        try:
            with open("/proc/cpuinfo") as f:
                for line in f:
                    if "model name" in line:
                        info["model"] = line.split(":")[1].strip()
                        break
        except:
            pass

        try:
            info["cores"] = os.cpu_count()
        except:
            pass

        try:
            def read_cpu_times():
                with open("/proc/stat") as f:
                    line = f.readline()
                    parts = line.split()[1:]
                    return [int(x) for x in parts]

            t1 = read_cpu_times()
            time.sleep(0.1)
            t2 = read_cpu_times()

            idle1, idle2 = t1[3], t2[3]
            total1, total2 = sum(t1), sum(t2)
            
            idle_delta = idle2 - idle1
            total_delta = total2 - total1
            
            if total_delta > 0:
                usage = 100.0 * (1.0 - idle_delta / total_delta)
                info["usage_pct"] = round(usage, 1)
        except:
            pass

        return info

    @classmethod
    def get_memory_info(cls):
        """Get memory stats in MB."""
        info = {"total": None, "used": None, "free": None, "usage_pct": None}

        try:
            with open("/proc/meminfo") as f:
                data = {}
                for line in f:
                    parts = line.split()
                    if len(parts) >= 2:
                        key = parts[0].rstrip(":")
                        val = int(parts[1])
                        data[key] = val

            total = data.get("MemTotal", 0)
            free = data.get("MemFree", 0)
            buffers = data.get("Buffers", 0)
            cached = data.get("Cached", 0)
            
            available = free + buffers + cached
            used = total - available

            info["total"] = total // 1024
            info["used"] = used // 1024
            info["free"] = available // 1024
            
            if total > 0:
                info["usage_pct"] = round(100.0 * used / total, 1)
        except:
            pass

        return info

    @classmethod
    def get_interface_info(cls, interface_name):
        """Get detailed interface information."""
        info = {
            "name": interface_name,
            "type": "ethernet",
            "vendor": None,
            "product": None,
            "driver": None,
            "driver_version": None,
            "link_speed": None,
            "duplex": None
        }

        if not interface_name or interface_name == "unknown":
            return info

        # Determine type
        if interface_name.startswith(("wl", "wlan", "wifi")):
            info["type"] = "wifi"
        elif interface_name.startswith(("eth", "enp", "eno", "ens")):
            info["type"] = "ethernet"

        # Get driver info via ethtool
        ethtool_i = cls._run_cmd(f"ethtool -i {interface_name} 2>/dev/null")
        for line in ethtool_i.split("\n"):
            if line.startswith("driver:"):
                info["driver"] = line.split(":", 1)[1].strip()
            elif line.startswith("version:"):
                info["driver_version"] = line.split(":", 1)[1].strip()

        # Get link speed and duplex
        ethtool = cls._run_cmd(f"ethtool {interface_name} 2>/dev/null")
        for line in ethtool.split("\n"):
            line = line.strip()
            if line.startswith("Speed:"):
                speed_str = line.split(":", 1)[1].strip()
                match = re.search(r"(\d+)", speed_str)
                if match:
                    info["link_speed"] = int(match.group(1))
            elif line.startswith("Duplex:"):
                info["duplex"] = line.split(":", 1)[1].strip().lower()

        # Get hardware info via /sys and lspci
        sys_path = f"/sys/class/net/{interface_name}/device"
        
        if os.path.exists(f"{sys_path}/uevent"):
            uevent = cls._read_file(f"{sys_path}/uevent")
            pci_slot = None
            for line in uevent.split("\n"):
                if line.startswith("PCI_SLOT_NAME="):
                    pci_slot = line.split("=", 1)[1]
                    break
            
            if pci_slot:
                lspci = cls._run_cmd(f"lspci -s {pci_slot} 2>/dev/null")
                if lspci:
                    parts = lspci.split(":", 2)
                    if len(parts) >= 3:
                        hw_info = parts[2].strip()
                        info["product"] = hw_info
                        if " " in hw_info:
                            info["vendor"] = hw_info.split()[0]

        # WiFi specific info
        if info["type"] == "wifi":
            iw_info = cls._run_cmd(f"iw dev {interface_name} info 2>/dev/null")
            iw_link = cls._run_cmd(f"iw dev {interface_name} link 2>/dev/null")
            
            for line in iw_info.split("\n"):
                line = line.strip()
                if line.startswith("ssid"):
                    info["ssid"] = line.split(None, 1)[1] if len(line.split()) > 1 else None
                elif line.startswith("channel"):
                    match = re.search(r"\((\d+\.?\d*)\s*MHz", line)
                    if match:
                        freq_mhz = float(match.group(1))
                        info["frequency_ghz"] = round(freq_mhz / 1000, 2)
            
            for line in iw_link.split("\n"):
                line = line.strip()
                if line.startswith("signal:"):
                    match = re.search(r"(-?\d+)", line)
                    if match:
                        info["signal_dbm"] = int(match.group(1))
                elif "bitrate" in line.lower():
                    match = re.search(r"(\d+\.?\d*)\s*MBit", line, re.IGNORECASE)
                    if match:
                        info["bitrate"] = float(match.group(1))

        return info

    @classmethod
    def get_local_ip(cls, interface_name):
        """Get local IP for interface."""
        if not interface_name or interface_name == "unknown":
            return None
        
        try:
            out = subprocess.check_output(
                ["ip", "addr", "show", interface_name], text=True
            )
            match = re.search(r"inet\s+(\d+\.\d+\.\d+\.\d+)", out)
            if match:
                return match.group(1)
        except:
            pass
        return None


class NetMon:
    def __init__(self):
        self.config = self.load_config()
        self.interface = self.get_interface()
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
        """Generate structured diagnosis."""
        dl_level = self.get_level(dl_pct)
        up_level = self.get_level(up_pct)
        overall_pct = (dl_pct + up_pct) / 2
        overall_level = self.get_level(overall_pct)

        return {
            "download": dl_level,
            "upload": up_level,
            "overall": overall_level
        }

    def collect_meta(self, public_ip, isp):
        """Collect all system metadata."""
        return {
            "hostname": SystemInfo.get_hostname(),
            "kernel": SystemInfo.get_kernel(),
            "distro": SystemInfo.get_distro(),
            "cpu": SystemInfo.get_cpu_info(),
            "memory": SystemInfo.get_memory_info(),
            "network": {
                "interface": SystemInfo.get_interface_info(self.interface),
                "local_ip": SystemInfo.get_local_ip(self.interface),
                "public_ip": public_ip,
                "isp": isp
            }
        }

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
            diagnosis = {"download": "error", "upload": "error", "overall": "error"}
        elif dl_pct <= 1 and up_pct <= 1:
            diagnosis = {"download": "no_internet", "upload": "no_internet", "overall": "no_internet"}
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

        # Network Metadata from speedtest result
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
            "meta": self.collect_meta(pub_ip, isp)
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

            logger.info(f"Result [{target}]: D={dl}% U={up}% [D:{diag['download']} U:{diag['upload']} O:{diag['overall']}]")

            # Wait between servers (except last)
            if i < len(targets) - 1:
                logger.info("Waiting 1 minute...")
                time.sleep(60)

        return cycle_results

    def get_worst_level(self, cycle_results):
        """Get the worst overall level from a cycle."""
        priority = ["no_internet", "error", "critical", "degraded", "low", "ok", "healthy"]
        worst = "healthy"

        for res in cycle_results:
            level = res['diagnosis']['overall']
            if level in priority:
                if priority.index(level) < priority.index(worst):
                    worst = level

        return worst

    def get_retry_interval(self, level):
        """Get retry interval in minutes based on level."""
        intervals = self.config.get('intervals', {})

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
            worst = self.get_worst_level(cycle_results)

            logger.info(f"Cycle {self.current_cycle} worst level: {worst}")

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
