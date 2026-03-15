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
    @staticmethod
    def get_info(interface_name):
        info = {
            "os": f"{platform.system()} {platform.release()}",
            "hostname": platform.node(),
            "cpu": None,
            "memory": None,
            "interface": interface_name,
            "local_ip": None,
            "mac_address": None
        }
        try:
            with open("/proc/cpuinfo", "r") as f:
                for line in f:
                    if "model name" in line:
                        info["cpu"] = line.split(":")[1].strip()
                        break
        except: pass
        try:
            with open("/proc/meminfo", "r") as f:
                for line in f:
                    if "MemTotal" in line:
                        info["memory"] = f"{int(line.split()[1]) // 1024}MB"
                        break
        except: pass
        try:
            if interface_name and interface_name != "unknown":
                out = subprocess.check_output(["ip", "addr", "show", interface_name], text=True)
                ip_match = re.search(r"inet\s+(\d+\.\d+\.\d+\.\d+)", out)
                mac_match = re.search(r"link/ether\s+([0-9a-fA-F:]+)", out)
                if ip_match: info["local_ip"] = ip_match.group(1)
                if mac_match: info["mac_address"] = mac_match.group(1)
        except: pass
        return info

class NetMon:
    def __init__(self):
        self.config = self.load_config()
        self.interface = self.get_interface()
        self.sys_info = SystemInfo.get_info(self.interface)
        self.session_results = []
        self.schedule_uuid = None 

    def load_config(self):
        if not os.path.exists(CONFIG_FILE):
            logger.error(f"Config file not found: {CONFIG_FILE}")
            sys.exit(1)
        try:
            with open(CONFIG_FILE, 'r') as f:
                config = json.load(f)
            def clean_speed(val):
                if isinstance(val, (int, float)): return float(val)
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
            res = subprocess.check_output(["ip", "route", "get", "8.8.8.8"], text=True)
            parts = res.split()
            if "dev" in parts: return parts[parts.index("dev") + 1]
        except: pass
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

    def create_result(self, output, duration, server_type, test_type, reason, retry_of):
        timestamp = datetime.now(timezone.utc).isoformat()
        data = {}
        valid_json = False
        try:
            data = json.loads(output)
            valid_json = True if "error" not in data else False
        except: valid_json = False

        dl_mbps = (data.get('download', {}).get('bandwidth', 0) or 0) * 8 / 1_000_000 if valid_json else 0.0
        up_mbps = (data.get('upload', {}).get('bandwidth', 0) or 0) * 8 / 1_000_000 if valid_json else 0.0
        
        c_down = self.config['contracted']['download_mbps']
        c_up = self.config['contracted']['upload_mbps']
        dl_pct = (dl_mbps * 100 / c_down) if c_down > 0 else 0
        up_pct = (up_mbps * 100 / c_up) if c_up > 0 else 0

        srv = data.get('server', {}) if valid_json else {}
        return {
            "timestamp": timestamp,
            "test_type": test_type,
            "retry_reason": reason,
            "retry_of": retry_of,
            "system_info": self.sys_info,
            "server": {
                "type": server_type,
                "id": srv.get('id'),
                "label": self.get_server_label(server_type, srv.get('id')),
                "name": srv.get('name'),
                "location": srv.get('location'),
                "country": srv.get('country'),
                "host": srv.get('host')
            },
            "network": {
                "public_ip": data.get('interface', {}).get('externalIp') if valid_json else None,
                "isp": data.get('isp') if valid_json else None
            },
            "results": {
                "download_mbps": round(dl_mbps, 2),
                "upload_mbps": round(up_mbps, 2),
                "ping_ms": data.get('ping', {}).get('latency', 0) if valid_json else 0,
                "jitter_ms": data.get('ping', {}).get('jitter', 0) if valid_json else 0,
                "packet_loss": data.get('packetLoss', 0) if valid_json else 0
            },
            "thresholds": {
                "download_pct": round(dl_pct, 1),
                "upload_pct": round(up_pct, 1)
            },
            "meta": { "duration_sec": duration }
        }

    def run_speedtest(self, server_id, server_type, test_type, reason):
        cmd = ["speedtest", "--format=json", "--accept-license", "--accept-gdpr"]
        if server_id: cmd.append(f"--server-id={server_id}")
        
        logger.info(f"Running test ({test_type}): {server_type}")
        start = time.time()
        try:
            res = subprocess.run(cmd, capture_output=True, text=True)
            output = res.stdout
        except Exception as e:
            logger.error(f"Exec Error: {e}")
            output = ""
        duration = int(time.time() - start)
        
        if test_type == "scheduled":
            retry_of = None
        else:
            retry_of = self.schedule_uuid

        result_obj = self.create_result(output, duration, server_type, test_type, reason, retry_of)
        
        if test_type == "scheduled" and self.schedule_uuid is None:
            self.schedule_uuid = result_obj['timestamp']
            
        return result_obj

    def save_data(self, data):
        day_str = datetime.now().strftime("%Y-%m-%d")
        filename = os.path.join(RESULTS_DIR, f"{day_str}.jsonl")
        try:
            with open(filename, 'a') as f:
                f.write(json.dumps(data) + "\n")
        except Exception as e: logger.error(f"Save Error: {e}")

    def run_cycle(self, cycle_type, cycle_reason):
        targets = list(self.config.get('servers', {}).keys())
        scores = []
        if cycle_type == "scheduled": self.schedule_uuid = None 

        for i, target in enumerate(targets):
            sid = self.get_server_id(target)
            res = self.run_speedtest(sid, target, cycle_type, cycle_reason)
            self.save_data(res)
            self.session_results.append(res)
            
            d = res['thresholds']['download_pct']
            u = res['thresholds']['upload_pct']
            scores.append((d + u) / 2)
            logger.info(f"Result [{target}]: D={d}% U={u}%")
            
            if i < len(targets) - 1:
                logger.info("Waiting 1 minute...")
                time.sleep(60)

        if not scores: return 0.0
        return sum(scores) / len(scores)

    def determine_next_step(self, avg):
        intervals = self.config.get('intervals', {})
        prefix = "ok"
        wait = 0
        
        # Keys match user's JSON structure
        if avg <= 1.0:
            prefix = "none"
            wait = intervals.get('no_internet', 10)
        elif avg < 20:
            prefix = "20"
            wait = intervals.get('retry_20', 1)
        elif avg < 40:
            prefix = "40"
            wait = intervals.get('retry_40', 5)
        elif avg < 60:
            prefix = "60"
            wait = intervals.get('retry_60', 10)
        elif avg < 80:
            prefix = "80"
            wait = intervals.get('retry_80', 15)
        else:
            return 0, True, "excellent"

        last_3 = self.session_results[-3:]
        d_avg = sum(x['thresholds']['download_pct'] for x in last_3) / len(last_3) if last_3 else 0
        u_avg = sum(x['thresholds']['upload_pct'] for x in last_3) / len(last_3) if last_3 else 0
        
        suffix = "both"
        if d_avg < 80 and u_avg >= 80: suffix = "download"
        elif u_avg < 80 and d_avg >= 80: suffix = "upload"
        
        return wait, False, f"{suffix}_{prefix}"

    def start(self):
        logger.info("=== Starting Session ===")
        cycle = 0
        cur_type = "scheduled"
        cur_reason = None
        
        # Use 'max_cycles' from config, default to 10 if missing
        max_cycles = self.config.get('retry', {}).get('max_cycles', 10)

        while True:
            cycle += 1
            logger.info(f"--- Cycle {cycle} ({cur_type}) ---")
            
            avg = self.run_cycle(cur_type, cur_reason)
            wait, exit_flag, reason = self.determine_next_step(avg)
            
            # Log status but exit if max_cycles reached (Constraint: Run once)
            logger.info(f"Cycle Avg: {round(avg, 1)}%. Status: {reason if reason else 'Excellent'}")
            
            # CRITICAL CHANGE: Check loop limit BEFORE sleeping
            if cycle >= max_cycles:
                logger.info(f"Cycle limit ({max_cycles}) reached. Exiting session.")
                break

            if exit_flag:
                logger.info("Performance Excellent. Exiting.")
                break
            
            cur_type = "retry"
            cur_reason = reason
            
            logger.info(f"Sleeping {wait}m before next retry...")
            time.sleep(wait * 60)

        logger.info("=== Session Complete ===")

def main():
    if len(sys.argv) > 1 and sys.argv[1] == "servers":
        subprocess.run(["speedtest", "-L"])
        sys.exit(0)
    sys.stdout.reconfigure(line_buffering=True)
    NetMon().start()

if __name__ == "__main__":
    main()