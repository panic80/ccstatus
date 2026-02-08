#!/usr/bin/env bash
# Claude Code Developer Status Line
# Shows: model, context usage, cost, lines changed, quota percentages
# Reads built-in JSON from stdin + fetches quota from Anthropic OAuth API (cached)

set -euo pipefail

# Ensure Homebrew tools are in PATH (needed for non-interactive shells)
for brew_path in /opt/homebrew/bin /usr/local/bin; do
  case ":$PATH:" in
    *":$brew_path:"*) ;;  # already in PATH
    *) [ -d "$brew_path" ] && export PATH="$brew_path:$PATH" ;;
  esac
done

if ! command -v jq &>/dev/null; then
  echo "jq is required: brew install jq"
  exit 1
fi

CACHE_DIR="${TMPDIR:-/tmp}"
CACHE_FILE="${CACHE_DIR}/claude-statusline-quota-cache.json"
CACHE_TTL=60  # seconds
LOCK_FILE="${CACHE_DIR}/claude-statusline-quota.lock"

# Clean stale lock (older than 5 minutes = stuck background process)
if [ -d "$LOCK_FILE" ]; then
  lock_age=$(( $(date +%s) - $(stat -f %m "$LOCK_FILE" 2>/dev/null || stat -c %Y "$LOCK_FILE" 2>/dev/null || echo "0") ))
  if (( lock_age > 300 )); then
    rmdir "$LOCK_FILE" 2>/dev/null || true
  fi
fi

# ── Colors ───────────────────────────────────────────────────────────────────
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
DIM="\033[2m"
BOLD="\033[1m"
RESET="\033[0m"

# ── Read stdin JSON ──────────────────────────────────────────────────────────
INPUT=$(cat)

model=$(echo "$INPUT" | jq -r '.model.display_name // "Unknown"' 2>/dev/null || echo "Unknown")
context_pct=$(echo "$INPUT" | jq -r '.context_window.used_percentage // 0' 2>/dev/null || echo "0")
cost=$(echo "$INPUT" | jq -r '.cost.total_cost_usd // 0' 2>/dev/null || echo "0")
lines_added=$(echo "$INPUT" | jq -r '.cost.total_lines_added // 0' 2>/dev/null || echo "0")
lines_removed=$(echo "$INPUT" | jq -r '.cost.total_lines_removed // 0' 2>/dev/null || echo "0")

# ── Helper: color based on percentage ────────────────────────────────────────
color_for_pct() {
  local pct=$1
  if (( pct >= 80 )); then
    echo -e "$RED"
  elif (( pct >= 50 )); then
    echo -e "$YELLOW"
  else
    echo -e "$GREEN"
  fi
}

# ── Helper: progress bar (granular using Unicode fractional blocks) ─────────
progress_bar() {
  local pct=$1
  local width=${2:-12}

  # Fractional block chars indexed by eighths (0=none, 1=▁ .. 7=▇)
  local -a fractional=( "" "▁" "▂" "▃" "▄" "▅" "▆" "▇" )

  local total_eighths=$(( pct * width * 8 / 100 ))
  local full=$(( total_eighths / 8 ))
  local partial=$(( total_eighths % 8 ))
  local has_partial=0
  (( partial > 0 )) && has_partial=1
  local empty=$(( width - full - has_partial ))

  local color
  color=$(color_for_pct "$pct")

  local bar="${color}"
  for ((i=0; i<full; i++)); do bar+="█"; done
  if (( partial > 0 )); then
    bar+="${fractional[$partial]}"
  fi
  bar+="${DIM}"
  for ((i=0; i<empty; i++)); do bar+="░"; done
  bar+="${RESET}"
  echo -e "$bar"
}

# ── Helper: format time until reset ──────────────────────────────────────────
format_reset_time() {
  local reset_at="$1"
  if [[ -z "$reset_at" || "$reset_at" == "null" ]]; then
    echo ""
    return
  fi
  local now reset_epoch diff days hours mins
  now=$(date +%s)
  # Handle both GNU and BSD date
  if date -d "2000-01-01" +%s &>/dev/null; then
    reset_epoch=$(date -d "$reset_at" +%s 2>/dev/null || echo "0")
  else
    # Strip fractional seconds, normalise tz for BSD date %z ("+00:00"→"+0000", "Z"→"+0000")
    local cleaned
    cleaned=$(echo "$reset_at" | sed -E 's/\.[0-9]+([\+\-Z])/\1/; s/([\+\-][0-9]{2}):([0-9]{2})$/\1\2/; s/Z$/+0000/')
    reset_epoch=$(date -jf "%Y-%m-%dT%H:%M:%S%z" "$cleaned" +%s 2>/dev/null || echo "0")
  fi
  if (( reset_epoch <= now )); then
    echo ""
    return
  fi
  diff=$(( reset_epoch - now ))
  days=$(( diff / 86400 ))
  hours=$(( (diff % 86400) / 3600 ))
  mins=$(( (diff % 3600) / 60 ))
  if (( days > 0 )); then
    echo " (resets ${days}d ${hours}h)"
  elif (( hours > 0 )); then
    echo " (resets ${hours}h ${mins}m)"
  else
    echo " (resets ${mins}m)"
  fi
}

