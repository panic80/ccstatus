# Claude Code Status Line

A custom status line for [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) that displays your account name, model, context usage, session cost, lines changed, and API quota — all in two compact lines.

```
Albert [Opus 4.6] Context: [████▁░░░░░] 42% | $1.23 | +50/-12
5h: [████▁░░░░░] 42% | Weekly: [█▄░░░░░░░░] 15%
```

## What it shows

| Line | Info |
|------|------|
| **1** | Login name (dimmed), model, context window usage bar, session cost, lines added/removed |
| **2** | 5-hour and weekly API quota usage bars with reset countdowns |

## Requirements

- macOS 12 (Monterey) or later
- Claude Code CLI with OAuth authentication
- `jq` — ships with macOS 15+; on older versions, install via `brew install jq`
- `curl` — ships with all macOS versions

## Install

One command — installs jq if missing, downloads the script, and configures Claude Code:

```bash
curl -fsSL https://raw.githubusercontent.com/panic80/ccstatus/main/install.sh | bash
```

Then restart Claude Code.

## Manual Install

### 1. Download the script

```bash
mkdir -p ~/.claude
curl -fsSL https://raw.githubusercontent.com/panic80/ccstatus/main/statusline.sh -o ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

### 2. Configure Claude Code to use it

If `~/.claude/settings.json` doesn't exist yet, create it:

```bash
echo '{"statusLine":{"type":"command","command":"~/.claude/statusline.sh","padding":2}}' > ~/.claude/settings.json
```

If it already exists, add the `statusLine` key to the existing JSON:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh",
    "padding": 2
  }
}
```

### 3. Restart Claude Code

The status line appears at the bottom of your terminal on the next session.

## How it works

- Claude Code pipes a JSON blob to the script's stdin on each render containing the current model, context window percentage, cost, and lines changed.
- The script fetches your **API quota** (5-hour and weekly utilization) and **account profile** (display name) from the Anthropic OAuth API using the token stored in the macOS Keychain.
- Both API calls run in a **background process** with results cached to a per-user temp directory (60-second TTL), so the status line renders instantly from cache.
- If the API calls fail or no token is found, the status line gracefully omits the quota and name — no errors shown.

## Customization

| Variable | Default | Description |
|----------|---------|-------------|
| `CACHE_TTL` | `60` | Seconds between API refreshes |
| `CACHE_DIR` | `$TMPDIR` (falls back to `/tmp`) | Directory for cache and lock files |

Edit these at the top of `statusline.sh`.

## Troubleshooting

**Status line shows "jq is required"**
Your PATH may not include Homebrew. Run: `eval "$(/opt/homebrew/bin/brew shellenv)"` (Apple Silicon) or `eval "$(/usr/local/bin/brew shellenv)"` (Intel) and ensure jq is installed. The hardened statusline.sh automatically adds Homebrew paths, but if you installed jq elsewhere, ensure it's in your PATH.

**Quota shows `--`**
The first render after a cold start has no cache yet. Wait ~60 seconds for the background fetch to complete. If it persists, check for a stale lock:

```bash
rmdir "${TMPDIR:-/tmp}/claude-statusline-quota.lock" 2>/dev/null
```

The script automatically cleans stale locks older than 5 minutes, but you can force it manually.

**Installer can't find brew**
On Apple Silicon, Homebrew is at `/opt/homebrew/bin` which may not be in PATH for `curl | bash`. The installer now auto-detects Homebrew location, but if issues persist, run the installer from your terminal after opening a new shell.

**Name not showing**
The profile API call may have failed. Check that your token has the `user:profile` scope (it does by default for Claude Code logins). Inspect the cache:

```bash
jq '.display_name' "${TMPDIR:-/tmp}/claude-statusline-quota-cache.json"
```

**No status line at all**
Verify the script runs standalone:

```bash
echo '{"model":{"display_name":"Test"},"context_window":{"used_percentage":50},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0}}' | ~/.claude/statusline.sh
```

## Uninstall

```bash
rm ~/.claude/statusline.sh
# Remove "statusLine" key from settings.json:
jq 'del(.statusLine)' ~/.claude/settings.json > ~/.claude/settings.json.tmp && mv ~/.claude/settings.json.tmp ~/.claude/settings.json
```
