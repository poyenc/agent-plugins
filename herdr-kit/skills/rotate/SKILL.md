---
name: rotate
description: >
  Rotate a running herdr coding agent (claude, pi, or codex): checkpoint its
  context to a handoff document, then exit and relaunch it in the SAME pane as a
  fresh session, replaying the launch flags (model, effort, and other options)
  recovered from the process argv — see "Known limitations" in SKILL.md for the
  cases (pi verification, positional prompts) this doesn't fully cover. Only
  invoke this when the USER
  explicitly asks for it in this turn — e.g. "rotate this agent", "refresh the
  agent's context", "restart the agent but keep its setup". Never self-trigger
  on your own judgment (e.g. noticing your own or another agent's context is
  getting full) — surface that observation to the user and let them decide.
  No-op outside herdr (HERDR_ENV != 1).
disable-model-invocation: true
allowed-tools: Bash(*/scripts/herdr-rotate *), Bash(*/scripts/herdr-rotate-* *), Bash(herdr *)
---

# rotate

Rotate a running herdr agent in place: handoff -> exit -> relaunch (fresh
session, same pane/tab/workspace/name, same launch command).

**This is a two-step, agent-in-the-loop skill.** A bash script cannot block
waiting for another agent's reply, so the invoking agent (you) drives it in two
calls with a pause in between.

## Usage

### Step 1 — request the handoff

`<base>` is the directory containing this SKILL.md file (e.g. `.../herdr-kit/skills/rotate`).

    <base>/../scripts/herdr-rotate handoff <name-or-pane> [--name N] [--model M] [--effort E]

This resolves the target and captures its launch argv. If no `--model`/`--effort`
override was given, it also detects a live mid-session model/effort change
itself, reading real, bounded command output — never the reflowing
header/footer/statusline:

- **claude** — opens `/status` (current model) and `/effort` (effort slider),
  reads the value, cancels both with Esc.
- **pi** — opens `/settings` searched to "thinking" (current thinking level)
  and `/model` (current model, marked with a checkmark), reads the value,
  cancels both with Esc.
- **codex** — reads `/status`, which reports both model and reasoning effort
  in one non-modal printout (nothing to cancel). `/model` is deliberately
  never used here: selecting even the already-current entry requires an Enter
  that can perturb session state.

It then
sends a self-contained handoff prompt telling the target to ping **you** back —
`herdr agent prompt $HERDR_PANE_ID "<target-pane>@<session-prefix>: <path>"` —
once it has written the handoff file. The tag is the target's **pane id**
(not its name — an unnamed agent has no resolvable name yet at this point)
plus the first 8 characters of its *current* `agent_session` id (so a stale
ping from an earlier rotation, or a pane whose occupant already changed, is
caught instead of silently rotating the wrong instance) — **claude only**:
pi's session id is a filesystem path (not a stable prefix), and codex's
integration in this environment doesn't report one at all, so for those
kinds the tag is just the bare pane id and this staleness check is skipped.
The command then returns immediately; it does not wait.

### Step 2 — wait for the ping, then finish

**Stop here and wait.** Do not poll, do not run other tool calls for this
rotation. The target's ping arrives as your own next incoming message (it is a
prompt addressed to your pane) — when it does, read the tag and the absolute
path straight out of it.

Then run, passing the **tag from the ping** (not just the bare name) as the target:

    <base>/../scripts/herdr-rotate finish <name-or-pane>[@<session-prefix>] <handoff-path> [--name N] [--model M] [--effort E] [--kickoff "<message>"] [--no-kickoff]

The `@<session-prefix>` is optional — omit it to skip the staleness check — but
including it is how you get the protection described above.

**Pass the exact same `--name`/`--model`/`--effort` you gave to `handoff`** —
nothing is persisted between the two calls, so this step re-derives the launch
argv (and re-detects the live model/effort the same way) from
scratch and needs the same options to produce the same result. `--kickoff`/
`--no-kickoff` are `finish`-only (the kickoff prompt is sent here, after
relaunch) — `handoff` rejects them. This step exits the target, relaunches it
in the same pane with the resulting argv, verifies it element-by-element, and
sends the kickoff prompt.

- `<name-or-pane>` — agent name or pane id (from `herdr agent list`).
- `--name N` — name for an unnamed agent on relaunch (default: derived `<kind>-<pane>`).
- `--model M` / `--effort E` — override launch model/effort (only if changed mid-session;
  pi model must be provider-qualified, e.g. `amd-gateway/gpt-5.6-terra`). Omitted -> replayed.
