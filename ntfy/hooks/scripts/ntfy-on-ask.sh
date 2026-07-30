#!/usr/bin/env bash
# PreToolUse hook on AskUserQuestion -- fires before the question is displayed.
set -euo pipefail

payload=$(cat)

session_id=$(printf '%s' "$payload" | python3 -c \
    "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null || true)

marker="${CLAUDE_CODE_TMPDIR:-/tmp}/ntfy-plugin/active/notify-enabled-${session_id}"
[ -f "$marker" ] || exit 0

stored_title=$(cat "$marker")
[ -n "$stored_title" ] && export NTFY_TITLE="$stored_title"

question=$(printf '%s' "$payload" | python3 -c "
import sys, json
d = json.load(sys.stdin)
qs = d.get('tool_input', {}).get('questions', [])
print(' / '.join(q.get('question', '') for q in qs))
" 2>/dev/null || true)

bash "${CLAUDE_PLUGIN_ROOT}/scripts/ntfy-send.sh" "$question"
