#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/herdr-prompt-guard.sh"
PASS=0; FAIL=0
assert_eq(){ if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; echo "    exp:[$2] act:[$3]"; FAIL=$((FAIL+1)); fi; }

mkjson(){ jq -nc --arg c "$1" '{session_id:"t",tool_name:"Bash",tool_input:{command:$c}}'; }
# Run hook on a command string, HERDR_ENV=1 (in-herdr). Prints hook stdout.
run(){ printf '%s' "$(mkjson "$1")" | HERDR_ENV=1 bash "$SCRIPT"; }
# Run hook on already-built JSON with an explicit HERDR_ENV state: "1", "0", or "unset".
run_env(){ local json="$1" state="$2"; if [ "$state" = unset ]; then printf '%s' "$json" | env -u HERDR_ENV bash "$SCRIPT"; else printf '%s' "$json" | HERDR_ENV="$state" bash "$SCRIPT"; fi; }
decision(){ [ -n "$1" ] || { echo none; return; }; printf '%s' "$1" | jq -r '.decision // "none"' 2>/dev/null; }
perm(){ printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null; }
ctx(){ printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }
valid_json(){ printf '%s' "$1" | jq -e . >/dev/null 2>&1 && echo ok || echo bad; }
has(){ printf '%s' "$1" | grep -qiF -- "$2" && echo yes || echo no; }

echo "== BLOCK: herdr agent prompt carrying --wait (flag anywhere, incl. at the end) =="
assert_eq "prompt ... --wait (at end)"         "block" "$(decision "$(run 'herdr agent prompt foo "hi" --wait')")"
assert_eq "prompt ... --wait --timeout"        "block" "$(decision "$(run 'herdr agent prompt foo "hi" --wait --timeout 5000')")"
assert_eq "prompt ... --wait --until idle"     "block" "$(decision "$(run 'herdr agent prompt foo "hi" --wait --until idle')")"
assert_eq "compound with ; "                   "block" "$(decision "$(run 'echo hi ; herdr agent prompt foo "x" --wait')")"
assert_eq "compound with ||"                   "block" "$(decision "$(run 'do_thing || herdr agent prompt foo "x" --wait')")"
assert_eq "compound with && + --timeout"       "block" "$(decision "$(run 'a && herdr agent prompt foo "x" --wait --timeout 3000')")"
assert_eq "line-split (newline before prompt)" "block" "$(decision "$(run $'herdr agent \\\nprompt foo "x" --wait')")"
assert_eq "--wait=true (=-attached value)"     "block" "$(decision "$(run 'herdr agent prompt foo "x" --wait=true')")"

echo "== BLOCK reason: valid JSON, points to the message skill + --callback, no fire-and-forget tail =="
blkout=$(run 'herdr agent prompt foo x --wait')
assert_eq "block payload parses as JSON"       "ok"  "$(valid_json "$blkout")"
assert_eq "block reason names --callback"      "yes" "$(has "$(printf '%s' "$blkout" | jq -r .reason)" -- '--callback')"
assert_eq "block reason has no F&F tail"       "no"  "$(has "$(printf '%s' "$blkout" | jq -r .reason)" 'fire-and-forget')"

echo "== ALLOW + hint: plain herdr agent prompt (no --wait) =="
hintout=$(run 'herdr agent prompt foo "hi"')
assert_eq "plain prompt: valid JSON"           "ok"    "$(valid_json "$hintout")"
assert_eq "plain prompt: no block decision"    "none"  "$(decision "$hintout")"
assert_eq "plain prompt: permissionDecision"   "allow" "$(perm "$hintout")"
assert_eq "plain prompt: hint names --callback" "yes"  "$(has "$(ctx "$hintout")" -- '--callback')"
assert_eq "plain prompt: hint is fire-and-forget framed" "yes" "$(has "$(ctx "$hintout")" 'fire-and-forget')"

echo "== SILENT allow: not a herdr agent prompt at all (no output, no auto-approve) =="
assert_eq "agent start --timeout (rotation)"   "" "$(run 'herdr agent start --timeout 120000 -- claude --model opus')"
assert_eq "agent list"                         "" "$(run 'herdr agent list')"
assert_eq "agent get"                          "" "$(run 'herdr agent get foo')"
assert_eq "message-skill send --callback"      "" "$(run '/plug/herdr-kit/skills/message/scripts/herdr-message send foo "hi" --callback')"

echo "== no-op outside herdr (HERDR_ENV != 1) =="
blk=$(mkjson 'herdr agent prompt foo "hi" --wait')
plain=$(mkjson 'herdr agent prompt foo "hi"')
assert_eq "HERDR_ENV unset, --wait: no output"  "" "$(run_env "$blk" unset)"
assert_eq "HERDR_ENV=0, --wait: no output"      "" "$(run_env "$blk" 0)"
assert_eq "HERDR_ENV unset, plain: no output"   "" "$(run_env "$plain" unset)"
assert_eq "HERDR_ENV=1, --wait: blocked"    "block" "$(decision "$(run_env "$blk" 1)")"

echo "== fail-open / robustness =="
assert_eq "no command field: no output" "" "$(run_env "$(jq -nc '{tool_input:{}}')" 1)"
assert_eq "empty command: no output"    "" "$(run '')"

echo "== hook process always exits 0 (decision is in the JSON body) =="
run 'herdr agent prompt foo "hi" --wait' >/dev/null 2>&1; assert_eq "block path exits 0" "0" "$?"
run 'herdr agent prompt foo "hi"'        >/dev/null 2>&1; assert_eq "hint path exits 0"  "0" "$?"
run 'herdr agent list'                    >/dev/null 2>&1; assert_eq "silent path exits 0" "0" "$?"

echo "== known limitation: a --wait token inside the message body is matched (accepted false positive) =="
assert_eq "body containing --wait: blocked (documented tradeoff)" "block" "$(decision "$(run 'herdr agent prompt foo "please --wait for me"')")"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
