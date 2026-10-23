#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/bg-timeout-cap.sh"
PASS=0; FAIL=0
assert_eq(){ if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; echo "    exp:[$2] act:[$3]"; FAIL=$((FAIL+1)); fi; }

# $1 = command, $2 = run_in_background ("" for omitted, else "true"/"false")
payload() {
  python3 -c "
import json, sys
d = {'tool_input': {'command': sys.argv[1]}}
if sys.argv[2]:
    d['tool_input']['run_in_background'] = (sys.argv[2] == 'true')
print(json.dumps(d))
" "$1" "$2"
}

# $1 = JSON payload, remaining args (optional) = NAME=VALUE env overrides for this one call.
run_hook() {
  local json="$1"; shift
  env "$@" bash -c 'printf "%s" "$1" | bash "$2"' _ "$json" "$SCRIPT"
}

is_block() { printf '%s' "$1" | jq -r '.decision == "block"' 2>/dev/null; }

echo "== foreground calls are entirely out of scope for this hook =="

out=$(run_hook "$(payload "./build.sh" "")")
assert_eq "run_in_background omitted: allowed (no output)" "" "$out"

out=$(run_hook "$(payload "./build.sh" "false")")
assert_eq "run_in_background:false: allowed (no output)" "" "$out"

echo "== background, no timeout wrapper at all =="

out=$(run_hook "$(payload "./build.sh" "true")")
assert_eq "no wrapper: blocked" "true" "$(is_block "$out")"
assert_eq "block reason explains the enforcement gap" "true" "$(printf '%s' "$out" | jq -R 'test("NOT enforced for run_in_background")' 2>/dev/null)"
assert_eq "block reason gives a concrete wrap example" "true" "$(printf '%s' "$out" | jq -R 'test("timeout 300 bash script\\.sh")' 2>/dev/null)"
assert_eq "block reason states the cap" "true" "$(printf '%s' "$out" | jq -R 'test("600 seconds")' 2>/dev/null)"

out=$(run_hook "$(payload "cd /tmp && timeout 300 ./build.sh" "true")")
assert_eq "wrapper not at the start of the command (chained): blocked, same as no wrapper" "true" "$(is_block "$out")"

out=$(run_hook "$(payload "FOO=bar timeout 300 ./build.sh" "true")")
assert_eq "wrapper prefixed by an env var assignment: blocked, same as no wrapper" "true" "$(is_block "$out")"

echo "== background, wrapped, within the default 600-second cap =="

out=$(run_hook "$(payload "timeout 300 ./build.sh" "true")")
assert_eq "bare seconds under cap: allowed (no output)" "" "$out"

out=$(run_hook "$(payload "timeout 600 ./build.sh" "true")")
assert_eq "bare seconds at cap: allowed (cap is inclusive, no output)" "" "$out"

out=$(run_hook "$(payload "timeout 9m ./build.sh" "true")")
assert_eq "9m (540s) under cap: allowed (no output)" "" "$out"

echo "== background, wrapped, over the default 600-second cap =="

out=$(run_hook "$(payload "timeout 900 ./build.sh" "true")")
assert_eq "bare seconds over cap: blocked" "true" "$(is_block "$out")"
assert_eq "block reason states the declared value and unit" "true" "$(printf '%s' "$out" | jq -R 'test("timeout:900 ")' 2>/dev/null)"
assert_eq "block reason states seconds equivalent" "true" "$(printf '%s' "$out" | jq -R 'test("\\(900 seconds\\)")' 2>/dev/null)"
assert_eq "block reason states the cap" "true" "$(printf '%s' "$out" | jq -R 'test("600 second cap")' 2>/dev/null)"

out=$(run_hook "$(payload "timeout 30m ./build.sh" "true")")
assert_eq "30m (1800s) over cap: blocked" "true" "$(is_block "$out")"
assert_eq "minutes converted to seconds in the reason" "true" "$(printf '%s' "$out" | jq -R 'test("\\(1800 seconds\\)")' 2>/dev/null)"

out=$(run_hook "$(payload "timeout 1h ./build.sh" "true")")
assert_eq "1h (3600s) over cap: blocked" "true" "$(is_block "$out")"
assert_eq "hours converted to seconds in the reason" "true" "$(printf '%s' "$out" | jq -R 'test("\\(3600 seconds\\)")' 2>/dev/null)"

