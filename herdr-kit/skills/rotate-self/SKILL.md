---
name: rotate-self
description: >
  Rotate THIS agent's own pane: checkpoint its own context to a handoff document, then
  exit and relaunch itself in place via a detached daemon process. Only invoke this when
  the USER explicitly asks the current agent to rotate/restart itself in this turn.
  Never self-trigger on your own judgment (e.g. noticing your own context is getting
  full) -- surface that observation to the user and let them decide. To rotate a
  DIFFERENT agent's pane, use rotate instead -- this skill only works on the
  calling agent's own pane. No-op outside herdr (HERDR_ENV != 1).
disable-model-invocation: true
allowed-tools: Bash(*/scripts/herdr-rotate-self *), Bash(herdr *)
---

# rotate-self

Rotate the calling agent's own pane in place: write your own handoff, launch a detached
daemon, then stop. The daemon runs herdr-rotate's own `finish` step against your pane
from a separate process -- the only way around `finish`'s own self-rotation deadlock
(see rotate's SKILL.md, "Known limitations": `finish` cannot target the calling
agent's own pane, because it would need its own process to have already exited before
it can confirm the pane empty).

## Usage

1. Write your own handoff document now -- if you have a handoff skill available, invoke
   it to get an absolute path; do not duplicate its judgment here. Do this BEFORE the
   next step; there is no ping/wait mechanism in this skill, unlike rotate's
   handoff/finish split -- you are not waiting on a different agent's turn to complete.

2. Run:

       <base>/../scripts/herdr-rotate-self <handoff-path> [--name N] [--model M] [--effort E] [--kickoff MSG|off]

   where `<base>` is the directory containing this SKILL.md file (e.g.
   `.../herdr-kit/skills/rotate-self`). This validates the handoff file, resolves
   your own pane/kind, and launches a detached process that will exit and relaunch this
   pane once you actually stop -- it returns immediately (well under a second).

3. **Stop here.** Say nothing further and take no more actions this turn -- you are
   about to be replaced. The detached daemon is watching for your pane to go idle
   (`ROTATE_SETTLE_POLL_SECS`, default 150s from when it starts watching, which is
   essentially immediately after step 2 returns) -- any further activity on your part
   eats directly into that window. If you keep working past it, the daemon times out
   and dies with you left untouched -- a safe, retryable failure, not data loss, but the
   rotation will not have happened.

- `--name N` -- name for an unnamed agent on relaunch (default: derived `<kind>-<pane>`).
- `--model M` / `--effort E` -- override launch model/effort (same semantics as
  herdr-rotate's own `finish`; pi model must be provider-qualified).
- `--kickoff "<msg>"` / `--kickoff off` -- same as herdr-rotate's `finish`.

## How it works

`herdr-rotate-self` resolves your own pane/kind (read-only), builds a target string
(your pane id, plus a session-staleness tag for claude), then spawns, detached:
`setsid env -u HERDR_PANE_ID herdr-rotate finish <target> <handoff-path> [flags]`. That
detached process is a genuinely separate actor -- with `HERDR_PANE_ID` stripped from its
environment, it does not match herdr-rotate's own self-rejection check, so the
*unmodified* `finish` flow runs against your pane exactly as it would for a second
orchestrating agent: wait for your pane to settle idle, `/quit`, confirm the pane empty,
relaunch with the same (or overridden) flags, verify, and send the kickoff prompt into
the fresh session. The kickoff prompt landing in the pane is the "done" signal -- there
is no other notification.

## Known limitations

- If the daemon's wait-for-idle times out (60s default) or `finish` dies for any reason
  (bad override, name collision, verify failure), there is no automatic notification --
  the old agent may already be gone. Check the daemon log (its path is printed to stderr
  when you invoke this script) or the pane directly.
- All of rotate's own known limitations apply verbatim here, since the daemon
  literally invokes herdr-rotate's own `finish` (positional-prompt replay, name-collision
  check-then-use window, codex global-options-before-subcommand).
- Model/effort/name validation happens only after you've already stopped talking (inside
  the daemon) -- you get no synchronous feedback if e.g. `--model` is malformed; it only
  shows up in the daemon log.
- This skill only rotates the CALLING agent's own pane. To rotate a different agent, use
  `rotate` instead.
