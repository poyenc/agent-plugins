# agent-plugins

A collection of Claude Code plugins for development workflow automation.

## Plugins

| Plugin | Description |
|--------|-------------|
| **[recall](recall/README.md)** | Automatic branch-aware recall system. Tracks project knowledge across branches and tasks with layered overlays, conditional topic loading, auto-save rules, and merge promotion. |

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

Plugins are loaded automatically by Claude Code when enabled. Each plugin provides slash commands — see individual plugin READMEs for details.
