#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../../scripts/rotate-common.sh"
# verify() reads these unconditionally (not just for kind=pi) -- every real per-kind script sets
# them at its own top, unconditionally, before anything can call verify(); this test sources
# rotate-common.sh directly (standing in for that role), so it must do the same, up front.
MODEL_FLAG=--model; EFFORT_FLAG=--effort; EFFORT_STYLE=flag
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

# verify() only checks MODEL_FLAG/EFFORT_FLAG values, the same scope as pi's own branch above.
# An earlier revision compared the WHOLE argv (an exact-suffix match tolerating a leading
# "prefix"), reasoning that a herdr-level default config always lands there -- confirmed live,
# but for the wrong reason: what was actually observed is this operator's own shell alias
# (`alias claude='claude --dangerously-skip-permissions --verbose'` in ~/.bashrc, likewise for
# codex) expanding ahead of whatever this script passes, not anything herdr itself injects.
# That's arbitrary local shell config, not a knowable, stable schema -- this tool's job is to
# pass launch flags through and confirm ITS OWN overrides took effect, not to gate a successful
# relaunch on the shape of flags it doesn't manage.
mkproc(){ jq -nc --args '{result:{process_info:{foreground_processes:[{name:"claude",argv:$ARGS.positional}]}}}' -- "$@"; }
herdr(){
  case "$1 $2" in
    "agent get") echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
    "pane process-info") printf '%s' "$PROC" ;;
    *) echo "{}" ;;
  esac
}
PROC=$(mkproc claude --model "opus a" --verbose)
assert_eq "verify match (spaced model value)" "0" "$(rc verify lead wG:p4 claude -- --model "opus a")"

# not ready -> fail
herdr(){ case "$1 $2" in "agent get") echo '{"result":{"agent":{"agent_status":"working"}}}';; *) echo "{}";; esac; }
ROTATE_VERIFY_POLL_SECS=2
assert_eq "verify not-ready fails" "1" "$(rc verify lead wG:p4 claude -- --model opus)"

herdr(){
  case "$1 $2" in
    "agent get") echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
    "pane process-info") printf '%s' "$PROC" ;;
    *) echo "{}" ;;
  esac
}

# An arbitrary prefix ahead of the model/effort flags (e.g. a shell alias's own flags) must NOT
# cause a rejection -- verify() only cares whether ITS OWN flags took effect, not what preceded
# them.
PROC=$(mkproc claude --dangerously-skip-permissions --verbose --model opus --effort high)
assert_eq "verify tolerates an arbitrary prefix (e.g. a shell alias's own flags)" "0" \
  "$(rc verify lead wG:p4 claude -- --model opus --effort high)"

# A genuinely corrupted model or effort value must still be caught.
PROC=$(mkproc claude --dangerously-skip-permissions --verbose --model medium --effort high)
assert_eq "verify still catches a real model value corruption" "1" \
  "$(rc verify lead wG:p4 claude -- --model opus --effort high)"
PROC=$(mkproc claude --model opus --effort low)
assert_eq "verify still catches a real effort value corruption" "1" \
  "$(rc verify lead wG:p4 claude -- --model opus --effort high)"

# A LATER, conflicting occurrence of the same flag must also be caught -- most real CLI arg
# parsers apply last-flag-wins, so a trailing "--model medium" after the correct-looking
# "--model opus" would mean the effective model is actually "medium", not what was intended.
PROC=$(mkproc claude --model opus --model medium)
assert_eq "verify rejects a later conflicting occurrence of the same flag (last-wins)" "1" \
  "$(rc verify lead wG:p4 claude -- --model opus)"

# A byte-identical intended/actual model must always pass, even when the flag repeats with
# different values along the way -- both sides resolve to the same LAST value.
PROC=$(mkproc claude --model sonnet --model opus)
assert_eq "verify accepts byte-identical intended/actual even with a repeated flag" "0" \
  "$(rc verify lead wG:p4 claude -- --model opus)"

# Flags/positionals this tool doesn't manage (a resume flag surviving, an initial-prompt
# positional, anything else in the live argv) are simply not this check's concern -- verify()'s
# only job is confirming its own model/effort overrides took effect, not gating a successful
# relaunch on anything else present.
PROC=$(mkproc claude --resume old-session --model opus hello)
assert_eq "verify does not block on flags/positionals it doesn't manage" "0" \
  "$(rc verify lead wG:p4 claude -- --model opus)"

# Neither model nor effort was ever intended (this rotation never overrode either) -- nothing of
# ours to check, so this must pass, not fail closed (unlike pi's branch above, which fails
# closed only because it has no OTHER verification signal at all for that kind).
PROC=$(mkproc claude --verbose)
assert_eq "verify passes when neither model nor effort was ever intended" "0" \
  "$(rc verify lead wG:p4 claude -- --verbose)"

# codex: alias spelling (-m vs --model) and kv-style effort must both be recognized, on the
# intended side and the live side.
MODEL_FLAG=--model MODEL_FLAG_ALIASES=(-m) EFFORT_FLAG=model_reasoning_effort EFFORT_STYLE=kv
PROC=$(jq -nc --args '{result:{process_info:{foreground_processes:[{name:"codex",argv:$ARGS.positional}]}}}' -- codex --model opus -c model_reasoning_effort=high)
assert_eq "verify matches codex's alias spelling + kv effort" "0" \
  "$(rc verify lead wG:p4 codex -- -m opus -c model_reasoning_effort=high)"

