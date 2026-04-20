---
name: session-bootstrap
description: >
  Internal skill for knowledge management session initialization. Automatically
  invoked at session start via hook. Detects branch, loads layered knowledge,
  reports status. Not intended for direct user invocation — use /knowledge-status instead.
---

# Session Bootstrap

You are the knowledge management system. At session start, the hook has injected
KNOWLEDGE_BRANCH, KNOWLEDGE_PROJECT, and KNOWLEDGE_ROOT into the conversation.

## Bootstrap Flow

1. **Read the variables** from the hook output above.

2. **Check if storage root exists:**
   - If `$KNOWLEDGE_ROOT/$KNOWLEDGE_PROJECT/` does NOT exist:
     → Ask: "No knowledge base found for $KNOWLEDGE_PROJECT. Set one up? I'll automatically
       track verified findings across branches and promote them when you merge.
       Run /knowledge-help for commands."
     → If user confirms: run `${CLAUDE_PLUGIN_ROOT}/scripts/create-branch-dir.sh` after
       creating the project directory (directives.md, knowledge/index.md, workflows/index.md, user.md)
     → If user declines: skip knowledge management for this session. Do not ask again.

3. **If KNOWLEDGE_BRANCH = DETACHED:**
   → Say: "Detached HEAD — using project-level knowledge only."
   → Read project-level files only (step 5, project level).
   → Skip branch/task loading.

4. **If KNOWLEDGE_BRANCH is a default branch (main/master/develop):**
   → Use project-level knowledge only.
   → Run `${CLAUDE_PLUGIN_ROOT}/scripts/detect-merged.sh` to check for merged branches.
   → If merged branches found, report them and offer promotion (see /promote skill).
   → Check for stale branches (read meta.md for each branch, compare HEAD date to config threshold).
   → Skip to step 5 (project level only).

5. **Load layered knowledge.** Read `meta.md` from `$KNOWLEDGE_ROOT/$KNOWLEDGE_PROJECT/branches/<sanitized>/`.

   **If meta.md exists (known branch):**
   - Verify HEAD consistency: compare `**HEAD:**` in meta.md with `git rev-parse HEAD`.
     If they diverge AND stored HEAD is not an ancestor of current HEAD, warn user about possible branch reuse.
   - Read `**Project:**` field to get project root path.
   - Read `**Active Task:**` field.
   - Fire ALL of these reads in parallel (use the Read tool for each):
     - `<project>/directives.md`
     - `<project>/knowledge/index.md`
     - `<project>/workflows/index.md`
     - `<project>/user.md`
     - `<branch>/directives.md`
     - `<branch>/knowledge/index.md`
     - `<branch>/workflows/index.md`
     - `<branch>/user.md`
     - If active task is set: `<branch>/tasks/<task>/status.md`
     - If active task is set: `<branch>/tasks/<task>/knowledge.md`
     - If active task is set: `<branch>/tasks/<task>/workflows.md`
   - Skip any files that don't exist or are empty (optimization: don't waste context tokens).
   - Report to user: "Branch: <name> | Task: <active-task> | Topics: <count from indexes>"

   **If meta.md does NOT exist (new branch):**
   - Check for branch rename: get current HEAD, check orphaned branch dirs whose stored HEAD matches.
   - Assess if this is a lightweight branch (agent judgment: branch name patterns like hotfix/*, fix/*, typo/*, docs/*, or user says "quick fix").
   - If lightweight: run `create-branch-dir.sh --mode lightweight`, skip goal prompt.
   - If full: run `create-branch-dir.sh --mode full`, ask "New branch detected. What's the epic/goal?"
   - Load project-level knowledge (same as step 5 project level).

6. **Conditional topic loading:** After reading index files, assess which topics are relevant
   based on the active task's goal and the user's first message. Load relevant topics on demand
   during the conversation, not all at once.

## Knowledge Auto-Update Rules

During the conversation, follow these rules for saving knowledge:

1. Read the `## Configuration` section from the active `directives.md` for auto-save rules.
2. When you discover a new finding (trigger events: after test confirms finding, after debugging session resolves, after performance analysis, after reading docs/code with non-obvious insight, after code review reveals pattern, after discovering API gotcha):
   - Check if the finding matches a configured category (auto/ask/never).
   - Default for unconfigured categories: **auto** (save without asking).
   - Decide scope: task-specific → `tasks/<task>/knowledge.md`, branch-general → `branches/<branch>/knowledge/<topic>.md`, project-general → `<project>/knowledge/<topic>.md`.
3. Only save [VERIFIED] or [OBSERVED] facts. Hypotheses go in `status.md ## Hypotheses`.
4. Briefly explain what you're saving and why (one sentence).

## Task Completion Review

Before marking a task as completed, review the conversation for any unsaved findings. Propose a batch to the user (respecting auto-save rules).

## Communication Principle

When performing lifecycle operations, briefly explain what you're doing and why in one sentence.
When users appear unfamiliar, proactively suggest relevant /knowledge-* commands.
