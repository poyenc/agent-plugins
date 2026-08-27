#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../../scripts/rotate-common.sh"
PASS=0; FAIL=0
assert_eq(){ if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; echo "    exp:[$2] act:[$3]"; FAIL=$((FAIL+1)); fi; }
rc(){ if "$@"; then echo 0; else echo 1; fi; }

MOCK_AGENTS='{"result":{"agents":[
  {"agent":"claude","pane_id":"wG:p4","name":"lead"},
  {"agent":"pi","pane_id":"wG:p7"}]}}'
herdr(){ case "$1 $2" in "agent list") printf '%s' "$MOCK_AGENTS";; *) echo "{}";; esac; }

resolve lead
assert_eq "kind by name" "claude" "$ROTATE_KIND"
assert_eq "pane by name" "wG:p4"  "$ROTATE_PANE"
assert_eq "name by name" "lead"   "$ROTATE_NAME"
OVERRIDE_NAME=""; resolve wG:p7
assert_eq "kind by pane"  "pi"      "$ROTATE_KIND"
assert_eq "derived name"  "pi-wgp7" "$ROTATE_NAME"
OVERRIDE_NAME="profiler"; resolve wG:p7
assert_eq "override name" "profiler" "$ROTATE_NAME"

# @<session-prefix> asserts the pane's CURRENT occupant matches what the ping was tagged with.
MOCK_AGENTS_SESS='{"result":{"agents":[
  {"agent":"claude","pane_id":"wG:p4","name":"lead","agent_session":{"kind":"id","value":"abcd1234-ef56-0000-0000-000000000000"}}]}}'
herdr(){ case "$1 $2" in "agent list") printf '%s' "$MOCK_AGENTS_SESS";; *) echo "{}";; esac; }
resolve lead@abcd1234
assert_eq "matching session tag resolves" "wG:p4" "$ROTATE_PANE"

# pi's agent_session.kind is "path" (not "id") -- its value must NOT be trusted as a
# correlation id (a filesystem path's prefix is not distinct across sessions).
MOCK_AGENTS_PATH='{"result":{"agents":[
  {"agent":"pi","pane_id":"wG:p7","name":"worker","agent_session":{"kind":"path","value":"/home/user/.pi/sessions/x.jsonl"}}]}}'
herdr(){ case "$1 $2" in "agent list") printf '%s' "$MOCK_AGENTS_PATH";; *) echo "{}";; esac; }
OVERRIDE_NAME=""; resolve worker
assert_eq "pi session (kind=path) not trusted as an id" "" "$ROTATE_SESSION"

# codex has no agent_session at all.
MOCK_AGENTS_NONE='{"result":{"agents":[{"agent":"codex","pane_id":"wG:p8","name":"cx"}]}}'
herdr(){ case "$1 $2" in "agent list") printf '%s' "$MOCK_AGENTS_NONE";; *) echo "{}";; esac; }
resolve cx
assert_eq "codex has no session id" "" "$ROTATE_SESSION"
herdr(){ case "$1 $2" in "agent list") printf '%s' "$MOCK_AGENTS_SESS";; *) echo "{}";; esac; }
( resolve lead@ffffffff >/dev/null 2>&1 ); assert_eq "mismatched session tag dies" "1" "$?"

# An UNNAMED agent with a real session id is the exact case that shifted fields under plain
# `IFS=$'\t' read` (an empty middle field is swallowed) -- name must stay empty (then derived)
# and the session must NOT end up holding what was actually the name column's neighbor.
MOCK_AGENTS_UNNAMED_SESS='{"result":{"agents":[
  {"agent":"claude","pane_id":"wG:p9","agent_session":{"kind":"id","value":"11112222-3333-4444-5555-666677778888"}}]}}'
herdr(){ case "$1 $2" in "agent list") printf '%s' "$MOCK_AGENTS_UNNAMED_SESS";; *) echo "{}";; esac; }
OVERRIDE_NAME=""; resolve wG:p9
assert_eq "unnamed agent still derives a name" "claude-wgp9" "$ROTATE_NAME"
assert_eq "session not shifted into the name slot" "11112222" "${ROTATE_SESSION:0:8}"

# argv with a space AND an embedded newline must survive; argv0 dropped; --continue stripped.
MOCK_PROCINFO=$(jq -nc '{result:{process_info:{foreground_processes:[
  {name:"claude",argv:["claude","--append-system-prompt","line1\nline2","--continue","--model","opus a"]}]}}}')
