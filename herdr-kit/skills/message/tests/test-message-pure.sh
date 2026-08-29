#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/../../scripts"
PASS=0; FAIL=0
assert_eq(){ if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; echo "    exp:[$2] act:[$3]"; FAIL=$((FAIL+1)); fi; }

# shellcheck source=SCRIPTDIR/../../scripts/herdr-message
source "$S/herdr-message"
set +e   # herdr-message's own `set -e` (imported by sourcing) would otherwise abort this
         # script on the very failure paths being asserted -- same convention as
         # test-claude-detect-override.sh sourcing herdr-rotate-claude.

# generate_message_id: format only, never an exact value (it's random by design)
id=$(generate_message_id)
assert_eq "message id is 6 characters" "6" "${#id}"
assert_eq "message id is lowercase alphanumeric only" "0" "$(printf '%s' "$id" | grep -cvE '^[a-z0-9]+$')"

# sender_from_line: named sender
herdr(){ case "$1 $2" in "agent get") echo '{"result":{"agent":{"name":"plugin-writer"}}}' ;; esac; }
HERDR_PANE_ID=wF:p1
assert_eq "sender_from_line includes the name when one is set" "plugin-writer@wF:p1" "$(sender_from_line)"

# sender_from_line: unnamed sender (empty name field in the response)
herdr(){ case "$1 $2" in "agent get") echo '{"result":{"agent":{"name":""}}}' ;; esac; }
assert_eq "sender_from_line falls back to the bare pane id when unnamed" "wF:p1" "$(sender_from_line)"

# sender_from_line: an `agent get` failure must not crash -- treated the same as unnamed
herdr(){ return 1; }
assert_eq "sender_from_line survives an agent-get failure, falls back to bare pane id" "wF:p1" "$(sender_from_line)"

# build_send_envelope: no callback requested
env=$(build_send_envelope "abc123" "wF:p1" "hello there" 0 "")
assert_eq "send envelope: id/from line" "1" "$(printf '%s' "$env" | grep -c '^\[msg-abc123 from wF:p1\]$')"
assert_eq "send envelope: body" "1" "$(printf '%s' "$env" | grep -c '^hello there$')"
assert_eq "send envelope (no callback): no callback block at all" "0" "$(printf '%s' "$env" | grep -c 'callback requested')"

# build_send_envelope: bare callback (default instruction, referencing herdr-message reply)
HERDR_PANE_ID=wF:p1
env=$(build_send_envelope "abc123" "wF:p1" "hello there" 1 "")
assert_eq "send envelope (bare callback): callback block present" "1" "$(printf '%s' "$env" | grep -c 'callback requested')"
assert_eq "send envelope (bare callback): default instruction tells the recipient to use herdr-message reply, targeting the sender's own pane and this message's id" \
  "1" "$(printf '%s' "$env" | grep -c "herdr-message reply wF:p1 abc123")"

# build_send_envelope: custom callback text overrides the default entirely
env=$(build_send_envelope "abc123" "wF:p1" "hello there" 1 "let me know when green")
assert_eq "send envelope (custom callback): custom text present" "1" "$(printf '%s' "$env" | grep -c 'let me know when green')"
assert_eq "send envelope (custom callback): default instruction is NOT also present" "0" "$(printf '%s' "$env" | grep -c 'herdr-message reply')"

# build_reply_envelope
env=$(build_reply_envelope "abc123" "skill-writer@wK:p1" "done, all green")
assert_eq "reply envelope: reply:<id>/from line" "1" "$(printf '%s' "$env" | grep -c '^\[reply:abc123 from skill-writer@wK:p1\]$')"
assert_eq "reply envelope: body" "1" "$(printf '%s' "$env" | grep -c '^done, all green$')"

echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
