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

# scan_screen_for_draft: the prompt box is the region between the last two rule lines; text there (after an
# optional leading "❯") is an unsent draft (exit status 0).
R='───────────────────────────────────────────────────────'
draft(){ printf '%s\n' "$1" | scan_screen_for_draft; echo $?; }   # prints the exit status: 0 = draft, 1 = no draft / cannot tell
assert_eq "claude: draft text after the prompt marker" "0" "$(draft "$(printf 'older output\n%s\n❯ half typed draft\n%s\n  ~/repo (main)\n  Sonnet 5 high' "$R" "$R")")"
assert_eq "claude: empty prompt box is no draft" "1" "$(draft "$(printf 'older output\n%s\n❯\n%s\n  ~/repo (main)\n  Sonnet 5 high' "$R" "$R")")"
assert_eq "claude: prompt marker with trailing spaces only is no draft" "1" "$(draft "$(printf '%s\n❯   \n%s\n  footer' "$R" "$R")")"
assert_eq "claude: a draft wrapped over two lines is a draft" "0" "$(draft "$(printf '%s\n❯ first line\n  second line\n%s\n  footer' "$R" "$R")")"
assert_eq "pi: draft text on its own line" "0" "$(draft "$(printf '%s\nhalf typed draft\n%s\n~/repo (main)\n0.0%%/1.1M (auto)  gpt-6-luna' "$R" "$R")")"
assert_eq "pi: empty box is no draft" "1" "$(draft "$(printf '%s\n\n%s\n~/repo (main)\n0.0%%/1.1M (auto)  gpt-6-luna' "$R" "$R")")"
assert_eq "pi: empty box under the Working rule is no draft" "1" "$(draft "$(printf '── ⠙ Working ───────────────────────\n\n%s\n~/repo (main)\n↑3 ↓93' "$R")")"
assert_eq "pi: draft under the Working rule is a draft" "0" "$(draft "$(printf '── ⠙ Working ───────────────────────\nhello there\n%s\n~/repo (main)' "$R")")"
assert_eq "only one rule on screen: cannot tell, no draft" "1" "$(draft "$(printf 'output\n%s\n❯ text' "$R")")"
assert_eq "no rules at all (empty screen): no draft" "1" "$(draft "")"
assert_eq "only the LAST two rules count (text above an earlier rule is ignored)" "1" "$(draft "$(printf '%s\ntext in old output\n%s\n❯\n%s\nfooter' "$R" "$R" "$R")")"

# scan_screen_for_draft: pi's schedule_prompt widget (pi-schedule-prompt's CronWidget, placed
# belowEditor) draws its own rule-bordered box between the editor and the footer whenever any job
# is loaded, even an already-ended one -- its own top/bottom rules would otherwise become the "last
# two" and its fixed "Scheduled Prompts" header/rows would be misread as a permanent draft. These
# cases are real pi screen shapes: editor's own two rules, immediately followed by the widget's own
# two rules, with zero gap between the editor's bottom rule and the widget's top rule.
assert_eq "pi: a real draft behind a trailing schedule_prompt widget is still found" "0" \
  "$(draft "$(printf '%s\nhalf typed draft\n%s\n%s\n Scheduled Prompts (3 jobs)\n ✓ check-logs\n%s\n~/repo (main)\n0.0%%/1.1M (auto)  gpt-6-luna' "$R" "$R" "$R" "$R")")"
assert_eq "pi: an empty editor behind a trailing schedule_prompt widget is no draft" "1" \
  "$(draft "$(printf '%s\n\n%s\n%s\n Scheduled Prompts (3 jobs)\n ✓ check-logs\n%s\n~/repo (main)\n0.0%%/1.1M (auto)  gpt-6-luna' "$R" "$R" "$R" "$R")")"
assert_eq "pi: only the schedule_prompt widget's own rule-pair visible (editor scrolled off) cannot tell, no draft" "1" \
  "$(draft "$(printf '%s\n Scheduled Prompts (3 jobs)\n ✓ check-logs\n%s\n~/repo (main)' "$R" "$R")")"

