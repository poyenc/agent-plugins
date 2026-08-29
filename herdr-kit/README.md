# herdr-kit

Herdr agent tools: rotation and async inter-agent messaging. A home for herdr-related skills that grows over time.

## Skills

| Skill | Description |
|-------|-------------|
| **[rotate](skills/rotate/SKILL.md)** | Rotate a running herdr coding agent (claude, pi, or codex) in place: checkpoint its context to a handoff document, then exit and relaunch it in the same pane with its launch flags replayed. Two-step, agent-in-the-loop (handoff, then finish after the ping arrives); requires herdr. |
| **[rotate-self](skills/rotate-self/SKILL.md)** | Rotate the CALLING agent's own pane. Writes its own handoff synchronously, then launches a detached daemon that runs rotate's own finish step against this agent's pane from a separate process — the only way to work around finish's own self-rotation deadlock. |
| **[message](skills/message/SKILL.md)** | Send a non-blocking, asynchronous message to another herdr agent, or reply to one. Never blocks — sending returns immediately, and a reply (if requested) arrives as your own next incoming turn. |
