---
name: knowledge-init
description: >
  One-time project setup for the knowledge management system. Creates the directory
  structure, default configuration, and initial files. Use when setting up a new project
  or when the user asks to initialize knowledge tracking.
---

# /knowledge-init

Set up the knowledge management system for the current project.

## Steps

1. Resolve the storage root (from settings.json `knowledge.root` or default `~/.local/share/claude/knowledge/`).
2. Detect project name from `git remote get-url origin`.
3. Create the project directory: `<storage-root>/<project>/`
4. Create these files:

**directives.md** with default configuration:
```yaml
auto-save:
  auto: [hardware findings, build errors, debugging root causes, API behaviors]
  ask: [coding conventions, architecture decisions]
  never: [temporary workarounds, debugging session logs]
  default: auto
promotion: auto
stale-branch-days: 30
default-branch: develop
confidence-min: observed
```

**knowledge/index.md** — empty topic index
**workflows/index.md** — empty workflow index
**user.md** — placeholder for container name, worktree path

5. If not on a default branch, also create the branch directory using `${CLAUDE_PLUGIN_ROOT}/scripts/create-branch-dir.sh`.
6. Report: "Knowledge base initialized at <path>. I'll automatically track verified findings across branches and promote them when you merge. Run /knowledge-help for commands."
