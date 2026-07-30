---
name: ntfy-off
description: Disable ntfy push notifications for this session. Use when the user says "ntfy off", "disable ntfy", "stop notifications", or no longer needs to be pinged.
---

Disable ntfy notifications for this session.

```bash
session_id=$(claude session-id 2>/dev/null || echo "")
if [ -z "$session_id" ]; then
  echo "ERROR: could not determine session ID" >&2
  exit 1
fi
bash "${CLAUDE_PLUGIN_ROOT}/scripts/toggle.sh" off "$session_id"
```

Tell the user: "ntfy notifications are now **off** for this session."
