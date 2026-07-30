#!/usr/bin/env bash
# Send an ntfy notification if notifications are enabled for this session.
# Usage: ntfy-user.sh <message>
set -euo pipefail

message="${1:-}"
if [ -z "$message" ]; then
    echo "Usage: ntfy-user.sh <message>" >&2
    exit 1
fi

session_id="${CLAUDE_CODE_SESSION_ID:-}"
marker="${CLAUDE_CODE_TMPDIR:-/tmp}/ntfy-plugin/active/notify-enabled-${session_id}"
[ -f "$marker" ] || exit 0

stored_title=$(cat "$marker")
[ -n "$stored_title" ] && export NTFY_TITLE="$stored_title"

bash "$(dirname "$0")/../../scripts/ntfy-send.sh" "$message"
