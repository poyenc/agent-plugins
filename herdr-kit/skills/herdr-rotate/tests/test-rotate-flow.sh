#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; S="$HERE/../../scripts"
PASS=0; FAIL=0
assert_eq(){ if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; echo "    exp:[$2] act:[$3]"; FAIL=$((FAIL+1)); fi; }

setup(){ # $1=kind $2=name  -> exports fresh state + PATH
  export TMPDIR; TMPDIR=$(mktemp -d)
  export MOCK_STATE; MOCK_STATE=$(mktemp -d)
  export MOCK_CALLS="$MOCK_STATE/calls"; : > "$MOCK_CALLS"
  export MOCK_KIND="$1" MOCK_PANE="wG:p4" MOCK_NAME="$2"
  unset MOCK_VERIFY_ARGV MOCK_COLLISION_NAME MOCK_COLLISION_PANE MOCK_FAIL_KICKOFF \
        MOCK_PANE_CHANGE_AFTER MOCK_PANE_2 MOCK_SESSION MOCK_SESSION_2 MOCK_SESSION_CHANGE_AFTER \
        MOCK_CLAUDE_MODAL_STUCK MOCK_PI_MODAL_STUCK
  printf -- '--model\nopus\n--verbose\n' > "$MOCK_STATE/argv"   # original launch flags
  export PATH="$HERE/mock:$PATH"
  export ROTATE_EXIT_POLL_SECS=5 ROTATE_VERIFY_POLL_SECS=5 ROTATE_DETECT_POLL_SECS=1
  export HERDR_PANE_ID=wG:p1
  # Isolated per-test lock/token namespace -- NEVER the real production
  # /tmp/herdr-rotate-lock-<user> path, which real concurrent rotations on this machine may
  # depend on. A test that needs to inspect/corrupt the lock directory (symlink probes, held
  # locks) must only ever touch this private one.
  export ROTATE_LOCK_ROOT="$TMPDIR"
  HANDOFF_PATH=$(mktemp); printf '# handoff\n' > "$HANDOFF_PATH"
}
run(){ HERDR_ENV=1 bash "$@" ; }   # returns exit code

# 1. happy claude flow: handoff then finish (two separate invocations, no shared state file)
setup claude lead
run "$S/herdr-rotate-claude" handoff lead >/dev/null 2>&1; assert_eq "handoff exit 0" "0" "$?"
assert_eq "handoff sends exactly one handoff prompt" "1" "$(grep -c 'Write a handoff' "$MOCK_CALLS")"
assert_eq "handoff does not quit"               "0" "$(grep -c '/quit' "$MOCK_CALLS")"
assert_eq "handoff does not relaunch"           "0" "$(grep -c 'agent start' "$MOCK_CALLS")"
run "$S/herdr-rotate-claude" finish lead "$HANDOFF_PATH" >/dev/null 2>&1; assert_eq "finish exit 0" "0" "$?"
ho=$(grep -n 'agent prompt' "$MOCK_CALLS" | head -n1 | cut -d: -f1)
q=$(grep -n '/quit' "$MOCK_CALLS" | head -n1 | cut -d: -f1)
st=$(grep -n 'agent start' "$MOCK_CALLS" | head -n1 | cut -d: -f1)
assert_eq "order handoff<quit" "1" "$([ "$ho" -lt "$q" ] && echo 1 || echo 0)"
assert_eq "order quit<start"  "1" "$([ "$q" -lt "$st" ] && echo 1 || echo 0)"
assert_eq "started argv preserved" $'--model\nopus\n--verbose' "$(cat "$MOCK_STATE/argv")"

# 2. finish with a missing/empty handoff path -> no /quit, no start, non-zero
setup claude lead
run "$S/herdr-rotate-claude" finish lead /no/such/handoff.md >/dev/null 2>&1
assert_eq "missing handoff-file non-zero" "1" "$?"
assert_eq "no /quit on missing handoff-file"  "0" "$(grep -c '/quit' "$MOCK_CALLS")"
assert_eq "no start on missing handoff-file"  "0" "$(grep -c 'agent start' "$MOCK_CALLS")"