PROC=$(jq -nc --args '{result:{process_info:{foreground_processes:[{name:"codex",argv:$ARGS.positional}]}}}' -- codex --model opus -m medium)
assert_eq "verify rejects a later conflicting occurrence through a DIFFERENT alias spelling" "1" \
  "$(rc verify lead wG:p4 codex -- --model opus)"

PROC=$(jq -nc --args '{result:{process_info:{foreground_processes:[{name:"codex",argv:$ARGS.positional}]}}}' -- codex -c model_reasoning_effort=low -c model_reasoning_effort=high)
assert_eq "verify rejects a later conflicting kv effort value" "1" \
  "$(rc verify lead wG:p4 codex -- -c model_reasoning_effort=low)"

PROC=$(jq -nc --args '{result:{process_info:{foreground_processes:[{name:"codex",argv:$ARGS.positional}]}}}' -- codex -mopus -m medium)
assert_eq "verify rejects a later conflicting occurrence through codex's attached -mVALUE form" "1" \
  "$(rc verify lead wG:p4 codex -- -mopus)"
MODEL_FLAG=--model MODEL_FLAG_ALIASES=() EFFORT_FLAG=--effort EFFORT_STYLE=flag

PROC=$(mkproc claude --model=opus --model medium)
assert_eq "verify rejects a later conflicting model when the intended one used inline --model=value" "1" \
  "$(rc verify lead wG:p4 claude -- --model=opus)"

# value_of_flag (used directly by pi's verify branch and by run_finish's pi precheck) must also
# resolve to the LAST occurrence, not the first -- a repeated flag's real, effective value is
# whichever occurrence a genuine CLI parser would apply last.
assert_eq "value_of_flag returns the last occurrence" "opus" "$(value_of_flag --model claude --model sonnet --model opus)"
assert_eq "value_of_flag empty when the flag never appears" "" "$(value_of_flag --model claude --verbose)"

# pi's own accepted "--flag=value" inline form must be recognized too, not just the two-token
# "--flag value" form -- a value_of_flag miss here would make pi's verify/precheck logic treat a
# genuinely-set model/effort as absent.
assert_eq "value_of_flag recognizes pi's inline --model=value form" "opus" "$(value_of_flag --model claude --model=opus --verbose)"

# value_of_flag must stop at a literal "--": nothing past it is a flag to any of these CLIs (see
# strip_context_flags), so positional data on the far side -- e.g. a trailing initial-prompt
# argument that happens to contain text shaped like a flag -- must never be misread as a later
# occurrence.
assert_eq "value_of_flag stops at --" "opus" "$(value_of_flag --model claude --model opus -- --model=wrong)"

# value_of_flag_any: alias-aware, same last-occurrence-wins semantics across ALL spellings
# combined -- a repeated flag's real, effective value doesn't care which alias each occurrence
# used, only the order.
assert_eq "value_of_flag_any returns the last occurrence across alias spellings" "medium" \
  "$(value_of_flag_any -m --model -- codex --model opus -m medium)"
assert_eq "value_of_flag_any recognizes the attached short-alias form" "opus" \
  "$(value_of_flag_any -m --model -- codex -mopus)"
assert_eq "value_of_flag_any empty when neither spelling appears" "" \
  "$(value_of_flag_any -m --model -- codex --verbose)"

# value_of_kv: codex's own "-c key=value" convention, last-occurrence-wins.
assert_eq "value_of_kv returns the last occurrence" "high" \
  "$(value_of_kv model_reasoning_effort codex -c model_reasoning_effort=low -c model_reasoning_effort=high)"
assert_eq "value_of_kv empty when the key never appears" "" \
  "$(value_of_kv model_reasoning_effort codex --verbose)"

# value_of_kv must also recognize codex's real, valid ATTACHED "-cKEY=VALUE" form (no space) --
# replace_or_append_kv (the write path) already recognizes this (confirmed live against the
# installed codex binary); value_of_kv (the read path) must match, or a codex agent originally
# launched with this form silently can't have its effort changes detected at all.
assert_eq "value_of_kv recognizes codex's attached -cKEY=VALUE form" "low" \
  "$(value_of_kv model_reasoning_effort -cmodel_reasoning_effort=low --verbose)"
assert_eq "value_of_kv: last occurrence wins across mixed two-token/attached forms" "high" \
  "$(value_of_kv model_reasoning_effort -c model_reasoning_effort=low -cmodel_reasoning_effort=high)"

# pi verify: if neither the captured argv nor a live detection ever produced a model/effort
# to check against, "intended" has nothing to compare the fresh session's live state to --
# this must fail closed, not report a vacuous pass just because detect_override itself
# "succeeded" (with empty DETECTED_MODEL/DETECTED_EFFORT).
MODEL_FLAG=--model; EFFORT_FLAG=--thinking
herdr(){ case "$1 $2" in "agent get") echo '{"result":{"agent":{"agent_status":"idle"}}}';; *) echo "{}";; esac; }
detect_override(){ DETECTED_MODEL="amd-gateway/unexpected"; DETECTED_EFFORT="max"; return 0; }
assert_eq "pi verify fails closed when intended has no model/effort" "1" "$(rc verify lead wG:p4 pi -- --verbose)"
unset -f detect_override 2>/dev/null || true

