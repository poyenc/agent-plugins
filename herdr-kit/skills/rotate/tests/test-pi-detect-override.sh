#!/usr/bin/env bash
# Direct unit tests for herdr-rotate-pi's detect_override and close_modal.
#
# Part 1 isolates the "recovery" close_modal call (fired when the settings picker never rendered
# during the initial wait, but turns out to still be open -- and stuck -- once that recovery
# close checks it). Not reachable as a meaningful end-to-end regression test via the full
# handoff/finish/verify machinery: set -e's own default behavior already aborts the handoff path
# regardless of this branch's own explicit propagation, and pi's verify() model/effort mismatch
# check already independently catches a never-rendered picker during the finish path -- both mask
# a broken `|| return 1` here. This calls detect_override directly instead, so its own return
# code is what's actually asserted. close_modal itself is STUBBED for this part -- the point here
# is detect_override's own call-count/propagation logic, not close_modal's internals (see Part 2
# for those).
#
# Part 2 exercises the REAL close_modal against the failure modes confirmed live this session (a
# real pi agent, throwaway pane, `herdr agent prompt`/`herdr pane read`, including a real
# 40-column narrow pane):
#   (a) a single matching (marker-absent) read is not sufficient evidence of closed -- two
#       consecutive clean polls are required, so a one-cycle flicker/race can't be mistaken for
#       genuine closure;
#   (b) the raw command text just sent (e.g. "/model") sitting alone on its own line, with NO
#       known marker present, must NOT be read as closed either -- confirmed live that a fresh
#       pi session's first /settings or /model can leave exactly that echoed for many
#       consecutive seconds while its catalog loads, before the picker actually renders;
#   (c) Escape is resent only while NOT yet clean, never on a round that already was -- confirmed
#       live that blindly resending Escape into an already-idle pane (every round,
#       unconditionally, as an earlier version of this function did) can trigger an unrelated pi
#       keybinding (reproduced: repeated Escapes after a picker had already closed opened pi's
#       own "Session Tree" browser) -- a new, self-inflicted problem, not progress toward closing
#       anything.
#
# A width-independent snapshot-EQUALITY design (compare against a baseline captured before
# opening, instead of any marker text) was tried and rejected before this: it produced spurious
# "never closes" failures in two separate live end-to-end runs even once the picker was
# genuinely closed and the correct value already read -- see close_modal's own comment. The
# SHORT, STATIC, CONTENT-INDEPENDENT markers used below (PI_SETTINGS_MARKER, PI_MODEL_SCOPE_
# MARKER) don't have that fragility, and were chosen specifically to survive the narrow-pane
# truncation/wrapping that broke the ORIGINAL (longer, value-dependent) markers -- see their own
# comment in herdr-rotate-pi for exactly what broke and why.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/../../scripts"
PASS=0; FAIL=0
assert_eq(){ if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; echo "    exp:[$2] act:[$3]"; FAIL=$((FAIL+1)); fi; }

# shellcheck source=SCRIPTDIR/../../scripts/herdr-rotate-pi
source "$S/herdr-rotate-pi"
set +e   # herdr-rotate-pi's own `set -e` (imported by sourcing) would otherwise abort THIS
         # script the moment detect_override below returns the very failure being tested for.

# Stub close_modal directly rather than driving it through herdr/wall-clock polling, so which
# invocation is "stuck" is asserted by call count, not by timing -- a poll loop that happens to
# run zero iterations can't produce a false pass this way (unlike gating on ROTATE_DETECT_POLL_
# SECS elapsing, which a prior version of this test did and which could vacuously pass without
# ever reaching the branch under test).
# Call 1 = the defensive pre-close before anything is opened by us -- succeeds (nothing open).
# Call 2 = the recovery close at the "settings picker never rendered" branch -- stuck.
close_modal_calls=0
close_modal(){
  close_modal_calls=$((close_modal_calls+1))
  [ "$close_modal_calls" -ge 2 ] && return 1
  return 0
}
# The render-wait poll checks pane read for the settings marker directly (not through
# close_modal) -- stub herdr so it never shows one, so seen stays 0 (reaching the branch under
# test) regardless of how many times, if any, that poll loop actually iterates.
herdr(){
  case "$1 $2" in
    "agent prompt") echo '{"result":{}}' ;;
    "pane read")    echo "agent ui drawing" ;;
    *) echo '{"result":{}}' ;;
  esac
}
ROTATE_DETECT_POLL_SECS=0

