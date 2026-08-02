---
name: recall-add
description: Add knowledge entry with scope control (--project/--branch flags).
---

# /recall-add <topic> [--project|--branch]

Add knowledge to a specific topic with explicit scope control.

## Arguments
- `<topic>`: topic name (e.g., "gfx942-latency", "coding-standards")
- `--project`: force saving to project-level knowledge
- `--branch`: force saving to branch-level knowledge
- (default): agent decides scope based on content

## Steps

1. Determine scope:
   - If `--project`: target is `<project>/topics/<topic>.md`
   - If `--branch`: target is `<branch>/topics/<topic>.md`
   - If neither: agent assesses — task-specific → `<task>/topics/<topic>.md`, branch-general → branch overlay, project-general → project level
2. Check confidence:
   - Read `confidence-min` from the target level's `settings.yaml`
   - Only write [VERIFIED] or [OBSERVED] facts. Reject hypotheses with guidance to use status.md
3. If topic file exists: read it, then integrate the finding so the file holds only what is true *now*:
   - If it **supersedes or updates** an existing fact, replace that fact in place — delete the old text, write the new. Never journal the change ("used to be X, now Y", "we updated the method to Y"): recall stores current truth, and git history holds how it got there (the `feedback-delete-stale-not-append-fix` principle).
   - If it is genuinely **new/additive**, append it with evidence citation.
   - Exception: a fact deliberately kept as a dead-end / falsified-lead record ("do not re-pursue", "so it is not re-hunted") is still true and load-bearing — keep it, don't treat it as superseded.
4. If topic file doesn't exist: create it, add entry to the relevant `topics/index.md`
5. Briefly explain: "Saved to <scope>/topics/<topic>.md — <reason>."
6. **Size check**: After writing, check file line count against `maintenance.topic-max-lines` (from the target level's `settings.yaml`).
   - Topic file over the limit: split `###` subsections into sibling topic files, update the parent index.
