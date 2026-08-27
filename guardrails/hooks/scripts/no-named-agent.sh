#!/usr/bin/env bash
# PreToolUse(Agent): block naming an agent. Named agents (SendMessage-addressable
# teammates) send idle_notification when their own turn ends, indistinguishable from
# actual completion — results get silently dropped when that's mistaken for "done".
set -euo pipefail

name=$(jq -r '.tool_input.name // ""')

[ -n "$name" ] || exit 0

printf '{"decision":"block","reason":"Named agents are banned. Use a background unnamed Agent instead — fire-and-forget, its result arrives inline via task-notification, with no idle_notification ambiguity to lose track of."}'
