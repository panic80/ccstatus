#!/usr/bin/env bash
# Installer for Claude Code Status Line
# Usage: curl -fsSL https://raw.githubusercontent.com/panic80/ccstatus/main/install.sh | bash

set -euo pipefail

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

# 4. Configure settings.json
SETTINGS=~/.claude/settings.json
STATUSLINE_CONFIG='{"type":"command","command":"~/.claude/statusline.sh","padding":2}'

if [ -f "$SETTINGS" ]; then
  # Merge into existing settings, preserving all other keys
  jq --argjson sl "$STATUSLINE_CONFIG" '. + {statusLine: $sl}' "$SETTINGS" > "${SETTINGS}.tmp" \
    && mv "${SETTINGS}.tmp" "$SETTINGS"
  echo "Updated existing $SETTINGS"
else
  echo "{\"statusLine\":$STATUSLINE_CONFIG}" | jq . > "$SETTINGS"
  echo "Created $SETTINGS"
fi

echo ""
echo "Done! Restart Claude Code to see the status line."
echo ""
echo "  YourName [Opus 4.6] Context: [████▁░░░░░] 42% | \$1.23 | +50/-12"
echo "  5h: [████▁░░░░░] 42% | Weekly: [█▄░░░░░░░░] 15%"
