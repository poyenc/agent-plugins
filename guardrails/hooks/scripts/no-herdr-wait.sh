#!/usr/bin/env bash
# PreToolUse(Bash): block any direct `herdr pane wait-output` or `herdr agent wait` invocation
# (through wrappers and `bash -c` bodies). Both block the caller's own turn until a match/state or
# --timeout, and --timeout is not reliably enforced (observed hanging well past a stated deadline,
# requiring manual interruption) -- so even a "bounded" wait is not actually bounded. The agent must
# stay responsive: run the underlying work with run_in_background and poll with short reads instead
# (or ScheduleWakeup/CronCreate for a longer interval). `herdr agent prompt ... --wait` is a
# different invocation (handled by herdr-prompt-guard.sh) and does not match here. No-op outside
# herdr.
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/scan-guard-lib.sh"

[ "${HERDR_ENV:-}" = 1 ] || exit 0

cmd=$(jq -r '.tool_input.command // ""')
[ -n "$cmd" ] || exit 0

# Is this segment's real command `herdr`, with `pane`+`wait-output` or `agent`+`wait` adjacent
# somewhere among its arguments? That pair is always adjacent in real CLI grammar.
herdr_wait_seg() {
  local cmdbase="$1"; shift
  [ "$cmdbase" = herdr ] || return 1
  local -a rest=("$@")
  local k a b
  for (( k=0; k<${#rest[@]}-1; k++ )); do
    a="$(dequote_full "${rest[$k]}")"
    b="$(dequote_full "${rest[$((k+1))]}")"
    if { [ "$a" = pane ] && [ "$b" = wait-output ]; } || { [ "$a" = agent ] && [ "$b" = wait ]; }; then
      return 0
    fi
  done
  return 1
}

scan_command "$cmd" herdr_wait_seg || exit 0

printf '{"decision":"block","reason":"Do not run `herdr pane wait-output` or `herdr agent wait` directly -- these block your own turn until a match/state (indefinitely without --timeout), and --timeout has been observed not to reliably enforce that deadline either, hanging well past it. Stay responsive instead: run the underlying command with run_in_background:true and poll progress yourself with short `herdr pane read` / `herdr agent read` calls a few seconds to tens of seconds apart, or use ScheduleWakeup/CronCreate for a longer-interval check. Never block waiting on another pane or agent."}'
