#!/usr/bin/env bash
# Tests for ntfy-on-permission.sh: on a PermissionRequest payload, send "[Permission Needed]" plus
# the tool name and its command or file path -- only when notifications are enabled for the session.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/ntfy-on-permission.sh"
PASS=0; FAIL=0
unset NTFY_TITLE   # a title set in the caller's environment must not leak into the title assertions
assert_eq(){ if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; echo "    exp:[$2] act:[$3]"; FAIL=$((FAIL+1)); fi; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/root/scripts"
# Stub sender: records the message and the title it was called with.
cat > "$T/root/scripts/ntfy-send.sh" <<EOF
#!/usr/bin/env bash
printf '%s' "\$1" > "$T/sent"; printf '%s' "\${NTFY_TITLE:-}" > "$T/title"
EOF
source "$HERE/../../scripts/marker.sh"   # seed markers through the one owner of their format
CLAUDE_CODE_TMPDIR="$T/tmp" ntfy_marker_enable on "my-title"
CLAUDE_CODE_TMPDIR="$T/tmp" ntfy_marker_enable empty   # /ntfy-on with no title leaves an empty marker

run(){ rm -f "$T/sent" "$T/title"; printf '%s' "$1" | CLAUDE_PLUGIN_ROOT="$T/root" CLAUDE_CODE_TMPDIR="$T/tmp" bash "$SCRIPT"; }
sent(){ [ -f "$T/sent" ] && cat "$T/sent" || echo NOT_SENT; }
mk(){ jq -nc --arg s "$1" --arg n "$2" --argjson i "$3" '{session_id:$s,tool_name:$n,tool_input:$i}'; }
NL=$'\n'

echo "== SEND: enabled session =="
run "$(mk on Bash '{"command":"rm -rf build/"}')"
assert_eq "Bash shows its command" "[Permission Needed]${NL}${NL}Bash: rm -rf build/" "$(sent)"
run "$(mk on Edit '{"file_path":"/a/b.txt","old_string":"x"}')"
assert_eq "Edit shows its file path" "[Permission Needed]${NL}${NL}Edit: /a/b.txt" "$(sent)"
run "$(mk on WebFetch '{"url":"https://x.test"}')"
assert_eq "other tool falls back to its input JSON" "[Permission Needed]${NL}${NL}WebFetch: {\"url\": \"https://x.test\"}" "$(sent)"
run "$(mk on Bash '{"command":"  ls -l  "}')"
assert_eq "detail is trimmed" "[Permission Needed]${NL}${NL}Bash: ls -l" "$(sent)"
run "$(mk on Bash '{"command":"echo hi","file_path":"/a/b"}')"
assert_eq "command wins over file_path" "[Permission Needed]${NL}${NL}Bash: echo hi" "$(sent)"
run "$(mk on WebFetch '{"url":"https://x.test/é"}')"
assert_eq "non-ASCII input JSON is not \\u-escaped" "[Permission Needed]${NL}${NL}WebFetch: {\"url\": \"https://x.test/é\"}" "$(sent)"
A300=$(printf 'a%.0s' {1..300})
run "$(mk on Bash "$(jq -nc --arg c "${A300}bbbbb" '{command:$c}')")"
assert_eq "detail is cut to 300 characters" "[Permission Needed]${NL}${NL}Bash: ${A300}" "$(sent)"
run "$(mk on Bash '{"command":"ls"}')"
assert_eq "title comes from the session marker" "my-title" "$(cat "$T/title")"

run "$(mk empty Bash '{"command":"ls"}')"
assert_eq "empty-title marker still sends" "[Permission Needed]${NL}${NL}Bash: ls" "$(sent)"

echo "== REAL SENDER: the command reaches curl byte for byte (not markdown-stripped) =="
mkdir -p "$T/bin"
cat > "$T/bin/curl" <<'EOF2'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do [ "$1" = "-d" ] && { printf '%s' "$2" > "$CURL_OUT"; break; }; shift; done
EOF2
chmod +x "$T/bin/curl"
REAL_ROOT="$(cd "$HERE/../.." && pwd)"
run_real(){ rm -f "$T/curl_out"; printf '%s' "$1" | PATH="$T/bin:$PATH" CURL_OUT="$T/curl_out" CLAUDE_PLUGIN_ROOT="$REAL_ROOT" CLAUDE_CODE_TMPDIR="$T/tmp" bash "$SCRIPT"; [ -f "$T/curl_out" ] && cat "$T/curl_out" || echo NOT_SENT; }
for cmd in 'ls *.py *.txt' 'echo `date` _x_ ~~y~~' 'rm -rf build_*_old' $'git commit -m "```a```"\n# note'; do
    assert_eq "verbatim: $cmd" "[Permission Needed]${NL}${NL}Bash: $cmd" "$(run_real "$(mk on Bash "$(jq -nc --arg c "$cmd" '{command:$c}')")")"
done

echo "== SKIP: nothing sent =="
run "$(mk off Bash '{"command":"ls"}')"
assert_eq "notifications not enabled for the session" NOT_SENT "$(sent)"
run '{"session_id":"on","tool_input":{"command":"ls"}}'
assert_eq "no tool_name" NOT_SENT "$(sent)"
run "$(mk on AskUserQuestion '{"questions":[{"question":"Pick A or B?"}]}')"
assert_eq "AskUserQuestion (its own hook already sends the question)" NOT_SENT "$(sent)"
run 'not json'
assert_eq "malformed payload" NOT_SENT "$(sent)"

# The hook must exit 0 and print nothing, or the permission dialog would be decided or disturbed.
out=$(printf '%s' "$(mk on Bash '{"command":"ls"}')" | CLAUDE_PLUGIN_ROOT="$T/root" CLAUDE_CODE_TMPDIR="$T/tmp" bash "$SCRIPT"; echo "rc=$?")
assert_eq "prints nothing and exits 0 (dialog still shows normally)" "rc=0" "$out"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
