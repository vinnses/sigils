import json
import socket
import uuid
from datetime import datetime, timezone
from pathlib import Path


def choose_port(start: int, end: int, in_use: set[int] | None = None) -> int:
    known_in_use = in_use or set()
    for port in range(start, end + 1):
        if port in known_in_use:
            continue
        with socket.socket() as sock:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            if sock.connect_ex(("127.0.0.1", port)) != 0:
                return port
    raise RuntimeError(f"no free port in range {start}-{end}")


class Registry:
    def __init__(self, root: Path):
        self.root = root
        self.root.mkdir(parents=True, exist_ok=True)

    def _path_for(self, instance_id: str) -> Path:
        return self.root / f"{instance_id}.json"

    def create_instance(self, **payload):
        instance = {
            "id": uuid.uuid4().hex[:8],
            "started_at": datetime.now(timezone.utc).isoformat(),
            **payload,
        }
        self._path_for(instance["id"]).write_text(json.dumps(instance, indent=2), encoding="utf-8")
        return instance

    def list_instances(self):
        items = []
        for path in sorted(self.root.glob("*.json")):
            items.append(json.loads(path.read_text(encoding="utf-8")))
        return items

    def get_instance(self, instance_id: str):
        path = self._path_for(instance_id)
        if not path.exists():
            return None
        return json.loads(path.read_text(encoding="utf-8"))

    def delete_instance(self, instance_id: str):
        path = self._path_for(instance_id)
        if path.exists():
            path.unlink()
