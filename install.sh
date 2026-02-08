#!/usr/bin/env bash
# Installer for Claude Code Status Line
# Usage: curl -fsSL https://raw.githubusercontent.com/panic80/ccstatus/main/install.sh | bash

set -euo pipefail

# Ensure Homebrew is in PATH (Apple Silicon vs Intel)
# Needed because curl|bash runs in a non-login shell where Homebrew may not be in PATH
if [ -x "/opt/homebrew/bin/brew" ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x "/usr/local/bin/brew" ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

echo "Installing Claude Code Status Line..."

# 1. Install jq if missing
if ! command -v jq &>/dev/null; then
  echo "jq not found — installing via Homebrew..."
  if ! command -v brew &>/dev/null; then
    echo "Error: Homebrew is required to install jq. Install it from https://brew.sh"
    exit 1
  fi
  brew install jq
fi

# 2. Ensure ~/.claude directory exists
mkdir -p ~/.claude

# 3. Download the statusline script
curl -fsSL https://raw.githubusercontent.com/panic80/ccstatus/main/statusline.sh -o ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh

# 4. Validate downloaded script
if [ ! -s ~/.claude/statusline.sh ]; then
  echo "Error: Download failed or file is empty. Try again."
  rm -f ~/.claude/statusline.sh
  exit 1
fi
if ! head -1 ~/.claude/statusline.sh | grep -q '^#!/'; then
  echo "Error: Downloaded file is corrupt (missing shebang). Try again."
  rm -f ~/.claude/statusline.sh
  exit 1
fi

# 5. Configure settings.json
SETTINGS=~/.claude/settings.json
STATUSLINE_CONFIG='{"type":"command","command":"~/.claude/statusline.sh","padding":2}'

if [ -f "$SETTINGS" ]; then
  # Backup existing settings before modifying
  cp "$SETTINGS" "${SETTINGS}.bak"

  if jq empty "$SETTINGS" 2>/dev/null; then
    # Valid JSON — merge, preserving all other keys
    jq --argjson sl "$STATUSLINE_CONFIG" '. + {statusLine: $sl}' "$SETTINGS" > "${SETTINGS}.tmp" \
      && mv "${SETTINGS}.tmp" "$SETTINGS"
    echo "Updated existing $SETTINGS (backup at ${SETTINGS}.bak)"
  else
    # Invalid JSON — warn and create fresh
    echo "Warning: existing $SETTINGS is not valid JSON. Backed up to ${SETTINGS}.bak and creating fresh."
    echo "{\"statusLine\":$STATUSLINE_CONFIG}" | jq . > "$SETTINGS"
  fi
else
  echo "{\"statusLine\":$STATUSLINE_CONFIG}" | jq . > "$SETTINGS"
  echo "Created $SETTINGS"
fi

echo ""
echo "Done! Restart Claude Code to see the status line."
echo ""
echo "  YourName [Opus 4.6] Context: [████▁░░░░░] 42% | \$1.23 | +50/-12"
echo "  5h: [████▁░░░░░] 42% | Weekly: [█▄░░░░░░░░] 15%"
