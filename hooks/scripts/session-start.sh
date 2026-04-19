#!/usr/bin/env bash
# hooks/scripts/session-start.sh — Minimal hook: output branch name and storage root

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/../../scripts/lib.sh"

if [ -f "$LIB" ]; then
    source "$LIB"
    ROOT="$(resolve_storage_root)"
else
    ROOT="${KNOWLEDGE_ROOT:-$HOME/.local/share/claude/knowledge}"
fi

BRANCH="$(git branch --show-current 2>/dev/null || echo "DETACHED")"
PROJECT="$(basename "$(git remote get-url origin 2>/dev/null | sed 's|.git$||; s|/$||')" 2>/dev/null || echo "unknown")"

echo "KNOWLEDGE_BRANCH=$BRANCH"
echo "KNOWLEDGE_PROJECT=$PROJECT"
echo "KNOWLEDGE_ROOT=$ROOT"
