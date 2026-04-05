import argparse
import os
import signal
import subprocess
import sys
from contextlib import suppress
from pathlib import Path

import yaml

from lib.registry import Registry, choose_port
from lib.server import AppState, serve_app


def normalize_argv(argv: list[str]) -> list[str]:
    if not argv:
        return ["serve", "."]

    first = argv[0]
    commands = {"serve", "list", "stop", "open", "help", "-h", "--help"}
    if first in commands:
        return argv
    return ["serve", *argv]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="mdview")
    subparsers = parser.add_subparsers(dest="command", required=True)

    serve = subparsers.add_parser("serve")
    serve.add_argument("path", nargs="?", default=".")
    serve.add_argument("-b", "--background", action="store_true")
    serve.add_argument("-p", "--port", type=int)
    serve.add_argument("-t", "--theme", default=None)
    serve.add_argument("--open", dest="open_browser", action="store_true")
    serve.add_argument("--no-watch", dest="watch", action="store_false", default=True)

    subparsers.add_parser("list")

    stop = subparsers.add_parser("stop")
    stop.add_argument("id")

    open_cmd = subparsers.add_parser("open")
    open_cmd.add_argument("id")

    return parser


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = build_parser()
    return parser.parse_args(argv)


def spell_dir() -> Path:
    raw = os.environ.get("SPELL_DIR")
    if raw:
        return Path(raw)
    return Path(__file__).resolve().parent.parent


def load_defaults() -> dict:
    config_path = spell_dir() / "config" / "mdview.defaults.yaml"
    with config_path.open("r", encoding="utf-8") as handle:
        return yaml.safe_load(handle) or {}


def invocation_cwd() -> Path:
    return Path(os.environ.get("MDVIEW_CALLER_CWD", os.getcwd()))


def resolve_cli_target(raw_path: str) -> Path:
    candidate = Path(raw_path).expanduser()
    if candidate.is_absolute():
        return candidate.resolve()
    return (invocation_cwd() / candidate).resolve()


def registry() -> Registry:
    return Registry(spell_dir() / "data")


def log_dir() -> Path:
    path = spell_dir() / "logs"
    path.mkdir(parents=True, exist_ok=True)
    return path


def _is_pid_alive(pid: int) -> bool:
    with suppress(OSError):
        os.kill(pid, 0)
        return True
    return False


def _live_instances():
    items = []
    current_registry = registry()
    for instance in current_registry.list_instances():
        pid = int(instance.get("pid", 0))
        if pid and _is_pid_alive(pid):
            items.append(instance)
        else:
            current_registry.delete_instance(instance["id"])
    return items


def _resolve_port(args: argparse.Namespace, defaults: dict) -> int:
    if args.port:
        return args.port
    in_use = {int(item["port"]) for item in _live_instances()}
    return choose_port(defaults["port_range_start"], defaults["port_range_end"], in_use=in_use)


def _resolve_app_state(args: argparse.Namespace) -> AppState:
    defaults = load_defaults()
    target = resolve_cli_target(args.path)
    if not target.exists():
        raise FileNotFoundError(target)
    return AppState.from_target(
        target,
        theme=args.theme or defaults.get("theme", "github"),
        watch=args.watch if args.watch is not None else defaults.get("watch", True),
        host=defaults.get("host", "127.0.0.1"),
        port=_resolve_port(args, defaults),
    )


def _python_executable() -> str:
    venv_python = spell_dir() / ".venv" / "bin" / "python3"
    if venv_python.exists():
        return str(venv_python)
    return sys.executable


def _spawn_background(args: argparse.Namespace, app_state: AppState) -> int:
    log_path = log_dir() / f"mdview-{app_state.port}.log"
    command = [_python_executable(), "-m", "lib.commands", "serve", str(resolve_cli_target(args.path)), "--port", str(app_state.port)]
    if args.theme:
        command.extend(["--theme", args.theme])
    if not app_state.watch:
        command.append("--no-watch")

    env = os.environ.copy()
    env["SPELL_DIR"] = str(spell_dir())
    env["MDVIEW_BACKGROUND_CHILD"] = "1"
    env["MDVIEW_CALLER_CWD"] = str(invocation_cwd())

    with log_path.open("ab") as handle:
        process = subprocess.Popen(
            command,
            cwd=spell_dir(),
            env=env,
            stdout=handle,
            stderr=handle,
            start_new_session=True,
        )

    instance = registry().create_instance(
        pid=process.pid,
        port=app_state.port,
        root_path=str(app_state.root_path),
        target_path=str(app_state.target_path),
        theme=app_state.theme,
        watch=app_state.watch,
        url=app_state.url(),
        log_path=str(log_path),
    )
    print(f"{instance['id']}\t{instance['url']}")
    return 0


def _list_instances() -> int:
    items = _live_instances()
    if not items:
        print("no background instances")
        return 0

    print("id\tpid\tport\ttheme\tpath\turl")
    for item in items:
        print(
            f"{item['id']}\t{item['pid']}\t{item['port']}\t{item['theme']}\t"
            f"{item['target_path']}\t{item['url']}"
        )
    return 0


def _open_instance(instance_id: str) -> int:
    instance = registry().get_instance(instance_id)
    if not instance:
        raise KeyError(instance_id)
    print(instance["url"])
    return 0


def _stop_instance(instance_id: str) -> int:
    current_registry = registry()
    instance = current_registry.get_instance(instance_id)
    if not instance:
        raise KeyError(instance_id)
    pid = int(instance["pid"])
    with suppress(ProcessLookupError):
        os.kill(pid, signal.SIGTERM)
    current_registry.delete_instance(instance_id)
    return 0


def main() -> int:
    args = parse_args(normalize_argv(os.sys.argv[1:]))
    if args.command == "list":
        return _list_instances()
    if args.command == "stop":
        return _stop_instance(args.id)
    if args.command == "open":
        return _open_instance(args.id)

    app_state = _resolve_app_state(args)
    if args.background and os.environ.get("MDVIEW_BACKGROUND_CHILD") != "1":
        return _spawn_background(args, app_state)

    print(app_state.url())
    serve_app(app_state)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
