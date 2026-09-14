---
description: >-
  Rotate a running herdr coding agent (claude, pi, or codex) in place: checkpoint its
  context to a handoff document, then exit and relaunch it in the same pane with its launch
  flags replayed. Only invoke when the USER explicitly asks for it in this turn -- never
  self-trigger on your own judgment. To rotate the calling agent's own pane, use the
  rotate-self prompt instead. No-op outside herdr (HERDR_ENV != 1).
argument-hint: '<name-or-pane> [--name N] [--model M] [--effort E]'
---
Rotate a running herdr agent in place: handoff -> exit -> relaunch (fresh session, same
pane/tab/workspace/name, same launch command). **This is a two-step, agent-in-the-loop
flow** -- a bash script cannot block waiting for another agent's reply, so you drive it in
two calls with a pause in between.

Raw slash-command arguments: $ARGUMENTS

The script lives at a fixed path installed alongside these prompt templates:
`~/.pi/agent/prompts/scripts/herdr-rotate` (`scripts` is a symlink into the plugin's shared
`scripts/`). Use that exact path for both steps below.

## Step 1 -- request the handoff

    ~/.pi/agent/prompts/scripts/herdr-rotate handoff <name-or-pane> [--name N] [--model M] [--effort E]

This resolves the target and captures its launch argv. If no `--model`/`--effort` override
was given, it also detects a live mid-session model/effort change itself, reading real,
bounded command output (never the reflowing header/footer/statusline):

- **claude** -- opens `/status` and `/effort`, reads the value, cancels both with Esc.
- **pi** -- opens `/settings` searched to "thinking" and `/model` (checkmarked current
  model), reads the value, cancels both with Esc.
- **codex** -- reads `/status`, which reports model and reasoning effort in one non-modal
  printout (nothing to cancel); `/model` is deliberately never used (selecting even the
  current entry needs an Enter that can perturb state).

It then sends a self-contained handoff prompt telling the target to ping **you** back --
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

    ~/.pi/agent/prompts/scripts/herdr-rotate finish <name-or-pane>[@<session-prefix>] <handoff-path> [--name N] [--model M] [--effort E] [--kickoff "<message>"|off]

The `@<session-prefix>` is optional (omit to skip the staleness check). **Pass the exact
same `--name`/`--model`/`--effort` you gave to `handoff`** -- nothing is persisted between
the two calls, so finish re-derives everything from scratch and needs the same options to
produce the same result. `--kickoff` is finish-only. This step exits the target, relaunches
it in the same pane with the resulting argv, verifies it, and sends the kickoff prompt.

- `<name-or-pane>` -- agent name or pane id (from `herdr agent list`).
- `--name N` -- name for an unnamed agent on relaunch (default: derived `<kind>-<pane>`).
- `--model M` / `--effort E` -- override launch model/effort (only if changed mid-session;
  pi model must be provider-qualified, e.g. `amd-gateway/gpt-5.6-terra`). Omitted -> replayed.
- `--kickoff "<msg>"` -- custom first prompt (default resumes from the handoff without
  telling the agent to read everything up front); `--kickoff off` -- relaunch with no resume
  prompt.

The dispatcher detects the kind and forwards to `herdr-rotate-<kind>`; you never name it.

## How it works

1. `handoff`: resolve target -> kind/pane/name; validate name + overrides; capture launch
   argv from `herdr pane process-info`; send the handoff prompt (dies loudly if the send
   fails) and return.
2. You wait for the target's ping (it lands in your own conversation).
3. `finish`: re-resolve (checking the session tag) + wait-settled (dies if it never settles)
   + re-capture + re-apply overrides; re-check the session tag right before the destructive
   step; `/quit`; confirm the pane free; `herdr agent start` same name+pane replaying argv;
   poll to idle, verify -- **kickoff is withheld if verification fails**. Verification is
   argv element-by-element for claude/codex; **pi is different** -- pi overwrites its own
   `/proc/<pid>/cmdline` on startup, so its argv can never be read back, and only the live
   model/effort can be verified for pi.

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
  first). Use the rotate-self prompt for your own pane.
- **The name-collision check before relaunch is check-then-use, not a reservation** -- a
  narrow window where another agent could take the name first.
- **A codex launch with global options before the `resume`/`fork` subcommand isn't
  detected.** Put `resume`/`fork` first when launching codex that way.
- **Do not alias the CLI binary itself** -- `herdr agent start` types the relaunch command
  into that aliased shell, so the alias's flags stack on every rotation.