# 3. override must be repeated at finish to reach the relaunch argv (nothing persists between calls)
setup claude lead
run "$S/herdr-rotate-claude" handoff lead --model sonnet --effort high >/dev/null 2>&1
assert_eq "override NOT yet in argv (handoff never relaunches)" "0" "$(grep -cx 'sonnet' "$MOCK_STATE/argv")"
run "$S/herdr-rotate-claude" finish lead "$HANDOFF_PATH" --model sonnet --effort high >/dev/null 2>&1
assert_eq "override in started argv" "1" "$(grep -cx 'sonnet' "$MOCK_STATE/argv")"

# 3a. a rotation where nothing changed (no explicit override, live-detected model/effort equal to
# launch) must leave the relaunch argv byte-for-byte identical to the original -- proving Tasks
# 1-3 work together through the real handoff/finish dispatch, not just in isolated unit tests.
setup claude lead
printf -- '--model\nhaiku\n--effort\nmedium\n--verbose\n' > "$MOCK_STATE/argv"
run "$S/herdr-rotate-claude" handoff lead >/dev/null 2>&1
run "$S/herdr-rotate-claude" finish lead "$HANDOFF_PATH" >/dev/null 2>&1
assert_eq "no-change rotation: finish exit 0" "0" "$?"
assert_eq "no-change rotation: relaunch argv byte-for-byte unchanged" $'--model\nhaiku\n--effort\nmedium\n--verbose' "$(cat "$MOCK_STATE/argv")"

# 3b. an explicit override at finish still replaces in place -- no duplicate flag in the relaunch
# argv.
setup claude lead
printf -- '--model\nhaiku\n--effort\nmedium\n' > "$MOCK_STATE/argv"
run "$S/herdr-rotate-claude" handoff lead >/dev/null 2>&1
run "$S/herdr-rotate-claude" finish lead "$HANDOFF_PATH" --model sonnet >/dev/null 2>&1
assert_eq "explicit override: finish exit 0" "0" "$?"
assert_eq "explicit override replaces in place, no duplicate --model" "1" "$(grep -cx -- '--model' "$MOCK_STATE/argv")"
assert_eq "explicit override: new value present" $'--model\nsonnet\n--effort\nmedium' "$(cat "$MOCK_STATE/argv")"

# 4. verify mismatch -> non-zero
setup claude lead
printf -- '--model\nhaiku\n' > "$MOCK_STATE/wrong"; export MOCK_VERIFY_ARGV="$MOCK_STATE/wrong"
run "$S/herdr-rotate-claude" handoff lead >/dev/null 2>&1
run "$S/herdr-rotate-claude" finish lead "$HANDOFF_PATH" >/dev/null 2>&1; assert_eq "verify mismatch non-zero" "1" "$?"
assert_eq "kickoff withheld on verify failure" "0" "$(grep -c 'Continue the work described' "$MOCK_CALLS")"

# 4a2. a failed kickoff send must NOT be reported as a completed rotation -- the new agent is
# correctly relaunched and verified, but was never actually told to resume.
setup claude lead
run "$S/herdr-rotate-claude" handoff lead >/dev/null 2>&1
export MOCK_FAIL_KICKOFF=1
run "$S/herdr-rotate-claude" finish lead "$HANDOFF_PATH" >/dev/null 2>&1
assert_eq "failed kickoff send is non-zero, not silent success" "1" "$?"
assert_eq "failed kickoff still relaunched (not a verify/pre-flight failure)" "1" "$(grep -c 'agent start' "$MOCK_CALLS")"
unset MOCK_FAIL_KICKOFF

# 4b. pi verify is screen-based (model/effort), not argv-based -- pi's own process.title rewrite
# makes argv comparison always fail for pi (confirmed live), so verify() must catch a real
# mismatch via the live /settings+/model reading instead, and still pass when they genuinely match.
setup pi worker
run "$S/herdr-rotate-pi" handoff worker --model amd-gateway/gpt-5.6-terra --effort high >/dev/null 2>&1
run "$S/herdr-rotate-pi" finish worker "$HANDOFF_PATH" --model amd-gateway/gpt-5.6-terra --effort high >/dev/null 2>&1
assert_eq "pi verify OK on genuine match" "0" "$?"

setup pi worker
printf -- '--model\nwrong-provider/wrong-model\n--thinking\nlow\n' > "$MOCK_STATE/wrong"; export MOCK_VERIFY_ARGV="$MOCK_STATE/wrong"
run "$S/herdr-rotate-pi" handoff worker --model amd-gateway/gpt-5.6-terra --effort high >/dev/null 2>&1
run "$S/herdr-rotate-pi" finish worker "$HANDOFF_PATH" --model amd-gateway/gpt-5.6-terra --effort high >/dev/null 2>&1
assert_eq "pi verify mismatch non-zero" "1" "$?"
unset MOCK_VERIFY_ARGV

