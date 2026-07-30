#!/usr/bin/env bash
# Stop hook -- best-effort catch for plain-text questions via "?" detection.
# Strips code blocks before checking to reduce false positives.
set -euo pipefail

payload=$(cat)

session_id=$(printf '%s' "$payload" | python3 -c \
    "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null || true)

marker="${CLAUDE_CODE_TMPDIR:-/tmp}/ntfy-plugin/active/notify-enabled-${session_id}"
[ -f "$marker" ] || exit 0

stored_title=$(cat "$marker")
[ -n "$stored_title" ] && export NTFY_TITLE="$stored_title"

msg=$(printf '%s' "$payload" | python3 -c \
    "import sys,json; print(json.load(sys.stdin).get('last_assistant_message',''))" 2>/dev/null || true)

[ -z "$msg" ] && exit 0

# Strip fenced and inline code blocks before checking for "?"
clean=$(printf '%s' "$msg" | python3 -c "
import sys, re
text = sys.stdin.read()
text = re.sub(r'\`\`\`.*?\`\`\`', '', text, flags=re.DOTALL)
text = re.sub(r'\`[^\`]+\`', '', text)
print(text)
" 2>/dev/null || true)

printf '%s' "$clean" | grep -qF '?' || exit 0

body=$(printf '%s' "$msg" | tail -c 300)
bash "$(dirname "$0")/ntfy-send.sh" "$body"

exit 0
