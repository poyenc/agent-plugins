---
name: message
description: >
  Send a non-blocking, asynchronous message to another herdr agent, or reply to one you
  received. Use whenever you are about to send a prompt or message to another agent --
  especially when you expect a response -- instead of a blocking `herdr agent prompt --wait`:
  to update, ask, or check in after delegating work, to flag something relevant to another
  agent's task, or to answer a message you were sent. Never blocks: sending returns
  immediately, and a reply (if you asked for one) arrives as your own next incoming turn,
  the same way any other prompt addressed to your pane does. Also covers delivering a bare
  slash-command (e.g. `/model`) to control a peer's own CLI, unwrapped, when a real message
  envelope would corrupt it. No-op outside herdr (HERDR_ENV != 1).
allowed-tools: Bash(*/scripts/herdr-message *), Bash(herdr *)
---

# message

Send an async message to another herdr agent, or reply to one. Unlike `herdr agent prompt
--wait --timeout`, this never blocks: `send`/`reply` both return as soon as the underlying
prompt is delivered, whether or not anyone ever answers.

## Sending

    <base>/scripts/herdr-message send <target> "<text>" [--callback [MSG]]

`<base>` is the real directory of this SKILL.md. How to find it depends on your harness:
- **Claude Code**: a `Base directory for this skill: <PATH>` line was injected above — use `<PATH>` directly as `$base`.
- **Pi, Codex, and others**: your skill listing shows the full path to this SKILL.md. Run:
  `base="$(dirname "$(readlink -f /path/from/your/skill/listing/SKILL.md)")"`

The script is then `$base/scripts/herdr-message`, where `scripts` is a committed symlink beside this SKILL.md pointing at the plugin's top-level `scripts/` directory.

- `<target>` -- agent name or pane id (from `herdr agent list`).
- `<text>` -- the message body.
- `--callback` -- request a reply, using a default instruction telling the recipient to run
  `herdr-message reply` back at you.
- `--callback "<msg>"` -- request a reply with your own custom instruction instead of the
  default.
- `--callback=<msg>` -- same as above, but takes everything after `=` literally, with zero
  ambiguity -- use this form if your custom instruction itself starts with `-`.
- Omit `--callback` entirely for a pure fire-and-forget message -- no reply implied or
  expected.

Prints `{"message_id":"<id>","sent_to":"<target>"}` on success -- note the `message_id` if you
want to recognize a later reply to this specific message; there is nothing else to track, and
nothing else the command waits for.

## Replying

    <base>/scripts/herdr-message reply <target> <message-id> "<text>" [--callback [MSG]]

`<target>` is the pane id or name to reply to (the sender's own identity is embedded in the
message you received, in its `[msg-<id> from <name>@<pane>]` header line -- reply to the
`<pane>` part). `<message-id>` is the `<id>` from that same header (or from a
`--callback`-requested instruction, if one was given). This builds the `[reply:<id> from
...]` envelope for you -- don't hand-construct it yourself.

`--callback [MSG]` works exactly as it does for `send` (default instruction, custom `MSG`, or
the literal `--callback=<msg>` form), and it appends the SAME callback-request block -- so a
threaded reply can ALSO ask for a further response in one call. The requested reply threads
under the SAME `<message-id>` you are replying to, keeping a multi-round exchange under one
correlation id.

## Sending a raw CLI command

    <base>/scripts/herdr-message command <target> </slash-command>

For controlling a peer's own CLI -- e.g. `/model`, `/clear`, `/compact` -- not for conversing
with it. `send`/`reply` always wrap your text in an envelope, which is correct for a message but
would corrupt a slash-command: the target would see the literal envelope text instead of
executing the command. `command` delivers the payload byte-for-byte, unwrapped.

- `<target>` -- same as `send`/`reply`.
- The payload must be a single bare slash-command with no spaces or extra arguments (e.g. `/model`,
  not `/model opus`) -- anything else is rejected before it is sent.
- No `--callback`, no other flags: a raw CLI command has no reply path.

Prints `{"sent_to":"<target>","command":"<command>"}` on success.

## How it works

`send`/`reply` build a short text envelope (sender identity, message id, your text, and an
optional reply-request block) and send it via a single `herdr agent prompt <target> "..."`
call -- no `--wait`, no timeout, ever. `command` sends the same way but with no envelope at all --
just the bare slash-command. There is no persisted message store, inbox, or delivery confirmation
beyond whatever `herdr agent prompt` itself reports; a failed send dies loudly rather than
reporting success.

## Known limitations

- **No delivery guarantee beyond the initial send succeeding.** If the target's pane closes,
  the agent exits, or it simply never reads/replies, there is no notification -- this mirrors
  `herdr agent prompt`'s own semantics, since that's the only thing this skill sends through.
- **Message ids are not unique across the whole session, only informally distinct.** A 6-char
  random id is meant to be human/agent-legible for casual correlation, not a collision-proof
  identifier -- don't rely on it for anything security- or correctness-critical.
- **A `<text>` starting with `-` needs no special handling** -- the leading positionals (send's
  `<target>`/`<text>`, reply's `<target>`/`<message-id>`/`<text>`) are fixed and never
  flag-sniffed. A custom `--callback` message starting with `-`, however -- for either subcommand
  -- DOES need the `--callback=<msg>` form specifically (see above): the bare `--callback [MSG]`
  peek-ahead form can never tell such a message apart from "no value given."
