#!/usr/bin/env bash
# Stop hook -- best-effort catch for plain-text questions via "?" detection.
# Strips code blocks before checking to reduce false positives.
set -euo pipefail

payload=$(cat)

session_id=$(printf '%s' "$payload" | python3 -c \
    "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null || true)

marker="${CLAUDE_CODE_TMPDIR:-/tmp}/ntfy-plugin/active/notify-enabled-${session_id}"
[ -f "$marker" ] || exit 0

stored_title=$(cat "$marker")
[ -n "$stored_title" ] && export NTFY_TITLE="$stored_title"

msg=$(printf '%s' "$payload" | python3 -c \
    "import sys,json; print(json.load(sys.stdin).get('last_assistant_message',''))" 2>/dev/null || true)

[ -z "$msg" ] && exit 0

# Strip fenced and inline code blocks before checking for "?"
clean=$(printf '%s' "$msg" | python3 -c "
import sys, re
text = sys.stdin.read()
text = re.sub(r'\`\`\`.*?\`\`\`', '', text, flags=re.DOTALL)
text = re.sub(r'\`([^\`]+)\`', r'\1', text)
print(text)
" 2>/dev/null || true)

printf '%s' "$clean" | grep -qF '?' || exit 0

# Extract the question and enough surrounding context to be useful.
body=$(printf '%s' "$clean" | python3 -c "
import sys, re
text = sys.stdin.read().strip()
paragraphs = [p.strip() for p in text.split('\n\n') if p.strip()]

def has_standalone_question(para):
    # '?' at end of the paragraph's last line
    return bool(re.search(r'\?\s*$', para))

q_idx = next((i for i, p in enumerate(paragraphs) if has_standalone_question(p)), None)
# Second-pass fallback: any paragraph containing '?'
if q_idx is None:
    q_idx = next((i for i, p in enumerate(paragraphs) if '?' in p), None)
if q_idx is None:
    print('')
else:
    parts = []
    if q_idx > 0:
        prev = paragraphs[q_idx - 1]
        if re.match(r'^[-*\d]', prev):
            # prev is a list — include one more paragraph before it as context
            if q_idx > 1:
                parts.append(paragraphs[q_idx - 2])
            parts.append(prev)
            parts.append(paragraphs[q_idx])
        else:
            if q_idx + 1 < len(paragraphs) and re.match(r'^[-*\d]', paragraphs[q_idx + 1]):
                # list after Q is self-sufficient — drop context, show Q + list
                parts.append(paragraphs[q_idx])
                parts.append(paragraphs[q_idx + 1])
            else:
                parts.append(prev)
                parts.append(paragraphs[q_idx])
    else:
        parts.append(paragraphs[q_idx])
        if q_idx + 1 < len(paragraphs) and re.match(r'^[-*\d]', paragraphs[q_idx + 1]):
            parts.append(paragraphs[q_idx + 1])
    print('\n\n'.join(parts))
" 2>/dev/null || true)
[ -z "$body" ] && body=$(printf '%s' "$msg" | tail -c 300)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/ntfy-send.sh" "[Answer Needed]

$body"

exit 0
