#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/no-long-foreground.sh"
PASS=0; FAIL=0
assert_eq(){ if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; echo "    exp:[$2] act:[$3]"; FAIL=$((FAIL+1)); fi; }

# $1 = run_in_background ("" for omitted, else "true"/"false"), $2 = timeout ("" for omitted)
payload() {
  python3 -c "
import json, sys
d = {'session_id': 'test', 'tool_name': 'Bash', 'tool_input': {'command': 'echo hi'}}
if sys.argv[1]:
    d['tool_input']['run_in_background'] = (sys.argv[1] == 'true')
if sys.argv[2]:
    d['tool_input']['timeout'] = int(sys.argv[2])
print(json.dumps(d))
" "$1" "$2"
}

# $1 = JSON payload, remaining args (optional) = NAME=VALUE env overrides for this one call.
run_hook() {
  local json="$1"; shift
  env "$@" bash -c 'printf "%s" "$1" | bash "$2"' _ "$json" "$SCRIPT"
}

is_block() { printf '%s' "$1" | jq -r '.decision == "block"' 2>/dev/null; }

# 1. run_in_background:true, no timeout at all -> always allowed, this hook only gates foreground.
out=$(run_hook "$(payload "true" "")")
assert_eq "background, no timeout: allowed (no output)" "" "$out"

# 2. run_in_background:true, huge timeout -> still allowed, background calls are out of scope here.
out=$(run_hook "$(payload "true" "999999999")")
assert_eq "background, huge timeout: allowed (no output)" "" "$out"

# 3. Foreground, no timeout declared -> blocked (unbounded blocking risk).
out=$(run_hook "$(payload "" "")")
assert_eq "foreground, no timeout: blocked" "true" "$(is_block "$out")"
assert_eq "block reason explains no declared timeout" "true" "$(printf '%s' "$out" | jq -R 'test("no declared timeout")' 2>/dev/null)"

# 4. Foreground, explicit run_in_background:false, no timeout -> blocked, same as omitted.
out=$(run_hook "$(payload "false" "")")
assert_eq "foreground (explicit false), no timeout: blocked" "true" "$(is_block "$out")"

# 5. Foreground, timeout under the default 60000ms cap -> allowed.
out=$(run_hook "$(payload "" "5000")")
assert_eq "foreground, timeout under default cap: allowed (no output)" "" "$out"

# 6. Foreground, timeout exactly at the default cap -> allowed (cap is inclusive).
out=$(run_hook "$(payload "" "60000")")
assert_eq "foreground, timeout at default cap: allowed (no output)" "" "$out"

# 7. Foreground, timeout over the default cap -> blocked, reason states both numbers.
out=$(run_hook "$(payload "" "90000")")
assert_eq "foreground, timeout over default cap: blocked" "true" "$(is_block "$out")"
assert_eq "block reason states declared timeout" "true" "$(printf '%s' "$out" | jq -R 'test("timeout:90000 ms")' 2>/dev/null)"
assert_eq "block reason states the cap" "true" "$(printf '%s' "$out" | jq -R 'test("60000 ms cap")' 2>/dev/null)"
assert_eq "block reason steers to run_in_background" "true" "$(printf '%s' "$out" | jq -R 'test("run_in_background:true")' 2>/dev/null)"
assert_eq "block reason steers to CronCreate/ScheduleWakeup" "true" "$(printf '%s' "$out" | jq -R 'test("CronCreate or ScheduleWakeup")' 2>/dev/null)"

# 8. Custom cap via env var -- a timeout that would pass the default cap is now blocked.
out=$(run_hook "$(payload "" "5000")" GUARDRAILS_MAX_FOREGROUND_TIMEOUT_MS=1000)
assert_eq "custom lower cap: foreground timeout above it is blocked" "true" "$(is_block "$out")"

# 9. Custom cap via env var -- raises the ceiling, a timeout that would fail the default cap passes.
out=$(run_hook "$(payload "" "90000")" GUARDRAILS_MAX_FOREGROUND_TIMEOUT_MS=120000)
assert_eq "custom higher cap: foreground timeout under it is allowed (no output)" "" "$out"

