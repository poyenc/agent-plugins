---
name: ntfy-on
description: Enable ntfy push notifications for this session. Use when the user says "ntfy on", "enable ntfy", "start notifications", or is about to go AFK and wants to be pinged when the agent asks a question.
---

Enable ntfy notifications for this session. The user may optionally provide a title after `/ntfy-on`; extract everything after the command as the title (empty string if not provided).

Run `<base>/../scripts/toggle.sh on "$CLAUDE_CODE_SESSION_ID" "<title>"` where `<base>` is the directory containing this SKILL.md file (e.g. `.../ntfy/skills/ntfy-on`) and `<title>` is everything after the command (empty string if none).

Tell the user: "ntfy notifications are now **on** for this session. You'll be pinged on ntfy when the agent asks you a question." If a title was provided, confirm it: "Notifications will use the title: **<title>**."
