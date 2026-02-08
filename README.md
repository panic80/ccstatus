# Claude Code Status Line

A rich status line for Claude Code showing model, context usage, cost, lines changed, and API quota — with switchable themes.

## Themes

Four built-in themes. The default is **braille**.

### Braille (default)
```
╭ Claude │ [Opus] │ Ctx ⣿⣿⣦⣀⣀⣀⣀⣀⣀⣀ 25% │ $0.50 │ +10/-3
╰ 5h ⣿⣿⣿⣿⣿⣀⣀⣀⣀⣀ 50% │ Wk ⣿⣿⣀⣀⣀⣀⣀⣀⣀⣀ 20%
```
Filled braille cells with dim bottom-row braille (`⣀`) for empty slots. Clean and compact.

### Blocks
```
╭ Claude │ [Opus] │ Ctx [██▄░░░░░░░] 25% │ $0.50 │ +10/-3
╰ 5h [█████░░░░░] 50% │ Wk [██░░░░░░░░] 20%
```
Classic block bars with fractional fill (`▁▂▃▄▅▆▇`) and `[brackets]`.

### Dots
```
╭ Claude │ [Opus] │ Ctx ●●●○○○○○○○ 25% │ $0.50 │ +10/-3
╰ 5h ●●●●●○○○○○ 50% │ Wk ●●○○○○○○○○ 20%
```
Filled/empty circles. No fractional fill — rounds to nearest dot.

### Compact
```
╭ Claude │ [Opus] │ Ctx 25% │ $0.50 │ +10/-3
╰ 5h 50% │ Wk 20%
```
Percentages only, no progress bars. Minimal footprint.

## Switching Themes

Write the theme name to `~/.claude/statusline-theme`:

```bash
echo "braille" > ~/.claude/statusline-theme
echo "blocks"  > ~/.claude/statusline-theme
echo "dots"    > ~/.claude/statusline-theme
echo "compact" > ~/.claude/statusline-theme
```

Changes take effect on the next status line refresh — no restart needed.

If the file doesn't exist, the default theme is `braille`.

## Installation

### Interactive install
```bash
bash ~/.claude/install.sh
```
Shows a menu to pick your theme.

### Non-interactive install
```bash
bash ~/.claude/install.sh --theme dots
```

### Installing via Claude Code
Tell Claude Code: "install ccstatus" or paste the repo URL.
Claude Code will ask which theme you prefer before installing.
You can also specify directly:
```bash
curl -fsSL <url>/install.sh | bash -s -- --theme dots
```

## Requirements

- **jq** — `brew install jq` (macOS) or `apt install jq` (Linux)
- **Claude Code** with StatusLine hook support

## How It Works

The status line script (`~/.claude/statusline.sh`) runs as a Claude Code StatusLine hook. It:

1. Reads JSON from stdin (model, context, cost, lines changed)
2. Fetches API quota data (cached, background refresh every 60s)
3. Renders a two-line status bar with the active theme

The theme is read fresh on every invocation from `~/.claude/statusline-theme`, so switching is instant.