# kickoff: default (no msg given at all -> the built-in default message)
KOLOG=$(mktemp)
herdr(){ case "$1 $2" in "agent prompt") shift; printf '%s\n' "$*" >> "$KOLOG";; esac; echo '{"result":{}}'; }
: > "$KOLOG"; kickoff wG:p4 /tmp/h/x.md
assert_eq "kickoff (no msg) cites path" "1" "$(grep -c '/tmp/h/x.md' "$KOLOG")"

# kickoff: custom message
: > "$KOLOG"; kickoff wG:p4 /tmp/h/x.md "custom go"
assert_eq "kickoff (custom msg) sends it" "1" "$(grep -c 'custom go' "$KOLOG")"

# kickoff: "off" sentinel suppresses it entirely -- one flag, three states, no separate
# NO_KICKOFF variable needed any more.
: > "$KOLOG"; kickoff wG:p4 /tmp/h/x.md "off"
assert_eq "kickoff off sends nothing" "0" "$(wc -l < "$KOLOG" | tr -d ' ')"

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

# resolve_and_prepare must NOT feed a detected value into apply_override when it's identical to
# what the original argv already had -- BASE_FLAGS must come out byte-for-byte unchanged in that
# case (per docs/superpowers/specs/2026-08-28-herdr-rotate-verify-override-design.md, Decision 3).
MODEL_FLAG=--model EFFORT_FLAG=--effort EFFORT_STYLE=flag
MOCK_AGENTS_NOCHANGE='{"result":{"agents":[{"agent":"claude","pane_id":"wG:p4","name":"lead"}]}}'
MOCK_PROC_NOCHANGE=$(jq -nc '{result:{process_info:{foreground_processes:[{name:"claude",argv:["claude","--model","haiku","--effort","medium"]}]}}}')
herdr(){ case "$1 $2" in "agent list") printf '%s' "$MOCK_AGENTS_NOCHANGE";; "pane process-info") printf '%s' "$MOCK_PROC_NOCHANGE";; "agent get") echo '{"result":{"agent":{"agent_status":"idle"}}}';; *) echo "{}";; esac; }
detect_override(){ DETECTED_MODEL="haiku"; DETECTED_EFFORT="medium"; }   # identical to the launch argv
OVERRIDE_NAME=""; OVERRIDE_MODEL=""; OVERRIDE_EFFORT=""
ROTATE_SETTLE_POLL_SECS=1 resolve_and_prepare claude lead
assert_eq "no-op detection leaves BASE_FLAGS byte-for-byte unchanged" "--model haiku --effort medium" "${BASE_FLAGS[*]}"
unset -f detect_override

# A genuinely CHANGED live value (the user ran /effort mid-session) must still be applied, and
# replace the original in place, not append a duplicate.
herdr(){ case "$1 $2" in "agent list") printf '%s' "$MOCK_AGENTS_NOCHANGE";; "pane process-info") printf '%s' "$MOCK_PROC_NOCHANGE";; "agent get") echo '{"result":{"agent":{"agent_status":"idle"}}}';; *) echo "{}";; esac; }
detect_override(){ DETECTED_MODEL="haiku"; DETECTED_EFFORT="high"; }   # effort changed live
OVERRIDE_NAME=""; OVERRIDE_MODEL=""; OVERRIDE_EFFORT=""
ROTATE_SETTLE_POLL_SECS=1 resolve_and_prepare claude lead
assert_eq "a genuinely changed detected effort is applied, replacing in place" "--model haiku --effort high" "${BASE_FLAGS[*]}"
unset -f detect_override

# The original argv had NO --model flag at all (implicit default) -- detection resolving to
# SOME concrete model must NOT synthesize an explicit --model flag; there's nothing to compare
# it against, so this is treated as "can't tell, don't touch," not "a change happened."
MOCK_PROC_NOFLAG=$(jq -nc '{result:{process_info:{foreground_processes:[{name:"claude",argv:["claude","--verbose"]}]}}}')
herdr(){ case "$1 $2" in "agent list") printf '%s' "$MOCK_AGENTS_NOCHANGE";; "pane process-info") printf '%s' "$MOCK_PROC_NOFLAG";; "agent get") echo '{"result":{"agent":{"agent_status":"idle"}}}';; *) echo "{}";; esac; }
detect_override(){ DETECTED_MODEL="sonnet"; DETECTED_EFFORT=""; }
OVERRIDE_NAME=""; OVERRIDE_MODEL=""; OVERRIDE_EFFORT=""
ROTATE_SETTLE_POLL_SECS=1 resolve_and_prepare claude lead
assert_eq "no original model flag: detection never synthesizes one" "--verbose" "${BASE_FLAGS[*]}"
unset -f detect_override

