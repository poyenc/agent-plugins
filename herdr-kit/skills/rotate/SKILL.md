---
name: rotate
description: >
  Rotate a running herdr coding agent (claude, pi, or codex) in place: checkpoint its context
  to a handoff document, then exit and relaunch it in the SAME pane as a fresh session with its
  launch flags (model, effort, and other options) replayed. Use this to refresh ANOTHER herdr
  agent whose context is getting full or stale, or when asked to restart/rotate an agent in
  place while keeping its setup -- e.g. "rotate <agent>", "refresh that agent's context",
  "restart the agent but keep its model/effort". An orchestrating agent may rotate a teammate
  on its own judgment (e.g. that teammate's context is saturated); it does not require a human
  to ask each time. Two-step, agent-in-the-loop: handoff, then finish once the target pings
  back. You CANNOT rotate your own pane with this -- use rotate-self for that; self-rotation is
  rejected here. No-op outside herdr (HERDR_ENV != 1).
allowed-tools: Bash(*/scripts/herdr-rotate *), Bash(*/scripts/herdr-rotate-* *), Bash(herdr *)
---

# rotate

Rotate a running herdr agent in place: handoff -> exit -> relaunch (fresh session, same
pane/tab/workspace/name, same launch command). Works the same for claude, pi, and codex --
the dispatcher detects the target's kind for you. **This is a two-step, agent-in-the-loop
flow** -- a bash script cannot block waiting for another agent's reply, so you drive it in
two calls with a pause in between.

This rotates ANOTHER agent (any target pane other than your own). To rotate your OWN pane,
use rotate-self instead -- `finish` below cannot exit the very process it is running inside,
so self-rotation is rejected here.

Each step below is a SEPARATE Bash tool call, and no shell state survives between calls, so
resolve the script path inline in EVERY invocation -- never set a variable in one call and
reuse it in a later one. `<base>` is shorthand for the REAL directory of this SKILL.md,
resolved with `readlink -f` (the skill installs as a symlink into the plugin tree, so a raw
`..` off the unresolved link would miss the real tree):

    <base> = $(dirname "$(readlink -f <this SKILL.md's listed path>)")

so `<base>/scripts/herdr-rotate` is the script (`scripts` is a symlink beside this skill,
into the plugin's shared `scripts/`). Never filesystem-search for it. Each step below shows
the full inline form -- use it exactly, substituting this SKILL.md's real listed path.

## Step 1 -- request the handoff

    "$(dirname "$(readlink -f <this SKILL.md's listed path>)")/scripts/herdr-rotate" handoff <name-or-pane> [--name N] [--model M] [--effort E]

This resolves and validates the target (kind, pane, name, and any `--name`/`--model`/`--effort`
you passed). It does NOT capture argv or probe the target's live model/effort here -- that all
happens in `finish` (nothing is persisted between the two calls). It then sends a self-contained
handoff prompt telling the target to ping **you** back --
`herdr agent prompt $HERDR_PANE_ID "<target-pane>@<session-prefix>: <path>"` -- once it has
written the handoff. The tag is the target's **pane id** plus the first 8 chars of its
*current* `agent_session` id, so a stale ping or a changed occupant is caught (**claude
only**: pi's session id is a filesystem path and codex reports none, so for those kinds the
tag is the bare pane id and this staleness check is skipped). The command returns
immediately; it does not wait.

## Step 2 -- wait for the ping, then finish

**Stop here and wait.** Do not poll or run other tool calls for this rotation. The target's
ping arrives as your own next incoming message (a prompt addressed to your pane) -- when it
does, read the tag and the absolute path straight out of it. Then run, passing the **tag
from the ping** (not just the bare name) as the target:

    "$(dirname "$(readlink -f <this SKILL.md's listed path>)")/scripts/herdr-rotate" finish <name-or-pane>[@<session-prefix>] <handoff-path> [--name N] [--model M] [--effort E] [--kickoff "<message>"|off]

The `@<session-prefix>` is optional (omit to skip the staleness check). **Pass the exact
same `--name`/`--model`/`--effort` you gave to `handoff`** -- nothing is persisted between
the two calls, so finish re-derives everything from scratch and needs the same options to
produce the same result. `--kickoff` is finish-only.

Finish first captures the target's launch argv (from `herdr pane process-info`); then, if you
gave no `--model`/`--effort` override, it detects a live mid-session model/effort change by
reading real, bounded command output (never the reflowing header/footer/statusline):

- **claude** -- opens `/model` once and reads BOTH the current model and the current effort from
  that single picker, then cancels with Esc.
- **pi** -- opens `/thinking` (current level, marked with a checkmark) and `/model` (checkmarked
  current model), reads the values, cancels both with Esc.
- **codex** -- reads `/status`, which reports model and reasoning effort in one non-modal
  printout (nothing to cancel); `/model` is deliberately never used (selecting even the current
  entry needs an Enter that can perturb state).

It then exits the target, relaunches it in the same pane with the resulting argv, verifies it,
and sends the kickoff prompt.

- `<name-or-pane>` -- agent name or pane id (from `herdr agent list`).
- `--name N` -- name for an unnamed agent on relaunch (default: derived `<kind>-<pane>`).
- `--model M` / `--effort E` -- override launch model/effort (only if changed mid-session;
  pi model must be provider-qualified, e.g. `amd-gateway/gpt-5.6-terra`). Omitted -> replayed.
- `--kickoff "<msg>"` -- custom first prompt (default resumes from the handoff without
  telling the agent to read everything up front); `--kickoff off` -- relaunch with no resume
  prompt.

The dispatcher detects the kind and forwards to `herdr-rotate-<kind>`; you never name it.

## How it works

1. `handoff`: resolve target -> kind/pane/name; validate name + overrides; send the handoff
   prompt (dies loudly if the send fails) and return. No argv capture or live probing here --
   that is all `finish`.
2. You wait for the target's ping (it lands in your own conversation).
3. `finish`: re-resolve (checking the session tag) + wait-settled (dies if it never settles)
   + capture argv + live-detect model/effort + apply overrides; re-check the session tag right before the destructive
   step; `/quit`; confirm the pane free; `herdr agent start` same name+pane replaying argv;
   poll to idle, verify -- **kickoff is withheld if verification fails**. Verification is
   argv element-by-element for claude/codex; **pi is different** -- it verifies the live
   model/effort (via the same `/thinking`+`/model` screen-reading), not argv. Current Linux
   (fork) pi preserves its argv, so its launch flags are captured and replayed; but macOS/older
   builds clobber it (`process.title`), so argv is not a reliable cross-platform verify source
   and only the live model/effort is verified for pi.

Nothing is parsed from header/footer/statusline, so it is robust to terminal width, though a
narrow-enough pane can still make live model/effort detection miss (fails safe: falls back
to what was already there, never replays a corrupted value).

## Known limitations

- **A positional prompt in the original launch is replayed** (e.g. `codex -m x "do the
  thing"`) -- it survives argv capture and re-executes as the first turn. Avoid by launching
  flags-only.
- **The handoff ping wait has no timeout.** Wait for exactly one ping before calling finish;
  don't issue a second handoff on the same target while waiting. If the ping never arrives,
  check the target's status manually.
- **`finish` cannot target the calling agent's own pane** (it would need this process gone
  first). Use rotate-self for your own pane.
- **The name-collision check before relaunch is check-then-use, not a reservation** -- a
  narrow window where another agent could take the name first.
- **A codex launch with global options before the `resume`/`fork` subcommand isn't
  detected.** Put `resume`/`fork` first when launching codex that way.
- **Do not alias the CLI binary itself** -- `herdr agent start` types the relaunch command
  into that aliased shell, so the alias's flags stack on every rotation.
