---
name: recall-add
description: >
  Add a knowledge entry with explicit scope control. Use when the user asks to save,
  document, or record a finding, or when the agent needs to override automatic scope decisions.
  Supports --project and --branch flags to force scope.
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
3. If topic file exists: read it, append the new finding with evidence citation
4. If topic file doesn't exist: create it, add entry to the relevant index.md
5. Briefly explain: "Saved to <scope>/knowledge/<topic>.md — <reason>."
