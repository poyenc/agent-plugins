#!/usr/bin/env bash
# PreToolUse(Bash): block `herdr agent prompt ... --wait`, which blocks the sender's own turn
# until the target agent settles (indefinitely when no --timeout is set). Async inter-agent
# messaging goes through the herdr-kit `message` skill instead. No-op outside herdr.
set -euo pipefail

[ "${HERDR_ENV:-}" = 1 ] || exit 0

cmd=$(jq -r '.tool_input.command // ""')

[ -n "$cmd" ] || exit 0

# Flatten a line-wrapped command onto one line so it can't slip past the single-line matcher:
# first join shell line-continuations (a trailing backslash-newline, which the shell would
# splice away), then collapse any remaining newlines to spaces.
cmd=${cmd//$'\\'$'\n'/}
cmd=${cmd//$'\n'/ }

# Two independent conditions: the command invokes `herdr ... agent prompt`, AND it carries a
# `--wait` flag token. --timeout is deliberately NOT matched on its own: it only bounds --wait,
# and `herdr agent start --timeout` (used by rotation) is a legitimate non-blocking use.
if echo "$cmd" | grep -qP '\bherdr\b.*\bagent\s+prompt\b' \
   && echo "$cmd" | grep -qP '(^|\s)--wait(\s|=|$)'; then
  printf '{"decision":"block","reason":"Do not run `herdr agent prompt --wait`: --wait blocks your own turn until the target agent settles (indefinitely when no --timeout is set), stalling you and everything queued behind you. To reach another agent without blocking, use the herdr-kit `message` skill -- `send` returns immediately, and if you need an answer pass `--callback` so the reply arrives as your own next incoming turn. Plain `herdr agent prompt <target> <text>` without --wait is also fine for a pure fire-and-forget send."}'
fi

exit 0
