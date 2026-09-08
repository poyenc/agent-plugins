---
description: >-
  Rotate THIS agent's own pane: checkpoint its own context to a handoff document, then
  exit and relaunch itself in place via a detached daemon process.
argument-hint: '<handoff-path> [--name N] [--model M] [--effort E] [--kickoff MSG|off]'
---
First resolve where this template's own checkout actually lives -- run
`readlink -f ~/.pi/agent/prompts/herdr-rotate-self.md`. The result is
`<repo>/herdr-kit/pi-prompts/rotate-self.md`; `<repo>/herdr-kit` is two directories up
from that.

Read `<repo>/herdr-kit/commands/rotate-self.md` for the full instructions -- the
write-handoff-then-daemon flow, argument reference, the "stop and say nothing further"
step, and known limitations all live there -- and follow it verbatim, with one
substitution: run the script from
`<repo>/herdr-kit/skills/scripts/herdr-rotate-self` instead of the
`${CLAUDE_PLUGIN_ROOT}/skills/scripts/herdr-rotate-self` path it shows -- pi doesn't
expand that Claude Code plugin variable.

Raw slash-command arguments: $ARGUMENTS
