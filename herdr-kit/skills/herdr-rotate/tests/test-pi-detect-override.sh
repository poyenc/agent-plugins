#!/usr/bin/env bash
# Direct unit test for herdr-rotate-pi's detect_override, isolating the "recovery" close_modal
# call (fired when the settings picker never rendered during the initial wait, but turns out to
# still be open -- and stuck -- once that recovery close checks it). Not reachable as a
# meaningful end-to-end regression test via the full handoff/finish/verify machinery: set -e's
# own default behavior already aborts the handoff path regardless of this branch's own explicit
# propagation, and pi's verify() model/effort mismatch check already independently catches a
# never-rendered picker during the finish path -- both mask a broken `|| return 1` here. This
# calls detect_override directly instead, so its own return code is what's actually asserted.
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

echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