# An EXPLICIT --model/--effort passed to finish always applies, even if it happens to equal the
# default already present -- it's a direct, deliberate ask, not a detection result, so it is
# never subject to the differs-from-default gate.
herdr(){ case "$1 $2" in "agent list") printf '%s' "$MOCK_AGENTS_NOCHANGE";; "pane process-info") printf '%s' "$MOCK_PROC_NOCHANGE";; "agent get") echo '{"result":{"agent":{"agent_status":"idle"}}}';; *) echo "{}";; esac; }
OVERRIDE_NAME=""; OVERRIDE_MODEL="haiku"; OVERRIDE_EFFORT=""   # explicit --model haiku, same as default
ROTATE_SETTLE_POLL_SECS=1 resolve_and_prepare claude lead
assert_eq "explicit override always applies even when it matches the default" "--model haiku --effort medium" "${BASE_FLAGS[*]}"
MODEL_FLAG=--model EFFORT_FLAG=--effort EFFORT_STYLE=flag

# End-to-end: a codex agent originally launched with the attached -cKEY=VALUE effort form must
# still have a genuine live effort CHANGE detected and applied on rotation -- this silently
# failed before value_of_kv's attached-form fix (default_effort parsed as empty, so the
# differs-from-default gate never fired).
MODEL_FLAG=--model MODEL_FLAG_ALIASES=(-m) EFFORT_FLAG=model_reasoning_effort EFFORT_STYLE=kv
MOCK_AGENTS_CODEX_ATTACHED='{"result":{"agents":[{"agent":"codex","pane_id":"wG:p4","name":"lead"}]}}'
MOCK_PROC_CODEX_ATTACHED=$(jq -nc '{result:{process_info:{foreground_processes:[{name:"codex",argv:["codex","--model","opus","-cmodel_reasoning_effort=low"]}]}}}')
herdr(){ case "$1 $2" in "agent list") printf '%s' "$MOCK_AGENTS_CODEX_ATTACHED";; "pane process-info") printf '%s' "$MOCK_PROC_CODEX_ATTACHED";; "agent get") echo '{"result":{"agent":{"agent_status":"idle"}}}';; *) echo "{}";; esac; }
detect_override(){ DETECTED_MODEL="opus"; DETECTED_EFFORT="high"; }   # genuinely changed live
OVERRIDE_NAME=""; OVERRIDE_MODEL=""; OVERRIDE_EFFORT=""
ROTATE_SETTLE_POLL_SECS=1 resolve_and_prepare codex lead
assert_eq "codex attached-kv-form: a genuinely changed live effort is detected and applied" "1" \
  "$(printf '%s\n' "${BASE_FLAGS[@]}" | grep -cx 'model_reasoning_effort=high')"
unset -f detect_override
MODEL_FLAG=--model MODEL_FLAG_ALIASES=() EFFORT_FLAG=--effort EFFORT_STYLE=flag

# pi: capture_argv is ALWAYS empty (process.title rewrite hides pi's real launch flags -- see
# capture_argv's comment and verify()'s pi branch), so default_model/default_effort are always
# empty for this kind -- the general differs-from-default gate would therefore never promote
# ANYTHING, leaving OVERRIDE_MODEL/OVERRIDE_EFFORT empty and tripping run_finish's pi preflight
# on every rotation. Any detected value must be promoted unconditionally for pi instead.
MODEL_FLAG=--model EFFORT_FLAG=--thinking EFFORT_STYLE=flag
MOCK_AGENTS_PI='{"result":{"agents":[{"agent":"pi","pane_id":"wG:p7","name":"worker"}]}}'
MOCK_PROC_PI_BARE=$(jq -nc '{result:{process_info:{foreground_processes:[{name:"pi",argv:["pi"]}]}}}')
herdr(){ case "$1 $2" in "agent list") printf '%s' "$MOCK_AGENTS_PI";; "pane process-info") printf '%s' "$MOCK_PROC_PI_BARE";; "agent get") echo '{"result":{"agent":{"agent_status":"idle"}}}';; *) echo "{}";; esac; }
detect_override(){ DETECTED_MODEL="amd-gateway/gpt-5.6-terra"; DETECTED_EFFORT="high"; }
OVERRIDE_NAME=""; OVERRIDE_MODEL=""; OVERRIDE_EFFORT=""
ROTATE_SETTLE_POLL_SECS=1 resolve_and_prepare pi worker
assert_eq "pi: detected model is promoted despite an always-empty default" "1" \
  "$(printf '%s\n' "${BASE_FLAGS[@]}" | grep -cx 'amd-gateway/gpt-5.6-terra')"
assert_eq "pi: detected effort is promoted despite an always-empty default" "1" \
  "$(printf '%s\n' "${BASE_FLAGS[@]}" | grep -cx 'high')"
unset -f detect_override
MODEL_FLAG=--model MODEL_FLAG_ALIASES=() EFFORT_FLAG=--effort EFFORT_STYLE=flag

