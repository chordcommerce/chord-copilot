#!/usr/bin/env bash
# Install the chord-copilot Claude Code skill, or register the
# chord-copilot MCP server in Claude Desktop's config.
#
# Usage:
#   ./install.sh [--client claude-code|claude-desktop] \
#                [--scope user|project] [--project-dir <path>] \
#                [--url <url>] [--force]
#
# --client claude-code (default): drops SKILL.md at
# ~/.claude/skills/chord-copilot/ (scope=user) or
# <project>/.claude/skills/chord-copilot/ (scope=project). Does NOT
# register the MCP server — run `claude mcp add` separately, or use the
# /plugin install path for one-step setup.
#
# --client claude-desktop: merges the chord-copilot MCP server entry
# into ~/Library/Application Support/Claude/claude_desktop_config.json
# (macOS) or ~/.config/Claude/claude_desktop_config.json (Linux) using
# the mcp-remote stdio shim. Requires jq. macOS/Linux only.
#
# --url overrides the MCP server URL (claude-desktop only).
# --force overwrites a differing existing install.
#
# Public one-liners:
#   # Claude Code skill:
#   curl -fsSL https://raw.githubusercontent.com/chordcommerce/chord-copilot/main/install.sh | bash
#   # Claude Desktop MCP registration:
#   curl -fsSL https://raw.githubusercontent.com/chordcommerce/chord-copilot/main/install.sh | bash -s -- --client claude-desktop

set -euo pipefail

SKILL_NAME="chord-copilot"
REPO_PATH="chordcommerce/chord-copilot"
SKILL_REPO_PATH="plugin/skills/copilot/SKILL.md"
DEFAULT_MCP_URL="https://mcp.staging.chorddemo.copilot.chord.co/mcp/"

CLIENT="claude-code"
SCOPE="user"
PROJECT_DIR="$(pwd)"
MCP_URL=""
FORCE=0

usage() {
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --client)
      CLIENT="${2:-}"
      shift 2
      ;;
    --client=*)
      CLIENT="${1#--client=}"
      shift
      ;;
    --scope)
      SCOPE="${2:-}"
      shift 2
      ;;
    --scope=*)
      SCOPE="${1#--scope=}"
      shift
      ;;
    --project-dir)
      PROJECT_DIR="${2:-}"
      shift 2
      ;;
    --project-dir=*)
      PROJECT_DIR="${1#--project-dir=}"
      shift
      ;;
    --url)
      MCP_URL="${2:-}"
      shift 2
      ;;
    --url=*)
      MCP_URL="${1#--url=}"
      shift
      ;;
    --force|-f)
      FORCE=1
      shift
      ;;
    -h|--help)
      usage 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage 1
      ;;
  esac
done

case "$CLIENT" in
  claude-code|claude-desktop) ;;
  *)
    echo "error: --client must be 'claude-code' or 'claude-desktop' (got: $CLIENT)" >&2
    exit 1
    ;;
esac

# ---- Claude Desktop branch: merge MCP entry into claude_desktop_config.json

