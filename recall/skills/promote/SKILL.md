---
name: promote
description: >
  Promote branch knowledge to project level after a merge. Can be triggered automatically
  (when merged branches are detected) or manually with /promote [branch]. Use when merging
  or when the user asks to promote knowledge.
---

# /promote [branch]

Promote branch knowledge to project level.

## Arguments
- `[branch]`: optional branch name. If omitted, auto-detects merged branches.

## Steps

1. If `[branch]` is provided:
   - Resolve the branch directory (sanitize name, find in branches/).
   - Proceed to step 3.
2. If no argument:
   - Run `${CLAUDE_PLUGIN_ROOT}/scripts/detect-merged.sh` to find merged branches.
   - If none found: "No merged branches with unpromoted knowledge."
   - If multiple found: list them and process each.
3. **For each branch to promote:**
   a. Read all knowledge/ and workflows/ topic files from the branch overlay.
   b. For each finding, classify:
      - **Promote** (general): architectural patterns, hardware behavior, debugging techniques, performance patterns, API insights, conventions
      - **Archive** (branch-specific): branch commit hashes, WIP status, temporary workarounds, task configs, unverified hypotheses
   c. For promotable content:
      - If a matching project-level topic exists → append to it
      - If no matching topic → create new topic file, add to project index.md
   d. Move `branches/<sanitized>/` to `archive/<sanitized>/`
   e. Update archive meta.md with `**Status:** promoted` and date
   f. Report: "Promoted <N> findings from '<branch>' to project level. Branch archived."
