#!/usr/bin/env bash
# Tests for ntfy-on-stop.sh: when the last assistant message contains a question mark outside code,
# push "[Answer Needed]" plus the question, only when notifications are enabled for the session.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/ntfy-on-stop.sh"
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
mk(){ jq -nc --arg s "$1" --arg m "$2" '{session_id:$s,last_assistant_message:$m}'; }
NL=$'\n'

echo "== SEND: enabled session, message with a question =="
run "$(mk on "Done with the build.${NL}${NL}Should I push it?")"
assert_eq "context paragraph plus the question" "[Answer Needed]${NL}${NL}Done with the build.${NL}${NL}Should I push it?" "$(sent)"
assert_eq "title comes from the session marker" "my-title" "$(cat "$T/title")"

run "$(mk empty "Done.${NL}${NL}Should I push it?")"
assert_eq "empty-title marker still sends" "[Answer Needed]${NL}${NL}Done.${NL}${NL}Should I push it?" "$(sent)"

echo "== SKIP: nothing sent =="
run "$(mk on 'All done.')"
assert_eq "no question mark" NOT_SENT "$(sent)"
run "$(mk on '```
what is this?
```')"
assert_eq "question mark only inside a code block" NOT_SENT "$(sent)"
run "$(mk off 'Should I push it?')"
assert_eq "notifications not enabled for the session" NOT_SENT "$(sent)"
run "$(mk on '')"
assert_eq "empty message" NOT_SENT "$(sent)"

# Contract with Claude Code: a hook that has nothing to send exits 0 and prints nothing.
out=$(printf '%s' "$(mk off 'Should I push it?')" | CLAUDE_PLUGIN_ROOT="$T/root" CLAUDE_CODE_TMPDIR="$T/tmp" bash "$SCRIPT"; echo "rc=$?")
assert_eq "not-enabled path exits 0 and prints nothing" "rc=0" "$out"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
