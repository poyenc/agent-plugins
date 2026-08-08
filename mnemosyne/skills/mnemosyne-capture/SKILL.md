---
name: mnemosyne-capture
description: >
  Capture a verified finding, procedure, or decision into mnemosyne with full detail.
  Invoke this skill proactively — without being asked — whenever ANY of these moments occur:
  (1) A multi-step procedure is established, corrected, or fully confirmed for the first time
      (how to build, run, deploy, test, profile, submit, or any repeatable workflow).
  (2) A decision is made with a clear rationale that should survive this session.
  (3) A non-obvious constraint, gotcha, or dead end is confirmed.
  (4) A measured result is obtained (benchmark number, profiling outcome, comparison).
  (5) The goal or direction of the current branch becomes clear.
  Do NOT invoke for hypotheses, plans, or things not yet verified. Do NOT invoke if the
  finding was already stored this session (recall first to check). The skill exists to ensure
  captured knowledge is comprehensive and well-structured, not just a one-liner.
---

# /mnemosyne-capture

Capture a verified finding into mnemosyne with the completeness of a reference document.

## Steps

1. **Identify what to capture** — from context: what was just verified, established, or decided?

2. **Recall first** — `mnemosyne_recall(query="[project] <topic>")` to check if a memory already exists.
   - If yes: is the existing memory complete and current? If so, done. If stale or shallow, update it with `mnemosyne_update` or invalidate and replace.
   - If no: proceed to write.

3. **Write a comprehensive entry** — not a one-liner. Include:
   - For procedures: every step in order, exact commands/flags, what breaks if skipped, non-obvious constraints
   - For decisions: what was decided, why, what alternatives were rejected and why
   - For gotchas/dead ends: what was tried, why it failed, what not to re-pursue
   - For measured results: exact numbers, configuration, date, what they mean
   - Label factual content `[VERIFIED]` or `[OBSERVED]`

4. **Store with correct scope and prefix:**
   - Procedure or project-wide fact: `mnemosyne_remember(content="[project] how to <X>: ...", scope="global", source="fact", importance=0.8)`
   - Branch-specific finding: `mnemosyne_remember(content="[project/branch] ...", scope="global", source="fact", importance=0.7)`
   - Branch goal/status: `mnemosyne_remember_canonical(category="branch-status", name="project/branch", body=...)`
   - Cross-project rule: `mnemosyne_shared_remember(content=..., kind="preference")`

5. **Confirm briefly** — one line: what was stored and at what scope. No need to repeat the full content.