# claude's model comparison is exact-match only (no substring/containment tolerance): a launch
# using a bare alias ("sonnet") vs. a live session that now shows a full identifier
# ("claude-sonnet-5") for the SAME underlying model is treated as a change -- there is no way to
# tell "same model, different spelling" apart from "different model, coincidentally overlapping
# name" using string containment alone (confirmed by two prior containment-based designs both
# being found unsafe on review), so this errs toward "changed" rather than silently keeping a
# stale alias.
MOCK_AGENTS_CLAUDE_FULL='{"result":{"agents":[{"agent":"claude","pane_id":"wG:p4","name":"lead"}]}}'
MOCK_PROC_CLAUDE_ALIAS=$(jq -nc '{result:{process_info:{foreground_processes:[{name:"claude",argv:["claude","--model","sonnet","--effort","medium"]}]}}}')
herdr(){ case "$1 $2" in "agent list") printf '%s' "$MOCK_AGENTS_CLAUDE_FULL";; "pane process-info") printf '%s' "$MOCK_PROC_CLAUDE_ALIAS";; "agent get") echo '{"result":{"agent":{"agent_status":"idle"}}}';; *) echo "{}";; esac; }
detect_override(){ DETECTED_MODEL="claude-sonnet-5"; DETECTED_EFFORT="medium"; }   # same model, more specific spelling
OVERRIDE_NAME=""; OVERRIDE_MODEL=""; OVERRIDE_EFFORT=""
ROTATE_SETTLE_POLL_SECS=1 resolve_and_prepare claude lead
assert_eq "claude: bare-alias default vs a more specific detected spelling is treated as changed" \
  "--model claude-sonnet-5 --effort medium" "${BASE_FLAGS[*]}"
unset -f detect_override

# The same full-name-vs-alias tolerance must NOT mask a genuine model change (opus -> sonnet).
detect_override(){ DETECTED_MODEL="sonnet"; DETECTED_EFFORT="medium"; }
MOCK_PROC_CLAUDE_OPUS=$(jq -nc '{result:{process_info:{foreground_processes:[{name:"claude",argv:["claude","--model","opus","--effort","medium"]}]}}}')
herdr(){ case "$1 $2" in "agent list") printf '%s' "$MOCK_AGENTS_CLAUDE_FULL";; "pane process-info") printf '%s' "$MOCK_PROC_CLAUDE_OPUS";; "agent get") echo '{"result":{"agent":{"agent_status":"idle"}}}';; *) echo "{}";; esac; }
OVERRIDE_NAME=""; OVERRIDE_MODEL=""; OVERRIDE_EFFORT=""
ROTATE_SETTLE_POLL_SECS=1 resolve_and_prepare claude lead
assert_eq "claude: a genuine model change (opus -> sonnet) is still detected and applied" \
  "--model sonnet --effort medium" "${BASE_FLAGS[*]}"
unset -f detect_override

# The full-name-vs-alias tolerance must NOT mask a genuine version change WITHIN the same
# family: two specific dated identifiers (Sonnet 4.5 vs Sonnet 5) are not substrings of each
# other, so this must still be treated as changed even though both are "Sonnet".
detect_override(){ DETECTED_MODEL="claude-sonnet-5"; DETECTED_EFFORT="medium"; }
MOCK_PROC_CLAUDE_SONNET45=$(jq -nc '{result:{process_info:{foreground_processes:[{name:"claude",argv:["claude","--model","claude-sonnet-4-5","--effort","medium"]}]}}}')
herdr(){ case "$1 $2" in "agent list") printf '%s' "$MOCK_AGENTS_CLAUDE_FULL";; "pane process-info") printf '%s' "$MOCK_PROC_CLAUDE_SONNET45";; "agent get") echo '{"result":{"agent":{"agent_status":"idle"}}}';; *) echo "{}";; esac; }
OVERRIDE_NAME=""; OVERRIDE_MODEL=""; OVERRIDE_EFFORT=""
ROTATE_SETTLE_POLL_SECS=1 resolve_and_prepare claude lead
assert_eq "claude: a same-family version change (sonnet-4-5 -> sonnet-5) is still detected and applied" \
  "--model claude-sonnet-5 --effort medium" "${BASE_FLAGS[*]}"
unset -f detect_override

# Model comparison is exact-match for every kind (see the claude tests above) -- a value that is
# merely a PREFIX/substring of the default must still be treated as a genuinely different model.
MODEL_FLAG=--model MODEL_FLAG_ALIASES=(-m) EFFORT_FLAG=model_reasoning_effort EFFORT_STYLE=kv
MOCK_AGENTS_CODEX_PREFIX='{"result":{"agents":[{"agent":"codex","pane_id":"wG:p4","name":"lead"}]}}'
MOCK_PROC_CODEX_PREFIX=$(jq -nc '{result:{process_info:{foreground_processes:[{name:"codex","argv":["codex","--model","gpt-5.6-terra-v2","-c","model_reasoning_effort=medium"]}]}}}')
herdr(){ case "$1 $2" in "agent list") printf '%s' "$MOCK_AGENTS_CODEX_PREFIX";; "pane process-info") printf '%s' "$MOCK_PROC_CODEX_PREFIX";; "agent get") echo '{"result":{"agent":{"agent_status":"idle"}}}';; *) echo "{}";; esac; }
detect_override(){ DETECTED_MODEL="gpt-5.6-terra"; DETECTED_EFFORT="medium"; }   # a PREFIX of the default, but a genuinely different model
OVERRIDE_NAME=""; OVERRIDE_MODEL=""; OVERRIDE_EFFORT=""
ROTATE_SETTLE_POLL_SECS=1 resolve_and_prepare codex lead
assert_eq "codex: a detected value that is a substring of the default is still treated as changed" "1" \
  "$(printf '%s\n' "${BASE_FLAGS[@]}" | grep -cx 'gpt-5.6-terra')"
