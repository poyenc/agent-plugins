#!/usr/bin/env bash
# The marker path below is spelled out on purpose: it is an independent check of the documented
# location (README), so a change to scripts/marker.sh that moves it must also be made here.
# Every ntfy script that touches the per-session marker must agree on where it lives. Drives them in
# sequence: toggle.sh on -> hooks and ntfy-user.sh see it -> session-end.sh removes it.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
PASS=0; FAIL=0
assert_eq(){ if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; echo "    exp:[$2] act:[$3]"; FAIL=$((FAIL+1)); fi; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
printf '#!/usr/bin/env bash\nwhile [ $# -gt 0 ]; do [ "$1" = "-d" ] && { printf "%%s" "$2" > "$T_OUT"; break; }; shift; done\n' > "$T/bin/curl"
chmod +x "$T/bin/curl"
export CLAUDE_CODE_TMPDIR="$T/tmp" CLAUDE_PLUGIN_ROOT="$ROOT" CLAUDE_CODE_SESSION_ID=sess1 T_OUT="$T/out"
export PATH="$T/bin:$PATH"

pushed(){ [ -f "$T/out" ] && echo yes || echo no; }
ask_hook(){ rm -f "$T/out"; printf '{"session_id":"sess1","tool_input":{"questions":[{"question":"Q?"}]}}' | bash "$ROOT/hooks/scripts/ntfy-on-ask.sh"; }
user_send(){ rm -f "$T/out"; bash "$ROOT/skills/scripts/ntfy-user.sh" "hello"; }

ask_hook;  assert_eq "before toggle on: ask hook sends nothing" no "$(pushed)"
user_send; assert_eq "before toggle on: ntfy-user sends nothing" no "$(pushed)"

bash "$ROOT/skills/scripts/toggle.sh" on sess1 "My Title" >/dev/null
ask_hook;  assert_eq "after toggle on: ask hook sends" yes "$(pushed)"
user_send; assert_eq "after toggle on: ntfy-user sends" yes "$(pushed)"
assert_eq "marker holds the title" "My Title" "$(cat "$T/tmp/ntfy-plugin/active/notify-enabled-sess1")"

printf '{"session_id":"sess1"}' | bash "$ROOT/hooks/scripts/session-end.sh"
ask_hook;  assert_eq "after session-end: ask hook sends nothing" no "$(pushed)"
assert_eq "after session-end: marker file is gone" no "$([ -e "$T/tmp/ntfy-plugin/active/notify-enabled-sess1" ] && echo yes || echo no)"

bash "$ROOT/skills/scripts/toggle.sh" on sess1 >/dev/null
bash "$ROOT/skills/scripts/toggle.sh" off sess1 >/dev/null
user_send; assert_eq "after toggle off: ntfy-user sends nothing" no "$(pushed)"

# Claude may wrap the session id in backticks; toggle.sh must strip them before building the marker path.
bash "$ROOT/skills/scripts/toggle.sh" on '`sess2`' >/dev/null
assert_eq "backticked id: marker is created under the bare id" yes "$([ -e "$T/tmp/ntfy-plugin/active/notify-enabled-sess2" ] && echo yes || echo no)"
assert_eq "backticked id: no backtick-named file is created" 0 "$(ls "$T/tmp/ntfy-plugin/active" | grep -c '`')"
bash "$ROOT/skills/scripts/toggle.sh" off '`sess2`' >/dev/null
assert_eq "backticked id: off removes the marker" no "$([ -e "$T/tmp/ntfy-plugin/active/notify-enabled-sess2" ] && echo yes || echo no)"

# Default location when CLAUDE_CODE_TMPDIR is unset (documented in the README).
DEFAULT_ID="default-dir-test-$$"
env -u CLAUDE_CODE_TMPDIR bash "$ROOT/skills/scripts/toggle.sh" on "$DEFAULT_ID" >/dev/null
assert_eq "default marker dir falls back to /tmp" yes "$([ -e "/tmp/ntfy-plugin/active/notify-enabled-$DEFAULT_ID" ] && echo yes || echo no)"
env -u CLAUDE_CODE_TMPDIR bash "$ROOT/skills/scripts/toggle.sh" off "$DEFAULT_ID" >/dev/null

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
