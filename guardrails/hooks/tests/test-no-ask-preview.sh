#!/usr/bin/env bash
# Tests for no-ask-preview.sh: block AskUserQuestion calls where any option carries a non-empty
# `preview` field; allow plain questions.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/no-ask-preview.sh"
PASS=0; FAIL=0
assert_eq(){ if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; echo "    exp:[$2] act:[$3]"; FAIL=$((FAIL+1)); fi; }

run(){ printf '%s' "$1" | bash "$SCRIPT"; }
decision(){ [ -n "$1" ] || { echo none; return; }; printf '%s' "$1" | jq -r '.decision // "none"' 2>/dev/null; }
blk(){ decision "$(run "$1")"; }
mk(){ jq -nc --argjson q "$1" '{session_id:"t",tool_name:"AskUserQuestion",tool_input:{questions:$q}}'; }

PLAIN='[{"question":"Which?","header":"H","multiSelect":false,"options":[{"label":"A","description":"a"},{"label":"B","description":"b"}]}]'
PREVIEW='[{"question":"Which?","header":"H","multiSelect":false,"options":[{"label":"A","description":"a","preview":"code a"},{"label":"B","description":"b"}]}]'
PREVIEW_SECOND_Q='[{"question":"One?","header":"H1","multiSelect":false,"options":[{"label":"A","description":"a"},{"label":"B","description":"b"}]},{"question":"Two?","header":"H2","multiSelect":false,"options":[{"label":"C","description":"c"},{"label":"D","description":"d","preview":"x"}]}]'
MULTISELECT_PREVIEW='[{"question":"Which?","header":"H","multiSelect":true,"options":[{"label":"A","description":"a","preview":"code a"},{"label":"B","description":"b"}]}]'
NULL_PREVIEW='[{"question":"Which?","header":"H","multiSelect":false,"options":[{"label":"A","description":"a","preview":null},{"label":"B","description":"b"}]}]'
EMPTY_PREVIEW='[{"question":"Which?","header":"H","multiSelect":false,"options":[{"label":"A","description":"a","preview":""},{"label":"B","description":"b"}]}]'

echo "== BLOCK: a preview on any option of any question =="
assert_eq "preview on one option"          block "$(blk "$(mk "$PREVIEW")")"
assert_eq "preview on a multi-select question (any option of any question)" block "$(blk "$(mk "$MULTISELECT_PREVIEW")")"
assert_eq "preview in the second question" block "$(blk "$(mk "$PREVIEW_SECOND_Q")")"

echo "== ALLOW: plain questions and degenerate inputs =="
assert_eq "plain question"                 none "$(blk "$(mk "$PLAIN")")"
assert_eq "empty-string preview"           none "$(blk "$(mk "$EMPTY_PREVIEW")")"
assert_eq "null preview"                   none "$(blk "$(mk "$NULL_PREVIEW")")"
assert_eq "no questions field"             none "$(blk '{"tool_name":"AskUserQuestion","tool_input":{}}')"
assert_eq "empty questions array"          none "$(blk "$(mk '[]')")"

echo "== block payload is valid JSON and steers to plain text =="
out=$(run "$(mk "$PREVIEW")")
assert_eq "payload parses as JSON" ok "$(printf '%s' "$out" | jq -e . >/dev/null 2>&1 && echo ok || echo bad)"
assert_eq "reason steers to plain text" yes "$(printf '%s' "$out" | jq -r .reason | grep -qi 'plain text' && echo yes || echo no)"

# The hook process must exit 0 on BOTH allow and block: the decision is in the JSON body, and Claude
# Code ignores that body unless the hook exits 0 (exit 1 is a non-blocking error, so a preview call
# would slip through; exit 2 blocks via stderr instead, which is not this hook's mechanism).
run_rc(){ printf '%s' "$1" | bash "$SCRIPT" >/dev/null 2>&1; echo $?; }
assert_eq "allow path: hook process exits 0" "0" "$(run_rc "$(mk "$PLAIN")")"
assert_eq "block path: hook process exits 0 (decision is in the JSON body, not the exit code)" "0" "$(run_rc "$(mk "$PREVIEW")")"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
