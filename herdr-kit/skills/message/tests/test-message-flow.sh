#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/../../../scripts"
PASS=0; FAIL=0
assert_eq(){ if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; echo "    exp:[$2] act:[$3]"; FAIL=$((FAIL+1)); fi; }

MOCK_CALLS=$(mktemp)
export MOCK_CALLS PATH="$HERE/mock:$PATH"
setup() { : > "$MOCK_CALLS"; export HERDR_ENV=1 HERDR_PANE_ID=wF:p1 HERDR_MESSAGE_TEST_POLL_SECONDS=0; unset MOCK_SENDER_NAME MOCK_FAIL_SEND MOCK_TARGET_KIND MOCK_TARGET_PANE MOCK_SCREEN MOCK_FAIL_READ MOCK_FAIL_READ_AT MOCK_SCREEN_CLEAR_AFTER MOCK_SCREEN_COUNT_FILE; }

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
assert_eq "send failure surfaces the underlying prompt's own diagnostic, not just a generic message" "1" "$(printf '%s' "$out" | grep -c 'agent_prompt_stalled')"

setup
export MOCK_FAIL_SEND=2
out=$(bash "$S/herdr-message" send wK:p1 "hello there" 2>&1); rc=$?
assert_eq "send failure with no underlying diagnostic still dies" "1" "$rc"
assert_eq "send failure with no underlying diagnostic has no dangling ': ' suffix" "0" "$(printf '%s' "$out" | grep -c ': *$')"

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

setup
export MOCK_SENDER_NAME=skill-writer
bash "$S/herdr-message" reply wF:p1 abc123 "done" --callback >/dev/null 2>&1
assert_eq "reply bare --callback: envelope requests a reply, threaded under the SAME id" "1" "$(grep -c 'herdr-message reply wF:p1 abc123' "$MOCK_CALLS")"
assert_eq "reply bare --callback: still carries the reply:<id> tag" "1" "$(grep -c 'reply:abc123 from skill-writer@wF:p1' "$MOCK_CALLS")"

setup
bash "$S/herdr-message" reply wF:p1 abc123 "done" --callback "your next verdict please" >/dev/null 2>&1
assert_eq "reply custom --callback text is used instead of the default" "1" "$(grep -c 'your next verdict please' "$MOCK_CALLS")"
assert_eq "reply custom --callback: default instruction is NOT also sent" "0" "$(grep -c 'herdr-message reply' "$MOCK_CALLS")"

setup
bash "$S/herdr-message" reply wF:p1 abc123 "done" --callback="- dash-leading verdict request" >/dev/null 2>&1
assert_eq "reply --callback=<msg> delivers a dash-leading custom callback" "1" "$(grep -c -- '- dash-leading verdict request' "$MOCK_CALLS")"
assert_eq "reply --callback=<msg>: default instruction is NOT also sent" "0" "$(grep -c 'herdr-message reply' "$MOCK_CALLS")"

# reply <text> starting with "-" must stay a positional (never flag-sniffed), same as send
setup
out=$(bash "$S/herdr-message" reply wF:p1 abc123 "- dash-leading reply body" 2>&1); rc=$?
assert_eq "reply <text> starting with '-' succeeds" "0" "$rc"
assert_eq "reply dash-leading text is delivered literally" "1" "$(grep -c -- '- dash-leading reply body' "$MOCK_CALLS")"

setup
export MOCK_FAIL_SEND=1
out=$(bash "$S/herdr-message" reply wF:p1 abc123 "done" 2>&1); rc=$?
assert_eq "reply propagates a failed underlying prompt (dies loudly, not swallowed to 0)" "1" "$rc"
assert_eq "reply failure surfaces the underlying prompt's own diagnostic, not just a generic message" "1" "$(printf '%s' "$out" | grep -c 'agent_prompt_stalled')"

setup
export MOCK_FAIL_SEND=2
out=$(bash "$S/herdr-message" reply wF:p1 abc123 "done" 2>&1); rc=$?
assert_eq "reply failure with no underlying diagnostic still dies" "1" "$rc"
assert_eq "reply failure with no underlying diagnostic has no dangling ': ' suffix" "0" "$(printf '%s' "$out" | grep -c ': *$')"

