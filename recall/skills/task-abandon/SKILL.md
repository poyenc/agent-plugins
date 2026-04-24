---
name: task-abandon
description: Abandon current task, capture learnings, salvage useful knowledge.
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
   - Read knowledge (knowledge.md if flat file, or knowledge/index.md + relevant topic files if split into directory).
   - Negative results ("approach X doesn't work because Y") → offer to promote to branch knowledge
   - Verified technical facts → offer to promote to branch knowledge
   - Everything else → leave in place
4.5. **Compact status.md** — if status.md exceeds maintenance.status-final-lines (from directives.md) or has `<!-- maintenance: compact needed -->` marker:
   a. Copy status.md to status.pre-compact.md as backup.
   b. Extract detailed content into knowledge topics. Consolidate "what failed and why" into a negative-results knowledge topic.
   c. Rewrite status.md in compact format (same as task-complete).
   d. If task knowledge now exceeds maintenance.task-knowledge-split-lines, split into knowledge/ directory.
   e. Verify, then delete status.pre-compact.md.
5. Update `**Status:** abandoned` in status.md.
6. Update `**Active Task:** none` in meta.md.
7. Report: "Task '<name>' abandoned. Reason captured. <N> findings salvaged to branch level."
