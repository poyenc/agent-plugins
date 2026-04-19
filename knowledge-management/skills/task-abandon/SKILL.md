---
name: task-abandon
description: >
  Abandon the current task, capture what was learned, and salvage useful knowledge.
  Use when an approach didn't work, requirements changed, or a task is no longer needed.
---

# /task-abandon [name]

Abandon a task and capture negative knowledge.

## Arguments
- `[name]`: optional task name. Defaults to the active task from meta.md.

## Steps

1. Resolve the task (active task from meta.md, or resolve `[name]` via fuzzy matching).
2. Ask: "Why is this task being abandoned?" Capture the reason.
3. Add `## Abandonment Reason` section to status.md with the reason and what was tried.
4. Review task knowledge for salvageable findings:
   - Negative results ("approach X doesn't work because Y") → offer to promote to branch knowledge
   - Verified technical facts → offer to promote to branch knowledge
   - Everything else → leave in place
5. Update `**Status:** abandoned` in status.md.
6. Update `**Active Task:** none` in meta.md.
7. Report: "Task '<name>' abandoned. Reason captured. <N> findings salvaged to branch level."
