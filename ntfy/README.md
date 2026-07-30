# ntfy

Push notifications via [ntfy.sh](https://ntfy.sh) when the agent asks you a question. Off by default; toggle per-session.

## Quick Start

1. Install the [ntfy app](https://ntfy.sh/#subscribe) on your phone or desktop and subscribe to a topic of your choosing.
2. Set `NTFY_TOPIC` to that topic (see Configuration below).
3. Before going AFK, say `ntfy on` — you'll be pinged whenever the agent asks you a question.

## Usage

| What you say | What happens |
|---|---|
| `ntfy on` or `/ntfy-on` | Enables notifications for the current session |
| `ntfy off` or `/ntfy-off` | Disables notifications for the current session |

Notifications are off by default each session and do not persist across sessions.

## How It Works

Two hooks fire when notifications are enabled:

| Hook | Trigger | Behavior |
|------|---------|----------|
| `PreToolUse` on `AskUserQuestion` | Agent uses the question tool | Sends notification with the exact question text (precise) |
| `Stop` | Agent stops and its message contains `?` | Sends notification with the last 300 chars of the message (best-effort fallback for plain-text questions) |

A `SessionEnd` hook cleans up the per-session marker file on exit.

The enabled state is stored as a marker file at `${CLAUDE_CODE_TMPDIR}/ntfy-plugin/active/notify-enabled-<session_id>`.

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
