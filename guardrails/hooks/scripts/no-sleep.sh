#!/usr/bin/env bash
# Blocks Bash commands that use sleep for waiting/polling.
# Fires on PreToolUse for Bash.

cmd=$(jq -r '.tool_input.command // ""')

if echo "$cmd" | grep -qE '(^|&&|;)[ \t]*sleep[ \t]'; then
  printf '{"decision":"block","reason":"sleep is banned for waiting. Options: (1) run_in_background:true on the long command — Claude Code notifies you when it finishes; (2) CronCreate to poll progress at a long interval (5–10 minutes minimum) to avoid flooding the context with status messages, then cancel the cron when done."}'
fi
