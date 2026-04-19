# knowledge-management

Automatic branch-aware knowledge management for Claude Code. Tracks project knowledge across branches and tasks with layered overlays, conditional topic loading, and merge promotion.

## How It Works

Knowledge is organized in three layers: **project > branch > task**. Each layer only contains what's new at that level — no duplication. The agent reads all layers at session start and merges them.

```
~/.local/share/claude/knowledge/<project>/
  directives.md           # agent behavior rules + configuration
  knowledge/              # project-level topics (loaded conditionally)
  workflows/              # project-level procedures (loaded conditionally)
  user.md                 # personal preferences (container, worktree, etc.)
  branches/
    <branch>/
      meta.md             # branch metadata, active task, parent info
      knowledge/          # branch overlay (only NEW findings)
      workflows/          # branch overlay (only NEW procedures)
      tasks/
        <task>/
          status.md       # task progress, hypotheses, next steps
          knowledge.md    # task-specific findings
```

## Features

- **Automatic branch detection** — detects new branches at session start, creates knowledge directories
- **Layered knowledge** — project > branch > task overlays, no duplication
- **Topic-based loading** — only relevant topics are loaded into context (index.md lists available topics)
- **Auto-save with rules** — configurable per-category: auto, ask, or never
- **Merge promotion** — detects merged branches (git + GitHub PR query), promotes general knowledge to project level
- **Lightweight branches** — hotfixes skip the full setup ceremony
- **Task management** — create, switch, complete, abandon tasks with fuzzy name matching
- **Knowledge integrity** — only [VERIFIED] and [OBSERVED] facts are saved; hypotheses stay in status.md

## Commands

| Command | Description |
|---------|-------------|
| `/knowledge-init` | One-time project setup |
| `/knowledge-status` | Show current branch, task, and knowledge state |
| `/knowledge-help` | List all commands and explain the system |
| `/knowledge-add <topic>` | Save a finding (use `--project` or `--branch` to set scope) |
| `/knowledge-search <query>` | Search across all knowledge including archives |
| `/knowledge-changelog` | Show recent knowledge changes |
| `/branch-status` | Overview of all branches and their knowledge |
| `/branch-abandon` | Abandon current branch, salvage useful knowledge |
| `/promote [branch]` | Promote branch knowledge to project level |
| `/task-create <name>` | Create a new task under current branch |
| `/task-switch <name>` | Switch to a different task (fuzzy matching) |
| `/task-complete` | Mark task done, review knowledge for promotion |
| `/task-abandon` | Abandon task, capture what was learned |

## Configuration

Settings live in `directives.md` under `## Configuration`:

```yaml
auto-save:
  auto: [hardware findings, build errors, debugging root causes]
  ask: [coding conventions, architecture decisions]
  never: [temporary workarounds, debugging session logs]
  default: auto
promotion: auto
stale-branch-days: 30
default-branch: develop
confidence-min: observed
```

Configure by talking to the agent: "auto-save hardware findings", "set stale threshold to 60 days".

## Storage

Default: `~/.local/share/claude/knowledge/` (XDG convention).

Override in `~/.claude/settings.json`:
```json
{
  "knowledge": {
    "root": "~/my-notes"
  }
}
```