# 10. Malformed cap env var (non-numeric) -- falls back to the documented default (60000).
out=$(run_hook "$(payload "" "90000")" GUARDRAILS_MAX_FOREGROUND_TIMEOUT_MS=not-a-number)
assert_eq "malformed cap env var: falls back to default, still blocks" "true" "$(is_block "$out")"
assert_eq "malformed cap env var: reason uses default cap value" "true" "$(printf '%s' "$out" | jq -R 'test("60000 ms cap")' 2>/dev/null)"

# 11. Leading-zero cap env var (e.g. an operator typo "01000") -- same convention as
# read-guard.sh's GUARDRAILS_MAX_READ_BYTES: rejected outright (not parsed as decimal or
# octal), falls back to the documented default (60000) rather than misbehaving on it.
out=$(run_hook "$(payload "" "90000")" GUARDRAILS_MAX_FOREGROUND_TIMEOUT_MS=01000)
assert_eq "leading-zero cap env var: falls back to default, still blocks" "true" "$(is_block "$out")"
assert_eq "leading-zero cap env var: reason uses default cap value" "true" "$(printf '%s' "$out" | jq -R 'test("60000 ms cap")' 2>/dev/null)"

# 12. A malformed timeout value (string type, doesn't parse as a plain decimal) -- not this
# hook's schema to enforce, fail open rather than guess.
out=$(run_hook '{"session_id":"test","tool_name":"Bash","tool_input":{"command":"echo hi","timeout":"not-a-number"}}')
assert_eq "malformed timeout value (string): fails open, allowed (no output)" "" "$out"

# 13. timeout:"" (present, empty string) must NOT be collapsed into "absent" -- that would
# misreport it as "no declared timeout" instead of the documented fail-open for a malformed
# present value (this was the bug `// empty` caused: `empty` and "" compare equal).
out=$(run_hook '{"session_id":"test","tool_name":"Bash","tool_input":{"command":"echo hi","timeout":""}}')
assert_eq "timeout:'' (present, empty string): fails open, allowed (no output)" "" "$out"

# 14. timeout:false -- same collapse risk as #13 (jq's `// empty` treats false as falsy too).
out=$(run_hook '{"session_id":"test","tool_name":"Bash","tool_input":{"command":"echo hi","timeout":false}}')
assert_eq "timeout:false: fails open, allowed (no output)" "" "$out"

# 15. timeout:null (explicit JSON null) -- semantically "no timeout declared", same as the key
# being absent entirely, distinct from a malformed-but-present value like #12-14.
out=$(run_hook '{"session_id":"test","tool_name":"Bash","tool_input":{"command":"echo hi","timeout":null}}')
assert_eq "timeout:null: blocked, same as absent" "true" "$(is_block "$out")"
assert_eq "timeout:null: block reason explains no declared timeout" "true" "$(printf '%s' "$out" | jq -R 'test("no declared timeout")' 2>/dev/null)"

# 16. timeout as a negative number or a non-integer float -- also malformed for this field,
# fails open same as #12-14.
out=$(run_hook '{"session_id":"test","tool_name":"Bash","tool_input":{"command":"echo hi","timeout":-5000}}')
assert_eq "negative timeout: fails open, allowed (no output)" "" "$out"
out=$(run_hook '{"session_id":"test","tool_name":"Bash","tool_input":{"command":"echo hi","timeout":5000.5}}')
assert_eq "non-integer timeout: fails open, allowed (no output)" "" "$out"

# 17. Non-Bash tool call (hook only matched on Bash via hooks.json, but defend in depth) --
# missing tool_input.command entirely still must not crash the hook.
out=$(run_hook '{"session_id":"test","tool_name":"Bash","tool_input":{}}')
assert_eq "empty tool_input, no run_in_background/timeout: blocked (treated as foreground)" "true" "$(is_block "$out")"

