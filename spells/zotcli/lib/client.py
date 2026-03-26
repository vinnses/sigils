"""
client.py — pyzotero initialization and credential loading.
"""
import os
import sys

SPELL_DIR = os.environ.get(
    "SPELL_DIR",
    os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
)
CREDENTIALS_FILE = os.path.join(SPELL_DIR, "config", "credentials.env")


def load_credentials():
    """Parse KEY=value lines from credentials.env, ignoring comments and blanks."""
    creds = {}
    try:
        with open(CREDENTIALS_FILE) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" in line:
                    key, _, value = line.partition("=")
                    creds[key.strip()] = value.strip()
    except FileNotFoundError:
        pass
    return creds


def get_zotero():
    """Return an authenticated pyzotero.zotero.Zotero instance."""
    try:
        from pyzotero import zotero
    except ImportError:
        print("pyzotero is not installed. Run: make install", file=sys.stderr)
        sys.exit(1)

    creds = load_credentials()

    # Environment variables override credentials file
    library_id = os.environ.get("ZOTERO_LIBRARY_ID") or creds.get("ZOTERO_LIBRARY_ID")
    api_key = os.environ.get("ZOTERO_API_KEY") or creds.get("ZOTERO_API_KEY")
    library_type = (
        os.environ.get("ZOTERO_LIBRARY_TYPE")
        or creds.get("ZOTERO_LIBRARY_TYPE", "user")
    )

    if not library_id or not api_key:
        print("Zotero credentials not found.", file=sys.stderr)
        print("Run 'zotcli connect' to set up your library ID and API key.", file=sys.stderr)
        sys.exit(1)

    return zotero.Zotero(library_id, library_type, api_key)
