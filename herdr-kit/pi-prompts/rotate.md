---
description: >-
  Rotate a running herdr coding agent (claude, pi, or codex) in place: checkpoint its
  context to a handoff document, then exit and relaunch it in the same pane with its
  launch flags replayed.
argument-hint: '<name-or-pane> [--name N] [--model M] [--effort E]'
---
First resolve where this template's own checkout actually lives -- run
`readlink -f ~/.pi/agent/prompts/rotate.md`. The result is
`<repo>/herdr-kit/pi-prompts/rotate.md`; `<repo>/herdr-kit` is two directories up from
that.

Read `<repo>/herdr-kit/commands/rotate.md` for the full instructions -- the two-step
handoff/finish flow, argument reference, and known limitations (positional-prompt replay,
codex global-options-before-subcommand, etc.) all live there --
and follow it verbatim, with one substitution: run the scripts from
`<repo>/herdr-kit/skills/scripts/herdr-rotate` instead of the
`${CLAUDE_PLUGIN_ROOT}/skills/scripts/herdr-rotate` path it shows -- pi doesn't expand that
Claude Code plugin variable.

Raw slash-command arguments: $ARGUMENTS
