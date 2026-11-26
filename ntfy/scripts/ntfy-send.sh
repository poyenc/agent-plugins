#!/usr/bin/env bash
# Shared ntfy sender. Usage: ntfy-send.sh [message]
# Reads NTFY_TOPIC, NTFY_URL, NTFY_PRIORITY, NTFY_TOKEN, NTFY_TITLE from env.
# Set NTFY_RAW=1 to send the body verbatim (skip markdown stripping) -- for literal text such as shell commands.
set -euo pipefail

body="${1:-Agent needs input}"

# Strip markdown formatting
if [ "${NTFY_RAW:-}" != 1 ]; then
body=$(printf '%s' "$body" | python3 -c "
import sys, re
text = sys.stdin.read()
text = re.sub(r'\`\`\`.*?\`\`\`', '', text, flags=re.DOTALL)
text = re.sub(r'\`([^\`]+)\`', r'\1', text)
text = re.sub(r'\*\*(.+?)\*\*', r'\1', text)
text = re.sub(r'\*(.+?)\*', r'\1', text)
text = re.sub(r'(?<!\w)__(.+?)__(?!\w)', r'\1', text)
text = re.sub(r'(?<!\w)_(.+?)_(?!\w)', r'\1', text)
text = re.sub(r'~~(.+?)~~', r'\1', text)
text = re.sub(r'\[([^\]]+)\]\([^\)]+\)', r'\1', text)
text = re.sub(r'!\[[^\]]*\]\([^\)]+\)', '', text)
text = re.sub(r'^#{1,6}\s+', '', text, flags=re.MULTILINE)
text = re.sub(r'^>\s+', '', text, flags=re.MULTILINE)
text = re.sub(r'^-{3,}$', '', text, flags=re.MULTILINE)
print(text.strip())
" 2>/dev/null || printf '%s' "$body")
fi

# Cap at 4096 bytes (ntfy hard limit)
if [ "${#body}" -gt 4096 ]; then
    body="${body:0:4096}…"
fi
title="${NTFY_TITLE:-Agent needs input}"

# Bounded: the hooks that call this run synchronously, and an unreachable server must not leave a
# curl process hanging. Pushes are a few hundred bytes, so 10 s is ample for a working server.
curl -s --max-time 10 \
    -H "Title: ${title}" \
    -H "Priority: ${NTFY_PRIORITY:-default}" \
    -H "Tags: bell" \
    ${NTFY_TOKEN:+-H "Authorization: Bearer ${NTFY_TOKEN}"} \
    --data-raw "${body}" \
    "${NTFY_URL:-https://ntfy.sh}/${NTFY_TOPIC:-agent-notify-topic}" >/dev/null || true
