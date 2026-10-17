#!/usr/bin/env bash
# PreToolUse(Bash): block commands that use sleep for waiting/polling.
set -euo pipefail

cmd=$(jq -r '.tool_input.command // ""')

[ -n "$cmd" ] || exit 0

if echo "$cmd" | grep -qP '(^|[\t ;|&()\n])sleep([\t ;|&()\n]|$)'; then
  printf '{"decision":"block","reason":"sleep is banned for waiting. On Claude Code: (1) run_in_background:true on the long command — you are notified when it finishes; (2) CronCreate to poll progress at a long interval (5-10 minutes minimum) to avoid flooding the context with status messages, then cancel the cron when done. On pi: (1) if an Agent tool is available, delegate the long command to it — it runs in the background by default and its result arrives as a follow-up notification (get_subagent_result returns the full text); (2) if schedule_prompt is available, schedule a one-shot check (type once), or a recurring one within the limits the schedule guard enforces (a block message states them), and remove it when done; (3) otherwise run the command directly without sleep — the tool call already blocks until it completes."}'
fi
