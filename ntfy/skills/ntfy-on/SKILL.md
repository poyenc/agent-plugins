---
name: ntfy-on
description: Enable ntfy push notifications for this session. Use when the user says "ntfy on", "enable ntfy", "start notifications", or is about to go AFK and wants to be pinged when the agent asks a question.
---

Enable ntfy notifications for this session. The user may optionally provide a title after `/ntfy-on`; extract everything after the command as the title (empty string if not provided).

```bash
session_id="${CLAUDE_CODE_SESSION_ID:-}"
if [ -z "$session_id" ]; then
  echo "ERROR: CLAUDE_CODE_SESSION_ID is not set" >&2
  exit 1
fi
title="EXTRACTED_TITLE"
bash "${CLAUDE_PLUGIN_ROOT}/skills/scripts/toggle.sh" on "$session_id" "$title"
```

Substitute the actual title (or empty string) for `EXTRACTED_TITLE` before running.

Tell the user: "ntfy notifications are now **on** for this session. You'll be pinged on ntfy when the agent asks you a question." If a title was provided, confirm it: "Notifications will use the title: **<title>**."