# 18. Registration: wired into hooks.json under PreToolUse/Bash, same convention the other
# hook tests assert for themselves.
HOOKS_JSON="$HERE/../hooks.json"
registered=$(jq -r '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[].command] | any(test("no-long-foreground\\.sh"))' "$HOOKS_JSON" 2>/dev/null)
assert_eq "hooks.json registers no-long-foreground.sh under PreToolUse/Bash" "true" "$registered"

# pi branch ("harness":"pi", as guardrails/pi-extensions/bash-guardrails.ts sends): no
# run_in_background concept at all -- every call is foreground, timeout is already in seconds.

# $1 = timeout ("" for omitted/null distinctions handled by raw payloads below)
pi_payload() {
  python3 -c "
import json, sys
d = {'tool_input': {'command': 'echo hi'}, 'harness': 'pi'}
if sys.argv[1]:
    d['tool_input']['timeout'] = int(sys.argv[1])
print(json.dumps(d))
" "$1"
}

# 19. pi, no timeout declared -> blocked, pi-specific message (Agent tool / schedule_prompt,
# no mention of run_in_background since pi has no such field).
out=$(run_hook "$(pi_payload "")")
assert_eq "pi, no timeout: blocked" "true" "$(is_block "$out")"
assert_eq "pi block reason explains no declared timeout" "true" "$(printf '%s' "$out" | jq -R 'test("no declared timeout")' 2>/dev/null)"
assert_eq "pi block reason steers to the Agent tool" "true" "$(printf '%s' "$out" | jq -R 'test("Agent tool")' 2>/dev/null)"
assert_eq "pi block reason steers to schedule_prompt" "true" "$(printf '%s' "$out" | jq -R 'test("schedule_prompt")' 2>/dev/null)"
assert_eq "pi block reason never mentions run_in_background" "false" "$(printf '%s' "$out" | jq -R 'test("run_in_background")' 2>/dev/null)"

# 20. pi, timeout under the default 60-second cap -> allowed.
out=$(run_hook "$(pi_payload "10")")
assert_eq "pi, timeout under default cap: allowed (no output)" "" "$out"

# 21. pi, timeout exactly at the default cap -> allowed (cap is inclusive).
out=$(run_hook "$(pi_payload "60")")
assert_eq "pi, timeout at default cap: allowed (no output)" "" "$out"

# 22. pi, timeout over the default cap -> blocked, reason states seconds (not ms) and the
# pi-specific cap env var default.
out=$(run_hook "$(pi_payload "120")")
assert_eq "pi, timeout over default cap: blocked" "true" "$(is_block "$out")"
assert_eq "pi block reason states declared timeout in seconds" "true" "$(printf '%s' "$out" | jq -R 'test("timeout:120 seconds")' 2>/dev/null)"
assert_eq "pi block reason states the 60 second cap" "true" "$(printf '%s' "$out" | jq -R 'test("60 second cap")' 2>/dev/null)"

# 23. pi, custom cap via its own (seconds) env var -- distinct from the Claude-side
# GUARDRAILS_MAX_FOREGROUND_TIMEOUT_MS, confirming the two caps don't cross-apply.
out=$(run_hook "$(pi_payload "120")" GUARDRAILS_MAX_FOREGROUND_TIMEOUT_SECONDS=600)
assert_eq "pi custom higher cap (seconds): allowed (no output)" "" "$out"
out=$(run_hook "$(pi_payload "120")" GUARDRAILS_MAX_FOREGROUND_TIMEOUT_MS=99999999)
assert_eq "pi ignores the ms-named cap entirely: still blocked at the 60s default" "true" "$(is_block "$out")"

# 24. pi, malformed timeout (same fail-open contract as the Claude branch, shared via the lib).
out=$(run_hook '{"tool_input":{"command":"echo hi","timeout":false},"harness":"pi"}')
assert_eq "pi, timeout:false: fails open, allowed (no output)" "" "$out"

echo
echo "no-long-foreground.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
