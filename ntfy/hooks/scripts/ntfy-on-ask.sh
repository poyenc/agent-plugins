#!/usr/bin/env bash
# PreToolUse hook on AskUserQuestion -- fires before the question is displayed.
set -euo pipefail

# Reads the hook payload into $payload; exits 0 here unless notifications are enabled for the session.
source "$(dirname "${BASH_SOURCE[0]}")/session-gate.sh"

question=$(printf '%s' "$payload" | python3 -c "
import sys, json
d = json.load(sys.stdin)
qs = d.get('tool_input', {}).get('questions', [])
parts = [q.get('question', '').strip() for q in qs if q.get('question', '').strip()]
if not parts:
    sys.exit(1)
print('[Answer Needed]\n\n' + ' / '.join(parts))
" 2>/dev/null) || exit 0

bash "${CLAUDE_PLUGIN_ROOT}/scripts/ntfy-send.sh" "$question"
