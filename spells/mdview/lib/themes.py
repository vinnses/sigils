THEMES = {
    "github": """
    :root { color-scheme: light; }
    * { box-sizing: border-box; }
    body { margin: 0; background: #f6f8fa; color: #24292f; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    main { max-width: 980px; margin: 0 auto; padding: 2rem; }
    .markdown-body, .directory-body { background: #ffffff; border: 1px solid #d0d7de; border-radius: 12px; padding: 2rem; }
    pre { overflow-x: auto; padding: 1rem; background: #f6f8fa; border-radius: 8px; }
    code { font-family: "SFMono-Regular", Consolas, monospace; }
    table { border-collapse: collapse; width: 100%; }
    th, td { border: 1px solid #d0d7de; padding: 0.5rem 0.75rem; text-align: left; }
    a { color: #0969da; }
    ul.task-list { list-style: none; padding-left: 0; }
    """,
    "vscode": """
    :root { color-scheme: dark; }
    * { box-sizing: border-box; }
    body { margin: 0; background: #1e1e1e; color: #d4d4d4; font-family: "Segoe UI", sans-serif; }
    main { max-width: 980px; margin: 0 auto; padding: 2rem; }
    .markdown-body, .directory-body { background: #252526; border: 1px solid #3c3c3c; border-radius: 12px; padding: 2rem; }
    pre { overflow-x: auto; padding: 1rem; background: #111111; border-radius: 8px; }
    code { font-family: Consolas, monospace; }
    table { border-collapse: collapse; width: 100%; }
    th, td { border: 1px solid #3c3c3c; padding: 0.5rem 0.75rem; text-align: left; }
    a { color: #4daafc; }
    ul.task-list { list-style: none; padding-left: 0; }
    """,
}


def theme_css(name: str) -> str:
    return THEMES.get(name, THEMES["github"])
