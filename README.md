# agent-plugins

A collection of Claude Code plugins for development workflow automation.

## Plugins

| Plugin | Description |
|--------|-------------|
| **[recall](recall/README.md)** | Automatic branch-aware recall system. Tracks project knowledge across branches and tasks with layered overlays, conditional topic loading, auto-save rules, and merge promotion. |
| **[ntfy](ntfy/README.md)** | Push notifications via ntfy.sh when the agent asks a question. Off by default; toggle per-session with `/ntfy-on` and `/ntfy-off`. Uses `PreToolUse` on `AskUserQuestion` (precise) plus `Stop` hook with `?` grep (best-effort fallback for plain-text questions). |
| **[guardrails](guardrails/README.md)** | Enforces safe agent behavior by blocking tool usage patterns that degrade session quality. Blocks `sleep` commands, blocks wrapping ssh/scp/sftp/rsync-over-ssh in `timeout` (steers to native `ConnectTimeout` fast-fail), blocks `Write`/`Edit` to the built-in memory directory (`~/.claude/projects/*/memory/`), enforces cron interval/count limits, blocks a single `Read` call from returning more than a configurable byte limit of text file content (images/PDFs/notebooks skipped), and blocks blind whole-tree scans — any `find` rooted at `/` or `$HOME`, plus the plain forms of recursive `grep -r`/`rg`/`fd`/`ls -R` there (split into two independently-tunable hooks). Configurable via `GUARDRAILS_MAX_CRONS`, `GUARDRAILS_MIN_CRON_MINUTES`, and `GUARDRAILS_MAX_READ_BYTES` (default 64 KiB). See [guardrails/README.md](guardrails/README.md) for the full hook list. |
| **[herdr-kit](herdr-kit/README.md)** | Herdr agent tools: checkpoint-and-relaunch a running claude/pi/codex agent in place (including self-rotation via a detached daemon), plus non-blocking async inter-agent messaging. |

### pi extensions

Standalone pi extensions live in [`pi-extensions/`](pi-extensions/). They are not Claude Code plugins -- no manifest or marketplace entry. A pi extension that adapts an existing plugin (shares its scripts or config) stays inside that plugin instead, e.g. `guardrails/pi-extensions/`.

Link the file into pi's auto-loaded extensions directory, then run `/reload` in a running pi session:

| Extension | Description |
|-----------|-------------|
| **[bash-guardrails](guardrails/pi-extensions/bash-guardrails.ts)** | Applies the [guardrails](guardrails/README.md) Bash command guards to pi by hooking its `tool_call` event and running the same scripts under `guardrails/hooks/scripts/`. Activate with `bash guardrails/pi-extensions/install.sh` (symlinks it into `~/.pi/agent/extensions/`). See [pi support](guardrails/README.md#pi-support). |
| **[cache-footer](pi-extensions/cache-footer.ts)** | Replaces pi's footer to add the prompt-cache hit rate as `CH<last request>%/<whole session>%`. Link with `ln -s "$PWD/pi-extensions/cache-footer.ts" ~/.pi/agent/extensions/cache-footer.ts`. |

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
    "guardrails@agent-plugins": true,
    "herdr-kit@agent-plugins": true
  }
}
```

Enable only the plugins you want — each key is independent.

## Usage

Plugins are loaded automatically by Claude Code when enabled. See each plugin's README for setup and configuration details.