# ── Fetch quota from API (background, cached) ───────────────────────────────
fetch_quota() {
  # Acquire lock (non-blocking) to prevent concurrent fetches
  if ! mkdir "$LOCK_FILE" 2>/dev/null; then
    return
  fi
  trap 'rmdir "$LOCK_FILE" 2>/dev/null' EXIT

  # Extract OAuth token from macOS Keychain
  local token
  token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null || echo "")
  if [[ -z "$token" ]]; then
    rmdir "$LOCK_FILE" 2>/dev/null
    return
  fi

  # The keychain stores JSON with nested structure: .claudeAiOauth.accessToken
  local access_token
  access_token=$(echo "$token" | jq -r '.claudeAiOauth.accessToken // .accessToken // .access_token // empty' 2>/dev/null || echo "")
  if [[ -z "$access_token" ]]; then
    rmdir "$LOCK_FILE" 2>/dev/null
    return
  fi

  # Detect Claude Code version for User-Agent
  local cc_version="0.0.0"
  if command -v claude &>/dev/null; then
    cc_version=$(claude --version 2>/dev/null | head -1 | awk '{print $1}') || cc_version="0.0.0"
  fi

  # Call the API
  local response
  response=$(curl -s --max-time 5 \
    -H "Authorization: Bearer ${access_token}" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "User-Agent: claude-code/${cc_version}" \
    "https://api.anthropic.com/api/oauth/usage" 2>/dev/null || echo "")

  if [[ -n "$response" ]] && echo "$response" | jq -e '.five_hour' &>/dev/null; then
    echo "$response" > "$CACHE_FILE"

    # Fetch profile to get display name (same token, same background cycle)
    local profile
    profile=$(curl -s --max-time 5 \
      -H "Authorization: Bearer ${access_token}" \
      -H "anthropic-beta: oauth-2025-04-20" \
      -H "User-Agent: claude-code/${cc_version}" \
      "https://api.anthropic.com/api/oauth/profile" 2>/dev/null || echo "")

    local display_name=""
    if [[ -n "$profile" ]]; then
      display_name=$(echo "$profile" | jq -r '.account.display_name // empty' 2>/dev/null || echo "")
    fi

    if [[ -n "$display_name" ]]; then
      jq --arg name "$display_name" '. + {display_name: $name}' "$CACHE_FILE" > "${CACHE_FILE}.tmp" \
        && mv "${CACHE_FILE}.tmp" "$CACHE_FILE"
    fi
  fi

  rmdir "$LOCK_FILE" 2>/dev/null
}

# ── Check cache and refresh if needed ────────────────────────────────────────
quota_5h_pct="--"
quota_weekly_pct="--"
reset_5h=""
reset_weekly=""

if [[ -f "$CACHE_FILE" ]]; then
  cache_age=$(( $(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || stat -c %Y "$CACHE_FILE" 2>/dev/null || echo "0") ))
else
  cache_age=$((CACHE_TTL + 1))  # Force fetch
fi

# Background fetch if cache is stale
if (( cache_age > CACHE_TTL )); then
  fetch_quota &
  disown 2>/dev/null
fi

# Read from cache (may be from previous cycle)
if [[ -f "$CACHE_FILE" ]]; then
  quota_5h=$(jq -r '.five_hour.utilization // empty' "$CACHE_FILE" 2>/dev/null || echo "")
  quota_weekly=$(jq -r '.seven_day.utilization // empty' "$CACHE_FILE" 2>/dev/null || echo "")
  reset_5h_at=$(jq -r '.five_hour.resets_at // empty' "$CACHE_FILE" 2>/dev/null || echo "")
  reset_weekly_at=$(jq -r '.seven_day.resets_at // empty' "$CACHE_FILE" 2>/dev/null || echo "")
  display_name=$(jq -r '.display_name // empty' "$CACHE_FILE" 2>/dev/null || echo "")

  if [[ -n "$quota_5h" ]]; then
    # Sanitize: strip anything that's not digits, dots, or minus
    quota_5h=$(echo "$quota_5h" | tr -cd '0-9.\-')
    quota_5h_pct=$(awk -v val="${quota_5h:-0}" 'BEGIN { printf "%.0f", val }')
    reset_5h=$(format_reset_time "$reset_5h_at")
  fi
  if [[ -n "$quota_weekly" ]]; then
    quota_weekly=$(echo "$quota_weekly" | tr -cd '0-9.\-')
    quota_weekly_pct=$(awk -v val="${quota_weekly:-0}" 'BEGIN { printf "%.0f", val }')
    reset_weekly=$(format_reset_time "$reset_weekly_at")
  fi
fi

# ── Format cost ──────────────────────────────────────────────────────────────
cost=$(echo "${cost:-0}" | tr -cd '0-9.\-')
formatted_cost=$(awk -v val="${cost:-0}" 'BEGIN { printf "$%.2f", val }')

# ── Round context percentage ─────────────────────────────────────────────────
context_pct=$(echo "${context_pct:-0}" | tr -cd '0-9.\-')
context_int=$(awk -v val="${context_pct:-0}" 'BEGIN { printf "%.0f", val }')

# ── Build output ─────────────────────────────────────────────────────────────
ctx_bar=$(progress_bar "$context_int" 10)
name_prefix=""
if [[ -n "${display_name:-}" ]]; then
  name_prefix="${DIM}${display_name}${RESET} "
fi
line1="${name_prefix}${BOLD}[${model}]${RESET} Context: [${ctx_bar}] ${context_int}% | ${formatted_cost} | ${GREEN}+${lines_added}${RESET}/${RED}-${lines_removed}${RESET}"

if [[ "$quota_5h_pct" == "--" ]]; then
  line2="5h: -- | Weekly: --"
else
  q5_bar=$(progress_bar "$quota_5h_pct" 10)
  qw_bar=$(progress_bar "$quota_weekly_pct" 10)
  line2="5h: [${q5_bar}] ${quota_5h_pct}%${reset_5h} | Weekly: [${qw_bar}] ${quota_weekly_pct}%${reset_weekly}"
fi

echo -e "$line1"
echo -e "$line2"
