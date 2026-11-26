#!/usr/bin/env bash
# PermissionRequest hook -- fires before the permission dialog is displayed.
# Prints nothing, so the dialog still shows normally.
set -euo pipefail

# Reads the hook payload into $payload; exits 0 here unless notifications are enabled for the session.
source "$(dirname "${BASH_SOURCE[0]}")/session-gate.sh"

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
