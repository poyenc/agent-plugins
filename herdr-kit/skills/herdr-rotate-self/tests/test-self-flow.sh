#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; S="$HERE/../../scripts"
PASS=0; FAIL=0
assert_eq(){ if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; echo "    exp:[$2] act:[$3]"; FAIL=$((FAIL+1)); fi; }

SUITE_ROOT=$(mktemp -d)
trap 'rm -rf "$SUITE_ROOT"' EXIT

setup(){
  export TMPDIR; TMPDIR=$(mktemp -d --tmpdir="$SUITE_ROOT")
  export MOCK_STATE; MOCK_STATE=$(mktemp -d --tmpdir="$SUITE_ROOT")
  export MOCK_CALLS="$MOCK_STATE/calls"; : > "$MOCK_CALLS"
  export MOCK_KIND="$1" MOCK_PANE="wG:p1" MOCK_NAME="target"
  unset MOCK_SESSION
  [ -n "${2:-}" ] && export MOCK_SESSION="$2"
  printf -- '--model\nopus\n--verbose\n' > "$MOCK_STATE/argv"
  export PATH="$HERE/mock:$PATH"
  export ROTATE_EXIT_POLL_SECS=5 ROTATE_VERIFY_POLL_SECS=5 ROTATE_DETECT_POLL_SECS=1 ROTATE_SETTLE_POLL_SECS=5
  export ROTATE_LOCK_ROOT="$TMPDIR"
  export HERDR_PANE_ID=wG:p1
  HANDOFF_PATH=$(mktemp --tmpdir="$SUITE_ROOT"); printf '# handoff\n' > "$HANDOFF_PATH"
}

# --- self_target(): pure function test, no daemon spawn ---
setup claude sess-abc12345
source "$S/herdr-rotate-self" >/dev/null 2>&1 </dev/null || true   # main-guard: sourcing runs nothing
set +e   # herdr-rotate-self itself sets -euo pipefail, which sourcing imports into THIS shell
tgt=$(self_target)
assert_eq "self_target claude w/ session" "wG:p1@sess-abc" "$tgt"

setup pi
tgt=$(self_target)
assert_eq "self_target pi (no session id available)" "wG:p1" "$tgt"

# --- full flow: run_self spawns a detached daemon that runs the real herdr-rotate finish ---
setup claude sess-abc12345
HERDR_ENV=1 HERDR_PANE_ID=wG:p1 bash "$S/herdr-rotate-self" "$HANDOFF_PATH" >/dev/null 2>&1
rc=$?
assert_eq "run_self returns fast, exit 0" "0" "$rc"

# Poll for the daemon to finish (it runs detached; give it up to 10s). Wait for the
# kickoff prompt specifically (the LAST call the daemon makes) rather than 'agent start'
# (an earlier call) -- breaking on 'agent start' races the daemon's own subsequent
# verify+kickoff steps and can fail the assertions below before they've happened yet.
deadline=$(( $(date +%s) + 10 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  grep -q 'Continue the work described' "$MOCK_CALLS" 2>/dev/null && break
  command sleep 0.2
done
assert_eq "daemon relaunched the agent" "1" "$(grep -c 'agent start' "$MOCK_CALLS")"
assert_eq "daemon sent /quit before relaunch" "1" "$([ "$(grep -n '/quit' "$MOCK_CALLS" | head -n1 | cut -d: -f1)" -lt "$(grep -n 'agent start' "$MOCK_CALLS" | head -n1 | cut -d: -f1)" ] && echo 1 || echo 0)"
assert_eq "daemon sent kickoff after relaunch" "1" "$(grep -c 'Continue the work described' "$MOCK_CALLS")"
assert_eq "no separate handoff-write prompt was sent (self-rotation skips the ping)" "0" "$(grep -c 'Write a handoff' "$MOCK_CALLS")"

echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
