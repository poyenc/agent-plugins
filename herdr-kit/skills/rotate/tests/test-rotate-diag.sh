#!/usr/bin/env bash
# Failure-path diagnostic logging (rotate-common.sh): log_pane_diag / pane_width, exit_agent's
# pre-die render dump, and resolve_and_prepare's "no live model detected -> replays launch argv"
# note. All three exist so a future detection/exit failure is diagnosable from the rotation log
# alone, WITHOUT launching a throwaway agent to re-probe a picker that's already closed by the
# time anything downstream notices the miss. The hard requirement they share: fire ONLY on the
# failure path, never adding happy-path noise -- asserted here both ways (fires on failure, stays
# silent on a matched-baseline success).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/../../../scripts"
source "$S/rotate-common.sh"
set +e   # rotate-common.sh imports no `set -e` of its own (it's sourced, the caller sets it), but
         # be explicit: exit_agent below is asserted via a subshell that MUST run its die path.
MODEL_FLAG=--model; EFFORT_FLAG=--effort; EFFORT_STYLE=flag
PASS=0; FAIL=0
assert_eq(){ if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; echo "    exp:[$2] act:[$3]"; FAIL=$((FAIL+1)); fi; }
ERR=$(mktemp)

# --- log_pane_diag: width from `herdr pane edges`, render dumped verbatim, delimited ---------
herdr(){
  case "$1 $2" in
    "pane edges") jq -nc --arg p "wG:p4" '{result:{edges:{layout:{panes:[{pane_id:$p,rect:{width:42,height:20}}]}}}}' ;;
    *) echo '{}' ;;
  esac
}
log_pane_diag wG:p4 "test ctx" $'row-one\nrow-two' 2>"$ERR"
assert_eq "diag reports the pane width read from herdr pane edges" "1" "$(grep -c 'width 42' "$ERR")"
assert_eq "diag dumps the captured render verbatim (line 1)" "1" "$(grep -cx 'row-one' "$ERR")"
assert_eq "diag dumps the captured render verbatim (line 2)" "1" "$(grep -cx 'row-two' "$ERR")"
assert_eq "diag carries the caller-supplied context label" "1" "$(grep -c 'test ctx' "$ERR")"
assert_eq "diag emits an end-of-render delimiter" "1" "$(grep -c 'end captured render for wG:p4' "$ERR")"

# width degrades to "unknown" (never fails the rotation) when herdr can't report edges.
herdr(){ echo '{}'; }
log_pane_diag wG:p4 "test ctx" "x" 2>"$ERR"
assert_eq "diag width degrades to 'unknown' when edges are unavailable" "1" "$(grep -c 'width unknown' "$ERR")"

# CONTRACT (the Medium finding): a failing/malformed `herdr pane edges` must NOT abort the caller
# under `set -euo pipefail`. pane_width is a herdr|jq|head pipeline, so under pipefail a nonzero
# `herdr pane edges` (or jq choking on malformed output) makes the pipeline nonzero -- and a bare
# `w=$(pane_width ...)` assignment would then terminate the rotation via set -e. Run in a genuine
# set -e subshell (this file's own `set +e` would mask the bug) and assert the caller SURVIVES,
# still logs the render, and degrades to "width unknown". Covers both failure shapes: edges exits
# nonzero, and edges emits non-JSON that jq rejects.
for edge_mode in "exit-nonzero" "malformed-json"; do
  out=$(
    set -euo pipefail
    source "$S/rotate-common.sh"
    if [ "$edge_mode" = exit-nonzero ]; then
      herdr(){ case "$1 $2" in "pane edges") return 1 ;; *) echo '{}' ;; esac; }
    else
      herdr(){ case "$1 $2" in "pane edges") printf 'not json at all\n' ;; *) echo '{}' ;; esac; }
    fi
    log_pane_diag wG:p4 "edge fail" "RENDER-BODY" 2>&1
    echo "SURVIVED"
  )
  assert_eq "set -e: a $edge_mode 'pane edges' does not abort the caller" "1" "$(printf '%s' "$out" | grep -c 'SURVIVED')"
  assert_eq "set -e: a $edge_mode 'pane edges' still degrades width to unknown" "1" "$(printf '%s' "$out" | grep -c 'width unknown')"
  assert_eq "set -e: a $edge_mode 'pane edges' still dumps the render" "1" "$(printf '%s' "$out" | grep -c 'RENDER-BODY')"
