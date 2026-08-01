#!/usr/bin/env bash
# PreToolUse(CronCreate): block when agent exceeds max crons or uses too-short interval.
set -euo pipefail

max_crons="${GUARDRAILS_MAX_CRONS:-1}"
min_minutes="${GUARDRAILS_MIN_CRON_MINUTES:-5}"

payload=$(cat)

session_id=$(printf '%s' "$payload" | jq -r '.session_id // ""')

count_file="${CLAUDE_CODE_TMPDIR:-/tmp}/guardrails-plugin/cron-count-${session_id}"
raw=$(cat "$count_file" 2>/dev/null || true)
count=0
[[ "$raw" =~ ^[0-9]+$ ]] && count="$raw"

# Check cron interval — parse minute field of the cron expression
cron_expr=$(printf '%s' "$payload" | jq -r '.tool_input.cron // ""')

if [ -n "$cron_expr" ]; then
  minute_field=$(echo "$cron_expr" | awk '{print $1}')
  interval=60
  if [ "$minute_field" = "*" ]; then
    interval=1
  elif [[ "$minute_field" =~ ^\*/([0-9]+)$ ]]; then
    interval="${BASH_REMATCH[1]}"
  fi

  if (( interval < min_minutes )); then
    printf '{"decision":"block","reason":"Cron interval is %s minute(s), below the minimum of %s minutes. Use a longer interval to avoid flooding the context window."}\n' \
      "$interval" "$min_minutes"
    exit 0
  fi
fi

# Check active cron count
if (( count >= max_crons )); then
  printf '{"decision":"block","reason":"You already have %s active cron(s) (max: %s). Cancel an existing cron with CronDelete before creating a new one."}\n' \
    "$count" "$max_crons"
  exit 0
fi