# 4c. predictable relaunch failures are caught BEFORE the destructive step (exit_agent),
# not discovered only after the old agent is already gone.
setup claude lead
printf -- '--model\nop\x01us\n' > "$MOCK_STATE/argv"   # a control char (0x01) embedded in a captured flag
run "$S/herdr-rotate-claude" handoff lead >/dev/null 2>&1
run "$S/herdr-rotate-claude" finish lead "$HANDOFF_PATH" >/dev/null 2>&1
assert_eq "control-char argv rejected non-zero" "1" "$?"
assert_eq "control-char rejection is before /quit"  "0" "$(grep -c '/quit' "$MOCK_CALLS")"
assert_eq "control-char rejection is before start"  "0" "$(grep -c 'agent start' "$MOCK_CALLS")"

setup claude lead
export MOCK_COLLISION_NAME="lead" MOCK_COLLISION_PANE="wG:pOTHER"
run "$S/herdr-rotate-claude" handoff lead >/dev/null 2>&1
run "$S/herdr-rotate-claude" finish lead "$HANDOFF_PATH" >/dev/null 2>&1
assert_eq "name collision rejected non-zero" "1" "$?"
assert_eq "name collision rejection is before /quit"  "0" "$(grep -c '/quit' "$MOCK_CALLS")"
assert_eq "name collision rejection is before start"  "0" "$(grep -c 'agent start' "$MOCK_CALLS")"

# 4d. finish refuses to run against a pane that already has another finish in progress --
# proven by holding the exact lock finish itself would take, then confirming it stops
# immediately (not racing exit/relaunch) instead of proceeding.
setup claude lead
run "$S/herdr-rotate-claude" handoff lead >/dev/null 2>&1
lock_dir="$ROTATE_LOCK_ROOT/herdr-rotate-lock-$(id -un)"; mkdir -m 700 -p "$lock_dir"
lock_file="$lock_dir/$(printf '%s' "$MOCK_PANE" | tr -c 'A-Za-z0-9' '_').lock"
exec {HELD_FD}>"$lock_file"; flock "$HELD_FD"
run "$S/herdr-rotate-claude" finish lead "$HANDOFF_PATH" >/dev/null 2>&1
assert_eq "locked-pane finish rejected non-zero" "1" "$?"
assert_eq "locked-pane rejection is before /quit"  "0" "$(grep -c '/quit' "$MOCK_CALLS")"
assert_eq "locked-pane rejection is before start"  "0" "$(grep -c 'agent start' "$MOCK_CALLS")"
flock -u "$HELD_FD"; exec {HELD_FD}>&-
unset MOCK_COLLISION_NAME MOCK_COLLISION_PANE

# 4d2. finish refuses to use the lock directory if something other than a real, owned
# directory already sits at its path (e.g. a symlink) -- and must reject it WITHOUT ever
# chmod'ing (mutating) whatever the symlink points at. Uses ROTATE_LOCK_ROOT's fresh, private,
# per-test directory -- never the real production lock namespace under /tmp.
setup claude lead
run "$S/herdr-rotate-claude" handoff lead >/dev/null 2>&1
lock_dir="$ROTATE_LOCK_ROOT/herdr-rotate-lock-$(id -un)"
victim=$(mktemp -d); chmod 755 "$victim"
ln -s "$victim" "$lock_dir"
mode_before=$(stat -c %a "$victim")
run "$S/herdr-rotate-claude" finish lead "$HANDOFF_PATH" >/dev/null 2>&1
assert_eq "symlinked lock dir rejected non-zero" "1" "$?"
assert_eq "symlink target permissions untouched" "$mode_before" "$(stat -c %a "$victim")"
rm -rf "$victim"

