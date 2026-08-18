#!/usr/bin/env bash
# PreToolUse(Bash): block wrapping ssh-family connections in `timeout`
# (timeout waits the full duration on a dead host; use native ConnectTimeout instead).
set -euo pipefail

cmd=$(jq -r '.tool_input.command // ""')

[ -n "$cmd" ] || exit 0

# timeout wrapping ssh/scp/sftp directly
if echo "$cmd" | grep -qP '\btimeout\s+((-{1,2}\S+|\d+[smhd]?)\s+)+(ssh|scp|sftp)\b'; then
  printf '{"decision":"block","reason":"Do not wrap ssh/scp/sftp in the timeout command: timeout bounds the whole session and still waits the full duration on a dead host. Use the native fast-fail option instead: -o ConnectTimeout=5 -o BatchMode=yes (a healthy host connects in under a second; a dead one errors out in ~5s)."}'
  exit 0
fi

# timeout wrapping rsync-over-ssh (not local rsync, not rsync:// or host:: daemon transport)
if echo "$cmd" | grep -qP '\btimeout\s+((-{1,2}\S+|\d+[smhd]?)\s+)+rsync\b' \
   && echo "$cmd" | grep -qP '(-e\s+\S*ssh|--rsh=\S*ssh|(^|\s)([\w.-]+@)?[\w.-]+:(?!:)(?!//))'; then
  printf '{"decision":"block","reason":"Do not wrap rsync-over-ssh in the timeout command for connection safety: on a dead host it burns the full timeout. Use rsync native options instead: rsync --timeout=30 -e '"'"'ssh -o ConnectTimeout=5'"'"' ... (ConnectTimeout fails fast on a dead host; --timeout bounds a stalled transfer)."}'
  exit 0
fi

exit 0
