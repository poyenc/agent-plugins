#!/usr/bin/env bash
# PostToolUse(CronDelete): decrement the active cron counter for this session.
set -euo pipefail

session_id=$(jq -r '.session_id // ""')

[ -n "$session_id" ] || exit 0

count_dir="${CLAUDE_CODE_TMPDIR:-/tmp}/guardrails-plugin"
count_file="${count_dir}/cron-count-${session_id}"
mkdir -p "$count_dir"
raw=$(cat "$count_file" 2>/dev/null || true)
count=0
[[ "$raw" =~ ^[0-9]+$ ]] && count="$raw"
new=$(( count > 0 ? count - 1 : 0 ))
echo "$new" > "$count_file"