setup
out=$(bash "$S/herdr-message" command wK:p1 "/model" 2>&1); rc=$?
assert_eq "command (bare slash-command) exits 0" "0" "$rc"
assert_eq "command never passes --wait to agent prompt" "0" "$(grep -c -- '--wait' "$MOCK_CALLS")"
assert_eq "command delivers the raw slash-command byte-for-byte, unwrapped (no [msg-...] envelope)" "1" "$(grep -c 'agent prompt wK:p1 /model$' "$MOCK_CALLS")"
assert_eq "command output includes sent_to" "1" "$(printf '%s' "$out" | grep -c '"sent_to":"wK:p1"')"
assert_eq "command output includes the command sent" "1" "$(printf '%s' "$out" | grep -c '"command":"/model"')"

setup
out=$(bash "$S/herdr-message" command wK:p1 "/model opus" 2>&1); rc=$?
assert_eq "command rejects a payload with a space (not a bare slash-command)" "1" "$rc"
assert_eq "rejected payload never reaches agent prompt" "0" "$(grep -c 'agent prompt' "$MOCK_CALLS")"

setup
out=$(bash "$S/herdr-message" command wK:p1 "please do the thing" 2>&1); rc=$?
assert_eq "command rejects prose (does not start with /)" "1" "$rc"

setup
out=$(bash "$S/herdr-message" command wK:p1 "/model" --callback 2>&1); rc=$?
assert_eq "command rejects --callback (no reply path for a raw CLI command)" "1" "$rc"

( HERDR_ENV=0; bash "$S/herdr-message" command wK:p1 "/model" >/dev/null 2>&1 ); assert_eq "command no-op outside herdr" "0" "$?"
( HERDR_ENV=1; bash "$S/herdr-message" command wK:p1 >/dev/null 2>&1 ); assert_eq "command missing payload dies" "1" "$?"

( HERDR_ENV=0; bash "$S/herdr-message" send wK:p1 "x" >/dev/null 2>&1 ); assert_eq "send no-op outside herdr" "0" "$?"
( HERDR_ENV=1; bash "$S/herdr-message" send wK:p1 >/dev/null 2>&1 ); assert_eq "send missing text dies" "1" "$?"
( HERDR_ENV=1 HERDR_PANE_ID=wF:p1; bash "$S/herdr-message" reply wF:p1 abc123 >/dev/null 2>&1 ); assert_eq "reply missing text dies" "1" "$?"
( HERDR_ENV=1 HERDR_PANE_ID=wF:p1; bash "$S/herdr-message" send wK:p1 "x" --bogus >/dev/null 2>&1 ); assert_eq "send rejects an unknown option" "1" "$?"
( HERDR_ENV=1 HERDR_PANE_ID=wF:p1; bash "$S/herdr-message" reply wF:p1 abc123 "x" --bogus >/dev/null 2>&1 ); assert_eq "reply rejects an unknown option" "1" "$?"

# --- typing guard: refuse (exit 75) when the target's prompt box holds unsent text ------------------
R='───────────────────────────────────────────────────────'
SCR=$(mktemp)
CNT=$(mktemp)
sent(){ grep -c 'agent prompt' "$MOCK_CALLS"; }

setup; printf '%s\n❯ half typed draft\n%s\n  footer\n' "$R" "$R" > "$SCR"; export MOCK_SCREEN="$SCR"
out=$(bash "$S/herdr-message" send wK:p1 "hi" 2>&1); rc=$?
assert_eq "send to a claude target with a draft exits 75" "75" "$rc"
assert_eq "send to a target with a draft sends nothing" "0" "$(sent)"
assert_eq "the refusal says someone is typing and to retry later" "1" "$(printf '%s' "$out" | grep -c 'someone is typing there')"
assert_eq "a draft that never clears is checked 26 times (the full internal retry budget), not just once" "26" "$(grep -c 'pane read' "$MOCK_CALLS")"

