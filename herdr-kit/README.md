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

## Codex and Pi mirrors

Codex has no command table at all — only skills, which (unlike commands) the model can
choose to invoke on its own judgment. Pi does have a command-like mechanism (prompt
templates, `/name`), but it's driven by a human typing in the editor, not read from a
Claude Code plugin's `commands/` directory. So `rotate`/`rotate-self` exist once per
harness as **self-contained** files: each carries the full flow, argument reference, and
known limitations for its own harness, and none reads another harness's doc. **Only the
scripts under `scripts/` are shared.** Keeping the docs per-harness is deliberate —
a non-Claude agent never encounters (and so can never mistakenly emit) the Claude-only
`${CLAUDE_PLUGIN_ROOT}` path.

- `commands/rotate.md`, `commands/rotate-self.md` — the Claude Code commands. They invoke
  the scripts via `${CLAUDE_PLUGIN_ROOT}/scripts/…` (Claude Code sets that variable).
- `codex-skills/rotate/SKILL.md`, `codex-skills/rotate-self/SKILL.md` — deliberately
  outside `skills/`, so Claude Code's own plugin scanner never surfaces them (that would
  reopen the autonomous-self-rotation risk `disable-model-invocation` exists to close).
  Symlinked into `~/.codex/skills/`. They invoke the script via `"$base/scripts/…"`, where
  `$base` is the readlink-resolved skill dir and `scripts` is a committed symlink beside
  each skill pointing at `../../scripts/`.
- `pi-prompts/rotate.md`, `pi-prompts/rotate-self.md` — symlinked into
  `~/.pi/agent/prompts/`. They invoke the script via the fixed
  `~/.pi/agent/prompts/scripts/herdr-rotate[-self]` path.

### Install symlinks

- Codex: `~/.codex/skills/{rotate,rotate-self}` → the repo `codex-skills/*` dirs. The
  `scripts` symlink beside each skill rides along, since it is committed in-repo.
- Pi: `~/.pi/agent/prompts/{rotate,rotate-self}.md` → the repo `pi-prompts/*.md`, **plus**
  `~/.pi/agent/prompts/scripts` → the repo `scripts/`. That last one is required and
  must be created install-side: pi symlinks the prompt files individually, so an in-repo
  sibling symlink would not follow them into `~/.pi/agent/prompts/`.
