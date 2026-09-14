#!/usr/bin/env bash
# End-to-end regression: the REAL herdr-rotate-claude detect_override (not a stub) feeding a
# hand-crafted /model screen through the REAL resolve_and_prepare (rotate-common.sh, sourced
# transitively by herdr-rotate-claude). Covers claude's "Default (recommended)" model entry,
# which carries no fixed identifier of its own (only a lossy family alias like "opus", never a
# dated/[1m] identifier -- see detect_override's own DETECTED_MODEL_DEFAULT comment) across all
# three combinations of (baseline present or not) x (live model via Default or a concrete entry):
# neither replaying a stale explicit --model nor synthesizing a new lossy one is ever correct for
# Default -- the only correct relaunch argv has NO --model flag at all, so it naturally follows
# whatever Default resolves to, same as the live session. Stub-level tests for the same gate
# logic already live in test-rotate-fns.sh; this file exercises the REAL claude-specific detector
# that produces the DETECTED_MODEL_DEFAULT signal, not a hand-typed stand-in for it.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/../../../scripts"
PASS=0; FAIL=0
assert_eq(){ if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; echo "    exp:[$2] act:[$3]"; FAIL=$((FAIL+1)); fi; }

# shellcheck source=SCRIPTDIR/../../../scripts/herdr-rotate-claude
source "$S/herdr-rotate-claude"   # transitively sources rotate-common.sh (resolve_and_prepare)
set +e   # herdr-rotate-claude's own `set -e` (imported by sourcing) would otherwise abort this
         # script on the very failure paths being asserted.

ROTATE_DETECT_POLL_SECS=1
MOCK_AGENTS='{"result":{"agents":[{"agent":"claude","pane_id":"wG:p4","name":"lead"}]}}'

# Verbatim (trimmed) from a real live probe -- the Default row is the one currently marked
# (❯ + ✔), its own description reads "currently Opus 5 (1M context)", and the fallback in
# detect_override reduces this to the bare family alias "opus" (no dated version, no [1m]).
SCREEN_DEFAULT_SELECTED=$'  Select model\n\n  \xe2\x9d\xaf 1. Default (recommended) \xe2\x9c\x94  Use the default model (currently Opus 5 (1M context))\n    2. Claude-Sonnet-5[1m]    Custom Sonnet model (1M context)\n\n  \xe2\x97\x90 High effort (default) \xe2\x86\x90/\xe2\x86\x92 to adjust\n\n  Enter to set as default \xc2\xb7 s to use this session only \xc2\xb7 Esc to cancel'
# A concrete numbered entry (not Default) selected instead -- its own specific identifier is
# extracted precisely, no lossy fallback involved.
SCREEN_CONCRETE_SELECTED=$'  Select model\n\n    1. Default (recommended)  Use the default model (currently Opus 5 (1M context))\n  \xe2\x9d\xaf 2. Claude-Sonnet-5[1m] \xe2\x9c\x94  Custom Sonnet model (1M context)\n\n  \xe2\x97\x90 High effort (default) \xe2\x86\x90/\xe2\x86\x92 to adjust\n\n  Enter to set as default \xc2\xb7 s to use this session only \xc2\xb7 Esc to cancel'

STAGE=""; CURRENT_SCREEN=""
# CURRENT_SCREEN is a real global, not a `local` captured by a closure: bash functions resolve
# free variable references via DYNAMIC scope at CALL TIME, not lexical capture at DEFINITION
# time, so a `local` set inside a one-shot setup function is already gone by the time `herdr` is
# actually invoked later from deep inside resolve_and_prepare -- confirmed the hard way (an
# earlier revision of this file used exactly that broken pattern and both cases silently read an
# empty screen, timing out detect_override's readiness wait instead of exercising either path).
mkmock(){ CURRENT_SCREEN="$1"; }   # $1=screen text
herdr(){
  case "$1 $2" in
    "agent list")        printf '%s' "$MOCK_AGENTS" ;;
    "pane process-info") printf '%s' "$MOCK_PROC" ;;
    "agent get")         echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
    "agent send-keys")   STAGE=""; echo '{"result":{}}' ;;
    "agent prompt")      case "$4" in /model) STAGE=model ;; esac; echo '{"result":{}}' ;;
    "pane read")
      case "$STAGE" in model) printf '%s' "$CURRENT_SCREEN" ;; *) printf 'user@host:~$ \n' ;; esac ;;
    *) echo '{"result":{}}' ;;
  esac
}

# Case 1: bare launch (no --model at all -- default_model will be empty), live model resolves via
# Default -- must NOT synthesize an explicit --model override.
MOCK_PROC=$(jq -nc '{result:{process_info:{foreground_processes:[{name:"claude",argv:["claude","--verbose"]}]}}}')
mkmock "$SCREEN_DEFAULT_SELECTED"
OVERRIDE_NAME=""; OVERRIDE_MODEL=""; OVERRIDE_EFFORT=""
resolve_and_prepare claude lead 1
assert_eq "bare launch + live model via Default: no --model synthesized" \
  "0" "$(printf '%s\n' "${BASE_FLAGS[@]}" | grep -cx -- '--model')"
# --effort IS still synthesized here (a bare launch with no --effort either): effort has no
# Default-style lossy fallback of its own, so it's unaffected by the model-specific guard above.
assert_eq "bare launch + live model via Default: only --effort synthesized, no --model" \
  "--verbose --effort high" "${BASE_FLAGS[*]}"

# Case 2: same bare launch, but the live session has a CONCRETE numbered entry selected instead
# of Default -- must synthesize the precise identifier as an explicit --model override.
mkmock "$SCREEN_CONCRETE_SELECTED"
OVERRIDE_NAME=""; OVERRIDE_MODEL=""; OVERRIDE_EFFORT=""
resolve_and_prepare claude lead 1
assert_eq "bare launch + live model via a concrete entry: --model synthesized with the precise identifier" \
  "--verbose --model claude-sonnet-5[1m] --effort high" "${BASE_FLAGS[*]}"

# Case 3: an EXPLICIT baseline WAS captured (--model claude-opus-5[1m] at original launch), but
# the live session has since switched to Default -- must REMOVE the stale --model entirely, not
# replay the old opus value (the original reported bug) and not synthesize the lossy "opus"
# alias either (loses precision and permanently pins away from Default going forward).
MOCK_PROC=$(jq -nc '{result:{process_info:{foreground_processes:[{name:"claude",argv:["claude","--model","claude-opus-5[1m]","--verbose"]}]}}}')
mkmock "$SCREEN_DEFAULT_SELECTED"
OVERRIDE_NAME=""; OVERRIDE_MODEL=""; OVERRIDE_EFFORT=""
resolve_and_prepare claude lead 1
assert_eq "explicit baseline + live model switched to Default: stale --model removed entirely" \
  "--verbose --effort high" "${BASE_FLAGS[*]}"

echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