unset -f detect_override
MODEL_FLAG=--model MODEL_FLAG_ALIASES=() EFFORT_FLAG=--effort EFFORT_STYLE=flag

# TOML permits (but doesn't require) quoting a string value -- `key="low"` and `key=low` are the
# same value (confirmed live: `codex -c 'model_reasoning_effort="low"' features list` and the
# unquoted form produce identical output). Live detection always reports the bare, unquoted
# level -- a launch that quoted its value must not look "different" just because of that spelling.
MODEL_FLAG=--model MODEL_FLAG_ALIASES=(-m) EFFORT_FLAG=model_reasoning_effort EFFORT_STYLE=kv
MOCK_AGENTS_CODEX_QUOTED='{"result":{"agents":[{"agent":"codex","pane_id":"wG:p4","name":"lead"}]}}'
MOCK_PROC_CODEX_QUOTED=$(jq -nc '{result:{process_info:{foreground_processes:[{name:"codex",argv:["codex","--model","opus","-c","model_reasoning_effort=\"low\""]}]}}}')
herdr(){ case "$1 $2" in "agent list") printf '%s' "$MOCK_AGENTS_CODEX_QUOTED";; "pane process-info") printf '%s' "$MOCK_PROC_CODEX_QUOTED";; "agent get") echo '{"result":{"agent":{"agent_status":"idle"}}}';; *) echo "{}";; esac; }
detect_override(){ DETECTED_MODEL="opus"; DETECTED_EFFORT="low"; }   # same value, unquoted spelling
OVERRIDE_NAME=""; OVERRIDE_MODEL=""; OVERRIDE_EFFORT=""
ROTATE_SETTLE_POLL_SECS=1 resolve_and_prepare codex lead
assert_eq "codex: quoted TOML effort vs detection's unquoted spelling of the SAME value is not a change" \
  "--model opus -c model_reasoning_effort=\"low\"" "${BASE_FLAGS[*]}"
unset -f detect_override

# Same tolerance for TOML's other equally valid string-quoting spelling: single quotes.
MOCK_PROC_CODEX_SINGLEQUOTED=$(jq -nc '{result:{process_info:{foreground_processes:[{name:"codex",argv:["codex","--model","opus","-c","model_reasoning_effort='"'"'low'"'"'"]}]}}}')
herdr(){ case "$1 $2" in "agent list") printf '%s' "$MOCK_AGENTS_CODEX_QUOTED";; "pane process-info") printf '%s' "$MOCK_PROC_CODEX_SINGLEQUOTED";; "agent get") echo '{"result":{"agent":{"agent_status":"idle"}}}';; *) echo "{}";; esac; }
detect_override(){ DETECTED_MODEL="opus"; DETECTED_EFFORT="low"; }
OVERRIDE_NAME=""; OVERRIDE_MODEL=""; OVERRIDE_EFFORT=""
ROTATE_SETTLE_POLL_SECS=1 resolve_and_prepare codex lead
assert_eq "codex: single-quoted TOML effort vs detection's unquoted spelling of the SAME value is not a change" \
  "--model opus -c model_reasoning_effort='low'" "${BASE_FLAGS[*]}"
unset -f detect_override

# Trailing whitespace after the (quoted) value must not be swallowed into the comparison value --
# a naive greedy capture would otherwise leave the quotes (and space) unstripped, making an
# unchanged launch look "different" and get rewritten unnecessarily.
MOCK_PROC_CODEX_TRAILWS=$(jq -nc '{result:{process_info:{foreground_processes:[{name:"codex",argv:["codex","--model","opus","-c","model_reasoning_effort = \"low\" "]}]}}}')
herdr(){ case "$1 $2" in "agent list") printf '%s' "$MOCK_AGENTS_CODEX_QUOTED";; "pane process-info") printf '%s' "$MOCK_PROC_CODEX_TRAILWS";; "agent get") echo '{"result":{"agent":{"agent_status":"idle"}}}';; *) echo "{}";; esac; }
detect_override(){ DETECTED_MODEL="opus"; DETECTED_EFFORT="low"; }
OVERRIDE_NAME=""; OVERRIDE_MODEL=""; OVERRIDE_EFFORT=""
ROTATE_SETTLE_POLL_SECS=1 resolve_and_prepare codex lead
assert_eq "codex: trailing whitespace after a quoted default is not a change" \
  "--model opus -c model_reasoning_effort = \"low\" " "${BASE_FLAGS[*]}"
unset -f detect_override

