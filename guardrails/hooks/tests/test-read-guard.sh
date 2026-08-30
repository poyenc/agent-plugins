#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/read-guard.sh"
PASS=0; FAIL=0
assert_eq(){ if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; echo "    exp:[$2] act:[$3]"; FAIL=$((FAIL+1)); fi; }

FIXTURES=$(mktemp -d)
trap 'rm -rf "$FIXTURES"' EXIT

# big.txt: 2000 lines of exactly 100 bytes each (99 'a' + newline) = 200000 bytes total.
python3 -c "
for _ in range(2000):
    print('a' * 99)
" > "$FIXTURES/big.txt"

# small.txt: 6 bytes, well under any realistic limit.
printf 'hello\n' > "$FIXTURES/small.txt"

# medium.txt: exactly 2000 bytes (1999 'a' + newline) -- allowed at the 64 KiB default,
# blocked once GUARDRAILS_MAX_READ_BYTES is lowered below 2000.
python3 -c "print('a' * 1999)" > "$FIXTURES/medium.txt"

# Same oversized content as big.txt, but skip-listed extensions (one lowercase, one uppercase).
cp "$FIXTURES/big.txt" "$FIXTURES/big.png"
cp "$FIXTURES/big.txt" "$FIXTURES/big.PNG"
cp "$FIXTURES/big.txt" "$FIXTURES/big.pdf"
cp "$FIXTURES/big.txt" "$FIXTURES/big.ipynb"

# unterminated.txt: one short newline-terminated line, then a large line with NO trailing
# newline -- `wc -l` undercounts this file's true content by one line (it only counts
# newlines), which the OLD code's `wc -l`-based end-of-file line number relied on. Total size
# (70002 bytes) exceeds the default 64 KiB limit.
{ printf 'x\n'; head -c 70000 /dev/zero | tr '\0' 'a'; } > "$FIXTURES/unterminated.txt"

# $1 = JSON payload, remaining args (optional) = NAME=VALUE env overrides for this one call.
run_hook() {
  local json="$1"; shift
  env "$@" bash -c 'printf "%s" "$1" | bash "$2"' _ "$json" "$SCRIPT"
}

# Same as run_hook, but returns the process's exit code instead of its stdout.
run_hook_rc() {
  local json="$1"; shift
  env "$@" bash -c 'printf "%s" "$1" | bash "$2"' _ "$json" "$SCRIPT" >/dev/null 2>&1
  echo $?
}

# $1 = file_path, $2 = offset ("" for omitted), $3 = limit ("" for omitted)
payload() {
  python3 -c "
import json, sys
d = {'session_id': 'test', 'tool_name': 'Read', 'tool_input': {'file_path': sys.argv[1]}}
if sys.argv[2]:
    d['tool_input']['offset'] = int(sys.argv[2])
if sys.argv[3]:
    d['tool_input']['limit'] = int(sys.argv[3])
print(json.dumps(d))
" "$1" "$2" "$3"
}

is_block() { printf '%s' "$1" | jq -r '.decision == "block"' 2>/dev/null; }

# 1. Whole file over the limit -> blocked.
out=$(run_hook "$(payload "$FIXTURES/big.txt" "" "")")
assert_eq "whole file over limit: blocked" "true" "$(is_block "$out")"

# 2. Ranged read whose slice is under the limit -> allowed (lines 1-100 = 10000 bytes).
out=$(run_hook "$(payload "$FIXTURES/big.txt" "1" "100")")
assert_eq "ranged read under limit: allowed (no output)" "" "$out"

# 3. Ranged read whose slice is over the limit -> blocked (lines 1-700 = 70000 bytes).
out=$(run_hook "$(payload "$FIXTURES/big.txt" "1" "700")")
assert_eq "ranged read over limit: blocked" "true" "$(is_block "$out")"

# 4. offset given, limit omitted -> measures offset..end-of-file (lines 1901-2000 = 10000 bytes).
out=$(run_hook "$(payload "$FIXTURES/big.txt" "1901" "")")
assert_eq "offset only (to end of file), under limit: allowed (no output)" "" "$out"

# 5. Skip-listed extension (lowercase), oversized content -> allowed regardless of size.
out=$(run_hook "$(payload "$FIXTURES/big.png" "" "")")
assert_eq "skip-listed extension (.png): allowed (no output)" "" "$out"

# 6. Skip-listed extension, uppercase -> extension match is case-insensitive.
out=$(run_hook "$(payload "$FIXTURES/big.PNG" "" "")")
assert_eq "skip-listed extension (.PNG, uppercase): allowed (no output)" "" "$out"

# Skip-list also covers .pdf/.ipynb, not just .png/.PNG.
out=$(run_hook "$(payload "$FIXTURES/big.pdf" "" "")")
assert_eq "skip-listed extension (.pdf): allowed (no output)" "" "$out"
out=$(run_hook "$(payload "$FIXTURES/big.ipynb" "" "")")
assert_eq "skip-listed extension (.ipynb): allowed (no output)" "" "$out"

# 7. Small text file -> allowed.
out=$(run_hook "$(payload "$FIXTURES/small.txt" "" "")")
assert_eq "small file: allowed (no output)" "" "$out"

# 8. Medium file at the default 64 KiB limit -> allowed.
out=$(run_hook "$(payload "$FIXTURES/medium.txt" "" "")")
assert_eq "medium file (2000 bytes) at default limit: allowed (no output)" "" "$out"