out=$(run_hook "$(payload "timeout 1d ./build.sh" "true")")
assert_eq "1d (86400s) over cap: blocked" "true" "$(is_block "$out")"
assert_eq "days converted to seconds in the reason" "true" "$(printf '%s' "$out" | jq -R 'test("\\(86400 seconds\\)")' 2>/dev/null)"

echo "== basic DURATION grammar: zero, decimals, oversized numerals, inf =="

out=$(run_hook "$(payload "timeout 0 ./build.sh" "true")")
assert_eq "timeout 0: blocked (GNU timeout: 0 disables the timeout entirely)" "true" "$(is_block "$out")"
assert_eq "zero block reason explains it disables the timeout" "true" "$(printf '%s' "$out" | jq -R 'test("disables the timeout entirely")' 2>/dev/null)"

out=$(run_hook "$(payload "timeout 0s ./build.sh" "true")")
assert_eq "timeout 0s: blocked, same as bare 0" "true" "$(is_block "$out")"

out=$(run_hook "$(payload "timeout 0.0 ./build.sh" "true")")
assert_eq "timeout 0.0: blocked, same as bare 0" "true" "$(is_block "$out")"

out=$(run_hook "$(payload "timeout 300.5 ./build.sh" "true")")
assert_eq "decimal duration under cap: allowed (no output)" "" "$out"

out=$(run_hook "$(payload "timeout 999.5 ./build.sh" "true")")
assert_eq "decimal duration over cap: blocked" "true" "$(is_block "$out")"
assert_eq "decimal block reason states the declared value" "true" "$(printf '%s' "$out" | jq -R 'test("timeout:999\\.5 ")' 2>/dev/null)"

out=$(run_hook "$(payload "timeout 12345678901 ./build.sh" "true")")
assert_eq "11-digit numeral, obviously over any cap: blocked, not failed open" "true" "$(is_block "$out")"

out=$(run_hook "$(payload "timeout 99999999999d ./build.sh" "true")")
assert_eq "huge numeral with a day suffix: blocked, not failed open" "true" "$(is_block "$out")"

out=$(run_hook "$(payload "timeout inf ./build.sh" "true")")
assert_eq "timeout inf: blocked (unbounded duration)" "true" "$(is_block "$out")"
assert_eq "inf block reason explains it's unbounded" "true" "$(printf '%s' "$out" | jq -R 'test("unbounded duration")' 2>/dev/null)"

out=$(run_hook "$(payload "timeout infinity ./build.sh" "true")")
assert_eq "timeout infinity: blocked, same as inf" "true" "$(is_block "$out")"

out=$(run_hook "$(payload "timeout INF ./build.sh" "true")")
assert_eq "timeout INF (uppercase): blocked, case-insensitive" "true" "$(is_block "$out")"

echo "== scope: only DURATION is recognized, no GNU timeout options at all -- a command using"
echo "   -k/-s/--foreground/etc isn't recognized as a wrapper (false block, safe direction) =="

out=$(run_hook "$(payload "timeout -k 10 300 ./build.sh" "true")")
assert_eq "timeout -k 10 300 ...: options not supported, blocked same as no wrapper" "true" "$(is_block "$out")"

out=$(run_hook "$(payload "timeout -s KILL 300 ./build.sh" "true")")
assert_eq "timeout -s KILL 300 ...: options not supported, blocked same as no wrapper" "true" "$(is_block "$out")"

out=$(run_hook "$(payload "timeout --foreground 300 ./build.sh" "true")")
assert_eq "timeout --foreground 300 ...: options not supported, blocked same as no wrapper" "true" "$(is_block "$out")"

echo "== owner-scoped decision: conservative LITERAL separator scan, no quote-awareness at all --"
echo "   a command merely CONTAINING one of these characters blocks, even inside quotes =="

out=$(run_hook "$(payload "timeout 300 first; second" "true")")
assert_eq "semicolon sequencing: blocked" "true" "$(is_block "$out")"
assert_eq "block reason explains the separator/script-file guidance" "true" "$(printf '%s' "$out" | jq -R 'test("shell separator")' 2>/dev/null)"
assert_eq "...and recommends a script file as the escape hatch" "true" "$(printf '%s' "$out" | jq -R 'test("timeout 300 bash script\\.sh")' 2>/dev/null)"

out=$(run_hook "$(payload "timeout 300 first && second" "true")")
assert_eq "&& chaining: blocked" "true" "$(is_block "$out")"

