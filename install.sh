#!/usr/bin/env bash
# Install the chord-copilot Claude Code skill.
#
# Usage:
#   ./install.sh [--scope user|project] [--project-dir <path>] [--ref <ref>] [--force]
#
# Default scope is `user` (~/.claude/skills/chord-copilot/), which makes the
# skill available in every Claude Code session for the current user.
# `--scope project` installs into <project-dir>/.claude/skills/chord-copilot/
# (defaults to the current working directory), which makes the skill travel
# with the repo for teammates who clone it.
#
# SKILL.md resolution: if a local copy sits at plugin/skills/copilot/SKILL.md
# relative to this script (the local-clone case), it is used directly.
# Otherwise — the typical `curl ... | bash` flow — SKILL.md is downloaded
# from
# https://raw.githubusercontent.com/chordcommerce/chord-copilot/<ref>/plugin/skills/copilot/SKILL.md
# `--ref` (or the CHORD_SKILL_REF env var) pins which branch/tag/sha to
# fetch from; defaults to `main`.
#
# Public one-liner:
#   curl -fsSL https://raw.githubusercontent.com/chordcommerce/chord-copilot/main/install.sh | bash
#   # project scope: append `-s -- --scope project --project-dir "$(pwd)"`
#
# Claude Code users can install both the MCP server registration AND the
# skill in one step via the Claude Code plugin format in this same repo:
#   /plugin install chordcommerce/chord-copilot
# This script is the fallback for non-Claude-Code MCP clients (Claude
# Desktop, etc.) that read SKILL.md but don't support plugins.

set -euo pipefail

SKILL_NAME="chord-copilot"
REPO_PATH="chordcommerce/chord-copilot"
SKILL_REPO_PATH="plugin/skills/copilot/SKILL.md"

SCOPE="user"
PROJECT_DIR="$(pwd)"
REF="${CHORD_SKILL_REF:-main}"
FORCE=0

usage() {
  sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
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
    --ref)
      REF="${2:-}"
      shift 2
      ;;
    --ref=*)
      REF="${1#--ref=}"
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
  URL="https://raw.githubusercontent.com/$REPO_PATH/$REF/$SKILL_REPO_PATH"
  TMP_SOURCE="$(mktemp -t chord-skill.XXXXXX)"
  trap 'rm -f "$TMP_SOURCE"' EXIT
  if ! curl -fsSL "$URL" -o "$TMP_SOURCE"; then
    echo "error: failed to download SKILL.md from $URL" >&2
    echo "       check the ref ('$REF') and your network connection." >&2
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
