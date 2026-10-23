#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/bg-timeout-cap.sh"
PASS=0; FAIL=0
assert_eq(){ if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; echo "    exp:[$2] act:[$3]"; FAIL=$((FAIL+1)); fi; }

# Builds a tool_input payload. Args (all optional, pass "" to omit/skip):
#   $1 = command (string)
#   $2 = run_in_background ("" omit, else "true"/"false")
#   $3 = timeout ("" omit, "null" for JSON null, else a raw JSON scalar e.g. 3000, 3000.5, "\"3000\"")
#   $4 = extra field value to attach as tool_input.description (for field-preservation checks), "" to omit
payload() {
  python3 -c "
import json, sys
cmd, bg, to, extra = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
d = {'tool_input': {'command': cmd}}
if bg:
    d['tool_input']['run_in_background'] = (bg == 'true')
if to == 'null':
    d['tool_input']['timeout'] = None
elif to:
    d['tool_input']['timeout'] = json.loads(to)
if extra:
    d['tool_input']['description'] = extra
print(json.dumps(d))
" "$1" "$2" "$3" "$4"
}

# $1 = JSON payload, remaining args (optional) = NAME=VALUE env overrides for this one call.
run_hook() {
  local json="$1"; shift
  env "$@" bash -c 'printf "%s" "$1" | bash "$2"' _ "$json" "$SCRIPT"
}

is_block() { printf '%s' "$1" | jq -r '.decision == "block"' 2>/dev/null; }
rewritten_command() { printf '%s' "$1" | jq -r '.hookSpecificOutput.updatedInput.command // empty' 2>/dev/null; }

echo "== foreground calls are entirely out of scope for this hook =="

out=$(run_hook "$(payload "./build.sh" "" "" "")")
assert_eq "run_in_background omitted: allowed (no output)" "" "$out"

out=$(run_hook "$(payload "./build.sh" "false" "" "")")
assert_eq "run_in_background:false: allowed (no output)" "" "$out"

echo "== background call must declare a timeout (same field foreground already requires) =="

out=$(run_hook "$(payload "./build.sh" "true" "" "")")
assert_eq "no timeout field at all: blocked" "true" "$(is_block "$out")"
assert_eq "block reason explains the enforcement gap" "true" "$(printf '%s' "$out" | jq -R 'test("NOT enforced for run_in_background")' 2>/dev/null)"
assert_eq "block reason states the cap" "true" "$(printf '%s' "$out" | jq -R 'test("600 seconds")' 2>/dev/null)"

out=$(run_hook "$(payload "./build.sh" "true" "null" "")")
assert_eq "timeout:null: blocked, same as absent" "true" "$(is_block "$out")"

out=$(run_hook "$(payload "./build.sh" "true" "\"3000\"" "")")
assert_eq "timeout as a JSON string (schema violation): blocked, not coerced" "true" "$(is_block "$out")"
assert_eq "...block reason explains it's not a valid integer ms value" "true" "$(printf '%s' "$out" | jq -R 'test("valid non-negative integer millisecond")' 2>/dev/null)"

out=$(run_hook "$(payload "./build.sh" "true" "-5" "")")
assert_eq "negative timeout: blocked" "true" "$(is_block "$out")"

out=$(run_hook "$(payload "./build.sh" "true" "3000.5" "")")
assert_eq "non-integer (fractional ms) timeout: blocked" "true" "$(is_block "$out")"

out=$(run_hook "$(payload "./build.sh" "true" "0" "")")
assert_eq "timeout:0: blocked (GNU timeout: 0 disables the timeout entirely)" "true" "$(is_block "$out")"
assert_eq "zero block reason explains it disables the timeout" "true" "$(printf '%s' "$out" | jq -R 'test("disables the timeout entirely")' 2>/dev/null)"

echo "== within cap: rewritten to timeout SECs bash -c '...', no permissionDecision, other"
echo "   tool_input fields preserved byte-for-byte =="

out=$(run_hook "$(payload "./build.sh" "true" "3000" "")")
assert_eq "3000ms (3s) under cap: rewritten command is 'timeout 3.000s bash -c ...'" "timeout 3.000s bash -c './build.sh'" "$(rewritten_command "$out")"
assert_eq "hookEventName is PreToolUse" "true" "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName == "PreToolUse"')"
assert_eq "permissionDecision is NOT set (normal permission flow applies)" "true" "$(printf '%s' "$out" | jq -r '(.hookSpecificOutput | has("permissionDecision")) | not')"
assert_eq "run_in_background preserved as true in updatedInput" "true" "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput.run_in_background == true')"
assert_eq "original timeout field preserved unchanged" "true" "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput.timeout == 3000')"

out=$(run_hook "$(payload "./build.sh" "true" "3000" "a description field")")
assert_eq "an unrelated extra field (description) survives byte-for-byte" "a description field" "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput.description')"

out=$(run_hook "$(payload "./build.sh" "true" "1" "")")
assert_eq "1ms: sub-second precision preserved, not floored to 0s" "timeout 0.001s bash -c './build.sh'" "$(rewritten_command "$out")"

out=$(run_hook "$(payload "./build.sh" "true" "1500" "")")
assert_eq "1500ms: 1.5s, not floored to 1s" "timeout 1.500s bash -c './build.sh'" "$(rewritten_command "$out")"

