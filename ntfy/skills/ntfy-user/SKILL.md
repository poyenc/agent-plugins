---
name: ntfy-user
description: >
  Send an ntfy push notification to the user for any event worth pinging them about — a
  question that needs their input, a task that completed, an error that blocked progress, a
  milestone reached, or any event the user has asked to be notified about. Call this whenever
  you want to reach the user out-of-band, especially in long-running or AFK sessions.
  Respects the per-session on/off toggle: sends only when notifications are enabled.
---

## When to invoke

Call this skill whenever you have something worth pinging the user about:

- **Question / blocked:** you need their input to continue
- **Task complete:** a long job finished (success or failure)
- **Error / blocker:** something failed and needs their attention
- **Milestone:** a meaningful checkpoint in multi-step work
- **User-requested:** the user explicitly asked to be notified when X happens

**Do NOT invoke for:** routine progress chatter that does not need a response or decision.

## How to send

Run `<base>/../scripts/ntfy-user.sh "<message>"` where `<base>` is the base directory for this skill.

## Composing the message

Make it self-contained — the user may be away and cannot see the conversation:

- **Question:** `What fallback behavior when the config file is missing — error out or use defaults?`
- **Complete:** `Kernel benchmark finished. gfx942 peak: 312 TFLOPS. Results in /tmp/bench.log.`
- **Error:** `Build failed: undefined symbol 'hsa_memory_allocate' in hip_runtime.cc:142.`
- **Milestone:** `All 47 unit tests passing after the refactor. Starting integration tests now.`

One sentence when possible. Pack enough context to act without switching back.

## After sending

Continue the conversation normally. The notification is a side-channel ping only. If notifications are off, the script exits silently — no ping is sent.
