# herdr-kit

Herdr agent tools: rotation and async inter-agent messaging. A home for herdr-related skills that grows over time.

## Commands

`rotate` and `rotate-self` are commands, not skills: both set `disable-model-invocation`
(an agent must never choose to restart itself or another agent on its own judgment,
only when the user explicitly asks), and a command's literal `/name` is resolved
directly by the harness's own command table regardless of that flag — unlike a skill,
which relies on the agent matching the typed name against its own visible skill list,
a list that flag also removes it from.

| Command | Description |
|---------|-------------|
| **[/rotate](commands/rotate.md)** | Rotate a running herdr coding agent (claude, pi, or codex) in place: checkpoint its context to a handoff document, then exit and relaunch it in the same pane with its launch flags replayed. Two-step, agent-in-the-loop (handoff, then finish after the ping arrives); requires herdr. |
| **[/rotate-self](commands/rotate-self.md)** | Rotate the CALLING agent's own pane. Writes its own handoff synchronously, then launches a detached daemon that runs rotate's own finish step against this agent's pane from a separate process — the only way to work around finish's own self-rotation deadlock. |

## Skills

| Skill | Description |
|-------|-------------|
| **[message](skills/message/SKILL.md)** | Send a non-blocking, asynchronous message to another herdr agent, or reply to one. Never blocks — sending returns immediately, and a reply (if requested) arrives as your own next incoming turn. |
