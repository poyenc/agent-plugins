# recall

Automatic branch-aware recall system for Claude Code. Tracks what you learn across branches and tasks so future sessions start with context instead of from scratch.

## Quick Start

**Step 1.** Add these 2 lines to your `CLAUDE.md` (global or per-project):

```markdown
## Recall
Use /recall-status at session start. Knowledge is stored at ~/.local/share/claude/recall/.
```

**Step 2.** Start a Claude Code session and run `/recall-init` once per project.

That's it. The agent now tracks your branch, loads relevant knowledge at session start, and saves findings as you work.

## What's Automatic vs. What You Type

Most of this plugin runs hands-free. You talk to the agent normally; it manages knowledge behind the scenes.

| What happens | Who does it |
|---|---|
| Detect branch, load knowledge at session start | **Automatic** (hook) |
| Save findings during debugging/exploration | **Agent** (based on auto-save config) |
| Detect merged branches, offer promotion | **Agent** (automatic) |
| Create/switch/complete tasks | **You or agent** — say it naturally or use a command |
| Explicitly save a specific finding | **You** — tell the agent what to remember |

**You rarely need to type commands.** Just talk:

- *"Remember that gfx950 needs the `--offload-arch` flag"* — agent saves it
- *"Switch to the gemm optimization task"* — agent runs `/task-switch`
- *"I'm done with this task"* — agent runs `/task-complete`
- *"This approach is a dead end"* — agent runs `/task-abandon`

Commands like `/task-switch optimize-gemm` exist for when you want to be explicit, but natural language works the same way.

## Scenarios

### "I just want it to learn as I work"

You don't need to do anything special. The agent auto-saves findings in categories you configure (hardware quirks, build errors, debugging root causes, etc.). Over time, project knowledge accumulates and gets loaded into future sessions automatically.

### "Save this — I'll need it later"

When you discover something non-obvious, tell the agent in plain language:

- *"Remember that gfx950 needs the `--offload-arch` flag for this kernel"*
- *"Save this: the V3 dispatch path requires `CK_LOG_LEVEL=1` to verify"*

The agent writes it to the appropriate scope (project or branch) based on context. To override scope, either say so naturally or use flags:

- *"Save this as project-level knowledge: ..."*
- *"/recall-add --project this applies everywhere"*
- *"/recall-add --branch this is specific to my current feature"*

### "I'm switching to a different task on this branch"

Just say *"switch to the gemm task"* — or use the command directly:

```
/task-switch optimize-gemm
```

This saves your current task's state and loads the target task's context. Fuzzy matching works — you don't need the exact name. To create a new task:

```
/task-create optimize-gemm
```

Each task gets its own `status.md` (hypotheses, next steps) and `knowledge.md` (verified findings). When you're done, say *"this task is done"* or *"abandon this task"*:

- `/task-complete` — marks it done, reviews findings for promotion to branch level
- `/task-abandon` — captures what was learned, archives the rest

### "I finished my feature branch"

When your branch merges, the agent detects it and offers to promote branch-level knowledge to the project level. This is how institutional knowledge grows — findings that started as branch-specific become available to all future sessions.

You can also trigger this manually: `/promote my-branch-name`

### "What do I know so far?"

Ask naturally (*"what knowledge do we have?"*) or use commands:

- `/recall-status` — current branch, active task, loaded topics
- `/recall-search <query>` — search across all knowledge including archived branches
- `/recall-changelog` — recent changes across all knowledge files
- `/branch-status` — overview of all tracked branches

### "This approach isn't working"

Say *"this isn't working, let's abandon this task"* or use commands:

- `/task-abandon` — salvages useful findings from the task before archiving
- `/branch-abandon` — salvages branch knowledge to project level, archives the branch

The key insight: even failed approaches produce knowledge. The abandon commands capture what you learned so it's not lost.

## How It Works

Knowledge is organized in three layers: **project > branch > task**. Each layer only contains what's new at that level — no duplication. The agent reads all layers at session start and merges them.

```
~/.local/share/claude/recall/<project>/
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

**Why build your own instead of sharing someone else's?** Project-level knowledge reflects what *you* explored, from *your* perspective. Someone else's findings encode their assumptions, focus areas, and mental models — which may not match yours. The plugin's value is the accumulation process, not any particular snapshot.

## Commands

| Command | Description |
|---------|-------------|
| `/recall-init` | One-time project setup |
| `/recall-status` | Show current branch, task, and knowledge state |
| `/recall-help` | List all commands and explain the system |
| `/recall-add <topic>` | Save a finding (use `--project` or `--branch` to set scope) |
| `/recall-search <query>` | Search across all knowledge including archives |
| `/recall-changelog` | Show recent knowledge changes |
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

Configure by talking to the agent: *"auto-save hardware findings"*, *"set stale threshold to 60 days"*.

## Storage

Default: `~/.local/share/claude/recall/` (XDG convention).

Override in `~/.claude/settings.json`:
```json
{
  "recall": {
    "root": "~/my-notes"
  }
}
```