# End-to-end timing regression (plugin-reviewer, PR #25 re-review): prove, at REAL wall-clock
# speed -- not scaled down -- that a permanently-busy target's full 26-check retry loop (25 real
# 2s sleeps = ~50s) still finishes, all 26 reads done and rc=75, strictly within the 60s
# no-long-foreground.sh foreground cap. A naively scaled-down version of this test (shrinking the
# poll interval to make it fast) is what missed the ORIGINAL 31-check/60s-cap pairing's lack of
# headroom, and would just as easily hide it here too in the wrong direction: this loop's own
# fixed per-iteration overhead (bash/jq subprocess spawns) does NOT shrink along with a
# compressed interval, so a compressed test exaggerates that overhead's weight relative to the
# interval and can report a false failure -- measured overhead here is ~8ms/iteration against a
# real 2s interval (under 1%), nowhere near enough to threaten the 60s cap on its own. This test
# therefore spends the real ~50s rather than a compressed approximation of it.
setup; export HERDR_MESSAGE_TEST_POLL_SECONDS=2 MOCK_SCREEN="$SCR"
start=$SECONDS
out=$(timeout 59 bash "$S/herdr-message" send wK:p1 "hi" 2>&1); rc=$?
elapsed=$((SECONDS - start))
assert_eq "real-time: a permanently busy target still exits 75, not killed by a 59s outer timeout" "75" "$rc"
assert_eq "real-time: all 26 checks happened" "26" "$(grep -c 'pane read' "$MOCK_CALLS")"
assert_eq "real-time: finishes with real headroom under the 60s foreground cap" "1" "$([ "$elapsed" -lt 55 ] && echo 1 || echo 0)"

# the target finishes typing partway through the retry loop -- the 3rd check (of 26) sees a clear
# screen, so the send proceeds instead of giving up after the 1st check.
setup; : > "$CNT"; export MOCK_SCREEN="$SCR" MOCK_SCREEN_CLEAR_AFTER=2 MOCK_SCREEN_COUNT_FILE="$CNT"
out=$(bash "$S/herdr-message" send wK:p1 "hi" 2>&1); rc=$?
assert_eq "a draft that clears partway through the retry loop: send eventually succeeds" "0" "$rc"
assert_eq "...and the message actually went out" "1" "$(sent)"
assert_eq "...after retrying (not sent on the very first, still-typing check)" "3" "$(grep -c 'pane read' "$MOCK_CALLS")"

# Regression: once a draft HAS been positively observed, a later attempt that merely FAILS to
# re-verify (a transient pane-read error, not a confirmed-clear screen) must not be mistaken for
# "cleared" -- it has to consume a retry and keep waiting, same as seeing the draft again.
setup; : > "$CNT"; export MOCK_SCREEN="$SCR" MOCK_FAIL_READ_AT=2 MOCK_SCREEN_COUNT_FILE="$CNT"
out=$(bash "$S/herdr-message" send wK:p1 "hi" 2>&1); rc=$?
assert_eq "draft seen, then a transient read failure, draft still there after: still exits 75 (not sent)" "75" "$rc"
assert_eq "...sends nothing despite the transient failure" "0" "$(sent)"
assert_eq "...all 26 checks still happen (the failed one didn't short-circuit the loop)" "26" "$(grep -c 'pane read' "$MOCK_CALLS")"

# Same transient-failure scenario, but the draft genuinely clears afterward -- the send should
# still succeed (the earlier failure must not have poisoned the final confirmed-clear result).
setup; : > "$CNT"; export MOCK_SCREEN="$SCR" MOCK_FAIL_READ_AT=2 MOCK_SCREEN_CLEAR_AFTER=3 MOCK_SCREEN_COUNT_FILE="$CNT"
out=$(bash "$S/herdr-message" send wK:p1 "hi" 2>&1); rc=$?
assert_eq "draft seen, transient read failure, then it genuinely clears: send still succeeds" "0" "$rc"
assert_eq "...and the message actually went out" "1" "$(sent)"

setup; export MOCK_SCREEN="$SCR"
bash "$S/herdr-message" reply wK:p1 abc123 "hi" >/dev/null 2>&1; assert_eq "reply to a target with a draft exits 75" "75" "$?"
assert_eq "reply to a target with a draft sends nothing" "0" "$(sent)"
setup; export MOCK_SCREEN="$SCR"
bash "$S/herdr-message" command wK:p1 /model >/dev/null 2>&1; assert_eq "command to a target with a draft exits 75" "75" "$?"
assert_eq "command to a target with a draft sends nothing" "0" "$(sent)"

