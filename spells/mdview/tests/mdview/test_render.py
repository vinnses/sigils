from lib.render import render_markdown


def test_render_markdown_supports_tables_and_task_lists():
    text = "| a | b |\n| - | - |\n| 1 | 2 |\n\n- [x] done"
    html = render_markdown(text, theme="github", title="demo")
    assert "<table>" in html
    assert 'type="checkbox"' in html
    assert "demo" in html


def test_render_markdown_wraps_output_in_full_html_document():
    html = render_markdown("# Title", theme="github", title="Title")
    assert "<!doctype html>" in html.lower()
    assert "<h1>Title</h1>" in html
