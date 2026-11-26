#!/usr/bin/env bash
# Tests for scripts/ntfy-send.sh: bounded curl, and NTFY_RAW skips markdown stripping.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/ntfy-send.sh"
PASS=0; FAIL=0
assert_eq(){ if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; echo "    exp:[$2] act:[$3]"; FAIL=$((FAIL+1)); fi; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
cat > "$T/bin/curl" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CURL_OUT"
EOS
chmod +x "$T/bin/curl"
send(){ rm -f "$T/args"; PATH="$T/bin:$PATH" CURL_OUT="$T/args" env -u NTFY_RAW "$@" bash "$SCRIPT" 'ls *.py *.txt'; }

send >/dev/null
assert_eq "curl is bounded by --max-time 10" "--max-time 10" "$(grep -x -A1 -- '--max-time' "$T/args" | paste -sd' ')"
assert_eq "markdown is stripped by default" "ls .py .txt" "$(grep -x 'ls .*' "$T/args")"
send NTFY_RAW=1 >/dev/null
assert_eq "NTFY_RAW=1 sends the text verbatim" "ls *.py *.txt" "$(grep -x 'ls .*' "$T/args")"

send NTFY_RAW=0 >/dev/null
assert_eq "NTFY_RAW=0 does not skip markdown stripping" "ls .py .txt" "$(grep -x 'ls .*' "$T/args")"

# A body starting with "@" must be sent as text; curl -d would read it as a file name.
PATH="$T/bin:$PATH" CURL_OUT="$T/args" bash "$SCRIPT" '@alice hi' >/dev/null
assert_eq "body starting with @ is sent as literal text (--data-raw)" "--data-raw @alice hi" "$(grep -x -A1 -- '--data-raw' "$T/args" | paste -sd' ')"

# curl exits 28 when --max-time fires; the sender must still exit 0 so the hook does.
printf '#!/usr/bin/env bash\nexit 28\n' > "$T/bin/curl"
PATH="$T/bin:$PATH" bash "$SCRIPT" 'x' >/dev/null 2>&1
assert_eq "curl timeout (exit 28) does not fail the sender" 0 "$?"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
