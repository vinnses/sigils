from html import escape

from markdown_it import MarkdownIt
from mdit_py_plugins.tasklists import tasklists_plugin

from lib.themes import theme_css


def live_reload_script() -> str:
    return """
    <script>
    (() => {
      let currentToken = null;
      async function poll() {
        try {
          const response = await fetch('/__mdview__/events', { cache: 'no-store' });
          if (!response.ok) return;
          const payload = await response.json();
          if (currentToken === null) {
            currentToken = payload.token;
            return;
          }
          if (payload.token !== currentToken) {
            window.location.reload();
          }
        } catch (_error) {
          return;
        }
      }
      setInterval(poll, 1000);
      poll();
    })();
    </script>
    """


def build_markdown_parser() -> MarkdownIt:
    return MarkdownIt("commonmark", {"html": True}).enable("table").use(tasklists_plugin)


def render_markdown(text: str, theme: str, title: str) -> str:
    parser = build_markdown_parser()
    body = parser.render(text)
    css = theme_css(theme)
    safe_title = escape(title)
    return f"""<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{safe_title}</title>
    <style>{css}</style>
  </head>
  <body>
    <main>
      <article class="markdown-body">
        {body}
      </article>
    </main>
    {live_reload_script()}
  </body>
</html>
"""
