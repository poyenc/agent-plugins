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
   - Read the task's knowledge (knowledge.md if flat file, or knowledge/index.md + relevant topic files if split into directory).
   - Review the conversation for any unsaved findings (task completion review trigger).
   - For each finding, apply auto-save rules (auto/ask/never from directives config).
   - Ask: "Promote any of this task's knowledge to branch level?" List candidates.
2.5. **Compact status.md** — if status.md exceeds maintenance.status-final-lines (from directives.md) or has `<!-- maintenance: compact needed -->` marker:
   a. Copy status.md to status.pre-compact.md as backup.
   b. Extract detailed content (experiment logs, raw data, debugging traces) into knowledge topics. Use task-level knowledge by default; use branch-level if the finding is general.
   c. Rewrite status.md in compact format: Goal (unchanged), Baseline, Current State (2-3 sentences), Applied Changes (one line each), Next Steps.
   d. If task knowledge now exceeds maintenance.task-knowledge-split-lines, split into knowledge/ directory with per-topic files + index.md. Leave a 2-line redirect at the original knowledge.md path.
   e. Verify compacted status.md has all required sections (Goal, Status, Current State). Then delete status.pre-compact.md.
3. Update `**Status:** completed` in the task's status.md.
4. Update `**Active Task:** none` in meta.md.
5. List remaining tasks: "Task '<name>' completed. Remaining tasks: <list>. Switch to one, or create a new task?"
