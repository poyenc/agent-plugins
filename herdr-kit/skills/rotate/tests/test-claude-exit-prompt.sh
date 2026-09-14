#!/usr/bin/env bash
# Direct unit test for herdr-rotate-claude's handle_exit_prompt: claude's own /quit, when a
# background task (e.g. a Bash tool call run with run_in_background=true) is still running,
# opens a confirmation menu instead of exiting immediately, with "Exit and stop tasks" already
# pre-selected. The fixture below is transcribed verbatim from a REAL live probe against a
# running Claude Code v2.1.237 session (herdr agent prompt "/quit" + herdr pane read against a
# throwaway agent with a backgrounded `tail -f /dev/null`, this session) -- not a hand-constructed
# guess. exit_agent's own poll loop otherwise waits out its full timeout and dies, since gone()
# never becomes true while this menu is on screen, and claude has no exit_fallback (unlike pi's
# double ctrl-d) to fall back on.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/../../../scripts"
PASS=0; FAIL=0
assert_eq(){ if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; echo "    exp:[$2] act:[$3]"; FAIL=$((FAIL+1)); fi; }

# shellcheck source=SCRIPTDIR/../../../scripts/herdr-rotate-claude
source "$S/herdr-rotate-claude"
set +e   # herdr-rotate-claude's own `set -e` (imported by sourcing) would otherwise abort this
         # script on the very failure paths being asserted.

SCREEN_QUIT_CONFIRM=$'─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────\n  Background work is running\n  The following will stop when you exit:\n\n  shell \xc2\xb7 tail -f /dev/null\n\n  \xe2\x9d\xaf 1. Exit and stop tasks\n    2. Move to background and exit\n    3. Stay\n\n  Enter to confirm \xc2\xb7 Esc to cancel'

SENTLOG=$(mktemp)
herdr(){
  case "$1 $2" in
    "agent send-keys") shift 2; printf '%s\n' "$*" >> "$SENTLOG"; echo '{"result":{}}' ;;
    "pane read")       printf '%s' "$SCREEN_QUIT_CONFIRM" ;;
    *) echo '{"result":{}}' ;;
  esac
}
handle_exit_prompt wG:p4
assert_eq "quit-confirmation menu is answered with a bare Enter" "1" "$(grep -cx 'wG:p4 enter' "$SENTLOG")"
: > "$SENTLOG"

# Ordinary output that happens to mention "Esc to cancel" (this menu's own footer shares that
# substring with /status/model/effort's CLAUDE_MODAL_MARKER) must NOT be mistaken for the
# quit-confirmation menu specifically -- the full compound footer ("Enter to confirm", not
# "Enter to set as default") is required, same reasoning as CLAUDE_MODAL_MARKER's own scoping.
herdr(){
  case "$1 $2" in
    "agent send-keys") shift 2; printf '%s\n' "$*" >> "$SENTLOG"; echo '{"result":{}}' ;;
    "pane read")       printf 'some ordinary output\nEnter to set as default \xc2\xb7 Esc to cancel\n' ;;
    *) echo '{"result":{}}' ;;
  esac
}
handle_exit_prompt wG:p4
assert_eq "an unrelated /model-style footer is not mistaken for the quit-confirmation menu" "0" "$(wc -l < "$SENTLOG" | tr -d ' ')"
: > "$SENTLOG"

# A stale mention of the exact footer phrase earlier in scrollback (not the bottommost line) must
# not trigger an Enter either -- same last-non-blank-line scoping as close_modal's own marker
# check.
herdr(){
  case "$1 $2" in
    "agent send-keys") shift 2; printf '%s\n' "$*" >> "$SENTLOG"; echo '{"result":{}}' ;;
    "pane read")       printf 'The docs say: Enter to confirm \xc2\xb7 Esc to cancel\nsome later, unrelated output\n' ;;
    *) echo '{"result":{}}' ;;
  esac
}
handle_exit_prompt wG:p4
assert_eq "stale footer mention above the tail does not trigger an Enter" "0" "$(wc -l < "$SENTLOG" | tr -d ' ')"
: > "$SENTLOG"

# The footer alone is a generic confirm/cancel footer that some OTHER dialog could plausibly
# share -- a bare Enter there would confirm THAT dialog's own default action, not this menu's.
# Without the quit-confirmation's own heading present, nothing must be sent even though the exact
# bottommost footer line matches.
herdr(){
  case "$1 $2" in
    "agent send-keys") shift 2; printf '%s\n' "$*" >> "$SENTLOG"; echo '{"result":{}}' ;;
    "pane read")       printf 'Some other confirmation dialog entirely\n\n  \xe2\x9d\xaf 1. Do something else\n\n  Enter to confirm \xc2\xb7 Esc to cancel\n' ;;
    *) echo '{"result":{}}' ;;
  esac
}
handle_exit_prompt wG:p4
assert_eq "an unrelated dialog sharing the same generic footer is not confirmed" "0" "$(wc -l < "$SENTLOG" | tr -d ' ')"
: > "$SENTLOG"

# Same quit-confirmation menu, but the selection has moved off option 1 (e.g. "2. Move to
# background and exit" is the one currently marked \xe2\x9d\xaf) -- an Enter here would confirm the WRONG
# option, so nothing must be sent even with the right heading and footer both present.
herdr(){
  case "$1 $2" in
    "agent send-keys") shift 2; printf '%s\n' "$*" >> "$SENTLOG"; echo '{"result":{}}' ;;
    "pane read")       printf '  Background work is running\n\n    1. Exit and stop tasks\n  \xe2\x9d\xaf 2. Move to background and exit\n    3. Stay\n\n  Enter to confirm \xc2\xb7 Esc to cancel\n' ;;
    *) echo '{"result":{}}' ;;
  esac
}
handle_exit_prompt wG:p4
assert_eq "option 2 selected instead of option 1 is not confirmed" "0" "$(wc -l < "$SENTLOG" | tr -d ' ')"
: > "$SENTLOG"

# A read failure must not be fatal (handle_exit_prompt is called every round of exit_agent's own
# poll loop, under that loop's `set -e`) and must not send anything.
(
  set -euo pipefail
  source "$S/herdr-rotate-claude"
  herdr(){ return 1; }
  handle_exit_prompt wG:p4
)
assert_eq "a pane-read failure does not abort under set -e" "0" "$?"

# Plain ordinary UI output (no menu at all) must not trigger an Enter.
herdr(){
  case "$1 $2" in
    "agent send-keys") shift 2; printf '%s\n' "$*" >> "$SENTLOG"; echo '{"result":{}}' ;;
    "pane read")       printf 'agent ui drawing\n' ;;
    *) echo '{"result":{}}' ;;
  esac
}
handle_exit_prompt wG:p4
assert_eq "ordinary UI output does not trigger an Enter" "0" "$(wc -l < "$SENTLOG" | tr -d ' ')"

echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
