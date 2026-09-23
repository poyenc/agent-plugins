#!/usr/bin/env bash
# PreToolUse(Bash): block commands that use sleep for waiting/polling.
set -euo pipefail

cmd=$(jq -r '.tool_input.command // ""')

[ -n "$cmd" ] || exit 0

if echo "$cmd" | grep -qP '(^|[\t ;|&()\n])sleep([\t ;|&()\n]|$)'; then
  printf '{"decision":"block","reason":"sleep is banned for waiting. On Claude Code: (1) run_in_background:true on the long command — you are notified when it finishes; (2) CronCreate to poll progress at a long interval (5-10 minutes minimum) to avoid flooding the context with status messages, then cancel the cron when done. On pi (no background-run or scheduler primitive): just run the long command directly without sleep — the tool call already blocks until it completes, so there is nothing to poll for."}'
fi
