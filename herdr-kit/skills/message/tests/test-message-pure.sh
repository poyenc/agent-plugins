#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/../../../scripts"
PASS=0; FAIL=0
assert_eq(){ if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; echo "    exp:[$2] act:[$3]"; FAIL=$((FAIL+1)); fi; }

# shellcheck source=SCRIPTDIR/../../../scripts/herdr-message
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

# build_reply_envelope: no callback
env=$(build_reply_envelope "abc123" "skill-writer@wK:p1" "done, all green" 0 "")
assert_eq "reply envelope: reply:<id>/from line" "1" "$(printf '%s' "$env" | grep -c '^\[reply:abc123 from skill-writer@wK:p1\]$')"
assert_eq "reply envelope: body" "1" "$(printf '%s' "$env" | grep -c '^done, all green$')"
assert_eq "reply envelope (no callback): no callback block at all" "0" "$(printf '%s' "$env" | grep -c 'callback requested')"

# build_reply_envelope: bare callback -- same block as send, threading under the SAME id replied to
HERDR_PANE_ID=wF:p1
env=$(build_reply_envelope "abc123" "skill-writer@wF:p1" "done, all green" 1 "")
assert_eq "reply envelope (bare callback): callback block present" "1" "$(printf '%s' "$env" | grep -c 'callback requested')"
assert_eq "reply envelope (bare callback): default instruction threads under the same id (herdr-message reply <own-pane> <same-id>)" \
  "1" "$(printf '%s' "$env" | grep -c 'herdr-message reply wF:p1 abc123')"

# build_reply_envelope: custom callback text overrides the default entirely
env=$(build_reply_envelope "abc123" "skill-writer@wF:p1" "done, all green" 1 "your next verdict please")
assert_eq "reply envelope (custom callback): custom text present" "1" "$(printf '%s' "$env" | grep -c 'your next verdict please')"
assert_eq "reply envelope (custom callback): default instruction is NOT also present" "0" "$(printf '%s' "$env" | grep -c 'herdr-message reply')"

# callback_suffix: the shared block builder used by both send and reply
assert_eq "callback_suffix: empty when callback=0" "" "$(callback_suffix 0 "" abc123)"
assert_eq "callback_suffix: carries the block when callback=1" "1" "$(callback_suffix 1 "" abc123 | grep -c 'callback requested')"
assert_eq "callback_suffix: custom message wins over the default" "1" "$(callback_suffix 1 'ping me' abc123 | grep -c '^ping me$')"

# The default callback instruction embeds a RUNNABLE `herdr-message reply ...` command. Reply ids
# are caller-supplied and unvalidated (a quote/whitespace-containing id is accepted and returned
# literally -- see the flow test), so the emitted command must stay a valid, argv-preserving
# invocation that recovers the EXACT id. Extract the command line, word-split it the way a shell
# would, and assert the id lands intact as the reply's <message-id> arg (position 4:
# <path> reply <pane> <id> "<your update>").
HERDR_PANE_ID=wF:p1
for weird in 'a"b' 'has space' "tick'q"; do
  env=$(build_reply_envelope "$weird" "skill-writer@wF:p1" "done" 1 "")
  cmd_line=$(printf '%s' "$env" | sed -n 's/^When convenient, reply with: //p')
  # Sentinels first: a well-formed command overwrites them; a broken one (unbalanced quoting from
  # an unquoted metachar id) leaves them, so the asserts FAIL cleanly instead of aborting eval.
  set -- x x x x x
  eval "set -- $cmd_line" 2>/dev/null || true
  assert_eq "default reply callback is a runnable command for a metachar id [$weird]: subcommand 'reply'" "reply" "${2:-x}"
  assert_eq "default reply callback round-trips the exact id [$weird] at arg 4" "$weird" "${4:-x}"
done

echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
