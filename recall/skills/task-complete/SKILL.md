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
   - Read the task's `topics/index.md` and relevant topic files.
   - Review the conversation for any unsaved findings (task completion review trigger).
   - For each finding, apply auto-save rules (auto/ask/never from the branch's settings.yaml).
   - Ask: "Promote any of this task's knowledge to branch level?" List candidates.
2.5. **Compact status.md** — if status.md exceeds maintenance.status-final-lines (from the branch's settings.yaml) or has `<!-- maintenance: compact needed -->` marker:
   a. Copy status.md to status.pre-compact.md as backup.
   b. Extract detailed content (experiment logs, raw data, debugging traces) into topic files under `topics/`. Use task-level topics by default; use branch-level if the finding is general.
   c. Rewrite status.md in compact format: Goal (unchanged), Baseline, Current State (2-3 sentences), Applied Changes (one line each), Next Steps.
   d. Verify compacted status.md has all required sections (Goal, Status, Current State). Then delete status.pre-compact.md.
3. Update `**Status:** completed` in the task's status.md.
4. Update `**Active Task:** none` in meta.md.
5. List remaining tasks: "Task '<name>' completed. Remaining tasks: <list>. Switch to one, or create a new task?"
