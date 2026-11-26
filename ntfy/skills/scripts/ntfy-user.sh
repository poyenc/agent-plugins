#!/usr/bin/env bash
# Send an ntfy notification if notifications are enabled for this session.
# Usage: ntfy-user.sh <message>
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/marker.sh"

message="${1:-}"
if [ -z "$message" ]; then
    echo "Usage: ntfy-user.sh <message>" >&2
    exit 1
fi

ntfy_require_enabled "${CLAUDE_CODE_SESSION_ID:-}"

bash "$(dirname "${BASH_SOURCE[0]}")/../../scripts/ntfy-send.sh" "$message"