detect_override wG:p4 >/dev/null 2>&1
assert_eq "recovery close_modal propagates a stuck picker (detect_override returns 1)" "1" "$?"
assert_eq "close_modal was called exactly twice (defensive pre-close, then recovery)" "2" "$close_modal_calls"

# --- Part 2: the REAL close_modal, unstubbed -----------------------------------------------
# Re-source to restore herdr-rotate-pi's own real close_modal -- `unset -f` alone can't bring it
# back, since Part 1's local definition above permanently replaced the sourced one, not merely
# shadowed it.
source "$S/herdr-rotate-pi"
set +e
ROTATE_DETECT_POLL_SECS=10

# herdr's own "pane read"/"agent send-keys" calls inside close_modal are captured via `$(...)`
# (the read) or run directly (the send-keys) -- a plain variable a mock incremented for either
# would not reliably persist back across a command-substitution subshell. File-based counters
# are used instead, matching this repo's own mock/herdr convention for the same reason.
READ_FILE=$(mktemp); ESC_FILE=$(mktemp)
read_count(){ cat "$READ_FILE" 2>/dev/null || echo 0; }
esc_count(){ cat "$ESC_FILE" 2>/dev/null || echo 0; }
mock_herdr_with_reads(){
  herdr(){
    case "$1 $2" in
      "agent send-keys") n=$(( $(esc_count) + 1 )); echo "$n" > "$ESC_FILE"; echo '{"result":{}}' ;;
      "pane read")
        n=$(( $(read_count) + 1 )); echo "$n" > "$READ_FILE"
        printf '%s\n' "${PANE_READS[$((n-1))]:-agent ui drawing}" ;;
      *) echo '{"result":{}}' ;;
    esac
  }
}

# (a): the marker stays present for two reads (still open), then genuinely absent -- requires
# TWO CONSECUTIVE clean polls (not one) before declaring closed.
PANE_READS=("Scope: all | scoped" "Scope: all | scoped" "agent ui drawing" "agent ui drawing")
echo 0 > "$READ_FILE"; echo 0 > "$ESC_FILE"
mock_herdr_with_reads
close_modal wG:p4 "$PI_MODEL_SCOPE_MARKER"
rc=$?
assert_eq "closes once the marker is absent on two consecutive reads" "0" "$rc"
assert_eq "all 4 scripted reads were consumed (didn't stop at the first clean read)" "4" "$(read_count)"

# (b): the reproduced pending-echo gap -- "/model" sitting alone on its own line (marker absent)
# must NOT be read as closed. Canned reads: 1-2 show the raw echo (no marker, but pending
# matches), 3 shows the picker fully open (marker present), 4-5 are genuinely clean.
PANE_READS=("/model" "/model" "Scope: all | scoped" "agent ui drawing" "agent ui drawing")
echo 0 > "$READ_FILE"; echo 0 > "$ESC_FILE"
close_modal wG:p4 "$PI_MODEL_SCOPE_MARKER" '^[[:space:]]*/model[[:space:]]*$'
rc=$?
assert_eq "pending-echo reads are not mistaken for closed" "0" "$rc"
assert_eq "all 5 scripted reads were consumed (didn't stop at the first marker-absent echo read)" "5" "$(read_count)"

# (c): once a read is already clean, no FURTHER Escape is sent unless it goes non-clean again --
# reproduced live that blindly resending Escape into an already-idle pane can trigger an
# unrelated pi keybinding (opened pi's own "Session Tree" browser). Reads: 1 has the marker
# present (still open), 2-3 are clean (the two confirming reads). Expected Escapes: the initial
# defensive one, plus exactly one more for read 1's non-clean result -- NOT a third for read 2
# (already clean).
PANE_READS=("Scope: all | scoped" "agent ui drawing" "agent ui drawing")
echo 0 > "$READ_FILE"; echo 0 > "$ESC_FILE"
close_modal wG:p4 "$PI_MODEL_SCOPE_MARKER"
rc=$?
assert_eq "closes correctly in the escape-count regression case" "0" "$rc"
assert_eq "exactly 2 escapes sent (initial + one for the non-clean read, none once already clean)" "2" "$(esc_count)"

rm -f "$READ_FILE" "$ESC_FILE"