out=$(run_hook "$(payload "timeout 300 first || second" "true")")
assert_eq "|| chaining: blocked" "true" "$(is_block "$out")"

out=$(run_hook "$(payload "timeout 300 first | second" "true")")
assert_eq "pipe: blocked" "true" "$(is_block "$out")"

out=$(run_hook "$(payload "(timeout 300 first); second" "true")")
assert_eq "subshell parens + semicolon: blocked" "true" "$(is_block "$out")"

multiline_cmd=$'timeout 300 bash -c \'first\nsecond\''
out=$(run_hook "$(payload "$multiline_cmd" "true")")
assert_eq "a literal newline anywhere in the string: blocked, no quote-awareness" "true" "$(is_block "$out")"

out=$(run_hook "$(payload "timeout 300 bash -c 'first; second'" "true")")
assert_eq "a separator INSIDE a quoted bash -c body: still blocked (intentional, no escape hatch)" "true" "$(is_block "$out")"

out=$(run_hook "$(payload "timeout 300 echo 'a;b'" "true")")
assert_eq "a separator inside a quoted literal argument: still blocked (intentional)" "true" "$(is_block "$out")"

out=$(run_hook "$(payload "timeout 300 bash script.sh" "true")")
assert_eq "the recommended escape hatch itself (no separators): allowed (no output)" "" "$out"

echo "== backtick substitution and redirections run BEFORE timeout's own exec even starts, so"
echo "   timeout never bounds them -- verified live: timeout 0.05 cat </tmp/fifo on an unread"
echo "   FIFO did not time out. Must block the same as a top-level separator =="

out=$(run_hook "$(payload 'timeout 300 echo `second`' "true")")
assert_eq "backtick command substitution: blocked" "true" "$(is_block "$out")"

out=$(run_hook "$(payload "timeout 300 cat </tmp/fifo" "true")")
assert_eq "input redirection: blocked" "true" "$(is_block "$out")"

out=$(run_hook "$(payload "timeout 300 cmd >/tmp/out" "true")")
assert_eq "output redirection: blocked" "true" "$(is_block "$out")"

out=$(run_hook "$(payload "timeout 300 echo 'a<b'" "true")")
assert_eq "a redirection-shaped character inside a quoted argument: still blocked (intentional)" "true" "$(is_block "$out")"

echo "== malformed / edge forms =="

out=$(run_hook "$(payload "timeout" "true")")
assert_eq "bare 'timeout' with nothing after it: blocked (no recognizable wrapper)" "true" "$(is_block "$out")"

out=$(run_hook "$(payload "timeoutsomething 300 ./build.sh" "true")")
assert_eq "command word merely starting with 'timeout' (not the command itself): blocked, not a real wrapper" "true" "$(is_block "$out")"

out=$(run_hook "$(payload "timeout KILL ./build.sh" "true")")
assert_eq "token isn't a valid duration at all: blocked, not failed open" "true" "$(is_block "$out")"

echo "== custom cap via env var =="

out=$(run_hook "$(payload "timeout 300 ./build.sh" "true")" GUARDRAILS_MAX_BG_TIMEOUT_SECONDS=100)
assert_eq "custom lower cap: a timeout that passed the default now blocks" "true" "$(is_block "$out")"

out=$(run_hook "$(payload "timeout 900 ./build.sh" "true")" GUARDRAILS_MAX_BG_TIMEOUT_SECONDS=3600)
assert_eq "custom higher cap: a timeout that failed the default now passes (no output)" "" "$out"

out=$(run_hook "$(payload "timeout 900 ./build.sh" "true")" GUARDRAILS_MAX_BG_TIMEOUT_SECONDS=not-a-number)
assert_eq "malformed cap env var: falls back to default, still blocks" "true" "$(is_block "$out")"
assert_eq "malformed cap env var: reason uses the default cap value" "true" "$(printf '%s' "$out" | jq -R 'test("600 second cap")' 2>/dev/null)"

echo "== registration: wired into hooks.json under PreToolUse/Bash =="

HOOKS_JSON="$HERE/../hooks.json"
registered=$(jq -r '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[].command] | any(test("bg-timeout-cap\\.sh"))' "$HOOKS_JSON" 2>/dev/null)
assert_eq "hooks.json registers bg-timeout-cap.sh under PreToolUse/Bash" "true" "$registered"

echo
echo "bg-timeout-cap.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
