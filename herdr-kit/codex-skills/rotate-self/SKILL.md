---
name: rotate-self
description: >
  Rotate THIS agent's own pane: checkpoint its own context to a handoff document, then
  exit and relaunch itself in place via a detached daemon process. Only invoke when the
  USER explicitly asks the current agent to rotate/restart itself in this turn -- never
  self-trigger on your own judgment (e.g. noticing your own context is getting full);
  surface that observation and let the user decide. To rotate a DIFFERENT agent's pane,
  use the rotate skill instead. No-op outside herdr (HERDR_ENV != 1). Codex-only mirror of
  the Claude Code /rotate-self command -- Codex has no command table of its own, only
  skills, so this file exists purely to make the capability discoverable here.
allowed-tools: Bash(*/scripts/herdr-rotate-self *), Bash(herdr *)
---

# rotate-self (Codex mirror)

Rotate the calling agent's own pane in place: write your own handoff, launch a detached
daemon, then stop. The daemon runs the rotation's own `finish` step against your pane from
a separate process -- the only way around finish's self-rotation deadlock (finish cannot
target the calling agent's own pane; it would need this very process to have already exited
before it could confirm the pane empty).

## Usage

1. Write your own handoff document now -- if you have a handoff skill available, invoke it
   to get an absolute path; do not duplicate its judgment here. Do this BEFORE the next
   step; there is no ping/wait mechanism here.

2. Resolve `<base>` (the real directory of this SKILL.md) from the path your skill listing
   shows for this file, then run the script:

       base="$(dirname "$(readlink -f /path/from/your/skill/listing/SKILL.md)")"
       "$base/scripts/herdr-rotate-self" <handoff-path> [--name N] [--model M] [--effort E] [--kickoff MSG|off]

   (`scripts` is a symlink beside this SKILL.md, into the plugin's shared `scripts/`.) This validates the handoff file, resolves your
   own pane/kind, and launches a detached process that will exit and relaunch this pane once
   you actually stop -- it returns immediately (well under a second).

3. **Stop here.** Say nothing further and take no more actions this turn -- you are about to
   be replaced. The detached daemon is watching for your pane to go idle
   (`ROTATE_SETTLE_POLL_SECS`, default 150s from when it starts watching, essentially
   immediately after step 2 returns) -- any further activity on your part eats directly into
   that window. If you keep working past it, the daemon times out and dies with you left
   untouched -- a safe, retryable failure, not data loss, but the rotation will not have
   happened.

- `--name N` -- name for an unnamed agent on relaunch (default: derived `<kind>-<pane>`).
- `--model M` / `--effort E` -- override launch model/effort.
- `--kickoff "<msg>"` -- custom first prompt; `--kickoff off` -- relaunch without one.

## How it works

`herdr-rotate-self` resolves your own pane/kind (read-only) and spawns, detached:
`setsid env -u HERDR_PANE_ID herdr-rotate finish <your-pane> <handoff-path> [flags]`. With
`HERDR_PANE_ID` stripped from its environment, that detached process is a genuinely separate
actor, so the unmodified `finish` flow runs against your pane exactly as if a second
orchestrating agent drove it: wait for your pane to settle idle, `/quit`, confirm the pane
empty, relaunch with the same (or overridden) flags, verify, and send the kickoff prompt
into the fresh session. The kickoff prompt landing in the pane is the "done" signal -- there
is no other notification.

## Known limitations

- If the daemon's wait-for-idle times out (150s default) or `finish` dies for any reason
  (bad override, name collision, verify failure), there is no automatic notification -- the
  old agent may already be gone. Check the daemon log (its path is printed to stderr when
  you invoke the script) or the pane directly.
- Model/effort/name validation happens only after you've already stopped talking (inside the
  daemon) -- you get no synchronous feedback if e.g. `--model` is malformed; it only shows
  up in the daemon log.
- A positional prompt in the original launch is replayed on relaunch (e.g. a trailing prompt
  argument passed to `codex`), and a codex launch with global options before a
  `resume`/`fork` subcommand isn't detected -- avoid both by launching flags-only.
- Do not alias the CLI binary itself -- the daemon's relaunch types the command into that
  aliased shell, so the alias's flags stack on every rotation.
- This only rotates the CALLING agent's own pane. To rotate a different agent, use the rotate
  skill instead.
