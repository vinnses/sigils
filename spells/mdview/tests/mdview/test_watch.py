from lib.watch import ChangeToken, FileWatcher


def test_file_watcher_starts_and_stops(tmp_path):
    token = ChangeToken()
    watcher = FileWatcher(tmp_path, token)
    watcher.start()
    watcher.stop()
    assert token.current() == 0
