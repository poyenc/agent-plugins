#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/orchestrator-delegate-reminder.sh"
PASS=0; FAIL=0
assert_eq(){ if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; echo "    exp:[$2] act:[$3]"; FAIL=$((FAIL+1)); fi; }

BASH_PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"ls"}}'
AGENT_PAYLOAD='{"tool_name":"Agent","tool_input":{"prompt":"x"}}'
SUBAGENT_PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"ls"},"agent_id":"a1b2","agent_type":"Explore"}'

# A stub `herdr` on PATH answers `pane process-info` with the JSON in $FIXTURE (or fails when
# FIXTURE is unset), so each case controls exactly what the pane's process looks like.
BIN=$(mktemp -d); trap 'rm -rf "$BIN"' EXIT
cat >"$BIN/herdr" <<'STUB'
#!/usr/bin/env bash
[ "$1 $2" = "pane process-info" ] || exit 2
[ -n "${FIXTURE:-}" ] || exit 1
printf '%s' "$FIXTURE"
STUB
chmod +x "$BIN/herdr"

# proc <name> <argv...> -> process-info JSON with one foreground process.
proc() {
  local name="$1"; shift
  # argv goes in NUL-separated: jq's own --args would parse "--system-prompt-file" as an option.
  printf '%s\0' "$@" | jq -Rsc --arg n "$name" \
    '(split("\u0000")[:-1]) as $a | {result:{process_info:{foreground_processes:[{pid:1,name:$n,argv:$a}]}}}'
}
# run <payload> <fixture-json> [ENV=VAL ...]
run() {
  local payload="$1" fixture="$2"; shift 2
  env PATH="$BIN:$PATH" HERDR_ENV=1 HERDR_PANE_ID=w1:p1 FIXTURE="$fixture" "$@" \
    bash -c 'printf "%s" "$1" | bash "$2"' _ "$payload" "$SCRIPT"
}
ctx() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }
event() { printf '%s' "$1" | jq -r '.hookSpecificOutput.hookEventName // ""' 2>/dev/null; }
decision() { printf '%s' "$1" | jq -r '.decision // .hookSpecificOutput.permissionDecision // "none"' 2>/dev/null; }

ORCH=$(proc claude claude --dangerously-skip-permissions --system-prompt-file /x/agents/orchestrator/system-prompt.md)

echo "== orchestrator session =="
out=$(run "$BASH_PAYLOAD" "$ORCH"); rc=$?
assert_eq "Bash call: exits 0" "0" "$rc"
assert_eq "Bash call: emits a PreToolUse reminder" "PreToolUse" "$(event "$out")"
assert_eq "Bash call: reminder mentions delegating" "1" "$(ctx "$out" | grep -c 'delegate')"
assert_eq "Bash call: never blocks" "none" "$(decision "$out")"
out=$(run "$AGENT_PAYLOAD" "$ORCH")
assert_eq "Agent call: emits the reminder too" "PreToolUse" "$(event "$out")"
out=$(run "$BASH_PAYLOAD" "$(proc claude claude --system-prompt-file /other/dir/orchestrator/system-prompt.md)")
assert_eq "custom base path still matches" "PreToolUse" "$(event "$out")"
out=$(run "$BASH_PAYLOAD" "$(proc claude claude --system-prompt-file /x/prompts/my-orchestrator-v2.md)")
assert_eq "any path containing 'orchestrator' matches, not only .../orchestrator/system-prompt.md" "PreToolUse" "$(event "$out")"
out=$(run "$BASH_PAYLOAD" "$(proc claude claude --system-prompt-file=/x/agents/orchestrator/system-prompt.md)")
assert_eq "--system-prompt-file=<path> form matches" "PreToolUse" "$(event "$out")"

echo "== orchestrator's own workers =="
out=$(run "$SUBAGENT_PAYLOAD" "$ORCH"); rc=$?
assert_eq "subagent call (agent_id present): exits 0" "0" "$rc"
assert_eq "subagent call (agent_id present): no output" "" "$out"

echo "== other sessions =="
out=$(run "$BASH_PAYLOAD" "$(proc claude claude --system-prompt-file /x/agents/implementer/system-prompt.md)"); rc=$?
assert_eq "other agent role: exits 0" "0" "$rc"
assert_eq "other agent role: no output" "" "$out"
out=$(run "$BASH_PAYLOAD" "$(proc claude claude --dangerously-skip-permissions)")
assert_eq "plain session, no --system-prompt-file: no output" "" "$out"

echo "== argv matching is exact =="
out=$(run "$BASH_PAYLOAD" "$(proc claude claude /x/agents/orchestrator/system-prompt.md)")
assert_eq "bare path element without the flag before it does not match" "" "$out"
out=$(run "$BASH_PAYLOAD" "$(proc claude claude "cd /tmp && P=/x/agents/orchestrator/system-prompt.md")")
assert_eq "path inside a larger argv element does not match" "" "$out"
out=$(run "$BASH_PAYLOAD" "$(proc claude claude --system-prompt-file)")
assert_eq "flag as the last element (no value) does not match or crash" "" "$out"

echo "== only the claude process counts =="
out=$(run "$BASH_PAYLOAD" "$(proc bash bash --system-prompt-file /x/agents/orchestrator/system-prompt.md)")
assert_eq "non-claude process carrying the orchestrator argv: no output" "" "$out"

echo "== herdr-only, fails silent =="
out=$(run "$BASH_PAYLOAD" "$ORCH" HERDR_ENV=0); rc=$?
assert_eq "HERDR_ENV != 1: exits 0" "0" "$rc"
assert_eq "HERDR_ENV != 1: no output" "" "$out"
out=$(run "$BASH_PAYLOAD" "$ORCH" HERDR_PANE_ID=); rc=$?
assert_eq "no HERDR_PANE_ID: no output" "" "$out"
out=$(run "$BASH_PAYLOAD" ""); rc=$?
assert_eq "herdr call failing: exits 0" "0" "$rc"
assert_eq "herdr call failing: no output" "" "$out"
out=$(run "$BASH_PAYLOAD" "not json"); rc=$?
assert_eq "unparseable herdr output: exits 0" "0" "$rc"
assert_eq "unparseable herdr output: no output" "" "$out"

echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
