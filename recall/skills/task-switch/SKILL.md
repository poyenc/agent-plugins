---
name: task-switch
description: Switch to a different task within the current branch (fuzzy match).
---

# /task-switch <name>

Switch the active task within the current branch.

## Arguments
- `<name>`: task name or partial match

## Steps

1. Read meta.md to get current branch directory and active task.
2. List all tasks: `ls <branch-dir>/tasks/`
3. Resolve task name:
   - Exact match on directory name
   - Substring match (if unique)
   - Grep `## Goal` sections in all status.md files for keywords
   - If multiple matches: list them and ask user to pick
   - If no match: ask "No task found matching '<name>'. Create a new task?"
4. Update `**Active Task:**` in meta.md using write_meta_field.
5. Read the new task's status.md, knowledge.md, and workflows.md.
6. Report: "Switched to task '<name>'. Status: <status>. Goal: <first line of goal>."
