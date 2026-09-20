#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/ssh-host-guard.sh"
PASS=0; FAIL=0
assert_eq(){ if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; echo "    exp:[$2] act:[$3]"; FAIL=$((FAIL+1)); fi; }

# $1 = command string, remaining args = NAME=VALUE env overrides for this one call.
run_hook() {
  local cmd="$1"; shift
  local json
  json=$(python3 -c 'import json,sys; print(json.dumps({"session_id":"test","tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$cmd")
  env "$@" bash -c 'printf "%s" "$1" | bash "$2"' _ "$json" "$SCRIPT"
}

run_hook_rc() {
  local cmd="$1"; shift
  run_hook "$cmd" "$@" >/dev/null 2>&1
  echo $?
}

is_deny() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision == "deny"' 2>/dev/null; }

BLOCK="blocked-*.example.test"
ALLOW="blocked-allowed.example.test"

# 1. Literal blocked hostname via ssh -> denied.
out=$(run_hook "ssh blocked-one.example.test uptime" GUARDRAILS_HOST_BLOCK="$BLOCK" GUARDRAILS_HOST_ALLOW="$ALLOW")
assert_eq "blocked host via ssh: denied" "true" "$(is_deny "$out")"
assert_eq "deny reason names the actual host" "true" "$(printf '%s' "$out" | jq -R 'test("blocked-one")' 2>/dev/null)"

# 2. Allowed host (in ALLOW, also matches BLOCK's glob pattern) -> allow wins.
out=$(run_hook "ssh blocked-allowed.example.test uptime" GUARDRAILS_HOST_BLOCK="$BLOCK" GUARDRAILS_HOST_ALLOW="$ALLOW")
assert_eq "allowed host (also matches BLOCK pattern): allow wins, no output" "" "$out"

# 3. Blocked host via scp -> denied (not just ssh).
out=$(run_hook "scp file.txt blocked-one.example.test:/tmp/" GUARDRAILS_HOST_BLOCK="$BLOCK" GUARDRAILS_HOST_ALLOW="$ALLOW")
assert_eq "blocked host via scp: denied" "true" "$(is_deny "$out")"

# 4. Blocked host via rsync -> denied.
out=$(run_hook "rsync -az ./ blocked-one.example.test:~/dest/" GUARDRAILS_HOST_BLOCK="$BLOCK" GUARDRAILS_HOST_ALLOW="$ALLOW")
assert_eq "blocked host via rsync: denied" "true" "$(is_deny "$out")"

# 5. Unrelated host, matches neither list -> allowed (the config only narrows, never widens).
out=$(run_hook "ssh git@github.com -T" GUARDRAILS_HOST_BLOCK="$BLOCK" GUARDRAILS_HOST_ALLOW="$ALLOW")
assert_eq "unrelated host (matches neither list): allowed (no output)" "" "$out"

# 6. A command using an unrelated command name is not a watched verb -> untouched even with
# a blocked-looking hostname argument.
out=$(run_hook "curl --resolve blocked-one.example.test:443:127.0.0.1 https://blocked-one.example.test/" GUARDRAILS_HOST_BLOCK="$BLOCK" GUARDRAILS_HOST_ALLOW="$ALLOW")
assert_eq "unwatched command with blocked-looking host: allowed (not ssh/scp/rsync)" "" "$out"

# 7. No env vars set at all -> the hook has no built-in default host list, so it's a
# complete no-op until configured.
out=$(run_hook "ssh blocked-one.example.test uptime")
assert_eq "no env vars set: allowed (hook inert with no config, no output)" "" "$out"

# 8. Empty GUARDRAILS_HOST_ALLOW (but BLOCK set) -> no exceptions, even the previously-allowed
# host is now blocked. Confirms empty ALLOW does NOT mean "allow everything".
out=$(run_hook "ssh blocked-allowed.example.test uptime" GUARDRAILS_HOST_BLOCK="$BLOCK" GUARDRAILS_HOST_ALLOW="")
assert_eq "BLOCK set, ALLOW explicitly empty: previously-allowed host now denied (empty ALLOW != allow-all)" "true" "$(is_deny "$out")"

# 9. A command with no ssh/scp/rsync verb at all -> untouched even mentioning a blocked host
# in, say, a grep pattern (comment/log inspection, not a connection).
out=$(run_hook "grep -rn blocked-one.example.test ~/notes.txt" GUARDRAILS_HOST_BLOCK="$BLOCK" GUARDRAILS_HOST_ALLOW="$ALLOW")
assert_eq "hostname mentioned in a non-connecting command: allowed (no output)" "" "$out"

# 10. Resolution mechanism itself: a real, universally-resolvable name (localhost) blocked by
# pattern, with no alias/config faking needed -- proves ssh -G's resolved hostname (not just
# the literal typed argument) is what gets checked.
out=$(run_hook "ssh localhost uptime" GUARDRAILS_HOST_BLOCK="localhost" GUARDRAILS_HOST_ALLOW="")
assert_eq "localhost matched via ssh -G resolution: denied" "true" "$(is_deny "$out")"

# 10b. Regression: a git-commit-via-heredoc whose MESSAGE BODY mentions "ssh" and a
# blocked-looking pattern in prose must not be scanned as a live connection -- confirmed live
# this false-positive actually blocked a real commit before the heredoc-stripping fix. The
# heredoc body is data, not command text.
heredoc_cmd=$'git commit -m "$(cat <<\'EOF\'\nfeat: ssh/scp/rsync destination guard\nblocks blocked-* except blocked-allowed.example.test\nEOF\n)"'
out=$(run_hook "$heredoc_cmd" GUARDRAILS_HOST_BLOCK="$BLOCK" GUARDRAILS_HOST_ALLOW="$ALLOW")
assert_eq "heredoc commit-message body mentioning ssh/blocked-*: allowed (heredoc body is data, not scanned)" "" "$out"

# 11. Missing tool_input.command -> allowed (no output), no crash.
out=$(env GUARDRAILS_HOST_BLOCK="$BLOCK" bash -c 'printf "%s" "{\"tool_input\":{}}" | bash "$1"' _ "$SCRIPT")
assert_eq "missing command: allowed (no output), no crash" "" "$out"

# 12. Hook process itself always exits 0 -- decision is in the JSON body, not the exit code.
rc=$(run_hook_rc "ssh blocked-allowed.example.test uptime" GUARDRAILS_HOST_BLOCK="$BLOCK" GUARDRAILS_HOST_ALLOW="$ALLOW")
assert_eq "allow path: hook process exits 0" "0" "$rc"
rc=$(run_hook_rc "ssh blocked-one.example.test uptime" GUARDRAILS_HOST_BLOCK="$BLOCK" GUARDRAILS_HOST_ALLOW="$ALLOW")
assert_eq "deny path: hook process exits 0" "0" "$rc"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
