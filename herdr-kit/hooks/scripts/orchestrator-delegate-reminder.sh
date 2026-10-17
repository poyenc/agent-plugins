#!/usr/bin/env bash
# SessionStart: tell the orchestrator agent, once, to delegate work to a worker instead of doing
# it directly. Never blocks. Active only inside herdr.
#
# "Orchestrator" = this session's claude was launched with
# --system-prompt-file <path containing "orchestrator">.
# A hook cannot see the system prompt or its own launch options, but herdr reports the real argv
# of the process running in the pane.
#
# Injected at session start (startup, resume, clear, compact) rather than on every tool call, so
# the text lands once, before the first prompt, and never sits in the middle of the history.
set -euo pipefail

[ "${HERDR_ENV:-}" = 1 ] && [ -n "${HERDR_PANE_ID:-}" ] || exit 0

cat >/dev/null

# Counts argv entries of the pane's claude process that are the flag followed by a matching
# path, or the --flag=path form. Whole argv elements, with the flag directly before the path;
# other processes in the pane (wrappers, tools) never count.
matches=$(herdr pane process-info --pane "$HERDR_PANE_ID" 2>/dev/null | jq -r '
  [ .result.process_info.foreground_processes[]?
    | select(.name == "claude")
    | .argv as $a
    | range(0; ($a | length))
    | select(($a[.] == "--system-prompt-file" and (($a[.+1] // "") | test("orchestrator")))
             or ($a[.] | test("^--system-prompt-file=.*orchestrator")))
  ] | length' 2>/dev/null || echo 0)
[ "${matches:-0}" -gt 0 ] 2>/dev/null || exit 0

# SessionStart adds plain stdout to the conversation as context.
echo "Orchestrator reminder: delegate work to a worker first. Do it yourself only when it is small preparation (gathering facts to brief a worker, a quick check, verifying a worker's result) or when handing it off would cost more than doing it."
