# herdr-kit

Herdr agent tools: rotation and async inter-agent messaging. A home for herdr-related skills that grows over time.

## Skills

`rotate` and `message` are skills — model-invocable, so an agent can choose to invoke them on
its own judgment. `rotate` is a single **unified** skill shared across all three harnesses
(claude/pi/codex): it resolves its own directory with `readlink -f` and calls
`<base>/scripts/herdr-rotate`, carrying no Claude-only `${CLAUDE_PLUGIN_ROOT}` path, so the one
file works identically wherever it is installed. Rotation is destructive (exit + relaunch), so
the only hard guard is in the script itself — `finish` refuses to rotate the calling agent's own
pane. Deciding *when* to rotate is left to the skill's description (the trigger the agent matches
on): e.g. refresh a teammate whose context is saturated, or when asked to restart an agent in
place.

| Skill | Description |
|-------|-------------|
| **[rotate](skills/rotate/SKILL.md)** | Rotate ANOTHER running herdr agent (claude, pi, or codex) in place: checkpoint its context to a handoff document, then exit and relaunch it in the same pane with its launch flags replayed. Two-step, agent-in-the-loop (handoff, then finish after the ping arrives); requires herdr. Cannot rotate the calling agent's own pane — use `/rotate-self`. |
| **[message](skills/message/SKILL.md)** | Send a non-blocking, asynchronous message to another herdr agent, or reply to one. Never blocks — sending returns immediately, and a reply (if requested) arrives as your own next incoming turn. |

## Commands

`rotate-self` is deliberately NOT a general model-invocable skill — restarting *yourself* on your
own judgment is the riskiest case (it can loop), so it stays gated, and each harness gates it
differently. The entry below is its **Claude** form: a command that sets `disable-model-invocation`
(a command's literal `/name` is resolved by the harness's own command table regardless of that flag
— unlike a skill, which relies on the agent matching the typed name against its own visible skill
list, a list that flag also removes it from). Codex and Pi gate the same intent differently (a Codex
skill kept out of `skills/`, and a Pi prompt); see "Codex and Pi mirrors" below.

| Command | Description |
|---------|-------------|
| **[/rotate-self](commands/rotate-self.md)** | Rotate the CALLING agent's own pane. Writes its own handoff synchronously, then launches a detached daemon that runs rotate's own finish step against this agent's pane from a separate process — the only way to work around finish's own self-rotation deadlock. |

## Codex and Pi mirrors

`rotate` is one unified skill (`skills/rotate/SKILL.md`), auto-discovered by Claude Code's plugin
scanner and symlinked into `~/.pi/agent/skills/` and `~/.codex/skills/`. The same
`readlink -f`/`<base>` trick that lets `message` be a single cross-harness skill works here too —
that is exactly what removes the Claude-only `${CLAUDE_PLUGIN_ROOT}` path that previously forced a
per-harness split. **Only the scripts under `scripts/` are shared, via a `scripts` symlink beside
the skill pointing at `../../scripts/`.**

`rotate-self` is NOT unified — it still exists once per harness, because it is deliberately gated
out of model-invocation and each harness gates differently:

- `commands/rotate-self.md` — the Claude Code command. Invokes the script via
  `${CLAUDE_PLUGIN_ROOT}/scripts/…` (Claude Code sets that variable).
- `codex-skills/rotate-self/SKILL.md` — deliberately outside `skills/`, so Claude Code's own
  plugin scanner never surfaces it (that would reopen the autonomous-self-rotation risk
  `disable-model-invocation` exists to close). Symlinked into `~/.codex/skills/`. Invokes the
  script via `"$base/scripts/…"`, where `$base` is the readlink-resolved skill dir and `scripts`
  is a committed symlink beside it into `../../scripts/`.
- `pi-prompts/rotate-self.md` — symlinked into `~/.pi/agent/prompts/`. Invokes the script via the
  fixed `~/.pi/agent/prompts/scripts/herdr-rotate-self` path.

### Install symlinks

- **rotate** (skill):
  - Claude: none — the plugin scanner surfaces `skills/rotate/` as `herdr-kit:rotate`.
  - Codex: `~/.codex/skills/rotate` → the repo `skills/rotate/`.
  - Pi: `~/.pi/agent/skills/rotate` → the repo `skills/rotate/`.

  The `scripts` symlink beside the skill rides along, since it is committed in-repo.
- **rotate-self** (command):
  - Codex: `~/.codex/skills/rotate-self` → the repo `codex-skills/rotate-self/`. The `scripts`
    symlink beside it rides along.
  - Pi: `~/.pi/agent/prompts/rotate-self.md` → the repo `pi-prompts/rotate-self.md`, **plus**
    `~/.pi/agent/prompts/scripts` → the repo `scripts/`. That last one is required and must be
    created install-side: pi symlinks the prompt file individually, so an in-repo sibling symlink
    would not follow it into `~/.pi/agent/prompts/`.
