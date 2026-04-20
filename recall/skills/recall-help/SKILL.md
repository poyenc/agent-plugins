---
name: recall-help
description: >
  List all recall commands with descriptions and explain how the system works.
  Use when the user asks for help, is new to the system, or asks about available commands.
---

# /recall-help

Explain the recall system and list available commands.

## Response

Print this help text:

```
Recall System
==============

The system automatically tracks verified findings across branches and tasks.
Knowledge is organized in layers: project > branch > task.
Each layer only contains what's NEW at that level — no duplication.

Available commands:

  Setup & Info
    /recall-init          Set up knowledge tracking for this project
    /recall-status        Show current branch, task, and knowledge state
    /recall-help          This help text

  Knowledge
    /recall-add <topic>   Save a finding (--project or --branch to set scope)
    /recall-search <q>    Search across all knowledge including archives
    /recall-changelog     Show recent knowledge changes

  Branches
    /branch-status           Overview of all branches and their knowledge
    /branch-abandon          Abandon current branch, salvage useful knowledge
    /promote [branch]        Promote branch knowledge to project level

  Tasks
    /task-create <name>      Create a new task under current branch
    /task-switch <name>      Switch to a different task
    /task-complete           Mark current task done, review knowledge
    /task-abandon            Abandon current task, capture what was learned

The system runs automatically — it detects new branches, saves findings
based on your auto-save rules, and promotes knowledge when branches merge.
Configure with: "set auto-save rules to ..." or "set stale threshold to ..."
```
