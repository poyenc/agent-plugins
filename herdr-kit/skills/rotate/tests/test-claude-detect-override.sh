#!/usr/bin/env bash
# Direct unit test for herdr-rotate-claude's detect_override: both model AND effort are read from
# the SAME /model screen. The synthetic screen below is transcribed from a REAL live probe against
# a running Claude Code v2.1.237 session (herdr agent prompt + herdr pane read against a throwaway
# agent in workspace wG, this session) -- not a hand-constructed guess.
#
# Model detection previously read /status instead (a separate probe): that live probe also
# disproved the fix-before-last's root cause for effort staying empty (the real /effort modal's
# footer DOES say "Enter to confirm", confirmed live) -- /model was already a strictly better
# source for effort regardless (a plain "<Level> effort ... to adjust" text line, no
# column-position math). Model was later moved to read from this same /model screen too: /status
# only ever shows the short alias (e.g. "sonnet"), which can't be reliably compared against a
# launch argv that used the full model identifier instead -- both are valid --model values. Using
# one probe for both values also removes the race window the old two-probe design had between
# them.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/../../scripts"
PASS=0; FAIL=0
assert_eq(){ if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; echo "    exp:[$2] act:[$3]"; FAIL=$((FAIL+1)); fi; }

# shellcheck source=SCRIPTDIR/../../scripts/herdr-rotate-claude
source "$S/herdr-rotate-claude"
set +e   # herdr-rotate-claude's own `set -e` (imported by sourcing) would otherwise abort this
         # script on the very failure paths being asserted.

# Verbatim (trimmed) from `herdr pane read` against a real /model modal -- current selection is
# marked by BOTH the cursor (❯) and a checkmark (✔) on the same line; the live effort appears as
# a plain "<Level> effort ... to adjust" line below the model list, with no "(default)" suffix
# in this particular capture (that suffix is conditional on the level matching the account-wide
# saved default -- also observed live, in a separate capture, and not required for detection).
SCREEN_MODEL=$'  Select model\n  Switch between Claude models. Your pick becomes the default for new sessions.\n\n    1. Default (recommended)  Use the default model (currently Opus 5 (1M context))\n    2. Claude-Opus-5[1m]      Custom Opus model (1M context)\n  \xe2\x9d\xaf 3. Claude-Sonnet-5[1m] \xe2\x9c\x94  Custom Sonnet model (1M context)\n    4. Claude-Haiku-4.5       Custom Haiku model\n\n  \xe2\x97\x90 Medium effort \xe2\x86\x90/\xe2\x86\x92 to adjust\n\n  Enter to set as default \xc2\xb7 s to use this session only \xc2\xb7 Esc to cancel'

STAGE=""
herdr(){
  case "$1 $2" in
    "agent send-keys") STAGE=""; echo '{"result":{}}' ;;
    "agent get")       echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
    "agent prompt")    case "$4" in /model) STAGE=model ;; esac; echo '{"result":{}}' ;;
    "pane read")
      # Default (STAGE=""): the pane's plain idle prompt, as a real `herdr pane read` never
      # actually returns truly empty content -- close_modal's defensive pre-close needs a
      # NON-empty, marker-free read to confirm "nothing is open" (see the empty-read fixture
      # below for why empty specifically must NOT be treated as confirmed-closed).
      case "$STAGE" in model) printf '%s' "$SCREEN_MODEL" ;; *) printf 'user@host:~$ \n' ;; esac ;;
    *) echo '{"result":{}}' ;;
  esac
}
ROTATE_DETECT_POLL_SECS=1

detect_override wG:p4
assert_eq "detect_override succeeds"                       "0"      "$?"
assert_eq "model recovered from /model's own marked row"   "claude-sonnet-5" "$DETECTED_MODEL"
assert_eq "effort recovered from /model"                   "medium" "$DETECTED_EFFORT"

# A stale "<Model> with <level> effort" banner line sitting earlier in the same scrollback (no
# "adjust" on it) must not be mistaken for the modal's own current-effort line.
STAGE=""
SCREEN_MODEL_WITH_BANNER=$'  Sonnet 5 with high effort \xc2\xb7 API Usage Billing\n'"$SCREEN_MODEL"
herdr(){
  case "$1 $2" in
    "agent send-keys") STAGE=""; echo '{"result":{}}' ;;
    "agent get")       echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
    "agent prompt")    case "$4" in /model) STAGE=model ;; esac; echo '{"result":{}}' ;;
    "pane read")
      case "$STAGE" in model) printf '%s' "$SCREEN_MODEL_WITH_BANNER" ;; *) printf 'user@host:~$ \n' ;; esac ;;
    *) echo '{"result":{}}' ;;
  esac
}
detect_override wG:p4
assert_eq "stale banner line ('high effort', no adjust) is ignored" "medium" "$DETECTED_EFFORT"

