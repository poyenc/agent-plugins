---
name: task-create
description: Create a new task under the current branch.
---

# /task-create <name>

Create a new task under the current branch.

## Arguments
- `<name>`: task name (kebab-case, e.g., "add-login", "fix-xnack-bug")

## Steps

1. Resolve the current branch directory from meta.md.
2. If on a default branch, say: "Tasks belong to feature branches. Create or switch to a branch first."
3. If the branch is in lightweight mode, offer to upgrade: "This branch is in lightweight mode. Upgrade to full mode to use tasks?"
4. If task already exists, say: "Task '<name>' already exists. Use /task-switch <name> to switch to it."
5. Ask for the goal if not provided: "What's the goal for this task?"
6. Run: `${CLAUDE_PLUGIN_ROOT}/scripts/create-task-dir.sh --branch-dir <branch-dir> --task <name> --goal "<goal>"`
7. Report: "Created task '<name>'. Now tracking progress in status.md."
