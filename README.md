# agent-plugins

A collection of Claude Code plugins for development workflow automation.

## Plugins

| Plugin | Description |
|--------|-------------|
| **[recall](recall/README.md)** | Automatic branch-aware recall system. Tracks project knowledge across branches and tasks with layered overlays, conditional topic loading, auto-save rules, and merge promotion. |
| **[ntfy](ntfy/README.md)** | Push notifications via ntfy.sh when the agent asks a question. Off by default; toggle per-session with `/ntfy-on` and `/ntfy-off`. Uses `PreToolUse` on `AskUserQuestion` (precise) plus `Stop` hook with `?` grep (best-effort fallback for plain-text questions). |
| **guardrails** | Enforces safe agent behavior by blocking tool usage patterns that degrade session quality. Blocks `sleep` commands, blocks `EnterPlanMode` (agent must describe approach and wait for approval instead), blocks `Write`/`Edit` to the built-in memory directory (`~/.claude/projects/*/memory/`), and enforces cron interval/count limits. Configurable via `GUARDRAILS_MAX_CRONS` and `GUARDRAILS_MIN_CRON_MINUTES`. |

## Installation

This repo is a local Claude Code marketplace. Add it to `~/.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "agent-plugins": {
      "source": {
        "source": "directory",
        "path": "/path/to/agent-plugins"
      }
    }
  },
  "enabledPlugins": {
    "recall@agent-plugins": true,
    "ntfy@agent-plugins": true,
    "guardrails@agent-plugins": true
  }
}
```

Enable only the plugins you want — each key is independent.

## Usage

Plugins are loaded automatically by Claude Code when enabled. See each plugin's README for setup and configuration details.
