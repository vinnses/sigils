"""
config.py — configuration loader for zotcli.

Priority (lowest → highest):
  1. config/zotcli.defaults.yaml
  2. config/zotcli.yaml  (user overrides, gitignored)
  3. Environment variables  ZOTCLI_<KEY>__<SUBKEY>=value
  4. CLI flags (handled in commands.py)
"""
import os
import sys

SPELL_DIR = os.environ.get(
    "SPELL_DIR",
    os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
)

DEFAULTS_FILE = os.path.join(SPELL_DIR, "config", "zotcli.defaults.yaml")
USER_FILE     = os.path.join(SPELL_DIR, "config", "zotcli.yaml")


def _load_yaml(path):
    try:
        import yaml
    except ImportError:
        print("pyyaml is not installed. Run: make install", file=sys.stderr)
        sys.exit(1)
    try:
        with open(path) as f:
            return yaml.safe_load(f) or {}
    except FileNotFoundError:
        return {}
    except Exception as e:
        print(f"Warning: could not parse {path}: {e}", file=sys.stderr)
        return {}


def _deep_merge(base, override):
    """Recursively merge override into base (returns new dict)."""
    result = dict(base)
    for key, val in override.items():
        if key in result and isinstance(result[key], dict) and isinstance(val, dict):
            result[key] = _deep_merge(result[key], val)
        else:
            result[key] = val
    return result


def _apply_env(config):
    """
    Apply env vars of the form ZOTCLI_<KEY>__<SUBKEY>=value.
    Double underscore separates nesting levels.
    Example: ZOTCLI_LS__DEFAULT_SORT=date → config['ls']['default_sort'] = 'date'
    """
    prefix = "ZOTCLI_"
    for key, val in os.environ.items():
        if not key.startswith(prefix):
            continue
        rest = key[len(prefix):]  # e.g. LS__DEFAULT_SORT
        parts = [p.lower() for p in rest.split("__")]
        if not parts:
            continue
        d = config
        for part in parts[:-1]:
            if part not in d or not isinstance(d[part], dict):
                d[part] = {}
            d = d[part]
        # Coerce booleans
        if val.lower() in ("true", "1", "yes"):
            d[parts[-1]] = True
        elif val.lower() in ("false", "0", "no"):
            d[parts[-1]] = False
        else:
            try:
                d[parts[-1]] = int(val)
            except ValueError:
                d[parts[-1]] = val
    return config


def load_config():
    """Return effective merged configuration dict."""
    defaults = _load_yaml(DEFAULTS_FILE)
    user     = _load_yaml(USER_FILE)
    merged   = _deep_merge(defaults, user)
    return _apply_env(merged)


def get_value(config, dotpath):
    """
    Return a value by dot-notation path (e.g. 'ls.default_sort').
    Returns None if path doesn't exist.
    """
    parts = dotpath.split(".")
    d = config
    for part in parts:
        if not isinstance(d, dict) or part not in d:
            return None
        d = d[part]
    return d


def set_value(dotpath, value):
    """
    Write a value to config/zotcli.yaml.
    Creates file if needed; preserves existing values.
    """
    try:
        import yaml
    except ImportError:
        print("pyyaml is not installed. Run: make install", file=sys.stderr)
        sys.exit(1)

    existing = _load_yaml(USER_FILE)
    parts = dotpath.split(".")
    d = existing
    for part in parts[:-1]:
        if part not in d or not isinstance(d[part], dict):
            d[part] = {}
        d = d[part]

    # Coerce value type
    if isinstance(value, str):
        if value.lower() in ("true", "1", "yes"):
            value = True
        elif value.lower() in ("false", "0", "no"):
            value = False
        else:
            try:
                value = int(value)
            except ValueError:
                pass

    d[parts[-1]] = value

    os.makedirs(os.path.dirname(USER_FILE), exist_ok=True)
    with open(USER_FILE, "w") as f:
        yaml.dump(existing, f, default_flow_style=False, allow_unicode=True)


def print_config(config):
    """Print effective merged config as YAML."""
    try:
        import yaml
    except ImportError:
        import json
        print(json.dumps(config, indent=2))
        return
    print(yaml.dump(config, default_flow_style=False, allow_unicode=True), end="")
