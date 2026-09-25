#!/usr/bin/env bash
# Tests for no-herdr-wait.sh: block direct `herdr pane wait-output` / `herdr agent wait`
# invocations, steering to run_in_background + polling instead. Command-position aware (via
# scan-guard-lib.sh), so a mere mention of the words is not blocked -- only a real invocation.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/no-herdr-wait.sh"
PASS=0; FAIL=0
assert_eq(){ if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; echo "    exp:[$2] act:[$3]"; FAIL=$((FAIL+1)); fi; }

mkjson(){ jq -nc --arg c "$1" '{session_id:"t",tool_name:"Bash",tool_input:{command:$c}}'; }
run(){ printf '%s' "$(mkjson "$1")" | HERDR_ENV=1 bash "$SCRIPT"; }
noherdr(){ printf '%s' "$(mkjson "$1")" | env -u HERDR_ENV bash "$SCRIPT"; }
decision(){ [ -n "$1" ] || { echo none; return; }; printf '%s' "$1" | jq -r '.decision // "none"' 2>/dev/null; }
valid_json(){ [ -n "$1" ] || { echo ok; return; }; printf '%s' "$1" | jq -e . >/dev/null 2>&1 && echo ok || echo bad; }
blk(){ decision "$(run "$1")"; }   # "block" or "none"

echo "== BLOCK: bare invocations of both commands =="
assert_eq "herdr pane wait-output p1 --match foo"       block "$(blk 'herdr pane wait-output p1 --match foo')"
assert_eq "herdr agent wait myagent --until idle"       block "$(blk 'herdr agent wait myagent --until idle')"
assert_eq "compound: echo hi && herdr agent wait foo"   block "$(blk 'echo hi && herdr agent wait foo')"
assert_eq "bash -c 'herdr pane wait-output p1 --match x'" block "$(blk "bash -c 'herdr pane wait-output p1 --match x'")"
assert_eq '"herdr" "pane" "wait-output" p1 (quoted words)' block "$(blk '"herdr" "pane" "wait-output" p1 --match x')"

echo "== ALLOW: disambiguation from herdr-prompt-guard's own --wait form =="
assert_eq "herdr agent prompt foo --wait (different command, not agent wait)" none "$(blk 'herdr agent prompt foo --wait')"

echo "== ALLOW: unrelated / non-matching herdr calls =="
assert_eq "herdr pane read p1 --lines 50"          none "$(blk 'herdr pane read p1 --lines 50')"
assert_eq "herdr agent list"                        none "$(blk 'herdr agent list')"
assert_eq "herdr agent get myagent"                 none "$(blk 'herdr agent get myagent')"
assert_eq "empty command"                           none "$(blk '')"

echo "== ALLOW: a mere mention (not a real invocation) is not blocked =="
assert_eq "grep -r 'wait-output' . (word present, not run as herdr)" none "$(blk "grep -r 'wait-output' .")"
assert_eq "echo 'herdr agent wait is banned' (prose mention)"        none "$(blk "echo 'herdr agent wait is banned'")"

echo "== documented fail-open: shared scan-guard-lib prechecks that DO apply here still apply =="
assert_eq "sudo -u root herdr agent wait foo (wrapper value-option)" none "$(blk 'sudo -u root herdr agent wait foo')"

echo "== NOT fail-open: a HOME mutation is irrelevant to this command-identity matcher =="
assert_eq "HOME=/tmp herdr agent wait foo (prefix assignment)"        block "$(blk 'HOME=/tmp herdr agent wait foo')"
assert_eq "env HOME=/tmp herdr pane wait-output p1 --match x (wrapper)" block "$(blk 'env HOME=/tmp herdr pane wait-output p1 --match x')"
assert_eq "herdr agent wait foo --extra HOME=/tmp (payload, not a real assignment)" block "$(blk 'herdr agent wait foo --extra HOME=/tmp')"

echo "== block payload is valid JSON and explains the fix =="
out=$(run 'herdr agent wait foo')
assert_eq "block payload parses as JSON" ok "$(valid_json "$out")"
assert_eq "reason mentions run_in_background" yes "$(printf '%s' "$out" | jq -r .reason | grep -qi 'run_in_background' && echo yes || echo no)"
assert_eq "reason mentions polling with a short read"  yes "$(printf '%s' "$out" | jq -r .reason | grep -qiE 'pane read|agent read' && echo yes || echo no)"

echo "== no-op outside herdr =="
assert_eq "HERDR_ENV unset: allowed even for a real invocation" none "$(decision "$(noherdr 'herdr agent wait foo')")"

echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