done

# --- exit_agent: dumps the pane's visible content right before aborting an exit that never took --
# gone() stays false (agent get keeps returning a live .result.agent), no exit_fallback is
# declared, so exit_agent times out and dies -- and must dump what's on screen first.
herdr(){
  case "$1 $2" in
    "agent prompt") echo '{"result":{}}' ;;
    "agent get")    echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;   # never "gone"
    "pane read")    printf 'STUCK-CONFIRM-PROMPT: press y to quit\n' ;;
    "pane edges")   echo '{}' ;;
    *) echo '{}' ;;
  esac
}
( ROTATE_EXIT_POLL_SECS=1 exit_agent wG:p4 ) 2>"$ERR"
rc=$?
assert_eq "exit_agent still aborts when the pane never frees" "1" "$rc"
assert_eq "exit_agent dumps the stuck pane's visible content before dying" "1" "$(grep -c 'STUCK-CONFIRM-PROMPT' "$ERR")"
assert_eq "exit_agent's dump is labelled as an exit failure" "1" "$(grep -c 'exit failure' "$ERR")"

# --- resolve_and_prepare: the "detection found nothing -> replays launch argv" note -----------
# Bare-launched claude (no --model in argv), detection comes back empty: the relaunch will silently
# replay the original bare argv, so this must be surfaced.
MOCK_AGENTS='{"result":{"agents":[{"agent":"claude","pane_id":"wG:p4","name":"lead"}]}}'
MOCK_PROC_BARE=$(jq -nc '{result:{process_info:{foreground_processes:[{name:"claude",argv:["claude"]}]}}}')
mk_herdr(){ herdr(){ case "$1 $2" in
  "agent list") printf '%s' "$MOCK_AGENTS" ;;
  "pane process-info") printf '%s' "$MOCK_PROC_BARE" ;;
  "agent get") echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
  *) echo '{}' ;;
esac; }; }
mk_herdr
detect_override(){ DETECTED_MODEL=""; DETECTED_EFFORT=""; return 0; }   # detection produced nothing
OVERRIDE_NAME=""; OVERRIDE_MODEL=""; OVERRIDE_EFFORT=""
( resolve_and_prepare claude lead ) 2>"$ERR" >/dev/null
assert_eq "note fires when detection yields no live model (relaunch replays launch argv)" "1" "$(grep -c 'no live model detected' "$ERR")"

# Matched-baseline success: detection DID read a model (identical to launch) -- OVERRIDE_MODEL
# stays empty because nothing changed, but DETECTED_MODEL is non-empty, so the note must NOT fire
# (that is the happy path, not a silent fallback).
MOCK_PROC_HAIKU=$(jq -nc '{result:{process_info:{foreground_processes:[{name:"claude",argv:["claude","--model","haiku"]}]}}}')
herdr(){ case "$1 $2" in
  "agent list") printf '%s' "$MOCK_AGENTS" ;;
  "pane process-info") printf '%s' "$MOCK_PROC_HAIKU" ;;
  "agent get") echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
  *) echo '{}' ;;
esac; }
detect_override(){ DETECTED_MODEL="haiku"; DETECTED_EFFORT=""; return 0; }   # read, unchanged
OVERRIDE_NAME=""; OVERRIDE_MODEL=""; OVERRIDE_EFFORT=""
( resolve_and_prepare claude lead ) 2>"$ERR" >/dev/null
assert_eq "note stays silent on a matched-baseline detection (no happy-path noise)" "0" "$(grep -c 'no live model detected' "$ERR")"
unset -f detect_override

rm -f "$ERR"
echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