# A stale line can coincidentally carry BOTH "effort" and "adjust" on the same line (e.g.
# leftover scrollback from an earlier /model invocation this same session, or just ordinary
# English) -- the modal's OWN current-effort line must still win because it's the newest
# (bottommost) match, not the first one found scanning top-down.
STAGE=""
SCREEN_MODEL_WITH_STALE_ADJUST=$'High effort can be changed later to adjust behavior\n'"$SCREEN_MODEL"
herdr(){
  case "$1 $2" in
    "agent send-keys") STAGE=""; echo '{"result":{}}' ;;
    "agent get")       echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
    "agent prompt")    case "$4" in /model) STAGE=model ;; esac; echo '{"result":{}}' ;;
    "pane read")
      case "$STAGE" in model) printf '%s' "$SCREEN_MODEL_WITH_STALE_ADJUST" ;; *) printf 'user@host:~$ \n' ;; esac ;;
    *) echo '{"result":{}}' ;;
  esac
}
detect_override wG:p4
assert_eq "stale line with its own 'effort'+'adjust' does not beat the modal's own line" "medium" "$DETECTED_EFFORT"

# A stale marked-row-like line (its own ❯/✔ pair, e.g. leftover scrollback from an earlier
# /model invocation this same session pointing at a DIFFERENT model) must not beat the modal's
# own current selection -- tail -n1 must pick the newest (bottommost) marked row, not the first.
STAGE=""
SCREEN_MODEL_WITH_STALE_ROW=$'  \xe2\x9d\xaf 2. Claude-Opus-5[1m] \xe2\x9c\x94  Custom Opus model (1M context)\n'"$SCREEN_MODEL"
herdr(){
  case "$1 $2" in
    "agent send-keys") STAGE=""; echo '{"result":{}}' ;;
    "agent get")       echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
    "agent prompt")    case "$4" in /model) STAGE=model ;; esac; echo '{"result":{}}' ;;
    "pane read")
      case "$STAGE" in model) printf '%s' "$SCREEN_MODEL_WITH_STALE_ROW" ;; *) printf 'user@host:~$ \n' ;; esac ;;
    *) echo '{"result":{}}' ;;
  esac
}
detect_override wG:p4
assert_eq "stale marked row (different model) does not beat the modal's own current selection" "claude-sonnet-5" "$DETECTED_MODEL"

# A model that landed on the list some other way (e.g. via --model at launch, rather than being
# one of the four standard numbered entries) gets its own row whose PRIMARY label is a
# SPACE-separated display name ("Sonnet 5", not "Claude-Sonnet-5[1m]") -- the real identifier
# only appears parenthesized in the description instead. Verbatim (trimmed) from a REAL live
# probe against Claude Code v2.1.237 (herdr agent prompt + herdr pane read against a throwaway
# agent in workspace wF). A position-relative-to-the-checkmark extraction grabs only the
# trailing "5" from "Sonnet 5" here -- this reproduces a real reported bug (a relaunch that
# replayed "--model 5").
STAGE=""
SCREEN_MODEL_LAUNCH_ENTRY=$'  Select model\n  Switch between Claude models. Your pick becomes the default for new sessions. For other/previous model names, specify with --model.\n\n    1. Default (recommended)  Use the default model (currently Opus 5 (1M context)) \xc2\xb7 $5/$25 per Mtok\n    2. Claude-Opus-5[1m]      Custom Opus model (1M context)\n    3. Claude-Sonnet-5[1m]    Custom Sonnet model (1M context)\n    4. Claude-Haiku-4.5       Custom Haiku model\n  \xe2\x9d\xaf 5. Sonnet 5 \xe2\x9c\x94             Efficient for routine tasks (Claude-Sonnet-5[1m])\n\n  \xe2\x97\x90 Medium effort \xe2\x86\x90/\xe2\x86\x92 to adjust\n\n  Enter to set as default \xc2\xb7 s to use this session only \xc2\xb7 Esc to cancel'
herdr(){
  case "$1 $2" in
    "agent send-keys") STAGE=""; echo '{"result":{}}' ;;
    "agent get")       echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
    "agent prompt")    case "$4" in /model) STAGE=model ;; esac; echo '{"result":{}}' ;;
    "pane read")
      case "$STAGE" in model) printf '%s' "$SCREEN_MODEL_LAUNCH_ENTRY" ;; *) printf 'user@host:~$ \n' ;; esac ;;
    *) echo '{"result":{}}' ;;
  esac
}
detect_override wG:p4
assert_eq "a launch-time --model entry's real identifier is found in its description, not truncated to a trailing digit" "claude-sonnet-5" "$DETECTED_MODEL"