herdr(){ case "$1 $2" in "pane process-info") printf '%s' "$MOCK_PROCINFO";; *) echo "{}";; esac; }
capture_argv wG:p4 claude
assert_eq "argv count"       "4" "${#BASE_FLAGS[@]}"
assert_eq "flag0" "--append-system-prompt" "${BASE_FLAGS[0]}"
assert_eq "multiline arg preserved" $'line1\nline2' "${BASE_FLAGS[1]}"
assert_eq "model flag" "--model" "${BASE_FLAGS[2]}"
assert_eq "spaced value preserved" "opus a" "${BASE_FLAGS[3]}"

# send_handoff: fires exactly one non-blocking prompt to the target, carrying the
# orchestrator's own pane ($HERDR_PANE_ID) and a pane@session-prefix tag (so two concurrent
# rotations, or a stale ping from an earlier rotation of the SAME agent, can't collide). Tagged
# by PANE, not name, so it's resolvable even when the agent is currently unnamed.
SENTLOG=$(mktemp)
herdr(){ case "$1 $2" in "agent prompt") shift 2; printf '%s\n' "${*//$'\n'/\\n}" >> "$SENTLOG"; echo '{"result":{}}';; *) echo "{}";; esac; }
export HERDR_PANE_ID=wG:p1
send_handoff wG:p4 lead abcd1234efgh
assert_eq "one prompt sent" "1" "$(wc -l < "$SENTLOG" | tr -d ' ')"
assert_eq "prompt targets the agent's pane" "1" "$(grep -c '^wG:p4 ' "$SENTLOG")"
assert_eq "prompt carries orchestrator pane" "1" "$(grep -c 'wG:p1' "$SENTLOG")"
assert_eq "prompt carries pane@session-prefix tag" "1" "$(grep -c 'wG:p4@abcd1234:' "$SENTLOG")"

# send_handoff must die (not silently succeed) when the prompt send itself fails.
herdr(){ return 42; }
( send_handoff wG:p4 lead abcd1234efgh >/dev/null 2>&1 ); assert_eq "send_handoff dies on prompt failure" "1" "$?"

# Transient error must NOT count as gone.
herdr(){ case "$1 $2" in "agent get") echo '{"error":{"code":"transport_error"}}' >&2; return 1;; esac; echo "{}"; }
assert_eq "transient != gone" "1" "$(rc gone wG:p4)"

# agent_not_found + shell prompt = gone.
herdr(){
  case "$1 $2" in
    "agent get") echo '{"error":{"code":"agent_not_found"}}' >&2; return 1 ;;
    "pane read") printf 'poyechen@host:~/x$ \n' ;;
    *) echo "{}" ;;
  esac
}
assert_eq "not_found+prompt = gone" "0" "$(rc gone wG:p4)"

# agent_not_found but NO shell prompt yet = not gone.
herdr(){
  case "$1 $2" in
    "agent get") echo '{"error":{"code":"agent_not_found"}}' >&2; return 1 ;;
    "pane read") printf 'still drawing agent ui\n' ;;
    *) echo "{}" ;;
  esac
}
assert_eq "not_found no-prompt = not gone" "1" "$(rc gone wG:p4)"

# exit_agent: present twice, then gone.
CNT=$(mktemp); echo 2 > "$CNT"
herdr(){
  case "$1 $2" in
    "agent prompt") echo '{"result":{}}' ;;
    "agent get")
      local n; n=$(cat "$CNT")
      if [ "$n" -le 0 ]; then echo '{"error":{"code":"agent_not_found"}}' >&2; return 1; fi
      echo $((n-1)) > "$CNT"; echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
    "pane read") printf 'user@host:~$ \n' ;;
    *) echo "{}" ;;
  esac
}
ROTATE_EXIT_POLL_SECS=6
assert_eq "exit succeeds when gone" "0" "$(rc exit_agent wG:p4)"

# wait_settled: succeeds once idle/done is observed; dies (does not silently proceed) if the
# target never settles, since the next step is destructive.
herdr(){ case "$1 $2" in "agent get") echo '{"result":{"agent":{"agent_status":"idle"}}}';; *) echo "{}";; esac; }
ROTATE_SETTLE_POLL_SECS=5
assert_eq "wait_settled succeeds when idle" "0" "$(rc wait_settled wG:p4)"
herdr(){ case "$1 $2" in "agent get") echo '{"result":{"agent":{"agent_status":"working"}}}';; *) echo "{}";; esac; }
ROTATE_SETTLE_POLL_SECS=2
( wait_settled wG:p4 >/dev/null 2>&1 ); assert_eq "wait_settled dies on timeout" "1" "$?"

