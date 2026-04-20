---
name: task-complete
description: Mark task completed and review knowledge for branch promotion.
---

# /task-complete [name]

Complete the current (or named) task and review its knowledge.

## Arguments
- `[name]`: optional task name. Defaults to the active task from meta.md.

## Steps

1. Resolve the task (active task from meta.md, or resolve `[name]` via fuzzy matching).
2. **Knowledge review** — before marking complete:
   - Read the task's knowledge.md.
   - Review the conversation for any unsaved findings (task completion review trigger).
   - For each finding, apply auto-save rules (auto/ask/never from directives config).
   - Ask: "Promote any of this task's knowledge to branch level?" List candidates.
3. Update `**Status:** completed` in the task's status.md.
4. Update `**Active Task:** none` in meta.md.
5. List remaining tasks: "Task '<name>' completed. Remaining tasks: <list>. Switch to one, or create a new task?"
