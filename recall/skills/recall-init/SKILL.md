---
name: recall-init
description: >
  One-time project setup for the recall system. Creates the directory
  structure, default configuration, and initial files. Use when setting up a new project
  or when the user asks to initialize knowledge tracking.
---

# /recall-init

Set up the recall system for the current project.

## Steps

1. Resolve the storage root (from settings.json `recall.root` or default `~/.local/share/claude/recall/`).
2. Detect project name from `git remote get-url origin`.
3. Create the project directory: `<storage-root>/<project>/`
4. Create these files:

**directives.md** — project config and rules (no markdown headings, no YAML fences):
```
auto-save.auto: [hardware findings, build errors, debugging root causes, API behaviors]
auto-save.ask: [coding conventions, architecture decisions]
auto-save.never: [temporary workarounds, debugging session logs]
auto-save.default: auto
promotion: auto
stale-branch-days: 30
default-branch: develop
confidence-min: observed
```
Add project-specific rules as bullet points after the config block. Only add rules the user requests — no placeholders.

**knowledge/index.md** — empty file (topics added as discovered)
**workflows/index.md** — empty file (workflows added as discovered)
**user.md** — key-value pairs only, no headings or boilerplate:
```
CONTAINER=<ask user>
WORKSPACE=<ask user>
editor: <ask user or omit>
commit-style: <ask user or omit>
test-prefs: <ask user or omit>
```
Only include fields the user provides. Omit any field they don't specify.

5. If not on a default branch, assess branch type from name pattern (lightweight: hotfix/*, fix/*, typo/*, docs/*; full: everything else), then create the branch directory using `${CLAUDE_PLUGIN_ROOT}/scripts/create-branch-dir.sh` with the appropriate `--mode` flag. For full branches, ask "What's the epic/goal for this branch?"
6. Report: "Knowledge base initialized at <path>. I'll automatically track verified findings across branches and promote them when you merge. Run /recall-help for commands."
