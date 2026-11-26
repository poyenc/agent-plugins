#!/usr/bin/env bash
# PermissionRequest hook -- fires before the permission dialog is displayed.
# Prints nothing, so the dialog still shows normally.
set -euo pipefail

payload=$(cat)

session_id=$(printf '%s' "$payload" | python3 -c \
    "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null || true)

marker="${CLAUDE_CODE_TMPDIR:-/tmp}/ntfy-plugin/active/notify-enabled-${session_id}"
[ -f "$marker" ] || exit 0

stored_title=$(cat "$marker")
[ -n "$stored_title" ] && export NTFY_TITLE="$stored_title"

message=$(printf '%s' "$payload" | python3 -c "
import sys, json
d = json.load(sys.stdin)
tool = d.get('tool_name', '').strip()
# AskUserQuestion also fires PermissionRequest; ntfy-on-ask.sh already sends its exact question.
if not tool or tool == 'AskUserQuestion':
    sys.exit(1)
ti = d.get('tool_input', {}) or {}
detail = ti.get('command') or ti.get('file_path') or json.dumps(ti, ensure_ascii=False)
print('[Permission Needed]\\n\\n' + tool + ': ' + detail.strip()[:300])
" 2>/dev/null) || exit 0

# The detail is a literal command or path: send it verbatim, not markdown-stripped.
NTFY_RAW=1 bash "${CLAUDE_PLUGIN_ROOT}/scripts/ntfy-send.sh" "$message"
