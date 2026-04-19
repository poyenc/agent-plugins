---
name: branch-abandon
description: >
  Abandon the current branch, salvage useful knowledge to project level, and archive.
  Use when a feature is cancelled, approach scrapped, or branch is no longer needed.
---

# /branch-abandon

Abandon the current branch and salvage knowledge.

## Steps

1. Confirm current branch is not a default branch (main/develop/master). Refuse if it is.
2. Ask: "Why is this branch being abandoned?" Capture the reason.
3. Review all branch-level knowledge and workflow overlays:
   - General insights (architectural patterns, hardware behavior, debugging techniques) → promote to project level
   - Negative results ("don't do X because Y") → promote to project `knowledge/lessons-learned.md`
   - Branch-specific details → archive only
4. Present summary: "This branch discovered: <list>. Promote these to project level?"
5. Apply promotions (append to project-level files, update indexes).
6. Move `branches/<sanitized>/` to `archive/<sanitized>/`.
7. Update `archive/<sanitized>/meta.md` with `**Status:** abandoned` and reason.
8. Report: "Branch abandoned. <N> findings promoted to project level, <M> archived."