# TOML also permits (but doesn't require) whitespace around "=" -- a launch that spelled it this
# way must be recognized both for reading its default (so a genuine live change is still
# detected) and for replacing it in place (so an explicit override doesn't append a duplicate).
MOCK_PROC_CODEX_SPACED=$(jq -nc '{result:{process_info:{foreground_processes:[{name:"codex",argv:["codex","--model","opus","-c","model_reasoning_effort = \"low\""]}]}}}')
herdr(){ case "$1 $2" in "agent list") printf '%s' "$MOCK_AGENTS_CODEX_QUOTED";; "pane process-info") printf '%s' "$MOCK_PROC_CODEX_SPACED";; "agent get") echo '{"result":{"agent":{"agent_status":"idle"}}}';; *) echo "{}";; esac; }
detect_override(){ DETECTED_MODEL="opus"; DETECTED_EFFORT="high"; }   # genuinely changed live
OVERRIDE_NAME=""; OVERRIDE_MODEL=""; OVERRIDE_EFFORT=""
ROTATE_SETTLE_POLL_SECS=1 resolve_and_prepare codex lead
assert_eq "codex: a genuine change past a whitespace-around-= default is detected and replaces in place (no duplicate)" \
  "--model opus -c model_reasoning_effort=high" "${BASE_FLAGS[*]}"
unset -f detect_override

# The quote-tolerant comparison must NOT mask a genuine effort change.
detect_override(){ DETECTED_MODEL="opus"; DETECTED_EFFORT="high"; }   # genuinely changed live
herdr(){ case "$1 $2" in "agent list") printf '%s' "$MOCK_AGENTS_CODEX_QUOTED";; "pane process-info") printf '%s' "$MOCK_PROC_CODEX_QUOTED";; "agent get") echo '{"result":{"agent":{"agent_status":"idle"}}}';; *) echo "{}";; esac; }
OVERRIDE_NAME=""; OVERRIDE_MODEL=""; OVERRIDE_EFFORT=""
ROTATE_SETTLE_POLL_SECS=1 resolve_and_prepare codex lead
assert_eq "codex: a genuine effort change is still detected past a quoted default" \
  "--model opus -c model_reasoning_effort=high" "${BASE_FLAGS[*]}"
unset -f detect_override
MODEL_FLAG=--model MODEL_FLAG_ALIASES=() EFFORT_FLAG=--effort EFFORT_STYLE=flag

# pi: an explicit override for ONE field must survive alongside the OTHER field being filled by
# detection -- only the "both absent" case was covered before, which would not have caught a
# regression that dropped either half of the pi bypass's own guards.
MODEL_FLAG=--model EFFORT_FLAG=--thinking EFFORT_STYLE=flag
herdr(){ case "$1 $2" in "agent list") printf '%s' "$MOCK_AGENTS_PI";; "pane process-info") printf '%s' "$MOCK_PROC_PI_BARE";; "agent get") echo '{"result":{"agent":{"agent_status":"idle"}}}';; *) echo "{}";; esac; }
detect_override(){ DETECTED_MODEL="should-not-be-used"; DETECTED_EFFORT="high"; }
OVERRIDE_NAME=""; OVERRIDE_MODEL="amd-gateway/gpt-5.6-terra"; OVERRIDE_EFFORT=""
ROTATE_SETTLE_POLL_SECS=1 resolve_and_prepare pi worker
assert_eq "pi: explicit model override survives alongside detection filling effort" "1" \
  "$(printf '%s\n' "${BASE_FLAGS[@]}" | grep -cx 'amd-gateway/gpt-5.6-terra')"
assert_eq "pi: detection does not override the explicit model" "0" \
  "$(printf '%s\n' "${BASE_FLAGS[@]}" | grep -cx 'should-not-be-used')"
assert_eq "pi: detection still fills the effort left unset" "1" \
  "$(printf '%s\n' "${BASE_FLAGS[@]}" | grep -cx 'high')"
unset -f detect_override

detect_override(){ DETECTED_MODEL="amd-gateway/gpt-5.6-terra"; DETECTED_EFFORT="should-not-be-used"; }
herdr(){ case "$1 $2" in "agent list") printf '%s' "$MOCK_AGENTS_PI";; "pane process-info") printf '%s' "$MOCK_PROC_PI_BARE";; "agent get") echo '{"result":{"agent":{"agent_status":"idle"}}}';; *) echo "{}";; esac; }
OVERRIDE_NAME=""; OVERRIDE_MODEL=""; OVERRIDE_EFFORT="high"
ROTATE_SETTLE_POLL_SECS=1 resolve_and_prepare pi worker
assert_eq "pi: explicit effort override survives alongside detection filling model" "1" \
  "$(printf '%s\n' "${BASE_FLAGS[@]}" | grep -cx 'high')"
assert_eq "pi: detection does not override the explicit effort" "0" \
  "$(printf '%s\n' "${BASE_FLAGS[@]}" | grep -cx 'should-not-be-used')"
assert_eq "pi: detection still fills the model left unset" "1" \
  "$(printf '%s\n' "${BASE_FLAGS[@]}" | grep -cx 'amd-gateway/gpt-5.6-terra')"
unset -f detect_override
MODEL_FLAG=--model MODEL_FLAG_ALIASES=() EFFORT_FLAG=--effort EFFORT_STYLE=flag

