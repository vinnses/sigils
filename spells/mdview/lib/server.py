import json
import mimetypes
import signal
from dataclasses import dataclass, field
from html import escape
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse

from lib.discovery import classify_target, list_directory_view, resolve_target_path
from lib.render import live_reload_script, render_markdown
from lib.themes import theme_css
from lib.watch import ChangeToken, FileWatcher


@dataclass
class AppState:
    root_path: Path
    target_path: Path
    theme: str = "github"
    watch: bool = True
    host: str = "127.0.0.1"
    port: int = 17700
    token: ChangeToken = field(default_factory=ChangeToken)
    watcher: FileWatcher | None = None

    @classmethod
    def from_target(
        cls,
        target: Path,
        *,
        theme: str = "github",
        watch: bool = True,
        host: str = "127.0.0.1",
        port: int = 17700,
    ):
        resolved = target.resolve()
        if resolved.is_dir():
            root_path = resolved
            target_path = resolved
        else:
            root_path = resolved.parent
            target_path = resolved
        return cls(root_path=root_path, target_path=target_path, theme=theme, watch=watch, host=host, port=port)

    def url(self) -> str:
        return f"http://{self.host}:{self.port}/"

    def start_watcher(self):
        if self.watch:
            self.watcher = FileWatcher(self.root_path, self.token).start()

    def stop_watcher(self):
        if self.watcher:
            self.watcher.stop()
            self.watcher = None


def render_directory_page(current_path: Path, root_path: Path, theme: str) -> str:
    entries = list_directory_view(current_path)
    css = theme_css(theme)
    title = current_path.name or root_path.name or "mdview"
    current_url = "/" if current_path == root_path else f"/{current_path.relative_to(root_path).as_posix()}/"

    items = []
    if current_path != root_path:
        parent = current_path.parent
        href = "/" if parent == root_path else f"/{parent.relative_to(root_path).as_posix()}/"
        items.append(f'<li><a href="{href}">..</a></li>')

    for entry in entries:
        path = entry["path"]
        if entry["kind"] == "directory":
            href = f"/{path.relative_to(root_path).as_posix()}/"
            label = f"{entry['name']}/"
        else:
            href = f"/{path.relative_to(root_path).as_posix()}"
            label = entry["name"]
        items.append(f'<li><a href="{href}">{escape(label)}</a></li>')

    listing = "\n".join(items) or "<li>No Markdown content here.</li>"

    return f"""<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{escape(title)}</title>
    <style>{css}</style>
  </head>
  <body>
    <main>
      <section class="directory-body">
        <h1>{escape(title)}</h1>
        <p>{escape(current_url)}</p>
        <ul>
          {listing}
        </ul>
      </section>
    </main>
    {live_reload_script()}
  </body>
</html>
"""


class MdviewHTTPServer(ThreadingHTTPServer):
    allow_reuse_address = True

    def __init__(self, server_address, request_handler_class, app_state: AppState):
        super().__init__(server_address, request_handler_class)
        self.app_state = app_state


class MdviewHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        return

    @property
    def app_state(self) -> AppState:
        return self.server.app_state

    def _send_html(self, html: str):
        body = html.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_json(self, payload: dict):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_file(self, path: Path):
        body = path.read_bytes()
        content_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _target_for_request(self, request_path: str) -> Path:
        decoded = unquote(request_path)
        if decoded in {"", "/"}:
            return self.app_state.target_path
        return resolve_target_path(self.app_state.root_path, decoded)

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/__mdview__/events":
            self._send_json({"token": self.app_state.token.current()})
            return

        try:
            target = self._target_for_request(parsed.path)
            kind = classify_target(target)
        except (FileNotFoundError, ValueError):
            self.send_error(404, "Not found")
            return

        if kind == "asset":
            self._send_file(target)
            return
        if kind == "directory":
            self._send_html(render_directory_page(target, self.app_state.root_path, self.app_state.theme))
            return

        html = render_markdown(target.read_text(encoding="utf-8"), theme=self.app_state.theme, title=target.stem)
        self._send_html(html)


def serve_app(app_state: AppState):
    app_state.start_watcher()
    httpd = MdviewHTTPServer((app_state.host, app_state.port), MdviewHandler, app_state)

    def shutdown_handler(_signum, _frame):
        httpd.shutdown()

    previous_sigterm = signal.getsignal(signal.SIGTERM)
    signal.signal(signal.SIGTERM, shutdown_handler)
    try:
        try:
            httpd.serve_forever(poll_interval=0.25)
        except KeyboardInterrupt:
            pass
    finally:
        httpd.server_close()
        app_state.stop_watcher()
        signal.signal(signal.SIGTERM, previous_sigterm)
