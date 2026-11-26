#!/usr/bin/env bash
# Tests for ntfy-on-ask.sh: push "[Answer Needed]" plus the question text of an AskUserQuestion call,
# only when notifications are enabled for the session.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/ntfy-on-ask.sh"
PASS=0; FAIL=0
unset NTFY_TITLE   # a title set in the caller's environment must not leak into the title assertions
assert_eq(){ if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; echo "    exp:[$2] act:[$3]"; FAIL=$((FAIL+1)); fi; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/root/scripts"
cat > "$T/root/scripts/ntfy-send.sh" <<EOS
#!/usr/bin/env bash
printf '%s' "\$1" > "$T/sent"; printf '%s' "\${NTFY_TITLE:-}" > "$T/title"
EOS
source "$HERE/../../scripts/marker.sh"   # seed markers through the one owner of their format
CLAUDE_CODE_TMPDIR="$T/tmp" ntfy_marker_enable on "my-title"
CLAUDE_CODE_TMPDIR="$T/tmp" ntfy_marker_enable empty   # /ntfy-on with no title leaves an empty marker

run(){ rm -f "$T/sent" "$T/title"; printf '%s' "$1" | CLAUDE_PLUGIN_ROOT="$T/root" CLAUDE_CODE_TMPDIR="$T/tmp" bash "$SCRIPT"; }
sent(){ [ -f "$T/sent" ] && cat "$T/sent" || echo NOT_SENT; }
mk(){ jq -nc --arg s "$1" --argjson q "$2" '{session_id:$s,tool_name:"AskUserQuestion",tool_input:{questions:$q}}'; }
NL=$'\n'

echo "== SEND: enabled session =="
run "$(mk on '[{"question":"Pick A or B?"}]')"
assert_eq "one question" "[Answer Needed]${NL}${NL}Pick A or B?" "$(sent)"
assert_eq "title comes from the session marker" "my-title" "$(cat "$T/title")"
run "$(mk on '[{"question":"One?"},{"question":"Two?"}]')"
assert_eq "several questions are joined" "[Answer Needed]${NL}${NL}One? / Two?" "$(sent)"

run "$(mk empty '[{"question":"Pick A or B?"}]')"
assert_eq "empty-title marker still sends" "[Answer Needed]${NL}${NL}Pick A or B?" "$(sent)"
assert_eq "empty-title marker leaves NTFY_TITLE unset" "" "$(cat "$T/title")"

echo "== SKIP: nothing sent =="
run "$(mk off '[{"question":"Pick A or B?"}]')"
assert_eq "notifications not enabled for the session" NOT_SENT "$(sent)"
run "$(mk on '[]')"
assert_eq "no questions" NOT_SENT "$(sent)"
run 'not json'
assert_eq "malformed payload" NOT_SENT "$(sent)"

# Contract with Claude Code: a hook that has nothing to send exits 0 and prints nothing.
out=$(printf '%s' "$(mk off '[{"question":"Pick A or B?"}]')" | CLAUDE_PLUGIN_ROOT="$T/root" CLAUDE_CODE_TMPDIR="$T/tmp" bash "$SCRIPT"; echo "rc=$?")
assert_eq "not-enabled path exits 0 and prints nothing" "rc=0" "$out"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