# 4e. finish is single-use per handoff: a second finish call with the IDENTICAL tag+path (same
# pane, same handoff document) must be rejected -- the pane lock alone only prevents
# SIMULTANEOUS calls, not this SEQUENTIAL replay after the first one already completed and
# released it (the concrete risk for pi/codex, which have no session id to catch a stale ping).
setup claude lead
run "$S/herdr-rotate-claude" handoff lead >/dev/null 2>&1
run "$S/herdr-rotate-claude" finish lead "$HANDOFF_PATH" >/dev/null 2>&1
assert_eq "first finish with this handoff succeeds" "0" "$?"
run "$S/herdr-rotate-claude" finish lead "$HANDOFF_PATH" >/dev/null 2>&1
assert_eq "replayed finish with same handoff rejected non-zero" "1" "$?"
assert_eq "replay does not /quit a second time" "1" "$(grep -c '/quit' "$MOCK_CALLS")"

# 4f. ...but a LATER, unrelated rotation that legitimately reuses the same stable filename (the
# handoff prompt permits choosing one instead of the timestamped default) must NOT be rejected
# as a replay once the file's actual CONTENT has changed -- only an exact, byte-for-byte
# unchanged replay is a true replay (keyed on content, not path/metadata alone: a `touch` with
# no content change must NOT be enough to bypass the single-use check -- see 4g below).
stable_path=$(mktemp)
printf '# handoff v1\n' > "$stable_path"
setup claude lead
run "$S/herdr-rotate-claude" handoff lead >/dev/null 2>&1
run "$S/herdr-rotate-claude" finish lead "$stable_path" >/dev/null 2>&1
assert_eq "first finish at a stable (non-timestamped) path succeeds" "0" "$?"
# No setup() call in between -- must stay in the SAME lock/token namespace (ROTATE_LOCK_ROOT)
# as the first call, exactly like production would, only the content changes.
printf '# handoff v2 -- a later, unrelated rotation reusing the same path\n' > "$stable_path"
run "$S/herdr-rotate-claude" handoff lead >/dev/null 2>&1
run "$S/herdr-rotate-claude" finish lead "$stable_path" >/dev/null 2>&1
assert_eq "later rotation reusing the same path with new content succeeds" "0" "$?"

# 4g. ...and merely touching the SAME unchanged content (metadata-only change: inode/mtime/
# size can all differ after a touch) must NOT be enough to bypass single-use -- identity is
# keyed on content, so this is still a true replay of the same handoff.
touch_path=$(mktemp)
printf '# handoff, unchanged\n' > "$touch_path"
setup claude lead
run "$S/herdr-rotate-claude" handoff lead >/dev/null 2>&1
run "$S/herdr-rotate-claude" finish lead "$touch_path" >/dev/null 2>&1
assert_eq "first finish before touch succeeds" "0" "$?"
touch -d '2035-01-01 00:00:00 UTC' "$touch_path"   # metadata changed, content byte-for-byte unchanged
run "$S/herdr-rotate-claude" handoff lead >/dev/null 2>&1
run "$S/herdr-rotate-claude" finish lead "$touch_path" >/dev/null 2>&1
assert_eq "touched-but-unchanged content is still rejected as a replay" "1" "$?"

# 5. pi bare-model override rejected BEFORE destructive steps, at both phases
setup pi worker
run "$S/herdr-rotate-pi" handoff worker --model bareword >/dev/null 2>&1; assert_eq "pi bare model rejected at handoff" "1" "$?"
assert_eq "pi handoff rejection sends no prompt" "0" "$(grep -c 'agent prompt' "$MOCK_CALLS")"
run "$S/herdr-rotate-pi" handoff worker >/dev/null 2>&1
run "$S/herdr-rotate-pi" finish worker "$HANDOFF_PATH" --model bareword >/dev/null 2>&1; assert_eq "pi bare model rejected at finish" "1" "$?"
assert_eq "pi finish rejects before /quit"  "0" "$(grep -c '/quit' "$MOCK_CALLS")"
assert_eq "pi finish rejects before start"  "0" "$(grep -c 'agent start' "$MOCK_CALLS")"

# 5b. pi finish rejected BEFORE exit_agent when neither the original argv nor live detection
# produced a model/effort value to verify against (no --model/--effort override given either) --
# the round-11 fix for verify()'s vacuous-pass gap, checked here as an actual pre-flight
# rejection rather than only inside verify() after the old agent is already gone.
setup pi worker
run "$S/herdr-rotate-pi" handoff worker >/dev/null 2>&1
run "$S/herdr-rotate-pi" finish worker "$HANDOFF_PATH" >/dev/null 2>&1
assert_eq "pi missing model/effort rejected non-zero" "1" "$?"
assert_eq "pi missing model/effort rejection is before /quit"  "0" "$(grep -c '/quit' "$MOCK_CALLS")"
assert_eq "pi missing model/effort rejection is before start"  "0" "$(grep -c 'agent start' "$MOCK_CALLS")"

