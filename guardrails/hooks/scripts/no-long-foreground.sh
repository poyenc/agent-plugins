#!/usr/bin/env bash
# PreToolUse(Bash) on Claude Code / tool_call(bash) on pi: block a foreground call that can
# block the turn for a long time.
#
# Claude Code branch (no "harness":"pi" marker in the payload -- only bash-guardrails.ts adds
# that, a genuine Claude Code PreToolUse call never does): run_in_background:true is always
# allowed, since the caller is notified when it finishes instead of blocking. A foreground call
# only passes if it declares a short timeout; the Bash tool's own `timeout` field is
# milliseconds and is enforced for foreground calls (unlike background ones, where it is
# accepted but silently not enforced -- verified live: a background call declaring
# timeout:3000 ran to completion ~15s later, exit 0).
#
# pi branch ("harness":"pi", set by guardrails/pi-extensions/bash-guardrails.ts, which passes
# pi's real tool_call input through): pi's Bash tool has no run_in_background field or
# background-execution mode at all -- every call is synchronous by construction (confirmed
# against pi's bashSchema/BashToolCallEvent and resolveTimeoutMs()) -- so every call is treated
# as foreground, and `timeout` is already in seconds (pi's own unit, no conversion needed).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/timeout-cap-lib.sh
source "$HERE/lib/timeout-cap-lib.sh"

payload=$(cat)

harness=$(printf '%s' "$payload" | jq -r '.harness // "claude"')

if [ "$harness" != "pi" ]; then
  run_in_background=$(printf '%s' "$payload" | jq -r '.tool_input.run_in_background // false')
  [ "$run_in_background" = "true" ] && exit 0

  cap_ms=$(safe_cap "${GUARDRAILS_MAX_FOREGROUND_TIMEOUT_MS:-60000}" 60000)

  if [ "$(timeout_declared "$payload")" != "true" ]; then
    printf '{"decision":"block","reason":"This foreground command has no declared timeout, so it can block the turn for the harness default (minutes). Either set run_in_background:true (you are notified when it finishes -- use CronCreate or ScheduleWakeup if you need to check progress, never sleep or poll) or, only if this command is genuinely quick, set an explicit timeout <= %s ms."}\n' "$cap_ms"
    exit 0
  fi

  timeout_ms=$(timeout_value "$payload")
  [ -n "$timeout_ms" ] || exit 0

  if [ "$timeout_ms" -gt "$cap_ms" ]; then
    printf '{"decision":"block","reason":"This foreground command declares timeout:%s ms, above the %s ms cap for blocking the turn. Set run_in_background:true instead -- you are notified when it finishes; use CronCreate or ScheduleWakeup to check progress if needed, never sleep or poll."}\n' "$timeout_ms" "$cap_ms"
  fi
  exit 0
fi

# pi branch: no run_in_background concept -- every call is foreground by construction.
cap_s=$(safe_cap "${GUARDRAILS_MAX_FOREGROUND_TIMEOUT_SECONDS:-60}" 60)

if [ "$(timeout_declared "$payload")" != "true" ]; then
  printf '{"decision":"block","reason":"This command has no declared timeout, so it can block the turn indefinitely -- pi'"'"'s Bash tool has no default timeout and no background mode of its own. Either delegate this command to the Agent tool (runs in the background, result arrives as a follow-up notification) or, only if it is genuinely quick, set an explicit timeout <= %s seconds. For a long-running command you still need to check on periodically, use schedule_prompt instead of waiting or polling."}\n' "$cap_s"
  exit 0
fi

timeout_s=$(timeout_value "$payload")
[ -n "$timeout_s" ] || exit 0

if [ "$timeout_s" -gt "$cap_s" ]; then
  printf '{"decision":"block","reason":"This command declares timeout:%s seconds, above the %s second cap for blocking the turn. Delegate it to the Agent tool instead -- it runs in the background and its result arrives as a follow-up notification; use schedule_prompt if you need to check progress periodically."}\n' "$timeout_s" "$cap_s"
fi
