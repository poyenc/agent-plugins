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
   - If `--project`: target is `<project>/knowledge/<topic>.md`
   - If `--branch`: target is `<branch>/knowledge/<topic>.md`
   - If neither: agent assesses — task-specific → task knowledge.md, branch-general → branch overlay, project-general → project level
2. Check confidence:
   - Read confidence-min from directives config
   - Only write [VERIFIED] or [OBSERVED] facts. Reject hypotheses with guidance to use status.md
3. Determine target file:
   - If writing to task knowledge and knowledge/ directory exists: target is knowledge/<topic>.md (create if new, update index.md).
   - If writing to task knowledge and knowledge.md exists (flat): target is knowledge.md, append under matching ## section (create section if new).
   - If writing to branch/project topic: target is knowledge/<topic>.md as before.
4. If topic file exists: read it, append the new finding with evidence citation
4.5. If topic file doesn't exist: create it, add entry to the relevant index.md
5. Briefly explain: "Saved to <scope>/knowledge/<topic>.md — <reason>."
6. **Size check**: After writing, check file line count against maintenance limits (from directives.md).
   - Topic file over topic-max-lines: split ### subsections into sibling topic files, update the parent index.
   - Task knowledge.md over task-knowledge-split-lines: split into knowledge/ directory with per-topic files + index.md. Leave a 2-line redirect at the original knowledge.md path.
