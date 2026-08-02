---
name: promote
description: Promote branch knowledge to project level after merge.
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
   - Run `${CLAUDE_PLUGIN_ROOT}/scripts/detect-merged.sh --project-dir <project-dir> --target-branch <default-branch>` to find merged branches.
   - If none found: "No merged branches with unpromoted knowledge."
   - If multiple found: list them and process each.
3. **For each branch to promote:**
   a. Read all topic files from the branch overlay's `topics/`.
   b. For each finding, classify:
      - **Promote** (general): architectural patterns, hardware behavior, debugging techniques, performance patterns, API insights, conventions
      - **Archive** (branch-specific): branch commit hashes, WIP status, temporary workarounds, task configs, unverified hypotheses
   c. For promotable content:
      - If a matching project-level topic exists → integrate so it holds only current truth: replace any fact the branch finding supersedes in place (never journal "used to be X, now Y" — git history holds that); append only genuinely new facts. Preserve deliberately-kept dead-end records.
      - If no matching topic → create new topic file, add to project `topics/index.md`
      - After appending, if the topic file exceeds maintenance.topic-max-lines (from the project's settings.yaml), split ### subsections into sibling topic files and update the project `topics/index.md`.
   d. Move `branches/<sanitized>/` to `archive/<sanitized>/`
   e. Update archive meta.md with `**Status:** promoted` and date
   f. Report: "Promoted <N> findings from '<branch>' to project level. Branch archived."
