#!/usr/bin/env bash
# PreToolUse(CronCreate): block when agent exceeds max crons or uses too-short interval.
set -euo pipefail

max_crons="${GUARDRAILS_MAX_CRONS:-1}"
min_minutes="${GUARDRAILS_MIN_CRON_MINUTES:-5}"

payload=$(cat)

# Block one-shot crons (recurring:false). ScheduleWakeup is the right tool for
# one-time delayed actions; one-shot CronCreate also breaks cron-count accounting
# because auto-deletion never emits CronDelete.
recurring=$(printf '%s' "$payload" | jq -r 'if .tool_input.recurring == false then "false" else "true" end')
if [ "$recurring" = "false" ]; then
  printf '{"decision":"block","reason":"One-shot CronCreate (recurring:false) is banned. For a one-time delayed action use ScheduleWakeup instead — it is designed for that pattern and does not interact with the active-cron count."}\n'
  exit 0
fi

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
  # A minute field can be a comma-separated list of subfields (e.g.
  # "1-10/5,20-59/15"), each parsed independently; the effective interval is
  # the TIGHTEST (smallest) one, since that's how often the cron actually
  # fires. Scanning only the last subfield (or the whole field as one regex)
  # would miss a tighter step hiding earlier in the list.
  IFS=',' read -ra subfields <<< "$minute_field"
  for sub in "${subfields[@]}"; do
    if [ "$sub" = "*" ]; then
      sub_interval=1
    elif [[ "$sub" =~ /([0-9]+)$ ]]; then
      # Any step suffix counts, not just a leading bare "*/N" -- step-ranges
      # like "2-59/5" are the normal way to offset a recurring cron off
      # :00/:30 and must hit the same interval check, not fall through to
      # the single-value default below.
      # Force base-10: a zero-padded step like "08" would otherwise be read
      # as an invalid octal literal by the arithmetic comparison below.
      sub_interval=$((10#${BASH_REMATCH[1]}))
    else
      sub_interval=60
    fi
    (( sub_interval < interval )) && interval=$sub_interval
  done

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
