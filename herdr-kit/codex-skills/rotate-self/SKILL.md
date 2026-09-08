---
name: rotate-self
description: >
  Rotate THIS agent's own pane: checkpoint its own context to a handoff document, then
  exit and relaunch itself in place via a detached daemon process. Only invoke this
  when the USER explicitly asks the current agent to rotate/restart itself in this
  turn. Never self-trigger on your own judgment (e.g. noticing your own context is
  getting full) -- surface that observation to the user and let them decide. To rotate
  a DIFFERENT agent's pane, use the rotate skill instead -- this only works on the
  calling agent's own pane. No-op outside herdr (HERDR_ENV != 1). Codex-only mirror of
  the Claude Code /rotate-self command -- Codex has no command table of its own, only
  skills, so this file exists purely to make the capability discoverable here.
allowed-tools: Bash(*/scripts/herdr-rotate-self *), Bash(herdr *)
---

# rotate-self (Codex mirror)

This is the Codex-visible copy of Claude Code's `/rotate-self` command. **Read
`<base>/../../commands/rotate-self.md` first** -- the write-handoff-then-daemon flow,
argument reference (`<handoff-path> [--name N] [--model M] [--effort E] [--kickoff
MSG|off]`), the "stop and say nothing further" step, and known limitations all live
there; this file does not duplicate them.

Follow that file verbatim, with one substitution: run the script from
`<base>/../../skills/scripts/herdr-rotate-self` instead of the
`${CLAUDE_PLUGIN_ROOT}/skills/scripts/herdr-rotate-self` path it shows -- Codex doesn't
expand that Claude Code plugin variable. `<base>` is the directory containing this
SKILL.md.
