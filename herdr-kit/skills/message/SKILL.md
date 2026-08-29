---
name: message
description: >
  Send a non-blocking, asynchronous message to another herdr agent, or reply to one you
  received. Use whenever you want to update, ask, or check in with another agent without
  blocking on its response -- e.g. after delegating work, to flag something relevant to
  another agent's task, or to answer a message you were sent. Never blocks: sending returns
  immediately, and a reply (if you asked for one) arrives as your own next incoming turn,
  the same way any other prompt addressed to your pane does. No-op outside herdr
  (HERDR_ENV != 1).
allowed-tools: Bash(*/scripts/herdr-message *), Bash(herdr *)
---

# message

Send an async message to another herdr agent, or reply to one. Unlike `herdr agent prompt
--wait --timeout`, this never blocks: `send`/`reply` both return as soon as the underlying
prompt is delivered, whether or not anyone ever answers.

## Sending

    <base>/../scripts/herdr-message send <target> "<text>" [--callback [MSG]]

- `<target>` -- agent name or pane id (from `herdr agent list`).
- `<text>` -- the message body.
- `--callback` -- request a reply, using a default instruction telling the recipient to run
  `herdr-message reply` back at you.
- `--callback "<msg>"` -- request a reply with your own custom instruction instead of the
  default.
- Omit `--callback` entirely for a pure fire-and-forget message -- no reply implied or
  expected.

Prints `{"message_id":"<id>","sent_to":"<target>"}` on success -- note the `message_id` if you
want to recognize a later reply to this specific message; there is nothing else to track, and
nothing else the command waits for.

## Replying

    <base>/../scripts/herdr-message reply <target> <message-id> "<text>"

`<target>` is the pane id or name to reply to (the sender's own identity is embedded in the
message you received, in its `[msg-<id> from <name>@<pane>]` header line -- reply to the
`<pane>` part). `<message-id>` is the `<id>` from that same header (or from a
`--callback`-requested instruction, if one was given). This builds the `[reply:<id> from
...]` envelope for you -- don't hand-construct it yourself.

## How it works

Both commands build a short text envelope (sender identity, message id, your text, and an
optional reply-request block) and send it via a single `herdr agent prompt <target> "..."`
call -- no `--wait`, no timeout, ever. There is no persisted message store, inbox, or delivery
confirmation beyond whatever `herdr agent prompt` itself reports; a failed send dies loudly
rather than reporting success.

## Known limitations

- **No delivery guarantee beyond the initial send succeeding.** If the target's pane closes,
  the agent exits, or it simply never reads/replies, there is no notification -- this mirrors
  `herdr agent prompt`'s own semantics, since that's the only thing this skill sends through.
- **Message ids are not unique across the whole session, only informally distinct.** A 6-char
  random id is meant to be human/agent-legible for casual correlation, not a collision-proof
  identifier -- don't rely on it for anything security- or correctness-critical.
