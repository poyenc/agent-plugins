#!/usr/bin/env bash
# Shared ntfy sender. Usage: ntfy-send.sh [message]
# Reads NTFY_TOPIC, NTFY_URL, NTFY_PRIORITY, NTFY_TOKEN, NTFY_TITLE from env.
set -euo pipefail

body="${1:-Agent needs input}"

# Strip markdown formatting
body=$(printf '%s' "$body" | python3 -c "
import sys, re
text = sys.stdin.read()
text = re.sub(r'\`\`\`.*?\`\`\`', '', text, flags=re.DOTALL)
text = re.sub(r'\`([^\`]+)\`', r'\1', text)
text = re.sub(r'\*\*(.+?)\*\*', r'\1', text)
text = re.sub(r'\*(.+?)\*', r'\1', text)
text = re.sub(r'__(.+?)__', r'\1', text)
text = re.sub(r'_(.+?)_', r'\1', text)
text = re.sub(r'~~(.+?)~~', r'\1', text)
text = re.sub(r'\[([^\]]+)\]\([^\)]+\)', r'\1', text)
text = re.sub(r'!\[[^\]]*\]\([^\)]+\)', '', text)
text = re.sub(r'^#{1,6}\s+', '', text, flags=re.MULTILINE)
text = re.sub(r'^>\s+', '', text, flags=re.MULTILINE)
text = re.sub(r'^-{3,}$', '', text, flags=re.MULTILINE)
print(text.strip())
" 2>/dev/null || printf '%s' "$body")

# Cap at 4096 bytes (ntfy hard limit)
if [ "${#body}" -gt 4096 ]; then
    body="${body:0:4096}…"
fi
title="${NTFY_TITLE:-Agent needs input}"

curl -s \
    -H "Title: ${title}" \
    -H "Priority: ${NTFY_PRIORITY:-default}" \
    -H "Tags: bell" \
    ${NTFY_TOKEN:+-H "Authorization: Bearer ${NTFY_TOKEN}"} \
    -d "${body}" \
    "${NTFY_URL:-https://ntfy.sh}/${NTFY_TOPIC:-agent-notify-topic}" >/dev/null || true
