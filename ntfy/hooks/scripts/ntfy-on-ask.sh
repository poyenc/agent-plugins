#!/usr/bin/env bash
# PreToolUse hook on AskUserQuestion -- fires before the question is displayed.
set -euo pipefail

payload=$(cat)

session_id=$(printf '%s' "$payload" | python3 -c \
    "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null || true)

[ -f "${CLAUDE_PLUGIN_DATA}/active/notify-enabled-${session_id}" ] || exit 0

question=$(printf '%s' "$payload" | python3 -c "
import sys, json
d = json.load(sys.stdin)
qs = d.get('tool_input', {}).get('questions', [])
print(' / '.join(q.get('question', '') for q in qs))
" 2>/dev/null || true)

bash "$(dirname "$0")/ntfy-send.sh" "${question:-Claude is asking a question}" "Claude needs input"
