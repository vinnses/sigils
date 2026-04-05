# mdview

Local Markdown preview spell for files and directories.

## Commands

- `mdview [PATH]`
- `mdview serve [PATH]`
- `mdview list`
- `mdview stop <id>`
- `mdview open <id>`

## Behavior

- File targets render the selected Markdown file at `/`
- Directory targets render an index that shows only Markdown files and nested directories that contain Markdown
- Relative links inside rendered Markdown are served from the same root
- Theme selection is currently `github` or `vscode`
- Live reload uses full-page refresh polling

## Background workflow

```bash
mdview serve docs -b
mdview list
mdview open <id>
mdview stop <id>
```

## Defaults

- Host: `127.0.0.1`
- Port range: `17700-17799`
- Theme: `github`
- Watch: enabled

## Non-goals

- No Arcane integration
- No reverse proxy or domain routing
- No editing UI