# a tall wrapped draft: the two rules are more than 40 lines apart, so a 40-line read would miss the top rule
setup; { printf 'older output\n%s\n' "$R"; printf '❯ draft line %s\n' $(seq 1 60); printf '%s\n  footer one\n  footer two\n' "$R"; } > "$SCR"; export MOCK_SCREEN="$SCR"
bash "$S/herdr-message" send wK:p1 "hi" >/dev/null 2>&1; assert_eq "a draft whose rules are 60 lines apart is still refused" "75" "$?"
assert_eq "the tall draft sends nothing" "0" "$(sent)"

setup; printf '%s\n❯\n%s\n  footer\n' "$R" "$R" > "$SCR"; export MOCK_SCREEN="$SCR"
bash "$S/herdr-message" send wK:p1 "hi" >/dev/null 2>&1; assert_eq "an empty prompt box sends" "0" "$?"
assert_eq "an empty prompt box delivers the message" "1" "$(sent)"

setup; printf '%s\nhalf typed draft\n%s\nfooter\n' "$R" "$R" > "$SCR"; export MOCK_SCREEN="$SCR" MOCK_TARGET_KIND=pi
bash "$S/herdr-message" send wK:p1 "hi" >/dev/null 2>&1; assert_eq "send to a pi target with a draft exits 75" "75" "$?"
setup; printf '%s\n\n%s\nfooter\n' "$R" "$R" > "$SCR"; export MOCK_SCREEN="$SCR" MOCK_TARGET_KIND=pi
bash "$S/herdr-message" send wK:p1 "hi" >/dev/null 2>&1; assert_eq "send to a pi target with an empty box sends" "0" "$?"

setup; printf '%s\n❯ text\n%s\n' "$R" "$R" > "$SCR"; export MOCK_SCREEN="$SCR" MOCK_TARGET_KIND=codex
bash "$S/herdr-message" send wK:p1 "hi" >/dev/null 2>&1; assert_eq "a codex target is not checked (cannot parse it)" "0" "$?"
setup; printf '%s\n❯ text\n%s\n' "$R" "$R" > "$SCR"; export MOCK_SCREEN="$SCR" MOCK_TARGET_PANE=wF:p1
bash "$S/herdr-message" send wK:p1 "hi" >/dev/null 2>&1; assert_eq "the caller's own pane is not checked" "0" "$?"
setup; printf '%s\n❯ text\n%s\n' "$R" "$R" > "$SCR"; export MOCK_SCREEN="$SCR" MOCK_FAIL_READ=1
bash "$S/herdr-message" send wK:p1 "hi" >/dev/null 2>&1; assert_eq "a failing screen read lets the send proceed" "0" "$?"
assert_eq "a failing screen read still delivers" "1" "$(sent)"
# claude queues a message entered while it is busy: the box then holds only a dim hint (with the shaded
# cursor on its first letter), which is not typed text, so the send must go through; real typed text is
# still refused.
NB=$(printf '\302\240')
RA=$(printf '\033[0m\033[38;2;136;136;136m%s\033[0m' "$R")
setup; { printf 'older output\n%s\n' "$RA"; printf '\033[0m\033[38;2;153;153;153m❯%s\033[0m\033[7mP\033[0m\033[2mress up to edit queued messages\033[0m\r\n' "$NB"; printf '%s\n  footer\n' "$RA"; } > "$SCR"; export MOCK_SCREEN="$SCR"
bash "$S/herdr-message" send wK:p1 "hi" >/dev/null 2>&1; assert_eq "claude with a queued message (dim hint in the box) is sent to" "0" "$?"
assert_eq "the message is delivered despite the queued hint" "1" "$(sent)"
setup; { printf 'older output\n%s\n' "$RA"; printf '\033[0m\033[38;2;153;153;153m❯%s\033[0mREALDRAFT\033[0m\033[7m \033[0m\r\n' "$NB"; printf '%s\n  footer\n' "$RA"; } > "$SCR"; export MOCK_SCREEN="$SCR"
bash "$S/herdr-message" send wK:p1 "hi" >/dev/null 2>&1; assert_eq "claude with normal-colored typed text in the ANSI box is refused" "75" "$?"
assert_eq "nothing is sent over a typed ANSI draft" "0" "$(sent)"

rm -f "$SCR" "$CNT"

rm -f "$MOCK_CALLS"
echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
