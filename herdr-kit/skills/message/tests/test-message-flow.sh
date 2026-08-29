#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/../../scripts"
PASS=0; FAIL=0
assert_eq(){ if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; echo "    exp:[$2] act:[$3]"; FAIL=$((FAIL+1)); fi; }

MOCK_CALLS=$(mktemp)
export MOCK_CALLS PATH="$HERE/mock:$PATH"
setup() { : > "$MOCK_CALLS"; export HERDR_ENV=1 HERDR_PANE_ID=wF:p1; unset MOCK_SENDER_NAME MOCK_FAIL_SEND; }

setup
export MOCK_SENDER_NAME=plugin-writer
out=$(bash "$S/herdr-message" send wK:p1 "hello there" 2>&1); rc=$?
assert_eq "send (no callback) exits 0" "0" "$rc"
assert_eq "send never passes --wait to agent prompt" "0" "$(grep -c -- '--wait' "$MOCK_CALLS")"
assert_eq "send output includes a 6-char message_id" "1" "$(printf '%s' "$out" | grep -cE '"message_id":"[a-z0-9]{6}"')"
assert_eq "send output includes sent_to" "1" "$(printf '%s' "$out" | grep -c '"sent_to":"wK:p1"')"
assert_eq "the envelope sent to the target carries the sender's name and pane" "1" "$(grep -c 'from plugin-writer@wF:p1' "$MOCK_CALLS")"

setup
export MOCK_SENDER_NAME=""
bash "$S/herdr-message" send wK:p1 "hello there" >/dev/null 2>&1
assert_eq "unnamed sender: envelope falls back to the bare pane id" "1" "$(grep -cF 'from wF:p1' "$MOCK_CALLS")"

setup
export MOCK_SENDER_NAME=plugin-writer
bash "$S/herdr-message" send wK:p1 "please review" --callback >/dev/null 2>&1
assert_eq "bare --callback: envelope requests a reply via herdr-message reply" "1" "$(grep -c 'herdr-message reply wF:p1' "$MOCK_CALLS")"

setup
bash "$S/herdr-message" send wK:p1 "please review" --callback "let me know when done" >/dev/null 2>&1
assert_eq "custom --callback text is used instead of the default" "1" "$(grep -c 'let me know when done' "$MOCK_CALLS")"
assert_eq "custom --callback: default instruction is NOT also sent" "0" "$(grep -c 'herdr-message reply' "$MOCK_CALLS")"

# <text> starting with "-" must not be misread as an unrecognized flag -- target/text are fixed
# positionals taken by position, never flag-sniffed. An LLM writing free-form message text (a
# bullet point, an em-dash opener, "-1", ...) has no reason to know to escape a leading "-".
setup
out=$(bash "$S/herdr-message" send wK:p1 "- first bullet point of update" 2>&1); rc=$?
assert_eq "send <text> starting with '-' succeeds" "0" "$rc"
assert_eq "dash-leading text is delivered literally" "1" "$(grep -c -- '- first bullet point of update' "$MOCK_CALLS")"

# --callback=<msg>: the attached "=" form takes everything after it literally, so a custom
# callback message that itself starts with "-" (which the bare peek-ahead form can never
# represent, since it always looks like "no value given") can still be sent unambiguously.
setup
bash "$S/herdr-message" send wK:p1 "please review" --callback="- dash-leading custom callback" >/dev/null 2>&1
assert_eq "--callback=<msg> delivers a dash-leading custom callback message" "1" "$(grep -c -- '- dash-leading custom callback' "$MOCK_CALLS")"
assert_eq "--callback=<msg>: default instruction is NOT also sent" "0" "$(grep -c 'herdr-message reply' "$MOCK_CALLS")"

setup
export MOCK_FAIL_SEND=1
out=$(bash "$S/herdr-message" send wK:p1 "hello there" 2>&1); rc=$?
assert_eq "send propagates a failed underlying prompt (dies loudly, not swallowed to 0)" "1" "$rc"

setup
export MOCK_SENDER_NAME=skill-writer
out=$(bash "$S/herdr-message" reply wF:p1 abc123 "done, all green" 2>&1); rc=$?
assert_eq "reply exits 0" "0" "$rc"
assert_eq "reply never passes --wait" "0" "$(grep -c -- '--wait' "$MOCK_CALLS")"
assert_eq "reply envelope carries the reply:<id> tag and sender identity" "1" "$(grep -c 'reply:abc123 from skill-writer@wF:p1' "$MOCK_CALLS")"
assert_eq "reply output includes the same message_id" "1" "$(printf '%s' "$out" | grep -c '"message_id":"abc123"')"

setup
export MOCK_SENDER_NAME=skill-writer
out=$(bash "$S/herdr-message" reply wF:p1 'a"b' "done" 2>&1); rc=$?
assert_eq "reply with a quote-containing id still exits 0" "0" "$rc"
assert_eq "reply output is valid JSON even with a quote-containing id" "0" "$(printf '%s' "$out" | jq . >/dev/null 2>&1; echo $?)"
assert_eq "reply output's message_id decodes back to the literal quote-containing id" "1" "$(printf '%s' "$out" | jq -r '.message_id' | grep -cF 'a"b')"

( HERDR_ENV=0; bash "$S/herdr-message" send wK:p1 "x" >/dev/null 2>&1 ); assert_eq "send no-op outside herdr" "0" "$?"
( HERDR_ENV=1; bash "$S/herdr-message" send wK:p1 >/dev/null 2>&1 ); assert_eq "send missing text dies" "1" "$?"
( HERDR_ENV=1 HERDR_PANE_ID=wF:p1; bash "$S/herdr-message" reply wF:p1 abc123 >/dev/null 2>&1 ); assert_eq "reply missing text dies" "1" "$?"
( HERDR_ENV=1 HERDR_PANE_ID=wF:p1; bash "$S/herdr-message" send wK:p1 "x" --bogus >/dev/null 2>&1 ); assert_eq "send rejects an unknown option" "1" "$?"

rm -f "$MOCK_CALLS"
echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
