#!/usr/bin/env bash
# Claude Code Status Line — Installer
# Usage:
#   bash install.sh                       # interactive theme selection
#   bash install.sh --theme braille       # non-interactive, explicit theme
#   curl -fsSL <url>/install.sh | bash -s -- --theme dots

set -euo pipefail

INSTALL_DIR="$HOME/.claude"
THEME_FILE="$INSTALL_DIR/statusline-theme"
SCRIPT_URL="${CCSTATUS_SCRIPT_URL:-}"  # set externally for remote installs

# ── Parse arguments ──────────────────────────────────────────────────────────
theme=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --theme)
      theme="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

# ── Validate theme if provided ───────────────────────────────────────────────
if [[ -n "$theme" ]]; then
  case "$theme" in
    braille|blocks|dots|compact) ;;
    *)
      echo "Error: unknown theme '$theme'"
      echo "Valid themes: braille, blocks, dots, compact"
      exit 1
      ;;
  esac
fi

# ── Check dependencies ──────────────────────────────────────────────────────
if ! command -v jq &>/dev/null; then
  echo "jq is required but not installed."
  echo "  brew install jq    (macOS)"
  echo "  apt install jq     (Debian/Ubuntu)"
  exit 1
fi

# ── Theme selection (interactive) ────────────────────────────────────────────
if [[ -z "$theme" ]]; then
  if [ -t 0 ] || [ -e /dev/tty ]; then
    echo ""
    echo "  Select a status line theme:"
    echo ""
    echo "    1) Braille   ⣿⣿⣦⣀⣀⣀⣀⣀⣀⣀  (default)"
    echo "    2) Blocks    [██▄░░░░░░░]"
    echo "    3) Dots      ●●●○○○○○○○"
    echo "    4) Compact   (no bars)"
    echo ""
    read -r -p "  Choice [1]: " choice </dev/tty 2>/dev/null || choice=""
    case "$choice" in
      2) theme="blocks"  ;;
      3) theme="dots"    ;;
      4) theme="compact" ;;
      *) theme="braille" ;;
    esac
  else
    theme="braille"  # non-interactive fallback
  fi
fi

# ── Create install directory ─────────────────────────────────────────────────
mkdir -p "$INSTALL_DIR"

# ── Download statusline.sh (if URL provided) ────────────────────────────────
if [[ -n "$SCRIPT_URL" ]]; then
  echo "  Downloading statusline.sh..."
  curl -fsSL "$SCRIPT_URL" -o "$INSTALL_DIR/statusline.sh"
  chmod +x "$INSTALL_DIR/statusline.sh"
fi

# ── Write theme config ──────────────────────────────────────────────────────
echo "$theme" > "$THEME_FILE"

# ── Configure Claude Code settings ──────────────────────────────────────────
SETTINGS_FILE="$INSTALL_DIR/settings.json"
if [[ -f "$SETTINGS_FILE" ]]; then
  # Migrate: remove broken hooks.StatusLine from previous installs
  if jq -e '.hooks.StatusLine' "$SETTINGS_FILE" &>/dev/null; then
    jq 'del(.hooks.StatusLine) | if .hooks == {} then del(.hooks) else . end' \
      "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
    echo "  Removed invalid hooks.StatusLine from settings.json"
  fi
  # Add top-level statusLine config if not already present
  if ! jq -e '.statusLine' "$SETTINGS_FILE" &>/dev/null; then
    jq '.statusLine = {"type": "command", "command": "bash ~/.claude/statusline.sh", "padding": 2}' \
      "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
    echo "  Added status line config to settings.json"
  fi
else
  cat > "$SETTINGS_FILE" << 'SETTINGS'
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline.sh",
    "padding": 2
  }
}
SETTINGS
  echo "  Created settings.json with status line config"
fi

# ── Post-install output ─────────────────────────────────────────────────────
echo ""
echo "  Done! Restart Claude Code to see the status line."
echo ""
echo "  Theme: $theme (selected)"
echo ""
echo "  Available themes:"
echo "    echo \"braille\" > ~/.claude/statusline-theme   ⣿⣿⣦⣀⣀⣀⣀⣀⣀⣀"
echo "    echo \"blocks\"  > ~/.claude/statusline-theme   [██▄░░░░░░░]"
echo "    echo \"dots\"    > ~/.claude/statusline-theme   ●●●○○○○○○○"
echo "    echo \"compact\" > ~/.claude/statusline-theme   (no bars)"
echo ""
echo "  Changes take effect on next refresh — no restart needed."
echo ""
