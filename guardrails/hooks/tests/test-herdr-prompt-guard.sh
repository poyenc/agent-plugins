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
valid_json(){ printf '%s' "$1" | jq -e . >/dev/null 2>&1 && echo ok || echo bad; }
has(){ printf '%s' "$1" | grep -qiF -- "$2" && echo yes || echo no; }

echo "== BLOCK: herdr agent prompt carrying --wait (flag anywhere, incl. at the end) =="
assert_eq "prompt ... --wait (at end)"         "block" "$(decision "$(run 'herdr agent prompt foo "hi" --wait')")"
assert_eq "prompt ... --wait --timeout"        "block" "$(decision "$(run 'herdr agent prompt foo "hi" --wait --timeout 5000')")"
assert_eq "prompt ... --wait --until idle"     "block" "$(decision "$(run 'herdr agent prompt foo "hi" --wait --until idle')")"
assert_eq "compound with ; "                   "block" "$(decision "$(run 'echo hi ; herdr agent prompt foo "x" --wait')")"
assert_eq "compound with ||"                   "block" "$(decision "$(run 'do_thing || herdr agent prompt foo "x" --wait')")"
assert_eq "compound with && + --timeout"       "block" "$(decision "$(run 'a && herdr agent prompt foo "x" --wait --timeout 3000')")"
assert_eq "--wait=true (=-attached value)"     "block" "$(decision "$(run 'herdr agent prompt foo "x" --wait=true')")"
assert_eq "sudo-wrapped (no-option wrapper)"    "block" "$(decision "$(run 'sudo herdr agent prompt foo "x" --wait')")"
assert_eq "through bash -c"                     "block" "$(decision "$(run "bash -c 'herdr agent prompt foo \"x\" --wait'")")"

echo "== BLOCK reason: valid JSON, points to the message skill + --callback =="
blkout=$(run 'herdr agent prompt foo x --wait')
assert_eq "block payload parses as JSON"       "ok"  "$(valid_json "$blkout")"
assert_eq "block reason names --callback"      "yes" "$(has "$(printf '%s' "$blkout" | jq -r .reason)" -- '--callback')"
assert_eq "block reason names the message skill" "yes" "$(has "$(printf '%s' "$blkout" | jq -r .reason)" 'message')"

echo "== BLOCK: plain herdr agent prompt (no --wait) is banned too, not just hinted =="
plainout=$(run 'herdr agent prompt foo "hi"')
assert_eq "plain prompt: valid JSON"           "ok"    "$(valid_json "$plainout")"
assert_eq "plain prompt: blocked"              "block" "$(decision "$plainout")"
assert_eq "plain prompt: no allow permissionDecision" "none" "$(perm "$plainout")"
assert_eq "plain prompt: reason names --callback" "yes" "$(has "$(printf '%s' "$plainout" | jq -r .reason)" -- '--callback')"

echo "== SILENT allow: not a herdr agent prompt at all (no output, no auto-approve) =="
assert_eq "agent start --timeout (rotation)"   "" "$(run 'herdr agent start --timeout 120000 -- claude --model opus')"
assert_eq "agent list"                         "" "$(run 'herdr agent list')"
assert_eq "agent get"                          "" "$(run 'herdr agent get foo')"
assert_eq "message-skill send --callback"      "" "$(run '/plug/herdr-kit/skills/message/scripts/herdr-message send foo "hi" --callback')"

echo "== SILENT allow: a MENTION of the phrase is not an invocation (command-position-aware) =="
assert_eq "git grep for the phrase"            "" "$(run "git grep 'herdr agent prompt'")"
assert_eq "printf-ing the phrase"               "" "$(run 'printf "herdr agent prompt\n"')"
assert_eq "message-skill send whose BODY names the phrase" "" \
  "$(run '/plug/herdr-kit/skills/message/scripts/herdr-message send foo "Please replace herdr agent prompt with the message skill" --callback')"

echo "== BLOCK: a HOME mention/mutation must not suppress this guard (HOME only matters to blind-scan root detection) =="
assert_eq "HOME=/tmp prefix assignment"        "block" "$(decision "$(run 'HOME=/tmp herdr agent prompt foo hi')")"
assert_eq "env HOME=/tmp wrapper"              "block" "$(decision "$(run 'env HOME=/tmp herdr agent prompt foo hi')")"
assert_eq "message body literally HOME=/tmp"   "block" "$(decision "$(run 'herdr agent prompt foo "HOME=/tmp"')")"

echo "== documented fail-open: an unquoted backslash-newline line continuation is data-shaped and missed =="
# Matches scan-guard-lib.sh's own _has_quoted_newline contract (shared by no-blind-find/-search):
# such a split fails the WHOLE command open rather than risk mis-splitting real quoted data.
assert_eq "line-split (newline before prompt): missed, not mis-blocked" "" "$(run $'herdr agent \\\nprompt foo "x" --wait')"

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
run 'herdr agent prompt foo "hi" --wait' >/dev/null 2>&1; assert_eq "--wait path exits 0" "0" "$?"
run 'herdr agent prompt foo "hi"'        >/dev/null 2>&1; assert_eq "plain path exits 0"  "0" "$?"
run 'herdr agent list'                    >/dev/null 2>&1; assert_eq "silent path exits 0" "0" "$?"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
