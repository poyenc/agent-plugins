#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=SCRIPTDIR/lib-wait-for-turn.sh
source "$HERE/lib-wait-for-turn.sh"
PASS=0; FAIL=0
assert_eq(){ if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; echo "    exp:[$2] act:[$3]"; FAIL=$((FAIL+1)); fi; }

# A confirmed working/blocked transition, then a confirmed settle -> succeeds.
herdr(){ case "$1 $2" in
  "agent get")  echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "agent wait") echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
  *) echo "{}" ;;
esac; }
( wait_for_turn who 2 1000 >/dev/null 2>&1 )
assert_eq "turn observed + settled succeeds" "0" "$?"

# The transition into working/blocked is never observed (status stays idle throughout) --
# must fail here rather than falling through to `agent wait`, which would otherwise report a
# STALE idle as if this turn had actually happened. `agent wait` here is stubbed to FAIL (not
# just to stay silent): if the observation guard were ever accidentally skipped or removed, this
# makes the accidental call surface as the OTHER failure message instead of the assertion below
# passing vacuously.
herdr(){ case "$1 $2" in
  "agent get")  echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
  "agent wait") echo '{"error":{"code":"timeout"}}' >&2; return 1 ;;
  *) echo "{}" ;;
esac; }
out=$( wait_for_turn who 1 1000 2>&1 ); rc=$?
assert_eq "unobserved turn transition fails"           "1" "$rc"
assert_eq "unobserved turn transition never calls agent wait" "0" "$(printf '%s' "$out" | grep -c 'did not confirm idle/done')"

# Transition observed, but the subsequent settle (agent wait) itself fails/times out.
herdr(){ case "$1 $2" in
  "agent get") echo '{"result":{"agent":{"agent_status":"blocked"}}}' ;;
  "agent wait") echo '{"error":{"code":"timeout"}}' >&2; return 1 ;;
  *) echo "{}" ;;
esac; }
( wait_for_turn who 1 1000 >/dev/null 2>&1 )
assert_eq "observed turn but failed settle still fails" "1" "$?"

echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