# run_handoff / run_finish early-exit paths (no herdr contact needed; guard/parse fail first)
MODEL_FLAG=--model EFFORT_FLAG=--effort EFFORT_STYLE=flag
( HERDR_ENV=0; run_handoff claude foo >/dev/null 2>&1 ); assert_eq "handoff no-op outside herdr" "0" "$?"
( HERDR_ENV=0; run_finish claude foo /tmp/x.md >/dev/null 2>&1 ); assert_eq "finish no-op outside herdr" "0" "$?"
( HERDR_ENV=1; herdr(){ :;}; run_handoff claude --bogus x >/dev/null 2>&1 ); assert_eq "handoff unknown option dies" "1" "$?"
( HERDR_ENV=1; herdr(){ :;}; run_handoff claude --model >/dev/null 2>&1 ); assert_eq "handoff missing value dies" "1" "$?"
( HERDR_ENV=1; herdr(){ :;}; run_handoff claude a b >/dev/null 2>&1 ); assert_eq "handoff extra positional dies" "1" "$?"
( HERDR_ENV=1; herdr(){ :;}; run_handoff claude a --kickoff off >/dev/null 2>&1 ); assert_eq "handoff rejects --kickoff (any value, including the off sentinel)" "1" "$?"
( HERDR_ENV=1; herdr(){ :;}; run_handoff claude a --kickoff "some message" >/dev/null 2>&1 ); assert_eq "handoff rejects --kickoff with a real message too" "1" "$?"
( HERDR_ENV=1; herdr(){ :;}; run_finish claude a >/dev/null 2>&1 ); assert_eq "finish missing handoff-path positional dies" "1" "$?"
( HERDR_ENV=1; herdr(){ :;}; run_finish claude a /no/such/file.md >/dev/null 2>&1 ); assert_eq "finish missing handoff file dies" "1" "$?"

# An explicitly empty --kickoff value is otherwise indistinguishable from omitting the flag
# entirely (both would leave KICKOFF=""), so it must be rejected at parse time -- BEFORE any
# herdr interaction, not merely happen to die downstream for an unrelated reason. A no-op herdr
# mock (as used for the early-exit tests above) can't tell these apart: it dies either way (from
# resolve()'s own "agent list failed" once past parse_args), so a real, successful-looking mock
# is needed to prove the old code did NOT reject this and instead ran the rotation to completion.
herdr(){
  case "$1 $2" in
    "agent list") printf '%s' "$MOCK_AGENTS" ;;
    "agent prompt") echo '{"result":{}}' ;;
    *) echo "{}" ;;
  esac
}
( HERDR_ENV=1 run_handoff claude lead --kickoff "" >/dev/null 2>&1 )
assert_eq "handoff rejects an explicitly empty --kickoff value (old code would silently send the handoff prompt instead)" "1" "$?"

# Same gap for finish, which needs the full exit/relaunch/verify/kickoff path mocked to
# completion to prove the discriminating point: the old code let "--kickoff ''" fall through
# untouched, and kickoff() itself treats an empty message exactly like "not given at all" (sends
# the DEFAULT continue-the-handoff message) -- so the old code doesn't just fail to reject it, it
# actively reports the whole rotation "complete".
HF_KICKOFF=$(mktemp); printf 'handoff body\n' > "$HF_KICKOFF"
LOCKROOT_KICKOFF=$(mktemp -d)
MOCK_PROC_FINISH_KICKOFF=$(jq -nc '{result:{process_info:{foreground_processes:[{name:"claude",argv:["claude","--verbose"]}]}}}')
CNT_WG4_KICKOFF=$(mktemp); echo 0 > "$CNT_WG4_KICKOFF"
herdr(){
  case "$1 $2" in
    "agent list") printf '%s' "$MOCK_AGENTS" ;;
    "pane process-info") printf '%s' "$MOCK_PROC_FINISH_KICKOFF" ;;
    "agent prompt") echo '{"result":{}}' ;;
    "agent get")
      if [ "$3" = lead ]; then echo '{"result":{"agent":{"agent_status":"idle"}}}'
      else
        # First call (wait_settled) reports idle so the rotation can proceed; every call after
        # that (exit_agent's gone() polling) reports not_found, combined with "pane read" below,
        # so exit_agent sees the old agent as already gone and relaunch can proceed.
        local n; n=$(cat "$CNT_WG4_KICKOFF"); echo $((n+1)) > "$CNT_WG4_KICKOFF"
        if [ "$n" -eq 0 ]; then echo '{"result":{"agent":{"agent_status":"idle"}}}'
        else echo '{"error":{"code":"agent_not_found"}}' >&2; return 1; fi
      fi ;;
    "pane read") printf 'user@host:~$ \n' ;;
    "agent start") echo '{"result":{"agent":{}}}' ;;
    *) echo "{}" ;;
  esac
}
( HERDR_ENV=1 ROTATE_LOCK_ROOT="$LOCKROOT_KICKOFF" ROTATE_SETTLE_POLL_SECS=2 ROTATE_EXIT_POLL_SECS=2 ROTATE_VERIFY_POLL_SECS=2 \
  run_finish claude lead "$HF_KICKOFF" --kickoff "" >/dev/null 2>&1 )
assert_eq "finish rejects an explicitly empty --kickoff value (old code would silently complete using the default kickoff message instead)" "1" "$?"
rm -f "$HF_KICKOFF" "$CNT_WG4_KICKOFF"; rm -rf "$LOCKROOT_KICKOFF"

echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
