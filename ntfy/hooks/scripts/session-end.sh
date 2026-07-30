#!/usr/bin/env bash
# SessionEnd hook -- clean up the marker file for this session.
set -euo pipefail

payload=$(cat)

session_id=$(printf '%s' "$payload" | python3 -c \
    "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null || true)

[ -n "$session_id" ] || exit 0

rm -f "${CLAUDE_CODE_TMPDIR:-/tmp}/ntfy-plugin/active/notify-enabled-${session_id}"
exit 0
