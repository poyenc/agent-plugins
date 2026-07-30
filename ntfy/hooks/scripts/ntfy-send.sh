#!/usr/bin/env bash
# Shared ntfy sender. Usage: ntfy-send.sh [message]
# Reads NTFY_TOPIC, NTFY_URL, NTFY_PRIORITY, NTFY_TOKEN, NTFY_TITLE from env.
set -euo pipefail

body="${1:-Agent needs input}"
title="${NTFY_TITLE:-Agent needs input}"

curl -s \
    -H "Title: ${title}" \
    -H "Priority: ${NTFY_PRIORITY:-default}" \
    -H "Tags: bell" \
    ${NTFY_TOKEN:+-H "Authorization: Bearer ${NTFY_TOKEN}"} \
    -d "${body}" \
    "${NTFY_URL:-https://ntfy.sh}/${NTFY_TOPIC:-agent-notify-topic}" >/dev/null || true