# Two dated versions within the SAME family (e.g. Sonnet 4.5 vs Sonnet 5) both show the identical
# generic "Custom Sonnet model" description -- extraction must read the row's own specific
# identifier, not that shared description, or a live switch between them would be invisible.
STAGE=""
SCREEN_MODEL_SONNET45=$'  Select model\n\n    1. Default (recommended)  Use the default model (currently Opus 5 (1M context))\n  \xe2\x9d\xaf 2. Claude-Sonnet-4-5[1m] \xe2\x9c\x94  Custom Sonnet model\n\n  \xe2\x97\x90 Medium effort \xe2\x86\x90/\xe2\x86\x92 to adjust\n\n  Enter to set as default \xc2\xb7 s to use this session only \xc2\xb7 Esc to cancel'
herdr(){
  case "$1 $2" in
    "agent send-keys") STAGE=""; echo '{"result":{}}' ;;
    "agent get")       echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
    "agent prompt")    case "$4" in /model) STAGE=model ;; esac; echo '{"result":{}}' ;;
    "pane read")
      case "$STAGE" in model) printf '%s' "$SCREEN_MODEL_SONNET45" ;; *) printf 'user@host:~$ \n' ;; esac ;;
    *) echo '{"result":{}}' ;;
  esac
}
detect_override wG:p4
assert_eq "same-family, different dated version is extracted distinctly (not just 'sonnet')" "claude-sonnet-4-5" "$DETECTED_MODEL"

# close_modal itself: an unrelated mention of the marker phrase earlier in scrollback (not the
# bottommost lines) must not be mistaken for a still-open modal.
herdr(){
  case "$1 $2" in
    "agent send-keys") echo '{"result":{}}' ;;
    "pane read") printf 'The documentation says Esc to cancel when a modal is open.\n\nsome later output\nmore output\n' ;;
    *) echo '{"result":{}}' ;;
  esac
}
assert_eq "close_modal ignores an unrelated marker mention above the tail" "0" "$(close_modal wG:p4 >/dev/null 2>&1; echo $?)"

# A fixed multi-line tail window isn't narrow enough either: an unrelated mention on the line
# just ABOVE genuine trailing output can still fall inside it. Only the exact last non-blank line
# may ever be treated as the modal's own footer.
herdr(){
  case "$1 $2" in
    "agent send-keys") echo '{"result":{}}' ;;
    "pane read") printf 'some output\nThe documentation says Esc to cancel when a modal is open.\nlast real line\n' ;;
    *) echo '{"result":{}}' ;;
  esac
}
assert_eq "close_modal ignores an unrelated marker mention on the second-to-last line" "0" "$(close_modal wG:p4 >/dev/null 2>&1; echo $?)"

# close_modal must actually poll and retry, not just check once: the marker genuinely present on
# the first read, then genuinely gone on a later read, must still resolve to "closed". A plain
# shell variable can't track this across calls -- `out=$(herdr ...)` runs the mock in a SUBSHELL,
# so any mutation to a shell variable inside it is discarded the moment that command substitution
# returns; a file-backed counter is required to actually persist across reads.
CLOSE_ROUND_FILE=$(mktemp); echo 0 > "$CLOSE_ROUND_FILE"
herdr(){
  case "$1 $2" in
    "agent send-keys") echo '{"result":{}}' ;;
    "pane read")
      local n; n=$(( $(cat "$CLOSE_ROUND_FILE") + 1 )); echo "$n" > "$CLOSE_ROUND_FILE"
      if [ "$n" -lt 2 ]; then printf 'Esc to cancel\n'; else printf 'closed now\n'; fi ;;
    *) echo '{"result":{}}' ;;
  esac
}
ROTATE_DETECT_POLL_SECS=5
assert_eq "close_modal succeeds once the marker actually disappears on a later poll" "0" "$(close_modal wG:p4 >/dev/null 2>&1; echo $?)"
assert_eq "close_modal actually re-read the pane more than once" "1" "$([ "$(cat "$CLOSE_ROUND_FILE")" -gt 1 ] && echo 1 || echo 0)"
rm -f "$CLOSE_ROUND_FILE"

