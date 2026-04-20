---
name: task-create
description: >
  Create a new task under the current branch. Use when the user says "create a task",
  "start working on X", or "new task". Requires being on a non-default branch with
  knowledge tracking initialized.
---

# /task-create <name>

Create a new task under the current branch.

## Arguments
- `<name>`: task name (kebab-case, e.g., "add-login", "fix-xnack-bug")

## Steps

1. Resolve the current branch directory from meta.md.
2. If on a default branch, say: "Tasks belong to feature branches. Create or switch to a branch first."
3. If the branch is in lightweight mode, offer to upgrade: "This branch is in lightweight mode. Upgrade to full mode to use tasks?"
4. Resolve task name (exact match → substring → grep Goal sections → ask if ambiguous → offer to create if no match).
5. If task already exists, say: "Task '<name>' already exists. Use /task-switch <name> to switch to it."
6. Ask for the goal if not provided: "What's the goal for this task?"
7. Run: `${CLAUDE_PLUGIN_ROOT}/scripts/create-task-dir.sh --branch-dir <branch-dir> --task <name> --goal "<goal>"`
8. Report: "Created task '<name>'. Now tracking progress in status.md."
