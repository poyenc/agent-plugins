---
name: rotate
description: >
  Rotate a running herdr coding agent (claude, pi, or codex) in place: checkpoint its
  context to a handoff document, then exit and relaunch it in the same pane with its
  launch flags replayed. Only invoke this when the USER explicitly asks for it in this
  turn -- e.g. "rotate this agent", "refresh the agent's context", "restart the agent
  but keep its setup". Never self-trigger on your own judgment (e.g. noticing your own
  or another agent's context is getting full) -- surface that observation to the user
  and let them decide. To rotate the calling agent's own pane, use the rotate-self
  skill instead. No-op outside herdr (HERDR_ENV != 1). Codex-only mirror of the Claude
  Code /rotate command -- Codex has no command table of its own, only skills, so this
  file exists purely to make the capability discoverable here.
allowed-tools: Bash(*/scripts/herdr-rotate *), Bash(*/scripts/herdr-rotate-* *), Bash(herdr *)
---

# rotate (Codex mirror)

This is the Codex-visible copy of Claude Code's `/rotate` command. **Read
`<base>/../../commands/rotate.md` first** -- the full two-step handoff/finish flow,
argument reference (`<name-or-pane> [--name N] [--model M] [--effort E]`), and known
limitations (positional-prompt replay, codex global-options-before-subcommand,
`ROTATE_DROP_FLAGS_<KIND>`, etc.) all live there; this file does not duplicate them.

Follow that file verbatim, with one substitution: run the scripts from
`<base>/../../skills/scripts/herdr-rotate` instead of the
`${CLAUDE_PLUGIN_ROOT}/skills/scripts/herdr-rotate` path it shows -- Codex doesn't
expand that Claude Code plugin variable. `<base>` is the directory containing this
SKILL.md.