# 5c. a moved/rebound name is caught immediately after the second resolve, before any further
# live interaction (settle-wait, argv capture, model/effort detection) touches the wrong pane --
# not just before the final destructive step.
setup claude lead
# No prior handoff call here -- it would consume the mock's shared "agent list" call counter,
# shifting exactly which call (the pre-lock resolve vs. resolve_and_prepare's own resolve)
# MOCK_PANE_CHANGE_AFTER lands on.
export MOCK_PANE_CHANGE_AFTER=1 MOCK_PANE_2=wG:pOTHER
run "$S/herdr-rotate-claude" finish lead "$HANDOFF_PATH" >/dev/null 2>&1
assert_eq "rebound pane rejected non-zero" "1" "$?"
assert_eq "rebound pane rejection is before /quit"   "0" "$(grep -c '/quit' "$MOCK_CALLS")"
assert_eq "rebound pane rejection is before start"   "0" "$(grep -c 'agent start' "$MOCK_CALLS")"
assert_eq "rebound pane rejection is before /status" "0" "$(grep -c '/status' "$MOCK_CALLS")"
unset MOCK_PANE_CHANGE_AFTER MOCK_PANE_2

# 5d. finish refuses to use a lock FILE if a dangling symlink already sits at that path --
# without following it to create/truncate whatever it points at.
setup claude lead
run "$S/herdr-rotate-claude" handoff lead >/dev/null 2>&1
lock_dir="$ROTATE_LOCK_ROOT/herdr-rotate-lock-$(id -un)"; mkdir -m 700 -p "$lock_dir"
victim2=$(mktemp -u)   # a path that does not exist -- a dangling symlink target
lock_file="$lock_dir/$(printf '%s' "$MOCK_PANE" | tr -c 'A-Za-z0-9' '_').lock"
ln -s "$victim2" "$lock_file"
run "$S/herdr-rotate-claude" finish lead "$HANDOFF_PATH" >/dev/null 2>&1
assert_eq "dangling lock-file symlink rejected non-zero" "1" "$?"
assert_eq "dangling symlink target was never created" "0" "$([ -e "$victim2" ] && echo 1 || echo 0)"
rm -f "$lock_file"

# 5e. token claim happens only AFTER revalidate_session succeeds -- a legitimate revalidation
# failure (the pane's live session changed just before the destructive step) must not burn the
# token, so a corrected retry with the SAME handoff path can still succeed afterward.
setup claude lead
export MOCK_SESSION="aaaaaaaa-1111-2222-3333-444444444444" MOCK_SESSION_2="bbbbbbbb-1111-2222-3333-444444444444"
export MOCK_SESSION_CHANGE_AFTER=3   # 4th "agent list" call is revalidate_session's own check
run "$S/herdr-rotate-claude" finish 'lead@aaaaaaaa' "$HANDOFF_PATH" >/dev/null 2>&1
assert_eq "revalidation failure rejected non-zero" "1" "$?"
assert_eq "revalidation failure is before /quit" "0" "$(grep -c '/quit' "$MOCK_CALLS")"
unset MOCK_SESSION_CHANGE_AFTER
run "$S/herdr-rotate-claude" finish 'lead@aaaaaaaa' "$HANDOFF_PATH" >/dev/null 2>&1
assert_eq "retry with same handoff after revalidation failure succeeds" "0" "$?"
unset MOCK_SESSION MOCK_SESSION_2

# 5f. handoff no longer probes the target's UI at all -- capture_argv/detect_override moved
# exclusively into finish (their result was previously discarded by handoff; see
# resolve_and_validate/resolve_and_prepare in rotate-common.sh), so a pre-existing stuck modal on
# the target must NOT block handoff from sending its prompt any more.
setup claude lead
export MOCK_CLAUDE_MODAL_STUCK=1
run "$S/herdr-rotate-claude" handoff lead >/dev/null 2>&1
assert_eq "claude stuck modal no longer blocks handoff" "0" "$?"
assert_eq "claude stuck modal handoff still sends its prompt" "1" "$(grep -c 'Write a handoff' "$MOCK_CALLS")"
unset MOCK_CLAUDE_MODAL_STUCK