# ANSI screens as herdr emits them with --format ansi (sequences captured from real claude and pi panes).
# claude draws a placeholder hint DIM with the shaded (reverse-video) cursor on its first letter; neither
# the dim cells nor the cursor cell may count as typed text, while normal-colored text must.
RA=$(printf '\033[0m\033[38;2;136;136;136m%s\033[0m' "$R")
NB=$(printf '\302\240')
clr_empty=$(printf '\033[0m\033[38;2;153;153;153m❯%s\033[0m\033[7m \033[0m\r' "$NB")
clr_hint=$(printf '\033[0m\033[38;2;153;153;153m❯%s\033[0m\033[7mP\033[0m\033[2mress up to edit queued messages\033[0m\r' "$NB")
clr_draft=$(printf '\033[0m\033[38;2;153;153;153m❯%s\033[0mREALDRAFT\033[0m\033[7m \033[0m\r' "$NB")
pi_empty=$(printf '\033[0m\033[7m \033[0m                                  \r')
pi_draft=$(printf 'TYPED DRAFT TEXT\033[0m\033[7m \033[0m                  \r')
ansi_screen(){ printf 'older output\n%s\n%s\n%s\n  footer\n' "$RA" "$1" "$RA"; }
assert_eq "ansi claude: the dim queued-messages hint with a shaded cursor is no draft" "1" "$(draft "$(ansi_screen "$clr_hint")")"
assert_eq "ansi claude: empty box (cursor only) is no draft" "1" "$(draft "$(ansi_screen "$clr_empty")")"
assert_eq "ansi claude: normal-colored typed text is a draft" "0" "$(draft "$(ansi_screen "$clr_draft")")"
assert_eq "ansi pi: empty box (cursor only) is no draft" "1" "$(draft "$(ansi_screen "$pi_empty")")"
assert_eq "ansi pi: typed text is a draft" "0" "$(draft "$(ansi_screen "$pi_draft")")"
assert_eq "ansi: rule lines wrapped in color codes still delimit the box" "0" "$(draft "$(printf 'x\n%s\n%s\n%s\n' "$RA" "$clr_draft" "$RA")")"
assert_eq "ansi: a truecolor sequence (38;2;2;2;2) is not mistaken for dim" "0" "$(draft "$(ansi_screen "$(printf '\033[38;2;2;2;2mvisible text\033[0m')")")"
assert_eq "ansi: dim ended by 22 lets later text count" "0" "$(draft "$(ansi_screen "$(printf '\033[2mhint\033[22m typed\033[0m')")")"
assert_eq "ansi: bold+dim (1;2) text is ignored" "1" "$(draft "$(ansi_screen "$(printf '\033[1;2mhint only\033[0m')")")"
assert_eq "ansi: a draft after a dim hint on the same line still counts" "0" "$(draft "$(ansi_screen "$(printf '\033[2mhint\033[0m real')")")"
assert_eq "ansi: a rule drawn dim is still recognized as a rule" "0" "$(draft "$(printf 'x\n%s\n%s\n%s\n' "$(printf '\033[2m%s\033[0m' "$R")" "$clr_draft" "$(printf '\033[2m%s\033[0m' "$R")")")"

# Finding: reverse-video text is real input unless it is the cursor on a dim hint.
assert_eq "ansi: a single real character under the cursor is a draft" "0" "$(draft "$(ansi_screen "$(printf '\033[0m\033[38;2;153;153;153m❯%s\033[0m\033[7mX\033[0m' "$NB")")")"
assert_eq "ansi: selected (reverse-video) draft text is a draft" "0" "$(draft "$(ansi_screen "$(printf '\033[0m\033[38;2;153;153;153m❯%s\033[0m\033[7mREALDRAFT\033[0m' "$NB")")")"
assert_eq "ansi: cursor over a letter inside typed text keeps the whole draft" "0" "$(draft "$(ansi_screen "$(printf '❯%shel\033[7ml\033[0mo' "$NB")")")"
assert_eq "ansi: a blank reverse cursor cell alone is no draft" "1" "$(draft "$(ansi_screen "$(printf '❯%s\033[7m \033[0m' "$NB")")")"

