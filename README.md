# agent-plugins

A collection of Claude Code plugins for development workflow automation.

## Plugins

| Plugin | Description |
|--------|-------------|
| **[recall](recall/README.md)** | Automatic branch-aware recall system. Tracks project knowledge across branches and tasks with layered overlays, conditional topic loading, auto-save rules, and merge promotion. |
| **ntfy** | Push notifications via ntfy.sh when the agent asks a question. Off by default; toggle per-session with `/ntfy-on` and `/ntfy-off`. Uses `PreToolUse` on `AskUserQuestion` (precise) plus `Stop` hook with `?` grep (best-effort fallback for plain-text questions). |

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
    "recall@agent-plugins": true
  }
}
```

## Usage

Plugins are loaded automatically by Claude Code when enabled. Each plugin provides slash commands -- see individual plugin READMEs for details.
