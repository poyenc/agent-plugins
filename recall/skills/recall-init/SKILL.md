---
name: recall-init
description: One-time project setup — creates directories, config, and initial files.
---

# /recall-init

Set up the recall system for the current project.

## Steps

1. Resolve the storage root (from settings.json `recall.root` or default `~/.local/share/claude/recall/`).
2. Detect project name from `git remote get-url origin`.
3. Create the project directory: `<storage-root>/<project>/`
4. Create these files:

**settings.yaml** — project config, pure YAML, no prose:
```
auto-save:
  auto: [hardware findings, build errors, debugging root causes, API behaviors]
  ask: [coding conventions, architecture decisions]
  never: [temporary workarounds, debugging session logs]
  default: auto
promotion: auto
stale-branch-days: 30
default-branch: develop
confidence-min: observed
maintenance:
  status-max-lines: 150
  status-final-lines: 100
  topic-max-lines: 200
```
Ask the user for environment values and add them as additional top-level keys (only fields they provide — omit the rest):
```
WORKSPACE: <ask user>
CONTAINER: <ask user or omit>
```

**topics/index.md** — empty file (topics added as discovered; no separate workflows index — a workflow-type finding is just another topic in the same file, grouped by whichever thematic `## ` header fits)

5. If not on a default branch, assess branch type from name pattern (lightweight: hotfix/*, fix/*, typo/*, docs/*; full: everything else), then create the branch directory:
   ```
   ${CLAUDE_PLUGIN_ROOT}/scripts/create-branch-dir.sh --project-dir <project-dir> --branch <branch-name> --parent <parent-branch> --mode <full|lightweight>
   ```
   For full branches, ask "What's the epic/goal for this branch?"
6. Report: "Knowledge base initialized at <path>. I'll automatically track verified findings across branches and promote them when you merge. Run /recall-help for commands."

### Size Maintenance

When writing to status.md or topic files, check line counts against maintenance limits from settings.yaml:
- **status.md over status-max-lines**: Insert `<!-- maintenance: compact needed -->` at line 1. Do not compact now.
- **Topic file over topic-max-lines**: Split `###` subsections into sibling files, update index.

Hard compaction (rewriting status.md to compact format) happens only at lifecycle events (`/task-complete`, `/task-abandon`) or when session-start detects an oversized file or the compact-needed marker.

### Quality Maintenance

Every knowledge file read is also a quality check. Fix in-place (Tier 1): factual errors, stale references, duplicates, vague claims — only when you have the precise replacement in current context. Maximum 2 quality edits per file read. Never modify benchmark tables, commit hashes, code snippets, or quoted output. Flag cross-file issues as `<!-- quality-review: ... -->` comments (Tier 2) for later resolution.