# 5f2. finish's own DEFENSIVE close_modal (a pre-existing modal, not one we opened) must still
# abort the whole rotation if it's confirmed stuck, not just skip live detection and proceed to
# exit/relaunch against a target whose UI state is unknown -- detect_override now runs
# exclusively here, not at handoff.
setup claude lead
export MOCK_CLAUDE_MODAL_STUCK=1
run "$S/herdr-rotate-claude" finish lead "$HANDOFF_PATH" >/dev/null 2>&1
assert_eq "claude stuck defensive modal aborts finish non-zero" "1" "$?"
assert_eq "claude stuck modal finish never reaches /quit" "0" "$(grep -c '/quit' "$MOCK_CALLS")"
unset MOCK_CLAUDE_MODAL_STUCK

# 5g. same for pi: handoff no longer probes its UI either, so a pre-existing stuck picker must
# not block it.
setup pi worker
echo 1 > "$MOCK_STATE/pi_modal_open"   # a picker already open before detect_override even runs
export MOCK_PI_MODAL_STUCK=1 ROTATE_DETECT_POLL_SECS=1
run "$S/herdr-rotate-pi" handoff worker >/dev/null 2>&1
assert_eq "pi stuck modal no longer blocks handoff" "0" "$?"
assert_eq "pi stuck modal handoff still sends its prompt" "1" "$(grep -c 'Write a handoff' "$MOCK_CALLS")"
unset MOCK_PI_MODAL_STUCK

# 5g2. pi's detect_override must still abort finish (not silently proceed) if a picker is
# confirmed stuck open -- exercised at finish, where a pre-existing stuck picker is discovered by
# the very first defensive close_modal call.
setup pi worker
echo 1 > "$MOCK_STATE/pi_modal_open"
export MOCK_PI_MODAL_STUCK=1 ROTATE_DETECT_POLL_SECS=1
run "$S/herdr-rotate-pi" finish worker "$HANDOFF_PATH" >/dev/null 2>&1
assert_eq "pi stuck modal aborts finish non-zero" "1" "$?"
assert_eq "pi stuck modal finish never reaches /quit" "0" "$(grep -c '/quit' "$MOCK_CALLS")"
unset MOCK_PI_MODAL_STUCK

# 6. dispatcher routes by kind + forwards (kind=pi) and succeeds across both phases
setup pi worker
run "$S/herdr-rotate" handoff worker --model amd-gateway/gpt-5.6-terra --effort high >/dev/null 2>&1; assert_eq "dispatch handoff pi exit 0" "0" "$?"
run "$S/herdr-rotate" finish worker "$HANDOFF_PATH" --model amd-gateway/gpt-5.6-terra --effort high >/dev/null 2>&1; assert_eq "dispatch finish pi exit 0" "0" "$?"
assert_eq "dispatch forwarded override" "1" "$(grep -cx 'amd-gateway/gpt-5.6-terra' "$MOCK_STATE/argv")"

# 6b. dispatcher resolves target correctly when a value-flag precedes it
setup pi worker
run "$S/herdr-rotate" handoff --model amd-gateway/gpt-5.6-terra --effort high worker >/dev/null 2>&1; assert_eq "dispatch flag-before-target handoff exit 0" "0" "$?"
run "$S/herdr-rotate" finish --model amd-gateway/gpt-5.6-terra --effort high worker "$HANDOFF_PATH" >/dev/null 2>&1; assert_eq "dispatch flag-before-target finish exit 0" "0" "$?"
assert_eq "dispatch flag-before-target forwarded override" "1" "$(grep -cx 'amd-gateway/gpt-5.6-terra' "$MOCK_STATE/argv")"

# 7. no-op via per-kind exec outside herdr (no herdr calls), both subcommands
setup claude lead
( env -u HERDR_ENV bash "$S/herdr-rotate-claude" handoff lead >/dev/null 2>&1 ); assert_eq "handoff no-op exit 0" "0" "$?"
( env -u HERDR_ENV bash "$S/herdr-rotate-claude" finish lead "$HANDOFF_PATH" >/dev/null 2>&1 ); assert_eq "finish no-op exit 0" "0" "$?"
assert_eq "no-op made no herdr calls" "0" "$(wc -l < "$MOCK_CALLS" | tr -d ' ')"

echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