# --- Part 3: rotate-common.sh's pi-tolerance branch, through resolve_and_prepare -----------
# The bare `detect_override "$ROTATE_PANE"` call in resolve_and_prepare (rotate-common.sh) is
# wrapped in a kind-specific tolerance for pi: a detect_override failure there should NOT abort
# resolve_and_prepare under set -e, and whatever DETECTED_MODEL/DETECTED_EFFORT it already
# populated before failing should still get promoted into OVERRIDE_MODEL/OVERRIDE_EFFORT. The
# only failure mode that actually matters here is a LATE one -- detect_override succeeding at
# reading both values, then failing only on its FINAL close_modal call (a picker it couldn't
# confirm closed after everything was already read) -- since an EARLY (defensive/first-call)
# failure never reaches this promotion logic at all: DETECTED_MODEL/DETECTED_EFFORT are still
# empty at that point, and run_finish's own separate, pre-existing preflight (which requires
# both to be non-empty before anything destructive runs) aborts identically whether or not this
# tolerance branch exists.
#
# Run as a SEPARATE bash subprocess with set -e genuinely active throughout (herdr-rotate-pi's
# own `set -euo pipefail`, never locally disabled) -- not sourced inline with `set +e` the way
# Parts 1/2 are. `set +e` is exactly what the real bug needs disabled to reproduce: with it on,
# a bare failing statement inside resolve_and_prepare would NOT abort the calling process either
# way, so a test written that way can't tell the fix apart from its absence (confirmed: an
# earlier version of this test passed identically against the pre-fix, bare-statement
# rotate-common.sh). The subprocess prints a survival marker only if it reaches the line after
# resolve_and_prepare; if set -e killed it instead, that marker (and the exit code) prove it.
PART3_SCRIPT=$(mktemp)
cat > "$PART3_SCRIPT" <<SCRIPT
source "$S/herdr-rotate-pi"
ROTATE_DETECT_POLL_SECS=10
unset HERDR_PANE_ID   # must not accidentally equal the mock pane below (would trip the
                       # self-rotation guard in resolve_and_validate)

close_modal_calls=0
close_modal(){
  close_modal_calls=\$((close_modal_calls+1))
  [ "\$close_modal_calls" -ge 3 ] && return 1
  return 0
}
herdr(){
  case "\$1 \$2" in
    "agent list") echo '{"result":{"agents":[{"agent":"pi","pane_id":"wG:p4","name":"worker"}]}}' ;;
    "pane process-info") echo '{"result":{"process_info":{"foreground_processes":[{"name":"pi","argv":["pi"]}]}}}' ;;
    "agent get") echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
    "agent prompt") echo '{"result":{}}' ;;
    "pane read")
      # Renders both pickers' markers unconditionally (matching this repo's own shared
      # mock/herdr's approach) -- close_modal itself is stubbed above, so only detect_override's
      # own bare open-detection reads ever reach this.
      printf 'Scope: all | scoped\nType to search \xc2\xb7 Enter/Space to change \xc2\xb7 Esc to cancel\nThinking level          high\ngpt-5.6-terra [amd-gateway] \xe2\x9c\x93\n' ;;
    *) echo '{"result":{}}' ;;
  esac
}
OVERRIDE_NAME="" OVERRIDE_MODEL="" OVERRIDE_EFFORT="" KICKOFF=""
resolve_and_prepare pi worker 0 ""
echo "SURVIVED=1;OVERRIDE_MODEL=\$OVERRIDE_MODEL;OVERRIDE_EFFORT=\$OVERRIDE_EFFORT;CLOSE_MODAL_CALLS=\$close_modal_calls"
SCRIPT
part3_out=$(bash "$PART3_SCRIPT" 2>/tmp/pi-part3-stderr.txt)
part3_rc=$?
rm -f "$PART3_SCRIPT" /tmp/pi-part3-stderr.txt
assert_eq "resolve_and_prepare does not abort on a late-only detect_override failure" "0" "$part3_rc"
assert_eq "subprocess reached the line after resolve_and_prepare (not killed by set -e)" "1" "$(printf '%s' "$part3_out" | grep -oE 'SURVIVED=[01]' | cut -d= -f2)"
assert_eq "close_modal was called exactly 3 times (defensive, settings-close, model-close)" "3" "$(printf '%s' "$part3_out" | grep -oE 'CLOSE_MODAL_CALLS=[0-9]+' | cut -d= -f2)"
assert_eq "OVERRIDE_MODEL promoted from the already-detected value despite the late failure" "amd-gateway/gpt-5.6-terra" "$(printf '%s' "$part3_out" | grep -oE 'OVERRIDE_MODEL=[^;]*' | cut -d= -f2)"
assert_eq "OVERRIDE_EFFORT promoted from the already-detected value despite the late failure" "high" "$(printf '%s' "$part3_out" | grep -oE 'OVERRIDE_EFFORT=[^;]*' | cut -d= -f2)"

echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