# Finding: colon-form SGR and non-SGR escapes, in both directions (a miss, and a lockout).
RC=$(printf '\033[38:2:136:136:136m%s\033[0m' "$R")
assert_eq "ansi: colon-form color on the rule lines still delimits the box (draft found)" "0" "$(draft "$(printf 'x\n%s\n%s\n%s\n' "$RC" "$clr_draft" "$RC")")"
assert_eq "ansi: colon-form color with a colorspace slot (38:2::r:g:b) is not mistaken for dim" "0" "$(draft "$(ansi_screen "$(printf '\033[38:2::2:2:2mvisible\033[0m')")")"
assert_eq "ansi: colon-form color text in an otherwise empty box is no escape residue (no draft)" "1" "$(draft "$(ansi_screen "$(printf '\033[38:2:153:153:153m\033[0m\033[7m \033[0m')")")"
assert_eq "ansi: a non-SGR CSI (ESC[K) in an empty box is no draft" "1" "$(draft "$(ansi_screen "$(printf '\033[7m \033[0m\033[K')")")"
assert_eq "ansi: an OSC hyperlink wrapper in an empty box is no draft" "1" "$(draft "$(ansi_screen "$(printf '\033]8;;http://x\033\\\033[7m \033[0m\033]8;;\033\\')")")"
assert_eq "ansi: an OSC closed by BEL in an empty box is no draft" "1" "$(draft "$(ansi_screen "$(printf '\033]0;title\007\033[7m \033[0m')")")"
assert_eq "ansi: a dangling ESC at the end of an empty box line is no draft" "1" "$(draft "$(ansi_screen "$(printf '\033[7m \033[0m\033')")")"
assert_eq "ansi: a charset escape in an empty box is no draft" "1" "$(draft "$(ansi_screen "$(printf '\033(B\033[7m \033[0m')")")"
assert_eq "ansi: typed text next to a non-SGR CSI is still a draft" "0" "$(draft "$(ansi_screen "$(printf 'typed\033[K')")")"

# Finding: SGR state persists across lines, so a wrapped dim hint stays dim on its continuation line.
wrapped=$(printf '%s\n%s\n%s\n%s\n%s\n' "$RA" "$(printf '\033[0m\033[38;2;153;153;153m❯%s\033[0m\033[7mP\033[0m\033[2mress up to edit' "$NB")" "queued messages $(printf '\033[0m')" "$RA" "  footer")
assert_eq "ansi: a dim hint wrapped over two lines is no draft" "1" "$(draft "$(printf 'x\n%s' "$wrapped")")"
assert_eq "ansi: dim state carried to the next line ends at its reset" "0" "$(draft "$(printf 'x\n%s\n%s\n%s\n%s\n' "$RA" "$(printf '\033[2mdim one')" "$(printf '\033[0mnormal two')" "$RA")")"

# Finding: more escape families (DEC save/restore, other charset designators, string controls) are
# stripped both ways -- no lockout over residue, and typed text beside them is still found.
assert_eq "ansi: DEC save/restore cursor (ESC 7 / ESC 8) in an empty box is no draft" "1" "$(draft "$(ansi_screen "$(printf '\0337\033[7m \033[0m\0338')")")"
assert_eq "ansi: charset designator ESC * B in an empty box is no draft" "1" "$(draft "$(ansi_screen "$(printf '\033*B\033[7m \033[0m')")")"
assert_eq "ansi: a DCS string closed by ST in an empty box is no draft" "1" "$(draft "$(ansi_screen "$(printf '\033Pq#0;2;0;0;0\033\\\033[7m \033[0m')")")"
assert_eq "ansi: an APC string closed by ST in an empty box is no draft" "1" "$(draft "$(ansi_screen "$(printf '\033_Gf=100;data\033\\\033[7m \033[0m')")")"
assert_eq "ansi: an SOS/PM string closed by BEL in an empty box is no draft" "1" "$(draft "$(ansi_screen "$(printf '\033^note\007\033[7m \033[0m')")")"
assert_eq "ansi: an unterminated OSC drops the rest of its line (no draft)" "1" "$(draft "$(ansi_screen "$(printf '\033]8;;http://never-closed junk text')")")"
assert_eq "ansi: an unterminated DCS drops the rest of its line (no draft)" "1" "$(draft "$(ansi_screen "$(printf '\033Pjunk text with no terminator')")")"
assert_eq "ansi: typed text before an ESC 7 is still a draft" "0" "$(draft "$(ansi_screen "$(printf 'typed\0337')")")"
assert_eq "ansi: typed text after a DCS string is still a draft" "0" "$(draft "$(ansi_screen "$(printf '\033Pq\033\\typed')")")"

# Finding: a reverse cell followed by dim text is dropped only when nothing was typed before it.
assert_eq "ansi: typed text, then a reverse cell, then dim text keeps the draft" "0" "$(draft "$(ansi_screen "$(printf '❯%shello \033[7mw\033[0m\033[2m ghost\033[0m' "$NB")")")"
assert_eq "ansi: the cursor on the first letter of a dim hint with nothing before it is the hint (no draft)" "1" "$(draft "$(ansi_screen "$(printf '❯%s\033[7mT\033[0m\033[2mry something\033[0m' "$NB")")")"
assert_eq "ansi: a multi-character reverse run before dim text is kept (selected text)" "0" "$(draft "$(ansi_screen "$(printf '❯%s\033[7mselected text\033[0m\033[2m hint\033[0m' "$NB")")")"

echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
