#!/usr/bin/env bash
# Manage the per-session notification marker file.
# Usage: toggle.sh on|off <session_id> [title]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/marker.sh"

action="${1:-}"
session_id="${2:-}"
session_id="${session_id//\`/}"  # strip backticks that claude session-id may wrap around the value
title="${3:-}"

if [ -z "$action" ] || [ -z "$session_id" ]; then
    echo "Usage: toggle.sh on|off <session_id> [title]" >&2
    exit 1
fi

case "$action" in
    on)
        ntfy_marker_enable "$session_id" "$title"
        echo "ntfy notifications enabled for session ${session_id}"
        ;;
    off)
        ntfy_marker_disable "$session_id"
        echo "ntfy notifications disabled for session ${session_id}"
        ;;
    *)
        echo "Unknown action: ${action}" >&2
        exit 1
        ;;
esac
