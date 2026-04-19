---
name: knowledge-status
description: >
  Show the current state of the knowledge management system: active branch, current task,
  knowledge topics loaded, stale branches, unpromoted knowledge. Use at session start or
  when the user asks about the current knowledge state.
---

# /knowledge-status

Show the current knowledge management state.

## Steps

1. Resolve storage root and project directory.
2. Get current branch: `git branch --show-current`
3. If on a default branch:
   - Show project-level stats: topic count in knowledge/ and workflows/, directives summary.
   - Run `${CLAUDE_PLUGIN_ROOT}/scripts/detect-merged.sh` to list branches with unpromoted knowledge.
   - Check for stale branches (meta.md with old HEAD dates vs configured threshold).
4. If on a feature branch:
   - Read meta.md for branch info.
   - Show: branch name, parent, mode, active task.
   - Show: branch overlay topic count, task knowledge size.
   - Show: project-level topic count available.
5. Format output as a compact status block:

```
Knowledge Status
  Project:  <name> (<storage-root>/<project>/)
  Branch:   <branch> (parent: <parent>, mode: <mode>)
  Task:     <active-task> (status: <status>)
  Topics:   <N> project + <M> branch overlay
  Workflows: <N> project + <M> branch overlay
  Config:   auto-save: <default>, confidence: <min-level>
  Alerts:   <stale branches, merged branches needing promotion>
```
