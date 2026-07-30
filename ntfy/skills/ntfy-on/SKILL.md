---
name: ntfy-on
description: Enable ntfy push notifications for this session. Use when the user says "ntfy on", "enable ntfy", "start notifications", or is about to go AFK and wants to be pinged when the agent asks a question.
---

Enable ntfy notifications for this session.

```bash
session_id="${CLAUDE_CODE_SESSION_ID:-}"
if [ -z "$session_id" ]; then
  echo "ERROR: CLAUDE_CODE_SESSION_ID is not set" >&2
  exit 1
fi
bash "${CLAUDE_PLUGIN_ROOT}/skills/scripts/toggle.sh" on "$session_id"
```

Tell the user: "ntfy notifications are now **on** for this session. You'll be pinged on ntfy when the agent asks you a question."
