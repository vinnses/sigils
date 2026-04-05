from pathlib import Path
from threading import Event, Lock, Thread

from watchfiles import watch


WATCH_SUFFIXES = {".md", ".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp"}


class ChangeToken:
    def __init__(self):
        self._lock = Lock()
        self._value = 0

    def current(self) -> int:
        with self._lock:
            return self._value

    def bump(self) -> int:
        with self._lock:
            self._value += 1
            return self._value


class FileWatcher:
    def __init__(self, root_path: Path, token: ChangeToken):
        self.root_path = root_path
        self.token = token
        self._stop_event = Event()
        self._thread: Thread | None = None

    def _relevant(self, changed_path: str) -> bool:
        return Path(changed_path).suffix.lower() in WATCH_SUFFIXES

    def _run(self):
        if not self.root_path.exists():
            return

        for changes in watch(
            self.root_path,
            stop_event=self._stop_event,
            rust_timeout=250,
            yield_on_timeout=True,
        ):
            if self._stop_event.is_set():
                break
            if any(self._relevant(changed_path) for _change, changed_path in changes):
                self.token.bump()

    def start(self):
        if self._thread and self._thread.is_alive():
            return self

        self._thread = Thread(target=self._run, daemon=True)
        self._thread.start()
        return self

    def stop(self):
        self._stop_event.set()
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=1)
