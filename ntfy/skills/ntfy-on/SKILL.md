---
name: ntfy-on
description: Enable ntfy push notifications for this session. Use when the user says "ntfy on", "enable ntfy", "start notifications", or is about to go AFK and wants to be pinged when the agent asks a question.
---

Enable ntfy notifications for this session by creating the session marker file.

```bash
session_id=$(claude session-id 2>/dev/null || echo "")
if [ -z "$session_id" ]; then
  echo "ERROR: could not determine session ID" >&2
  exit 1
fi
touch "/tmp/ntfy-session-${session_id}"
echo "ntfy notifications enabled for session ${session_id}"
```

Tell the user: "ntfy notifications are now **on** for this session. You'll be pinged on ntfy when I ask you a question."
