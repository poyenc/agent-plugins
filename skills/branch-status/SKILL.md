---
name: branch-status
description: >
  Show an overview of all tracked branches: active, stale, merged, archived.
  Use when the user asks about branch state, "what branches exist", or "show branches".
---

# /branch-status

Show an overview of all tracked branches.

## Steps

1. Resolve project directory.
2. List all directories under `<project>/branches/`.
3. For each branch directory, read meta.md and extract: branch name, status, mode, active task, HEAD, created date.
4. Check git for each branch:
   - Does the branch still exist locally? (`git branch --list <name>`)
   - Is it merged into the default branch? (use `${CLAUDE_PLUGIN_ROOT}/scripts/detect-merged.sh`)
   - Last commit date? (`git log -1 --format='%ci' <name>`)
5. Classify each branch: active, stale (no commits in N days per config), merged (unpromoted), archived.
6. List archived branches from `<project>/archive/` (count only).
7. Format as compact overview with categories.