# 9. Same medium file, GUARDRAILS_MAX_READ_BYTES lowered below its size -> blocked.
out=$(run_hook "$(payload "$FIXTURES/medium.txt" "" "")" GUARDRAILS_MAX_READ_BYTES=1000)
assert_eq "medium file with GUARDRAILS_MAX_READ_BYTES=1000: blocked" "true" "$(is_block "$out")"

# 10. Fail-open: missing file_path -> allowed (no output), no crash.
out=$(run_hook '{"session_id":"test","tool_name":"Read","tool_input":{}}')
assert_eq "missing file_path: allowed (no output)" "" "$out"

# 11. Fail-open: file_path does not exist -> allowed (no output), no crash.
out=$(run_hook "$(payload "$FIXTURES/does-not-exist.txt" "" "")")
assert_eq "nonexistent file: allowed (no output)" "" "$out"

# Fail-open: nonexistent file via the RANGED-read branch (offset/limit given) -- allowed
# (no output), no crash. The whole-file branch's fail-open-on-missing-file case is already
# covered above; this exercises the separate sed/wc code path at read-guard.sh's ranged branch.
out=$(run_hook "$(payload "$FIXTURES/does-not-exist.txt" "1" "100")")
assert_eq "nonexistent file via ranged-read branch: allowed (no output)" "" "$out"

# 12. Fail-open: non-numeric offset -> allowed (no output), no crash.
out=$(run_hook '{"session_id":"test","tool_name":"Read","tool_input":{"file_path":"'"$FIXTURES/big.txt"'","offset":"abc"}}')
assert_eq "non-numeric offset: allowed (no output)" "" "$out"

# Fail-open: non-numeric limit -> allowed (no output), no crash.
out=$(run_hook '{"session_id":"test","tool_name":"Read","tool_input":{"file_path":"'"$FIXTURES/big.txt"'","offset":1,"limit":"xyz"}}')
assert_eq "non-numeric limit: allowed (no output)" "" "$out"

# Degenerate range: offset=0 -> GNU sed rejects line address 0 as a start address, caught by
# the existing "|| exit 0" guard on read-guard.sh's sed pipeline -> fails open (allowed).
# Confirmed live: `sed -n '0,3p'` errors with "invalid usage of line address 0". Not reachable
# from the real Claude Code harness (confirmed live via a temporary probe hook: offset is only
# ever omitted entirely or a positive integer >= 1), but the code must still degrade safely if
# it somehow occurred.
out=$(run_hook "$(payload "$FIXTURES/big.txt" "0" "5")")
assert_eq "offset=0: allowed (no output, sed error fails open)" "" "$out"

# Degenerate range: limit=0 -> end = start + limit - 1 = 0, so "sed -n '1,0p'" runs successfully
# and prints just the start line (a small, correctly-measured 1-line slice), well under the
# limit -> allowed, not a crash. Confirmed live: `sed -n '1,0p'` exits 0 and prints line 1 only.
out=$(run_hook "$(payload "$FIXTURES/big.txt" "1" "0")")
assert_eq "limit=0: allowed (no output, degenerate 1-line slice under limit)" "" "$out"

# The hook process itself must always exit 0 -- both on allow AND on block. A PreToolUse hook
# signals its decision via the JSON body on stdout, not via its own exit code; a non-zero exit
# here would be a crash, not a decision.
rc=$(run_hook_rc "$(payload "$FIXTURES/small.txt" "" "")")
assert_eq "allow path: hook process exits 0" "0" "$rc"
rc=$(run_hook_rc "$(payload "$FIXTURES/big.txt" "" "")")
assert_eq "block path: hook process exits 0 (decision is in the JSON body, not the exit code)" "0" "$rc"

# Regression: offset-only read on a file whose final line has no trailing newline must still
# measure and block correctly -- confirmed live that the old wc -l-based approach undercounted
# this by one line, letting a 70002-byte unterminated read straight through unblocked.
out=$(run_hook "$(payload "$FIXTURES/unterminated.txt" "1" "")")
assert_eq "offset-only read on a file with an unterminated final line: blocked" "true" "$(is_block "$out")"

# Regression: a leading-zero numeric string (e.g. "08") is technically all-digits but bash
# arithmetic treats a leading-zero literal as octal, and "08" isn't valid octal -- must fail
# open (allowed), not crash.
out=$(run_hook '{"session_id":"test","tool_name":"Read","tool_input":{"file_path":"'"$FIXTURES/big.txt"'","offset":1,"limit":"08"}}')
assert_eq "leading-zero limit (08): allowed (no output), no crash" "" "$out"
out=$(run_hook '{"session_id":"test","tool_name":"Read","tool_input":{"file_path":"'"$FIXTURES/big.txt"'","offset":"08","limit":100}}')
assert_eq "leading-zero offset (08): allowed (no output), no crash" "" "$out"

# Regression: an invalid/unparseable GUARDRAILS_MAX_READ_BYTES falls back to the documented
# default (65536) instead of crashing.
out=$(run_hook "$(payload "$FIXTURES/small.txt" "" "")" GUARDRAILS_MAX_READ_BYTES=abc)
assert_eq "invalid GUARDRAILS_MAX_READ_BYTES=abc falls back to default, no crash" "" "$out"
out=$(run_hook "$(payload "$FIXTURES/big.txt" "" "")" GUARDRAILS_MAX_READ_BYTES=08)
assert_eq "invalid GUARDRAILS_MAX_READ_BYTES=08 (leading zero) falls back to default: blocked (big.txt is 200000 bytes > default 65536)" "true" "$(is_block "$out")"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