# resolve_and_prepare: self-rotation (target's pane == caller's own pane) with settle=0
# (handoff) must skip the settle-wait entirely -- the caller IS the target, so it can never
# observe itself go idle while this very call is running. Status is stubbed "working" (as it
# genuinely would be for a real self-target) specifically to prove the skip happened: if it
# weren't skipped, this would time out and die instead of completing.
MOCK_AGENTS_SELF='{"result":{"agents":[{"agent":"claude","pane_id":"wG:p9","name":"lead"}]}}'
MOCK_PROC_SELF=$(jq -nc '{result:{process_info:{foreground_processes:[{name:"claude",argv:["claude","--model","haiku"]}]}}}')
herdr(){ case "$1 $2" in
  "agent list") printf '%s' "$MOCK_AGENTS_SELF" ;;
  "pane process-info") printf '%s' "$MOCK_PROC_SELF" ;;
  "agent get") echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  *) echo "{}" ;;
esac; }
unset -f detect_override 2>/dev/null || true
OVERRIDE_NAME=""; OVERRIDE_MODEL=""; OVERRIDE_EFFORT=""
assert_eq "self-rotation (handoff, settle=0) skips settle-wait" "0" \
  "$(HERDR_PANE_ID=wG:p9 ROTATE_SETTLE_POLL_SECS=2 rc resolve_and_prepare claude lead 0)"

# resolve_and_prepare: self-rotation with settle=1 (finish) must be REJECTED outright, not
# merely skip the settle-wait -- finish's later exit_agent step needs this very process to
# have already exited, which can never happen while it's the one still running.
( HERDR_PANE_ID=wG:p9 ROTATE_SETTLE_POLL_SECS=2 resolve_and_prepare claude lead 1 >/dev/null 2>&1 )
assert_eq "self-rotation (finish, settle=1) is rejected" "1" "$?"

# revalidate_session: no-op when there's no expected session (pi/codex); dies if the pane's
# live session no longer matches what resolve() observed moments earlier.
herdr(){ case "$1 $2" in "agent list") echo '{"result":{"agents":[]}}';; *) echo "{}";; esac; }
assert_eq "revalidate_session no-op without an expected session" "0" "$(rc revalidate_session wG:p4 '')"
herdr(){ case "$1 $2" in "agent list") printf '%s' "$MOCK_AGENTS_SESS";; *) echo "{}";; esac; }
assert_eq "revalidate_session passes when unchanged" "0" "$(rc revalidate_session wG:p4 'abcd1234-ef56-0000-0000-000000000000')"
( revalidate_session wG:p4 'ffffffff-ffff-ffff-ffff-ffffffffffff' >/dev/null 2>&1 ); assert_eq "revalidate_session dies on mismatch" "1" "$?"

STARTLOG=$(mktemp)
herdr(){ case "$1 $2" in "agent start") shift; printf '%s\n' "$*" > "$STARTLOG"; echo '{"result":{"agent":{}}}';; esac; echo '{"result":{}}'; }
relaunch lead claude wG:p4 --model opus --verbose
assert_eq "start kind+pane" "0" "$(rc grep -q -- '--kind claude --pane wG:p4' "$STARTLOG")"
assert_eq "start replays flags" "0" "$(rc grep -q -- '-- --model opus --verbose' "$STARTLOG")"

# verify: ready + exact argv match (incl a spaced element)
mkproc(){ jq -nc --args '{result:{process_info:{foreground_processes:[{name:"claude",argv:$ARGS.positional}]}}}' -- "$@"; }
herdr(){
  case "$1 $2" in
    "agent get") echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
    "pane process-info") printf '%s' "$PROC" ;;
    *) echo "{}" ;;
  esac
}
PROC=$(mkproc claude --model "opus a" --verbose)
assert_eq "verify match (spaced arg)" "0" "$(rc verify lead wG:p4 claude -- --model "opus a" --verbose)"
# ambiguous split must NOT compare equal
PROC=$(mkproc claude --model opus --verbose)
assert_eq "verify rejects split diff" "1" "$(rc verify lead wG:p4 claude -- --model "opus --verbose")"
# not ready -> fail
herdr(){ case "$1 $2" in "agent get") echo '{"result":{"agent":{"agent_status":"working"}}}';; *) echo "{}";; esac; }
ROTATE_VERIFY_POLL_SECS=2
assert_eq "verify not-ready fails" "1" "$(rc verify lead wG:p4 claude -- --model opus)"

# pi verify: if neither the captured argv nor a live detection ever produced a model/effort
# to check against, "intended" has nothing to compare the fresh session's live state to --
# this must fail closed, not report a vacuous pass just because detect_override itself
# "succeeded" (with empty DETECTED_MODEL/DETECTED_EFFORT).
MODEL_FLAG=--model; EFFORT_FLAG=--thinking
herdr(){ case "$1 $2" in "agent get") echo '{"result":{"agent":{"agent_status":"idle"}}}';; *) echo "{}";; esac; }
detect_override(){ DETECTED_MODEL="amd-gateway/unexpected"; DETECTED_EFFORT="max"; return 0; }
assert_eq "pi verify fails closed when intended has no model/effort" "1" "$(rc verify lead wG:p4 pi -- --verbose)"
unset -f detect_override 2>/dev/null || true

