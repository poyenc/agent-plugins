#!/usr/bin/env bash
# Manage the per-session notification marker file.
# Usage: toggle.sh on|off <session_id>
set -euo pipefail

action="${1:-}"
session_id="${2:-}"
session_id="${session_id//\`/}"  # strip backticks that claude session-id may wrap around the value

if [ -z "$action" ] || [ -z "$session_id" ]; then
    echo "Usage: toggle.sh on|off <session_id>" >&2
    exit 1
fi

marker_dir="${CLAUDE_CODE_TMPDIR:-/tmp}/ntfy-plugin/active"
marker="${marker_dir}/notify-enabled-${session_id}"

case "$action" in
    on)
        mkdir -p "$marker_dir"
        touch "$marker"
        echo "ntfy notifications enabled for session ${session_id}"
        ;;
    off)
        rm -f "$marker"
        echo "ntfy notifications disabled for session ${session_id}"
        ;;
    *)
        echo "Unknown action: ${action}" >&2
        exit 1
        ;;
esac