- `--kickoff "<msg>"` — custom first prompt (default: "Continue the work described in the
  handoff at \<path\>, then pick up the task list where it leaves off." — deliberately doesn't
  say "read it fully" or mention referenced files; that phrasing has been observed to push the
  fresh agent into proactively reading everything the handoff references before doing any work).
- `--no-kickoff` — relaunch without sending a resume prompt.

The dispatcher detects the kind and forwards to `herdr-rotate-<kind>`; you never
need to name it yourself.

## How it works

1. `handoff`: resolve target -> kind, pane, name (derive if unnamed, verify session tag if
   given); validate name + overrides (no settle-wait here — the target is already idle when
   handoff runs); capture launch argv from `herdr pane process-info` (NUL-safe; the only
   source for the BASE flags being replayed — detecting a live override, if no `--model`/
   `--effort` was given, is the separate screen-reading mechanism described above); send the
   handoff prompt (dies loudly if the send itself fails) and return.
2. You wait for the target's ping (its reply lands in your own conversation).
3. `finish`: re-resolve (checking the session tag) + wait-settled (dies if it never settles —
   the next step is destructive) + re-capture + re-apply overrides (same result as step 1,
   since nothing about the target has changed); re-checks the session tag one more time right
   before the destructive step (closes the window between the first check and now); `/quit`;
   confirm the pane is free (`agent_not_found` + shell prompt); `herdr agent start` same
   name+pane, replaying argv; poll the new agent to idle, verify — **kickoff is withheld if
   verification fails**, so a mis-launched agent is never told to start working. Verification
   is argv element-by-element for claude/codex. **pi is different**: pi overwrites its own
   `/proc/pid/cmdline` on startup (`process.title = ...` in its own CLI), so argv can never be
   read back for pi — not at capture time, not at verify time. Only the live model/effort
   (via the same `/settings`+`/model` screen-reading used to detect them) can be verified for
   pi; any other launch flags are neither verifiable nor reliably replayed for this kind.

Nothing is parsed from header/footer/statusline, so it is robust to terminal width, though a
narrow-enough pane can still cause a live model/effort detection to miss (fails safe: falls
back to whatever was already there, never replays a corrupted value).

## Known limitations

- **A positional prompt in the original launch is replayed.** If the target was started with
  a trailing prompt argument (e.g. `codex -m x "implement the migration"`, or any launch that
  deviates from this skill's own recommended pattern of flags-only + a separate follow-up
  `agent prompt`), that argument survives argv capture and is replayed on relaunch — the fresh
  instance re-executes it as its first turn, before the kickoff prompt. This is not
  auto-stripped: reliably telling a genuine trailing positional apart from an ordinary flag's
  value (e.g. `--system-prompt "some text"`) needs a full per-kind flag-arity table this skill
  doesn't have, and guessing wrong risks silently corrupting some other flag instead. Avoid by
  never launching with a positional prompt in the first place (this skill's own recommended
  pattern already avoids it).
- **The handoff ping wait has no timeout.** Once you call `handoff`, you're expected to wait
  for exactly one ping before calling `finish` on that same target — don't issue a second
  `handoff` on the same target while still waiting on the first. If the target crashes, never
  writes the handoff, or its ping never arrives, there's no automatic recovery; check the
  target's status manually and decide whether to retry.
- **`finish` cannot target the calling agent's own pane.** It's rejected outright: the
  exit-and-relaunch step needs this very command's own process to have already exited before
  it can confirm the pane empty, which can never happen while it's still running as that
  command. Have a different agent run `finish` on this target. (`handoff` on your own pane is
  fine — it only sends a prompt and returns, nothing to wait out.)
- **The name-collision check before relaunch is check-then-use, not a reservation.** Between
  confirming a name is free and `agent start` actually claiming it, another agent could take
  it first — herdr's CLI has no atomic "reserve this name" primitive to close that window.
  `agent start` itself would then fail (it doesn't hand a fresh session the wrong name), but
  only after this rotation's own old agent has already been exited, so the pane would be left
  without its intended replacement. Narrow in practice (the window is a few JSON round-trips),
  but not eliminated.
- **A codex launch with global options before the `resume`/`fork` subcommand isn't detected**
  (e.g. `codex -m glm-5.2 resume session-123`) — context stripping only checks whether the
  first argument is the subcommand. Reliably skipping past preceding global options needs a
  full arity table for all of codex's top-level flags, which carries the same
  wrong-guess-corrupts-another-flag risk as the positional-prompt case above. Avoid by putting
  `resume`/`fork` first when launching codex this way.