if [[ "$CLIENT" == "claude-desktop" ]]; then
  case "$(uname -s)" in
    Darwin) CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json" ;;
    Linux)  CONFIG="$HOME/.config/Claude/claude_desktop_config.json" ;;
    *)
      echo "error: --client claude-desktop supports macOS and Linux only (got: $(uname -s))" >&2
      exit 1
      ;;
  esac

  if ! command -v jq >/dev/null 2>&1; then
    echo "error: jq is required for --client claude-desktop." >&2
    echo "       install with: brew install jq  (macOS)  or  apt install jq  (Linux)" >&2
    exit 1
  fi

  RESOLVED_URL="${MCP_URL:-$DEFAULT_MCP_URL}"
  DESIRED_ENTRY="$(jq -n --arg url "$RESOLVED_URL" \
    '{command:"npx", args:["-y","mcp-remote",$url]}')"

  mkdir -p "$(dirname "$CONFIG")"
  if [[ ! -f "$CONFIG" ]]; then
    printf '{}\n' > "$CONFIG"
  fi

  if ! jq empty "$CONFIG" >/dev/null 2>&1; then
    echo "error: $CONFIG is not valid JSON. Refusing to overwrite." >&2
    echo "       fix or remove the file and re-run." >&2
    exit 1
  fi

  EXISTING_ENTRY="$(jq --arg name "$SKILL_NAME" '.mcpServers[$name] // empty' "$CONFIG")"
  if [[ -n "$EXISTING_ENTRY" ]]; then
    CANON_EXISTING="$(echo "$EXISTING_ENTRY" | jq -S .)"
    CANON_DESIRED="$(echo "$DESIRED_ENTRY" | jq -S .)"
    if [[ "$CANON_EXISTING" == "$CANON_DESIRED" ]]; then
      echo "already registered (identical content): $CONFIG"
      exit 0
    fi
    if [[ $FORCE -ne 1 ]]; then
      echo "error: $CONFIG already has a '$SKILL_NAME' entry that differs." >&2
      echo "       pass --force to overwrite." >&2
      exit 1
    fi
  fi

  TMP_CONFIG="$(mktemp -t chord-desktop.XXXXXX)"
  trap 'rm -f "$TMP_CONFIG"' EXIT
  jq --arg name "$SKILL_NAME" --argjson entry "$DESIRED_ENTRY" \
    '.mcpServers[$name] = $entry' "$CONFIG" > "$TMP_CONFIG"
  mv "$TMP_CONFIG" "$CONFIG"

  echo "registered $SKILL_NAME in: $CONFIG"
  echo "  url: $RESOLVED_URL"
  echo "  next: full quit Claude Desktop (Cmd+Q on macOS) and reopen."
  echo "        first connection opens a browser for OAuth sign-in."
  exit 0
fi

# ---- Claude Code branch: drop SKILL.md under ~/.claude/skills/

case "$SCOPE" in
  user)    TARGET_ROOT="$HOME/.claude/skills" ;;
  project) TARGET_ROOT="$PROJECT_DIR/.claude/skills" ;;
  *)
    echo "error: --scope must be 'user' or 'project' (got: $SCOPE)" >&2
    exit 1
    ;;
esac

# Resolve SKILL.md source. A local clone wins; otherwise fetch from
# raw.githubusercontent.com. When piped via `curl | bash`,
# ${BASH_SOURCE[0]} is /dev/stdin or empty, so the local check fails
# naturally and we fall through to the network path.
LOCAL_SOURCE=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -f "$SCRIPT_DIR/$SKILL_REPO_PATH" ]]; then
    LOCAL_SOURCE="$SCRIPT_DIR/$SKILL_REPO_PATH"
  fi
fi

if [[ -n "$LOCAL_SOURCE" ]]; then
  SOURCE="$LOCAL_SOURCE"
  SOURCE_DESC="local: $LOCAL_SOURCE"
else
  if ! command -v curl >/dev/null 2>&1; then
    echo "error: curl is required to fetch SKILL.md when no local copy is present" >&2
    exit 1
  fi
  URL="https://raw.githubusercontent.com/$REPO_PATH/main/$SKILL_REPO_PATH"
  TMP_SOURCE="$(mktemp -t chord-skill.XXXXXX)"
  trap 'rm -f "$TMP_SOURCE"' EXIT
  if ! curl -fsSL "$URL" -o "$TMP_SOURCE"; then
    echo "error: failed to download SKILL.md from $URL" >&2
    echo "       check your network connection." >&2
    exit 1
  fi
  SOURCE="$TMP_SOURCE"
  SOURCE_DESC="github: $URL"
fi

TARGET_DIR="$TARGET_ROOT/$SKILL_NAME"
TARGET="$TARGET_DIR/SKILL.md"

if [[ -f "$TARGET" && $FORCE -ne 1 ]]; then
  if ! cmp -s "$SOURCE" "$TARGET"; then
    echo "error: $TARGET already exists and differs from the source." >&2
    echo "       source: $SOURCE_DESC" >&2
    echo "       pass --force to overwrite." >&2
    exit 1
  fi
  echo "already installed (identical content): $TARGET"
  exit 0
fi

mkdir -p "$TARGET_DIR"
cp "$SOURCE" "$TARGET"
echo "installed $SKILL_NAME ($SCOPE scope): $TARGET"
echo "  source: $SOURCE_DESC"
