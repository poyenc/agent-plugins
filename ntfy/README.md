# ntfy

Push notifications via [ntfy.sh](https://ntfy.sh) when the agent asks you a question or you want to be pinged on any event. Off by default; toggle per-session.

## Quick Start

1. Install the [ntfy app](https://ntfy.sh/#subscribe) on your phone or desktop and subscribe to a topic of your choosing.
2. Set `NTFY_TOPIC` to that topic (see Configuration below).
3. Before going AFK, say `ntfy on` — you'll be pinged whenever the agent asks you a question.

## Usage

| What you say / skill | What happens |
|---|---|
| `ntfy on` or `/ntfy-on [title]` | Enables automatic notifications for the current session; optional title overrides the default notification title |
| `ntfy off` or `/ntfy-off` | Disables automatic notifications for the current session |
| `/ntfy-user` (agent-invoked) | Agent sends a one-off notification for any event |

Automatic notifications are off by default each session and do not persist across sessions.

The `/ntfy-user` skill respects the on/off toggle — it checks the same per-session marker file
before sending. If notifications are off, it skips silently. The agent calls it explicitly when
asked to notify on a specific event (task complete, error, milestone, question, etc.).

## How It Works

Two hooks fire when notifications are enabled:

| Hook | Trigger | Behavior |
|------|---------|----------|
| `PreToolUse` on `AskUserQuestion` | Agent uses the question tool | Sends notification with the exact question text (precise) |
| `Stop` | Agent stops and its message contains `?` | Sends notification with the last 300 chars of the message (best-effort fallback for plain-text questions) |

A `SessionEnd` hook cleans up the per-session marker file on exit.

The enabled state is stored as a marker file at `${CLAUDE_CODE_TMPDIR}/ntfy-plugin/active/notify-enabled-<session_id>`. If a title was passed to `/ntfy-on`, it is written into that file and read back by the hooks and `/ntfy-user` to override `NTFY_TITLE` for all notifications in the session.

## Configuration

Set these environment variables (e.g. in `~/.claude/settings.json` under `"env"`, or export them in your shell profile):

| Variable | Default | Description |
|----------|---------|-------------|
| `NTFY_TOPIC` | `agent-notify-topic` | ntfy topic to publish to |
| `NTFY_URL` | `https://ntfy.sh` | ntfy server base URL |
| `NTFY_PRIORITY` | `default` | Message priority (`min`, `low`, `default`, `high`, `urgent`) |
| `NTFY_TOKEN` | _(none)_ | Bearer token for authenticated/private topics |
| `NTFY_TITLE` | `Agent needs input` | Default notification title |

Example `~/.claude/settings.json` snippet:

```json
{
  "env": {
    "NTFY_TOPIC": "my-private-topic",
    "NTFY_TOKEN": "tk_mytoken",
    "NTFY_PRIORITY": "high"
  }
}
```
