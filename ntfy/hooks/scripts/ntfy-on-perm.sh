#!/usr/bin/env bash
# Notification hook on permission_prompt -- fires when Claude needs tool approval.
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
transcript_path = d.get('transcript_path', '')

tool_detail = ''
if transcript_path:
    try:
        with open(transcript_path) as f:
            lines = [l.strip() for l in f if l.strip()]
        for line in reversed(lines):
            try:
                entry = json.loads(line)
                content = entry.get('message', {}).get('content', [])
                if isinstance(content, list):
                    for block in reversed(content):
                        if block.get('type') == 'tool_use':
                            name = block.get('name', '')
                            inp = block.get('input', {})
                            if len(inp) == 1:
                                val = str(next(iter(inp.values())))
                                tool_detail = name + ': ' + val.splitlines()[0]
                            else:
                                parts = ', '.join(k + '=' + str(v).splitlines()[0] for k, v in inp.items())
                                tool_detail = name + ': ' + parts[:200]
                            break
                if tool_detail:
                    break
            except Exception:
                continue
    except Exception:
        pass

if not tool_detail:
    tool_detail = d.get('message', '').strip()

print('[Permission Needed]\n' + tool_detail)
" 2>/dev/null || true)

bash "${CLAUDE_PLUGIN_ROOT}/scripts/ntfy-send.sh" "$message"
