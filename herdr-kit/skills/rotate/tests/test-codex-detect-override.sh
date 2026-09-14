#!/usr/bin/env bash
# Direct unit test for herdr-rotate-codex's detect_override (now source-able: the dispatch at the
# bottom of herdr-rotate-codex is guarded by `[ "${BASH_SOURCE[0]}" = "${0}" ]`, matching
# herdr-rotate-{claude,pi}, so sourcing it here does not run — and die on — the empty argv).
#
# codex reads model/effort from its own /status printout. Freshness is gated on a NEW "/status"
# echo actually rendering (the echo count increasing), so the mock returns a bare idle screen for
# the baseline read and the /status panel only after the /status prompt has been sent.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/../../../scripts"
PASS=0; FAIL=0
assert_eq(){ if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; echo "    exp:[$2] act:[$3]"; FAIL=$((FAIL+1)); fi; }

# shellcheck source=SCRIPTDIR/../../../scripts/herdr-rotate-codex
source "$S/herdr-rotate-codex"
set +e   # herdr-rotate-codex's own `set -e` (imported by sourcing) would otherwise abort this
         # script on the very miss paths being asserted.
ROTATE_DETECT_POLL_SECS=1

STATUS_SENT=$(mktemp)
# The post-/status read carries PRE-status pane history ahead of the fresh "/status" echo, so a
# dump that leaks the whole recent-unwrapped snapshot (rather than the isolated after_marker) is
# detectable by the sentinel below appearing in the log.
PRE_SENTINEL='PRE-STATUS-SENTINEL-earlier-history'
mk_codex_mock(){   # $1 = the /status panel body rendered AFTER a fresh /status echo
  AFTER_BODY="$1"
  echo 0 > "$STATUS_SENT"
  herdr(){
    case "$1 $2" in
      "agent prompt") case "$4" in /status) echo 1 > "$STATUS_SENT" ;; esac; echo '{"result":{}}' ;;
      "pane read")
        if [ "$(cat "$STATUS_SENT" 2>/dev/null)" = 1 ]; then printf '%s\n/status\n%s\n' "$PRE_SENTINEL" "$AFTER_BODY"
        else printf 'idle screen\n'; fi ;;
      "pane edges") echo '{}' ;;
      *) echo '{"result":{}}' ;;
    esac
  }
}

# (a) clean detect: a well-formed "Model: <name> (reasoning <level>)" line parses both values, and
# emits no miss diagnostic.
CXDIAG_ERR=$(mktemp)
mk_codex_mock 'Model: gpt-5.6-terra (reasoning high)'
DETECTED_MODEL=x DETECTED_EFFORT=x
detect_override wG:p4 2>"$CXDIAG_ERR"
assert_eq "clean detect: model parsed"  "gpt-5.6-terra" "$DETECTED_MODEL"
assert_eq "clean detect: effort parsed" "high"          "$DETECTED_EFFORT"
assert_eq "clean detect emits no miss diagnostic" "0" "$(grep -c 'detect_override miss' "$CXDIAG_ERR")"

# (b) genuine parse miss, panel SEEN: the /status panel DID render (Model line present, seen=1), but
# an adverse wrap spliced a border glyph into the model name, so the corruption guard blanks it ->
# empty. The ISOLATED after_marker must be dumped (Finding 3) -- NOT the full snapshot -- so the
# wrap point is diagnosable without copying unrelated pre-/status history into the log.
mk_codex_mock 'Model: gpt-5.6│terra (reasoning high)'
DETECTED_MODEL=x DETECTED_EFFORT=x
detect_override wG:p4 2>"$CXDIAG_ERR"
assert_eq "corrupted-name detect leaves model empty" "" "$DETECTED_MODEL"
assert_eq "seen-but-unparsed logs the shown-Model-line miss" "1" \
  "$(grep -c 'detect_override miss: codex /status shown' "$CXDIAG_ERR")"
assert_eq "the miss dump includes the actual on-screen Model line" "1" "$(grep -c 'gpt-5.6' "$CXDIAG_ERR")"
assert_eq "the miss dump does NOT leak pre-/status pane history (isolated after_marker only)" "0" \
  "$(grep -c "$PRE_SENTINEL" "$CXDIAG_ERR")"

# (c) fresh /status echo observed, but its Model line drifted out of the recognized shape: seen
# stays 0, yet after_marker WAS populated for that fresh response -- so the ISOLATED after_marker
# must be dumped, NOT the full snapshot (the same Finding-3 isolation as case (b), in the other
# branch). A codex session always has a model, so this is still a miss.
mk_codex_mock 'status panel with no recognizable model line here'
DETECTED_MODEL=x DETECTED_EFFORT=x
detect_override wG:p4 2>"$CXDIAG_ERR"
assert_eq "shape-drift miss leaves model empty" "" "$DETECTED_MODEL"
assert_eq "shape-drift miss logs the no-parseable-Model-line miss" "1" \
  "$(grep -c 'detect_override miss: codex /status produced no parseable Model line' "$CXDIAG_ERR")"
assert_eq "shape-drift miss dumps the isolated response, not pre-/status history" "0" \
  "$(grep -c "$PRE_SENTINEL" "$CXDIAG_ERR")"
assert_eq "shape-drift miss dump includes the drifted panel body" "1" \
  "$(grep -c 'no recognizable model line' "$CXDIAG_ERR")"

# (d) no fresh /status echo EVER appears (the prompt didn't take, or the panel vanished):
# after_marker stays empty, so the only thing to show is the last snapshot $out -- the fallback
# branch. The mock never emits a "/status" echo line, so after_count never exceeds before_count.
herdr(){
  case "$1 $2" in
    "agent prompt") echo '{"result":{}}' ;;
    "pane read")    printf 'NOFRESH-SENTINEL idle content, no status echo line\n' ;;
    "pane edges")   echo '{}' ;;
    *) echo '{"result":{}}' ;;
  esac
}
DETECTED_MODEL=x DETECTED_EFFORT=x
detect_override wG:p4 2>"$CXDIAG_ERR"
assert_eq "no-fresh-echo miss leaves model empty" "" "$DETECTED_MODEL"
assert_eq "no-fresh-echo miss logs the no-parseable-Model-line miss" "1" \
  "$(grep -c 'detect_override miss: codex /status produced no parseable Model line' "$CXDIAG_ERR")"
assert_eq "no-fresh-echo miss falls back to the last snapshot" "1" "$(grep -c 'NOFRESH-SENTINEL' "$CXDIAG_ERR")"

rm -f "$STATUS_SENT" "$CXDIAG_ERR"
echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