out=$(run_hook "$(payload "./build.sh" "true" "600000" "")")
assert_eq "600000ms (600s) at cap: allowed (cap is inclusive)" "timeout 600.000s bash -c './build.sh'" "$(rewritten_command "$out")"

echo "== over cap: BLOCKED, not silently clamped =="

out=$(run_hook "$(payload "./build.sh" "true" "900000" "")")
assert_eq "900000ms (900s) over cap: blocked" "true" "$(is_block "$out")"
assert_eq "block reason states the declared ms and seconds" "true" "$(printf '%s' "$out" | jq -R 'test("timeout:900000ms \\(900 seconds\\)")' 2>/dev/null)"
assert_eq "block reason states the cap" "true" "$(printf '%s' "$out" | jq -R 'test("600 second cap")' 2>/dev/null)"
assert_eq "over-cap case produces NO updatedInput (not a silent clamp)" "" "$(rewritten_command "$out")"

echo "== escaping correctness: the rewritten command actually round-trips through real bash =="

run_wrapped_and_capture() {
  # $1 = wrapped command string (as the hook would produce it). Executes it for real and
  # prints stdout, to prove the escaping reconstructs the EXACT original argument, not just
  # that the string looks plausible.
  bash -c "$1"
}

quote_cmd=$(printf 'echo "has a single quote%s"' "'")
out=$(run_hook "$(payload "$quote_cmd" "true" "3000" "")")
wrapped=$(rewritten_command "$out")
assert_eq "command containing a literal single quote: wrapped command executes and reproduces the original output" "has a single quote'" "$(run_wrapped_and_capture "$wrapped")"

multiline_cmd=$'echo first\necho second'
out=$(run_hook "$(payload "$multiline_cmd" "true" "3000" "")")
wrapped=$(rewritten_command "$out")
assert_eq "a command containing a real newline (e.g. multiple statements): both lines execute" $'first\nsecond' "$(run_wrapped_and_capture "$wrapped")"

heredoc_cmd=$'cat <<EOF\nline one\nline two\nEOF'
out=$(run_hook "$(payload "$heredoc_cmd" "true" "3000" "")")
wrapped=$(rewritten_command "$out")
assert_eq "a heredoc: executes correctly through the rewritten wrapper (no longer banned)" $'line one\nline two' "$(run_wrapped_and_capture "$wrapped")"

echo "== the hazards the old literal-scan design banned are now structurally bounded instead,"
echo "   not banned -- not re-tested for timing here (covered live in the session), just that"
echo "   these forms are no longer rejected and still execute correctly =="

out=$(run_hook "$(payload "echo first; echo second" "true" "3000" "")")
wrapped=$(rewritten_command "$out")
assert_eq "semicolon-separated commands: no longer blocked, both execute" $'first\nsecond' "$(run_wrapped_and_capture "$wrapped")"

out=$(run_hook "$(payload 'echo `echo sub`' "true" "3000" "")")
wrapped=$(rewritten_command "$out")
assert_eq "backtick substitution: no longer blocked, substitutes correctly" "sub" "$(run_wrapped_and_capture "$wrapped")"

out=$(run_hook "$(payload "echo redirected > /tmp/bg-timeout-cap-test-out.txt; cat /tmp/bg-timeout-cap-test-out.txt; rm -f /tmp/bg-timeout-cap-test-out.txt" "true" "3000" "")")
wrapped=$(rewritten_command "$out")
assert_eq "output redirection: no longer blocked, redirects correctly" "redirected" "$(run_wrapped_and_capture "$wrapped")"

echo "== malformed / edge forms =="

out=$(run_hook "$(payload "" "true" "3000" "")")
assert_eq "empty command: allowed (no output) -- nothing for this hook to do" "" "$out"

echo "== custom cap via env var =="

out=$(run_hook "$(payload "./build.sh" "true" "3000" "")" GUARDRAILS_MAX_BACKGROUND_TIMEOUT_SECONDS=1)
assert_eq "custom lower cap: a timeout that passed the default now blocks" "true" "$(is_block "$out")"

out=$(run_hook "$(payload "./build.sh" "true" "900000" "")" GUARDRAILS_MAX_BACKGROUND_TIMEOUT_SECONDS=3600)
assert_eq "custom higher cap: a timeout that failed the default now passes" "timeout 900.000s bash -c './build.sh'" "$(rewritten_command "$out")"

out=$(run_hook "$(payload "./build.sh" "true" "900000" "")" GUARDRAILS_MAX_BACKGROUND_TIMEOUT_SECONDS=not-a-number)
assert_eq "malformed cap env var: falls back to default, still blocks" "true" "$(is_block "$out")"
assert_eq "malformed cap env var: reason uses the default cap value" "true" "$(printf '%s' "$out" | jq -R 'test("600 second cap")' 2>/dev/null)"

echo "== registration: wired into hooks.json under PreToolUse/Bash =="

HOOKS_JSON="$HERE/../hooks.json"
registered=$(jq -r '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[].command] | any(test("bg-timeout-cap\\.sh"))' "$HOOKS_JSON" 2>/dev/null)
assert_eq "hooks.json registers bg-timeout-cap.sh under PreToolUse/Bash" "true" "$registered"

echo
echo "bg-timeout-cap.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
