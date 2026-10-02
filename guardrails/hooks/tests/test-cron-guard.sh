#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/cron-guard.sh"
PASS=0; FAIL=0
assert_eq() {
  if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; PASS=$((PASS+1))
  else echo "  FAIL: $1"; echo "    exp:[$2] act:[$3]"; FAIL=$((FAIL+1)); fi
}

# $1 = JSON payload string; remaining args = NAME=VALUE env overrides
run_hook() {
  local json="$1"; shift
  env "$@" bash -c 'printf "%s" "$1" | bash "$2"' _ "$json" "$SCRIPT"
}

decision() { [ -z "$1" ] && echo "allow" || printf '%s' "$1" | jq -r '.decision // "allow"'; }

# ── one-shot (recurring:false) must be blocked ──────────────────────────────
echo "--- one-shot cron blocks ---"

out=$(run_hook '{"session_id":"s1","tool_name":"CronCreate","tool_input":{"cron":"0 * * * *","prompt":"p","recurring":false}}')
assert_eq "recurring:false → block" "block" "$(decision "$out")"

out=$(run_hook '{"session_id":"s1","tool_name":"CronCreate","tool_input":{"cron":"*/5 * * * *","prompt":"p","recurring":false}}')
assert_eq "recurring:false short-interval → block (oneshot check wins)" "block" "$(decision "$out")"

# ── recurring (recurring:true or absent) must pass through ──────────────────
echo "--- recurring cron passes one-shot check ---"

# recurring:true with a valid interval and zero active crons should pass
out=$(run_hook '{"session_id":"s1","tool_name":"CronCreate","tool_input":{"cron":"0 * * * *","prompt":"p","recurring":true}}')
assert_eq "recurring:true → not blocked by oneshot check" "allow" "$(decision "$out")"

# recurring field absent (default=true) should also pass
out=$(run_hook '{"session_id":"s1","tool_name":"CronCreate","tool_input":{"cron":"0 * * * *","prompt":"p"}}')
assert_eq "recurring absent → not blocked by oneshot check" "allow" "$(decision "$out")"

# ── interval check: minute-field parsing ─────────────────────────────────────
echo "--- interval check (minute field parsing) ---"

out=$(run_hook '{"session_id":"s1","tool_name":"CronCreate","tool_input":{"cron":"*/5 * * * *","prompt":"p","recurring":true}}' GUARDRAILS_MIN_CRON_MINUTES=8)
assert_eq "*/5 below min(8) → block" "block" "$(decision "$out")"

out=$(run_hook '{"session_id":"s1","tool_name":"CronCreate","tool_input":{"cron":"2-59/5 * * * *","prompt":"p","recurring":true}}' GUARDRAILS_MIN_CRON_MINUTES=8)
assert_eq "2-59/5 step-range below min(8) → block" "block" "$(decision "$out")"

out=$(run_hook '{"session_id":"s1","tool_name":"CronCreate","tool_input":{"cron":"3-59/10 * * * *","prompt":"p","recurring":true}}' GUARDRAILS_MIN_CRON_MINUTES=8)
assert_eq "3-59/10 step-range at/above min(8) → allow" "allow" "$(decision "$out")"

out=$(run_hook '{"session_id":"s1","tool_name":"CronCreate","tool_input":{"cron":"* * * * *","prompt":"p","recurring":true}}' GUARDRAILS_MIN_CRON_MINUTES=8)
assert_eq "bare * (every minute) → block" "block" "$(decision "$out")"

out=$(run_hook '{"session_id":"s1","tool_name":"CronCreate","tool_input":{"cron":"0 * * * *","prompt":"p","recurring":true}}' GUARDRAILS_MIN_CRON_MINUTES=8)
assert_eq "specific-value minute (hourly) → allow" "allow" "$(decision "$out")"

out=$(run_hook '{"session_id":"s1","tool_name":"CronCreate","tool_input":{"cron":"1-10/5,20-59/15 * * * *","prompt":"p","recurring":true}}' GUARDRAILS_MIN_CRON_MINUTES=8)
assert_eq "comma-list takes tightest step (5), not the last (15) → block" "block" "$(decision "$out")"

out=$(run_hook '{"session_id":"s1","tool_name":"CronCreate","tool_input":{"cron":"1-10/15,20-59/20 * * * *","prompt":"p","recurring":true}}' GUARDRAILS_MIN_CRON_MINUTES=8)
assert_eq "comma-list all steps at/above min(8) → allow" "allow" "$(decision "$out")"

out=$(run_hook '{"session_id":"s1","tool_name":"CronCreate","tool_input":{"cron":"2-59/05 * * * *","prompt":"p","recurring":true}}' GUARDRAILS_MIN_CRON_MINUTES=8)
assert_eq "zero-padded step (05) parsed as base-10, not octal → block" "block" "$(decision "$out")"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
