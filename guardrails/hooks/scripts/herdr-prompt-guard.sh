#!/usr/bin/env bash
# PreToolUse(Bash): govern how agents use `herdr agent prompt` for inter-agent messaging.
#   - `... --wait`  -> BLOCK: --wait blocks the sender's own turn until the target settles.
#   - plain prompt  -> ALLOW + hint: a bare send has no reply path; steer toward the message
#                      skill's --callback when a response is expected.
# Async messaging belongs to the herdr-kit `message` skill. No-op outside herdr.
set -euo pipefail

[ "${HERDR_ENV:-}" = 1 ] || exit 0

cmd=$(jq -r '.tool_input.command // ""')

[ -n "$cmd" ] || exit 0

# Flatten a line-wrapped command onto one line so it can't slip past the single-line matcher:
# first join shell line-continuations (a trailing backslash-newline, which the shell would
# splice away), then collapse any remaining newlines to spaces.
cmd=${cmd//$'\\'$'\n'/}
cmd=${cmd//$'\n'/ }

# Only act on a `herdr ... agent prompt` invocation; anything else is none of this hook's business.
echo "$cmd" | grep -qP '\bherdr\b.*\bagent\s+prompt\b' || exit 0

# --wait blocks the sender's turn (indefinitely without --timeout). --timeout is NOT matched on
# its own: it only bounds --wait, and `herdr agent start --timeout` (rotation) never reaches here
# because it isn't `agent prompt`.
if echo "$cmd" | grep -qP '(^|\s)--wait(\s|=|$)'; then
  printf '{"decision":"block","reason":"Do not run `herdr agent prompt --wait`: --wait blocks your own turn until the target agent settles (indefinitely when no --timeout is set), stalling you and everything queued behind you. To reach another agent without blocking, use the herdr-kit `message` skill -- `send` returns immediately, and if you need an answer pass `--callback` so the reply comes back as your own next incoming turn."}'
else
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","additionalContext":"This `herdr agent prompt` is a fire-and-forget send: it delivers your text but sets up no reply path, so any response the other agent gives will not be routed back to you. If you expect an answer, send it through the herdr-kit `message` skill with `--callback` instead -- the reply then arrives as your own next incoming turn. If you do not need a reply, this bare send is fine."}}'
fi

exit 0
