#!/usr/bin/env bash
# PreToolUse(Bash): rewrite a run_in_background:true call to wrap it in the shell's own
# `timeout`, using the SAME tool_input.timeout (ms) field the agent already sets for foreground
# calls -- true foreground parity: the agent declares a duration via the structured field it
# already uses today, and this hook does the wrapping, instead of requiring the agent to
# hand-write a `timeout N ...` prefix as TEXT inside the command (which would reopen an entire
# shell-parsing problem to detect and validate).
#
# Live-verified (2026-10-23): PreToolUse's `updatedInput` takes effect WITHOUT setting
# `permissionDecision` at all -- normal permission flow is untouched, and a sibling guard's own
# block (e.g. no-sleep.sh) still wins even when this hook supplies `updatedInput` in the same
# parallel pass. `permissionDecision` is therefore deliberately omitted.
#
# Live-verified (2026-10-23): wrapping the ENTIRE original command inside `bash -c '...'`
# resolves the separator/backtick/redirection/heredoc hazards that a literal character scan
# would otherwise need to block, BY CONSTRUCTION, not by inspecting the command's syntax at
# all: `timeout 0.3 bash -c 'cat </tmp/fifo'` against an unread FIFO, `timeout 0.3 bash -c
# 'echo `yes >/dev/null`'` (backtick substitution), `timeout 0.3 bash -c 'true; yes >/dev/null'`
# (`;`-sequenced second command), and a heredoc followed by a hang all correctly exit 124 at
# ~0.3s. The reason: once everything is inside the quoted `-c` argument, all the shell-level
# work (redirection opening, substitution, sequencing) happens as part of the process `timeout`
# directly supervises, not as pre-exec setup by an outer, unsupervised shell -- so this hook
# does NOT need to recognize or ban any shell syntax in the command at all; it always wraps the
# whole thing unconditionally.
#
# Validation of tool_input.timeout mirrors no-long-foreground.sh's OWN validation of the same
# field (see lib/timeout-cap-lib.sh): present, a valid non-negative-integer-millisecond value is
# required -- missing/null/malformed blocks the same as "no timeout declared" does there.
# Converted to seconds via awk fixed-point (not bash integer arithmetic) to keep sub-second
# precision -- 1500ms becomes 1.500s, not floored to 1, and 1ms becomes 0.001s, not floored to 0
# and silently disabling GNU timeout's own enforcement.
#
# Parity means BLOCK an over-cap declared timeout, the same as no-long-foreground.sh does for
# foreground calls -- NOT silently clamp it. Clamping would silently run less work than the
# agent asked for, which is a worse failure mode than telling it to lower or split the work.
# A declared timeout of exactly 0 is rejected outright: GNU timeout treats 0 as "no limit",
# which defeats the whole point of wrapping a backgrounded command.
#
# KNOWN GAP (owner-accepted 2026-10-23, to revisit only if it causes a real problem in
# practice): all PreToolUse/Bash hooks run in parallel against the SAME original tool_input and
# are not re-run against this hook's updatedInput. no-timeout-ssh.sh bans `timeout ... ssh` by
# pattern-matching the ORIGINAL command text; if the agent backgrounds a plain `ssh ...` call
# with no `timeout` token in it, no-timeout-ssh.sh sees nothing to match and allows it, while
# this hook then rewrites the EXECUTED command to wrap ssh in `timeout` anyway -- the exact
# pattern no-timeout-ssh.sh exists to prevent, invisibly. Not special-cased here -- ship and
# observe real usage first rather than solve a hypothetical up front.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/timeout-cap-lib.sh
source "$HERE/lib/timeout-cap-lib.sh"

# Escape $1 for embedding inside a single-quoted bash argument: replace each literal ' with
# '\'' (end quote, escaped literal quote, reopen quote) -- the standard technique, correct
# including embedded newlines/heredocs (a real newline is ordinary data inside a quoted string,
# nothing special about it to escape).
single_quote_escape() {
  local s="$1" q="'" bs='\'
  printf '%s' "${s//$q/$q$bs$q$q}"
}

payload=$(cat)

run_in_background=$(printf '%s' "$payload" | jq -r '.tool_input.run_in_background // false')
[ "$run_in_background" = "true" ] || exit 0

cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""')
[ -n "$cmd" ] || exit 0

cap_s=$(safe_cap "${GUARDRAILS_MAX_BACKGROUND_TIMEOUT_SECONDS:-600}" 600)

if [ "$(timeout_declared "$payload")" != "true" ]; then
  printf '{"decision":"block","reason":"Backgrounded commands must declare a timeout (the SAME ms field already required for foreground calls) so this hook can wrap the command in the shell'"'"'s own timeout -- the field is accepted but NOT enforced for run_in_background:true calls on its own (verified live: a declared timeout:3000ms call still ran to completion ~15s later). Set timeout to a value <= %s seconds (in ms)."}\n' "$cap_s"
  exit 0
fi

timeout_ms=$(timeout_value "$payload")
if [ -z "$timeout_ms" ]; then
  printf '{"decision":"block","reason":"timeout is declared but isn'"'"'t a valid non-negative integer millisecond value -- not usable to bound this backgrounded command. Set a real timeout <= %s seconds (in ms)."}\n' "$cap_s"
  exit 0
fi

secs=$(awk -v ms="$timeout_ms" 'BEGIN { printf "%.3f", ms / 1000 }')

verdict=$(awk -v d="$secs" -v cap="$cap_s" 'BEGIN {
  if (d == 0) { print "zero"; exit }
  if (d > cap + 0) { printf "over:%.6g\n", d; exit }
  print "ok"
}')

case "$verdict" in
  zero)
    printf '{"decision":"block","reason":"timeout:0 disables the timeout entirely (GNU timeout: a duration of 0 means no limit) -- that defeats the whole point of wrapping a backgrounded command. Set a real timeout <= %s seconds (in ms)."}\n' "$cap_s"
    exit 0
    ;;
  over:*)
    total="${verdict#over:}"
    printf '{"decision":"block","reason":"This backgrounded command declares timeout:%sms (%s seconds), above the %s second cap for an unattended background run. Lower it, or if the work genuinely needs longer, split it into checkpoints you can each background separately."}\n' "$timeout_ms" "$total" "$cap_s"
    exit 0
    ;;
esac

escaped=$(single_quote_escape "$cmd")
wrapped="timeout ${secs}s bash -c '${escaped}'"

printf '%s' "$payload" | jq --arg cmd "$wrapped" '
  .tool_input.command = $cmd
  | {hookSpecificOutput: {hookEventName: "PreToolUse", updatedInput: .tool_input}}
'
