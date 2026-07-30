---
name: ntfy-off
description: Disable ntfy push notifications for this session. Use when the user says "ntfy off", "disable ntfy", "stop notifications", or no longer needs to be pinged.
---

Disable ntfy notifications for this session.

```bash
session_id="${CLAUDE_CODE_SESSION_ID:-}"
if [ -z "$session_id" ]; then
  echo "ERROR: CLAUDE_CODE_SESSION_ID is not set" >&2
  exit 1
fi
bash "${CLAUDE_PLUGIN_ROOT}/skills/scripts/toggle.sh" off "$session_id"
```

Tell the user: "ntfy notifications are now **off** for this session."