# kickoff
KOLOG=$(mktemp)
herdr(){ case "$1 $2" in "agent prompt") shift; printf '%s\n' "$*" >> "$KOLOG";; esac; echo '{"result":{}}'; }
: > "$KOLOG"; NO_KICKOFF=0; kickoff wG:p4 /tmp/h/x.md
assert_eq "kickoff cites path" "1" "$(grep -c '/tmp/h/x.md' "$KOLOG")"
: > "$KOLOG"; kickoff wG:p4 /tmp/h/x.md "custom go"
assert_eq "kickoff override" "1" "$(grep -c 'custom go' "$KOLOG")"
: > "$KOLOG"; NO_KICKOFF=1; kickoff wG:p4 /tmp/h/x.md
assert_eq "no-kickoff sends nothing" "0" "$(wc -l < "$KOLOG" | tr -d ' ')"
NO_KICKOFF=0

# kickoff must propagate a failed send (any nonzero, not swallowed to 0) -- a caller reporting
# "rotation complete" over a kickoff that never arrived would be misleading the operator.
herdr(){ return 42; }
assert_eq "kickoff propagates send failure" "1" "$(rc kickoff wG:p4 /tmp/h/x.md)"

# resolve_and_prepare: an explicit override for one field must not block live detection of
# the OTHER field, and must not itself be overwritten by detection.
MODEL_FLAG=--model EFFORT_FLAG=--effort EFFORT_STYLE=flag
MOCK_AGENTS_P='{"result":{"agents":[{"agent":"claude","pane_id":"wG:p4","name":"lead"}]}}'
MOCK_PROC_P=$(jq -nc '{result:{process_info:{foreground_processes:[{name:"claude",argv:["claude","--model","haiku","--effort","medium"]}]}}}')
herdr(){ case "$1 $2" in "agent list") printf '%s' "$MOCK_AGENTS_P";; "pane process-info") printf '%s' "$MOCK_PROC_P";; "agent get") echo '{"result":{"agent":{"agent_status":"idle"}}}';; *) echo "{}";; esac; }
detect_override(){ DETECTED_MODEL="should-not-be-used"; DETECTED_EFFORT="high"; }
OVERRIDE_NAME=""; OVERRIDE_MODEL="sonnet"; OVERRIDE_EFFORT=""
ROTATE_SETTLE_POLL_SECS=1 resolve_and_prepare claude lead
assert_eq "explicit override wins over detection" "1" "$(printf '%s\n' "${BASE_FLAGS[@]}" | grep -cx 'sonnet')"
assert_eq "missing field filled by detection"     "1" "$(printf '%s\n' "${BASE_FLAGS[@]}" | grep -cx 'high')"
assert_eq "not-overwritten field absent"          "0" "$(printf '%s\n' "${BASE_FLAGS[@]}" | grep -cx 'should-not-be-used')"
unset -f detect_override

# run_handoff / run_finish early-exit paths (no herdr contact needed; guard/parse fail first)
MODEL_FLAG=--model EFFORT_FLAG=--effort EFFORT_STYLE=flag
( HERDR_ENV=0; run_handoff claude foo >/dev/null 2>&1 ); assert_eq "handoff no-op outside herdr" "0" "$?"
( HERDR_ENV=0; run_finish claude foo /tmp/x.md >/dev/null 2>&1 ); assert_eq "finish no-op outside herdr" "0" "$?"
( HERDR_ENV=1; herdr(){ :;}; run_handoff claude --bogus x >/dev/null 2>&1 ); assert_eq "handoff unknown option dies" "1" "$?"
( HERDR_ENV=1; herdr(){ :;}; run_handoff claude --model >/dev/null 2>&1 ); assert_eq "handoff missing value dies" "1" "$?"
( HERDR_ENV=1; herdr(){ :;}; run_handoff claude a b >/dev/null 2>&1 ); assert_eq "handoff extra positional dies" "1" "$?"
( HERDR_ENV=1; herdr(){ :;}; run_handoff claude a --no-kickoff >/dev/null 2>&1 ); assert_eq "handoff rejects --no-kickoff" "1" "$?"
( HERDR_ENV=1; herdr(){ :;}; run_finish claude a >/dev/null 2>&1 ); assert_eq "finish missing handoff-path positional dies" "1" "$?"
( HERDR_ENV=1; herdr(){ :;}; run_finish claude a /no/such/file.md >/dev/null 2>&1 ); assert_eq "finish missing handoff file dies" "1" "$?"

echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
