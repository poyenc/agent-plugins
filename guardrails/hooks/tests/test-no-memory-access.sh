#!/usr/bin/env bash
# Tests for no-memory-access.sh: block Read/Write/Edit against Claude Code's built-in memory
# directory (~/.claude/projects/*/memory/*). All three tools key off the same tool_input.file_path,
# so one script and one test file cover all of them.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/no-memory-access.sh"
PASS=0; FAIL=0
assert_eq(){ if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; echo "    exp:[$2] act:[$3]"; FAIL=$((FAIL+1)); fi; }

MEM="$HOME/.claude/projects/some-project/memory/notes.md"
OTHER_PROJECT_FILE="$HOME/.claude/projects/some-project/src/main.py"
UNRELATED="/tmp/notes.md"

mkjson(){ jq -nc --arg t "$1" --arg p "$2" '{session_id:"t",tool_name:$t,tool_input:{file_path:$p}}'; }
run(){ printf '%s' "$(mkjson "$1" "$2")" | bash "$SCRIPT"; }
decision(){ [ -n "$1" ] || { echo none; return; }; printf '%s' "$1" | jq -r '.decision // "none"' 2>/dev/null; }
valid_json(){ [ -n "$1" ] || { echo ok; return; }; printf '%s' "$1" | jq -e . >/dev/null 2>&1 && echo ok || echo bad; }
blk(){ decision "$(run "$1" "$2")"; }

echo "== BLOCK: every tool surface, same memory path =="
assert_eq "Read under memory dir"  block "$(blk Read "$MEM")"
assert_eq "Write under memory dir" block "$(blk Write "$MEM")"
assert_eq "Edit under memory dir"  block "$(blk Edit "$MEM")"

echo "== ALLOW: same project, but not the memory subdirectory =="
assert_eq "Read a normal project file"  none "$(blk Read "$OTHER_PROJECT_FILE")"
assert_eq "Write a normal project file" none "$(blk Write "$OTHER_PROJECT_FILE")"

echo "== ALLOW: unrelated path, missing file_path, unknown tool =="
assert_eq "Read an unrelated path"      none "$(blk Read "$UNRELATED")"
assert_eq "missing file_path"           none "$(decision "$(printf '%s' "$(jq -nc --arg t Read '{tool_name:$t,tool_input:{}}')" | bash "$SCRIPT")")"
assert_eq "unrelated tool name, memory path (script only looks at file_path)" block "$(blk SomeOtherTool "$MEM")"

echo "== block payload is valid JSON and explains why =="
out=$(run Read "$MEM")
assert_eq "block payload parses as JSON" ok "$(valid_json "$out")"
assert_eq "reason mentions staleness/judgment rationale" yes "$(printf '%s' "$out" | jq -r .reason | grep -qi 'stale' && echo yes || echo no)"
assert_eq "reason mentions both read and write are covered" yes "$(printf '%s' "$out" | jq -r .reason | grep -qi 'read and write' && echo yes || echo no)"

echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
