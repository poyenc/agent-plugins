#!/usr/bin/env bash
# PreToolUse hook on AskUserQuestion -- fires before the question is displayed.
set -euo pipefail

payload=$(cat)
log="${CLAUDE_CODE_TMPDIR:-/tmp}/ntfy-plugin/debug.log"
mkdir -p "$(dirname "$log")"
echo "--- $(date) ---" >> "$log"
echo "payload: $payload" >> "$log"

session_id=$(printf '%s' "$payload" | python3 -c \
    "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null || true)

DATA_DIR="${CLAUDE_CODE_TMPDIR:-/tmp}/ntfy-plugin"
echo "session_id: $session_id" >> "$log"
echo "marker: ${DATA_DIR}/active/notify-enabled-${session_id}" >> "$log"
echo "marker exists: $([ -f "${DATA_DIR}/active/notify-enabled-${session_id}" ] && echo yes || echo no)" >> "$log"
[ -f "${DATA_DIR}/active/notify-enabled-${session_id}" ] || exit 0

question=$(printf '%s' "$payload" | python3 -c "
import sys, json
d = json.load(sys.stdin)
qs = d.get('tool_input', {}).get('questions', [])
print(' / '.join(q.get('question', '') for q in qs))
" 2>/dev/null || true)

bash "$(dirname "$0")/ntfy-send.sh" "$question"