# close_modal's marker extraction must never itself be fatal under `set -euo pipefail` (this
# script's own `set +e` above would otherwise mask that): an empty/all-blank `herdr pane read`
# is a normal, retryable polling outcome, not an error -- confirmed live that a plain (non-
# `local`) `var=$(failing pipeline)` assignment IS fatal there, aborting the whole rotation over
# a single transient short read. Run in an actual `set -e` subshell, not this file's own
# `set +e` context, or the very bug being tested for would be invisible. An empty read must ALSO
# NOT be treated as confirmed closure on its own (a genuinely closed pane always has SOME content,
# e.g. a shell prompt) -- confirmed live that a single blank redraw made close_modal report
# "closed" immediately, which can recreate the original race if the modal is genuinely still open
# and just happened to render blank on that one read. This fixture makes the FIRST read blank (a
# transient redraw) and the SECOND read the real, still-open marker -- both hazards are covered by
# a single case: no crash, no false-positive "closed", and it must actually re-read more than once.
EMPTY_ROUND_FILE=$(mktemp); echo 0 > "$EMPTY_ROUND_FILE"
(
  set -euo pipefail
  source "$S/herdr-rotate-claude"
  herdr(){
    case "$1 $2" in
      "agent send-keys") return 0 ;;
      "pane read")
        local n; n=$(( $(cat "$EMPTY_ROUND_FILE") + 1 )); echo "$n" > "$EMPTY_ROUND_FILE"
        if [ "$n" -lt 2 ]; then printf ''; else printf 'Esc to cancel\n'; fi ;;
    esac
    return 0
  }
  ROTATE_DETECT_POLL_SECS=5
  close_modal wG:p4
)
assert_eq "close_modal on a blank-then-still-open read times out (not a crash, not a false-positive close)" "1" "$?"
assert_eq "close_modal actually re-read the pane after a blank read, not just once" "1" "$([ "$(cat "$EMPTY_ROUND_FILE")" -gt 1 ] && echo 1 || echo 0)"
rm -f "$EMPTY_ROUND_FILE"

# Same hazard, different call site: detect_override's /model readiness loop extracts the last
# non-blank line on EVERY poll iteration, including the very first one, which can easily see an
# empty/all-blank read before the modal has rendered at all -- not just once at the very end like
# close_modal. Confirmed live: this specific line, before being routed through last_nonblank_line,
# aborted the whole script on an empty read.
(
  set -euo pipefail
  source "$S/herdr-rotate-claude"
  herdr(){
    case "$1 $2" in
      "agent send-keys") return 0 ;;
      "agent get")       printf '{"result":{"agent":{"agent_status":"idle"}}}\n' ;;
      "agent prompt")    return 0 ;;
      "pane read")       printf '' ;;
    esac
    return 0
  }
  ROTATE_DETECT_POLL_SECS=1
  detect_override wG:p4
)
assert_eq "detect_override's /model readiness check on an empty read does not abort under set -e" "1" "$?"

# The /model readiness ("seen") gate must use the SAME last-non-blank-line scoping as
# close_modal's own marker check -- an unscoped scan can find a stale footer phrase left over
# from before this rotation even started and report a value from that old scrollback instead of
# correctly recognizing the fresh modal never actually rendered this round.
STAGE=""
herdr(){
  case "$1 $2" in
    "agent send-keys") STAGE=""; echo '{"result":{}}' ;;
    "agent get")       echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
    "agent prompt")    case "$4" in /model) STAGE=model ;; esac; echo '{"result":{}}' ;;
    "pane read")
      case "$STAGE" in
        model) printf '\xe2\x9d\xaf STALE-WRONG-VALUE \xe2\x9c\x94  Custom Opus model\nEnter to set as default \xc2\xb7 Esc to cancel\n\n> \n' ;;
        *) printf 'user@host:~$ \n' ;;
      esac ;;
    *) echo '{"result":{}}' ;;
  esac
}
ROTATE_DETECT_POLL_SECS=1
detect_override wG:p4
assert_eq "stale marked row not on the readiness gate's own screen is not mistaken for a fresh /model" "" "$DETECTED_MODEL"

# The Default row's own description ("currently X") is the fallback pattern for when THAT row is
# the one marked as currently selected (no "Custom ... model" phrase on it).
STAGE=""
SCREEN_MODEL_DEFAULT_SELECTED=$'  Select model\n\n  \xe2\x9d\xaf 1. Default (recommended) \xe2\x9c\x94  Use the default model (currently Opus 5 (1M context))\n    2. Claude-Sonnet-5[1m]    Custom Sonnet model (1M context)\n\n  \xe2\x97\x90 High effort (default) \xe2\x86\x90/\xe2\x86\x92 to adjust\n\n  Enter to set as default \xc2\xb7 s to use this session only \xc2\xb7 Esc to cancel'
herdr(){
  case "$1 $2" in
    "agent send-keys") STAGE=""; echo '{"result":{}}' ;;
    "agent get")       echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
    "agent prompt")    case "$4" in /model) STAGE=model ;; esac; echo '{"result":{}}' ;;
    "pane read")
      case "$STAGE" in model) printf '%s' "$SCREEN_MODEL_DEFAULT_SELECTED" ;; *) printf 'user@host:~$ \n' ;; esac ;;
    *) echo '{"result":{}}' ;;
  esac
}
detect_override wG:p4
assert_eq "Default row's own 'currently X' description is the fallback when it's the selected row" "opus" "$DETECTED_MODEL"

echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
