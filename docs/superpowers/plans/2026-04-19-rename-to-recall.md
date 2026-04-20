# Rename knowledge-management to recall — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the knowledge-management plugin to recall across directory, skills, scripts, storage paths, env vars, settings, docs, and provide a migration script.

**Architecture:** Pure rename — no logic changes. Directory and skill folder renames via `git mv`, followed by text replacements in 20 files. A migration script handles user-local files (~/.claude/settings.json, ~/.claude/CLAUDE.md, ~/.local/share/claude/knowledge/).

**Tech Stack:** Bash (git mv, sed), Markdown editing

**Spec:** `docs/superpowers/specs/2026-04-19-rename-to-recall-design.md`

---

### Task 1: Rename top-level plugin directory

**Files:**
- Rename: `knowledge-management/` -> `recall/`

- [ ] **Step 1: Rename the directory**

```bash
cd /home/poyechen/workspace/repo/agent-plugins
git mv knowledge-management recall
```

- [ ] **Step 2: Verify the rename**

```bash
ls recall/.claude-plugin/plugin.json recall/scripts/lib.sh recall/hooks/hooks.json recall/skills/session-bootstrap/SKILL.md
```

Expected: all four files exist, no errors.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "Rename knowledge-management directory to recall"
```

---

### Task 2: Rename skill folders from knowledge-* to recall-*

**Files:**
- Rename: `recall/skills/knowledge-add/` -> `recall/skills/recall-add/`
- Rename: `recall/skills/knowledge-changelog/` -> `recall/skills/recall-changelog/`
- Rename: `recall/skills/knowledge-help/` -> `recall/skills/recall-help/`
- Rename: `recall/skills/knowledge-init/` -> `recall/skills/recall-init/`
- Rename: `recall/skills/knowledge-search/` -> `recall/skills/recall-search/`
- Rename: `recall/skills/knowledge-status/` -> `recall/skills/recall-status/`

- [ ] **Step 1: Rename all six skill directories**

```bash
cd /home/poyechen/workspace/repo/agent-plugins
git mv recall/skills/knowledge-add recall/skills/recall-add
git mv recall/skills/knowledge-changelog recall/skills/recall-changelog
git mv recall/skills/knowledge-help recall/skills/recall-help
git mv recall/skills/knowledge-init recall/skills/recall-init
git mv recall/skills/knowledge-search recall/skills/recall-search
git mv recall/skills/knowledge-status recall/skills/recall-status
```

- [ ] **Step 2: Verify**

```bash
ls recall/skills/ | sort
```

Expected directories: `branch-abandon`, `branch-status`, `promote`, `recall-add`, `recall-changelog`, `recall-help`, `recall-init`, `recall-search`, `recall-status`, `session-bootstrap`, `task-abandon`, `task-complete`, `task-create`, `task-switch`

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "Rename knowledge-* skill folders to recall-*"
```

---

### Task 3: Update plugin metadata files

**Files:**
- Modify: `recall/.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`

- [ ] **Step 1: Update plugin.json**

Change `recall/.claude-plugin/plugin.json` to:

```json
{
  "name": "recall",
  "description": "Automatic branch-aware recall system for Claude Code. Tracks project knowledge across branches and tasks with layered overlays, conditional topic loading, and merge promotion.",
  "version": "0.1.0",
  "author": {
    "name": "PoYen, Chen"
  },
  "keywords": ["recall", "knowledge", "memory", "branches", "tasks", "overlay", "promotion"]
}
```

Changes:
- `name`: `"knowledge-management"` -> `"recall"`
- `description`: `"knowledge management for Claude Code"` -> `"recall system for Claude Code"`
- `keywords`: added `"recall"`, kept `"knowledge"`

- [ ] **Step 2: Update marketplace.json**

In `.claude-plugin/marketplace.json`, change the plugin entry:

```json
{
  "name": "recall",
  "source": "./recall",
  "description": "Automatic branch-aware recall system with layered overlays, conditional topic loading, and merge promotion."
}
```

Changes:
- `name`: `"knowledge-management"` -> `"recall"`
- `source`: `"./knowledge-management"` -> `"./recall"`
- `description`: `"knowledge management"` -> `"recall system"`

- [ ] **Step 3: Commit**

```bash
git add recall/.claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "Update plugin.json and marketplace.json for recall rename"
```

---

### Task 4: Update repo-level README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the plugin table row**

Change line 9 from:
```
| **[knowledge-management](knowledge-management/README.md)** | Automatic branch-aware knowledge management. Tracks project knowledge across branches and tasks with layered overlays, conditional topic loading, auto-save rules, and merge promotion. |
```
to:
```
| **[recall](recall/README.md)** | Automatic branch-aware recall system. Tracks project knowledge across branches and tasks with layered overlays, conditional topic loading, auto-save rules, and merge promotion. |
```

- [ ] **Step 2: Update the settings example**

Change line 26 from:
```
    "knowledge-management@agent-plugins": true
```
to:
```
    "recall@agent-plugins": true
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Update README.md for recall rename"
```

---

### Task 5: Update scripts (lib.sh and session-start.sh)

**Files:**
- Modify: `recall/scripts/lib.sh`
- Modify: `recall/hooks/scripts/session-start.sh`

- [ ] **Step 1: Update lib.sh**

Three changes in `recall/scripts/lib.sh`:

1. Line 2 comment: `knowledge-management plugin` -> `recall plugin`
2. In `resolve_storage_root()`, the Python snippet reading settings — change `'knowledge'` to `'recall'`:
   ```python
   r = d.get('recall', {}).get('root', '')
   ```
3. Default path at end of function: `$HOME/.local/share/claude/knowledge` -> `$HOME/.local/share/claude/recall`

- [ ] **Step 2: Update session-start.sh**

Four changes in `recall/hooks/scripts/session-start.sh`:

1. Default path fallback: `$HOME/.local/share/claude/knowledge` -> `$HOME/.local/share/claude/recall`
2. `KNOWLEDGE_BRANCH` -> `RECALL_BRANCH`
3. `KNOWLEDGE_PROJECT` -> `RECALL_PROJECT`
4. `KNOWLEDGE_ROOT` -> `RECALL_ROOT`

Full updated file:

```bash
#!/usr/bin/env bash
# hooks/scripts/session-start.sh — Minimal hook: output branch name and storage root

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/../../scripts/lib.sh"

if [ -f "$LIB" ]; then
    source "$LIB"
    ROOT="$(resolve_storage_root)"
else
    ROOT="${RECALL_ROOT:-$HOME/.local/share/claude/recall}"
fi

BRANCH="$(git branch --show-current 2>/dev/null || echo "DETACHED")"
PROJECT="$(basename "$(git remote get-url origin 2>/dev/null | sed 's|.git$||; s|/$||')" 2>/dev/null || echo "unknown")"

echo "RECALL_BRANCH=$BRANCH"
echo "RECALL_PROJECT=$PROJECT"
echo "RECALL_ROOT=$ROOT"
```

- [ ] **Step 3: Commit**

```bash
git add recall/scripts/lib.sh recall/hooks/scripts/session-start.sh
git commit -m "Update scripts for recall rename: env vars, storage paths, settings key"
```

---

### Task 6: Update the 6 renamed SKILL.md files

**Files:**
- Modify: `recall/skills/recall-add/SKILL.md`
- Modify: `recall/skills/recall-changelog/SKILL.md`
- Modify: `recall/skills/recall-help/SKILL.md`
- Modify: `recall/skills/recall-init/SKILL.md`
- Modify: `recall/skills/recall-search/SKILL.md`
- Modify: `recall/skills/recall-status/SKILL.md`

For each file, apply these replacements:
- Frontmatter `name:` field: `knowledge-*` -> `recall-*`
- Heading: `/knowledge-*` -> `/recall-*`
- Command references in body text: `/knowledge-*` -> `/recall-*`
- System name references: `"knowledge management system"` -> `"recall system"` (where it names the system, not the content type)
- Settings key: `knowledge.root` -> `recall.root`
- Storage path: `~/.local/share/claude/knowledge/` -> `~/.local/share/claude/recall/`

- [ ] **Step 1: Update recall-add/SKILL.md**

```yaml
---
name: recall-add
description: >
  Add a knowledge entry with explicit scope control. Use when the user asks to save,
  document, or record a finding, or when the agent needs to override automatic scope decisions.
  Supports --project and --branch flags to force scope.
---
```

Heading: `# /recall-add <topic> [--project|--branch]`

Body: no other `/knowledge-*` references.

- [ ] **Step 2: Update recall-changelog/SKILL.md**

```yaml
---
name: recall-changelog
description: >
  Show recent changes across all knowledge files. Use when the user asks what's changed,
  "what did we learn recently", or wants a summary of recent findings.
---
```

Heading: `# /recall-changelog [days]`

- [ ] **Step 3: Update recall-search/SKILL.md**

```yaml
---
name: recall-search
description: >
  Search across all knowledge files including archives. Use when the user asks to find
  past findings, search knowledge, or look up information across branches.
---
```

Heading: `# /recall-search <query>`

- [ ] **Step 4: Update recall-status/SKILL.md**

```yaml
---
name: recall-status
description: >
  Show the current state of the recall system: active branch, current task,
  knowledge topics loaded, stale branches, unpromoted knowledge. Use at session start or
  when the user asks about the current knowledge state.
---
```

Heading: `# /recall-status`

Body line 11: `Show the current recall state.`

Status block title: `Recall Status` (was `Knowledge Status`)

- [ ] **Step 5: Update recall-init/SKILL.md**

```yaml
---
name: recall-init
description: >
  One-time project setup for the recall system. Creates the directory
  structure, default configuration, and initial files. Use when setting up a new project
  or when the user asks to initialize knowledge tracking.
---
```

Heading: `# /recall-init`

Body line 11: `Set up the recall system for the current project.`

Line 15: `settings.json \`recall.root\`` and `~/.local/share/claude/recall/`

Line 38: `Run /recall-help for commands.`

- [ ] **Step 6: Update recall-help/SKILL.md**

This file has the most changes — the full help text block:

```yaml
---
name: recall-help
description: >
  List all recall commands with descriptions and explain how the system works.
  Use when the user asks for help, is new to the system, or asks about available commands.
---
```

Heading: `# /recall-help`

Body line 10: `Explain the recall system and list available commands.`

Full help text block:

```
Recall System
==============

The system automatically tracks verified findings across branches and tasks.
Knowledge is organized in layers: project > branch > task.
Each layer only contains what's NEW at that level — no duplication.

Available commands:

  Setup & Info
    /recall-init             Set up knowledge tracking for this project
    /recall-status           Show current branch, task, and knowledge state
    /recall-help             This help text

  Knowledge
    /recall-add <topic>      Save a finding (--project or --branch to set scope)
    /recall-search <q>       Search across all knowledge including archives
    /recall-changelog        Show recent knowledge changes

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

- [ ] **Step 7: Commit**

```bash
git add recall/skills/recall-add/SKILL.md recall/skills/recall-changelog/SKILL.md recall/skills/recall-help/SKILL.md recall/skills/recall-init/SKILL.md recall/skills/recall-search/SKILL.md recall/skills/recall-status/SKILL.md
git commit -m "Update 6 renamed SKILL.md files: frontmatter, headings, command refs"
```

---

### Task 7: Update session-bootstrap/SKILL.md

**Files:**
- Modify: `recall/skills/session-bootstrap/SKILL.md`

This is the largest single-file change. All env var references (`KNOWLEDGE_*` -> `RECALL_*`), all command references (`/knowledge-*` -> `/recall-*`), and system name references.

- [ ] **Step 1: Update frontmatter**

```yaml
---
name: session-bootstrap
description: >
  Internal skill for recall session initialization. Automatically
  invoked at session start via hook. Detects branch, loads layered knowledge,
  reports status. Not intended for direct user invocation — use /recall-status instead.
---
```

- [ ] **Step 2: Update the body text**

Apply these replacements throughout the file:

| Old | New |
|-----|-----|
| `the knowledge management system` | `the recall system` |
| `KNOWLEDGE_BRANCH` | `RECALL_BRANCH` |
| `KNOWLEDGE_PROJECT` | `RECALL_PROJECT` |
| `KNOWLEDGE_ROOT` | `RECALL_ROOT` |
| `$KNOWLEDGE_ROOT` | `$RECALL_ROOT` |
| `/knowledge-help` | `/recall-help` |
| `/knowledge-*` | `/recall-*` |
| `skip knowledge management for this session` | `skip recall for this session` |

Specific lines to change (by content, not number — line numbers may shift from prior tasks):

1. `You are the knowledge management system.` -> `You are the recall system.`
2. `KNOWLEDGE_BRANCH, KNOWLEDGE_PROJECT, and KNOWLEDGE_ROOT` -> `RECALL_BRANCH, RECALL_PROJECT, and RECALL_ROOT`
3. `$KNOWLEDGE_ROOT/$KNOWLEDGE_PROJECT/` (3 occurrences) -> `$RECALL_ROOT/$RECALL_PROJECT/`
4. `Run /knowledge-help for commands.` -> `Run /recall-help for commands.`
5. `skip knowledge management for this session` -> `skip recall for this session`
6. `If KNOWLEDGE_BRANCH = DETACHED:` -> `If RECALL_BRANCH = DETACHED:`
7. `If KNOWLEDGE_BRANCH is a default branch` -> `If RECALL_BRANCH is a default branch`
8. `proactively suggest relevant /knowledge-* commands.` -> `proactively suggest relevant /recall-* commands.`

- [ ] **Step 3: Commit**

```bash
git add recall/skills/session-bootstrap/SKILL.md
git commit -m "Update session-bootstrap SKILL.md: env vars, commands, system name"
```

---

### Task 8: Update recall/README.md

**Files:**
- Modify: `recall/README.md`

- [ ] **Step 1: Update heading and tagline**

Line 1: `# recall`

Line 3: `Automatic branch-aware recall system for Claude Code. Tracks what you learn across branches and tasks so future sessions start with context instead of from scratch.`

- [ ] **Step 2: Update Quick Start CLAUDE.md example**

Change the example CLAUDE.md snippet:

```markdown
## Recall
Use /recall-status at session start. Knowledge is stored at ~/.local/share/claude/recall/.
```

- [ ] **Step 3: Update settings example**

```json
"enabledPlugins": {
    "recall@agent-plugins": true
}
```

- [ ] **Step 4: Update command table**

Replace all `/knowledge-*` commands with `/recall-*`:

| Command | Description |
|---------|-------------|
| `/recall-init` | One-time project setup |
| `/recall-status` | Show current branch, task, and knowledge state |
| `/recall-help` | List all commands and explain the system |
| `/recall-add <topic>` | Save a finding (use `--project` or `--branch` to set scope) |
| `/recall-search <query>` | Search across all knowledge including archives |
| `/recall-changelog` | Show recent knowledge changes |
| `/branch-status` | Overview of all branches and their knowledge |
| `/branch-abandon` | Abandon current branch, salvage useful knowledge |
| `/promote [branch]` | Promote branch knowledge to project level |
| `/task-create <name>` | Create a new task under current branch |
| `/task-switch <name>` | Switch to a different task (fuzzy matching) |
| `/task-complete` | Mark task done, review knowledge for promotion |
| `/task-abandon` | Abandon task, capture what was learned |

- [ ] **Step 5: Update storage path references**

Change all occurrences of:
- `~/.local/share/claude/knowledge/` -> `~/.local/share/claude/recall/`
- `"knowledge": { "root":` -> `"recall": { "root":`

The tree diagram keeps `knowledge/` subdirectories as-is (they describe content type).

- [ ] **Step 6: Update natural language references**

Where the README says "knowledge management" as a system name, change to "recall":
- `knowledge management` (as the name of this plugin/system) -> `recall`
- Keep "knowledge" when describing content (e.g. "tracks knowledge", "salvage useful knowledge")

- [ ] **Step 7: Commit**

```bash
git add recall/README.md
git commit -m "Update recall README: commands, paths, settings, branding"
```

---

### Task 9: Write the migration script

**Files:**
- Create: `recall/scripts/migrate-to-recall.sh`

- [ ] **Step 1: Write the migration script**

Create `recall/scripts/migrate-to-recall.sh`:

```bash
#!/usr/bin/env bash
# migrate-to-recall.sh — Migrate from knowledge-management to recall
# Updates: storage directory, settings.json, CLAUDE.md
# Does NOT commit changes (files are outside the repo)
set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "[DRY RUN] No changes will be made."
    echo
fi

CHANGES=0

# --- 1. Move storage directory ---
OLD_STORE="$HOME/.local/share/claude/knowledge"
NEW_STORE="$HOME/.local/share/claude/recall"

if [ -d "$OLD_STORE" ] && [ ! -d "$NEW_STORE" ]; then
    echo "Moving storage: $OLD_STORE -> $NEW_STORE"
    if [ "$DRY_RUN" = false ]; then
        mv "$OLD_STORE" "$NEW_STORE"
    fi
    CHANGES=$((CHANGES + 1))
elif [ -d "$OLD_STORE" ] && [ -d "$NEW_STORE" ]; then
    echo "WARNING: Both $OLD_STORE and $NEW_STORE exist. Skipping move — resolve manually."
elif [ ! -d "$OLD_STORE" ]; then
    echo "No old storage directory found at $OLD_STORE — skipping."
fi

# --- 2. Update ~/.claude/settings.json ---
SETTINGS="$HOME/.claude/settings.json"

if [ -f "$SETTINGS" ]; then
    if grep -q '"knowledge-management@agent-plugins"' "$SETTINGS" || grep -q '"knowledge"' "$SETTINGS"; then
        echo "Updating settings: $SETTINGS"
        if [ "$DRY_RUN" = false ]; then
            cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
            python3 -c "
import json, sys

with open(sys.argv[1], 'r') as f:
    data = json.load(f)

# Rename enabledPlugins key
ep = data.get('enabledPlugins', {})
if 'knowledge-management@agent-plugins' in ep:
    ep['recall@agent-plugins'] = ep.pop('knowledge-management@agent-plugins')

# Rename settings key
if 'knowledge' in data:
    data['recall'] = data.pop('knowledge')

with open(sys.argv[1], 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" "$SETTINGS"
        fi
        CHANGES=$((CHANGES + 1))
    else
        echo "No knowledge-management references in $SETTINGS — skipping."
    fi
else
    echo "No settings file found at $SETTINGS — skipping."
fi

# --- 3. Update ~/.claude/CLAUDE.md ---
CLAUDEMD="$HOME/.claude/CLAUDE.md"

if [ -f "$CLAUDEMD" ]; then
    if grep -q 'Knowledge Management\|/knowledge-status\|claude/knowledge/' "$CLAUDEMD"; then
        echo "Updating CLAUDE.md: $CLAUDEMD"
        if [ "$DRY_RUN" = false ]; then
            cp "$CLAUDEMD" "$CLAUDEMD.bak.$(date +%Y%m%d%H%M%S)"
            sed -i \
                -e 's/## Knowledge Management/## Recall/' \
                -e 's|/knowledge-status|/recall-status|g' \
                -e 's|claude/knowledge/|claude/recall/|g' \
                "$CLAUDEMD"
        fi
        CHANGES=$((CHANGES + 1))
    else
        echo "No knowledge-management references in $CLAUDEMD — skipping."
    fi
else
    echo "No CLAUDE.md found at $CLAUDEMD — skipping."
fi

# --- Summary ---
echo
if [ "$DRY_RUN" = true ]; then
    echo "[DRY RUN] Would have made $CHANGES change(s)."
else
    echo "Done. Made $CHANGES change(s)."
    echo "Backup files created with .bak.* suffix where applicable."
fi
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x recall/scripts/migrate-to-recall.sh
```

- [ ] **Step 3: Verify dry-run mode works**

```bash
recall/scripts/migrate-to-recall.sh --dry-run
```

Expected: prints what it would do, makes no changes.

- [ ] **Step 4: Commit**

```bash
git add recall/scripts/migrate-to-recall.sh
git commit -m "Add migration script for knowledge-management to recall rename"
```

---

### Task 10: Run migration on local machine

This task is NOT committed to the repo. It updates user-local files.

- [ ] **Step 1: Run the migration script for real**

```bash
/home/poyechen/workspace/repo/agent-plugins/recall/scripts/migrate-to-recall.sh
```

Expected output:
```
Moving storage: /home/poyechen/.local/share/claude/knowledge -> /home/poyechen/.local/share/claude/recall
Updating settings: /home/poyechen/.claude/settings.json
Updating CLAUDE.md: /home/poyechen/.claude/CLAUDE.md

Done. Made 3 change(s).
Backup files created with .bak.* suffix where applicable.
```

- [ ] **Step 2: Verify settings.json**

```bash
grep -E 'recall|knowledge' ~/.claude/settings.json
```

Expected: `"recall@agent-plugins": true` — no "knowledge" references remain.

- [ ] **Step 3: Verify CLAUDE.md**

```bash
head -4 ~/.claude/CLAUDE.md
```

Expected:
```
# ~/.claude/CLAUDE.md

## Recall
Use /recall-status at session start. Knowledge is stored at ~/.local/share/claude/recall/.
```

- [ ] **Step 4: Verify storage directory**

```bash
ls ~/.local/share/claude/recall/
```

Expected: project directories that were previously under `knowledge/`.

---

### Task 11: Final verification

- [ ] **Step 1: Grep for leftover "knowledge-management" in repo**

```bash
cd /home/poyechen/workspace/repo/agent-plugins
grep -r "knowledge-management" --include="*.md" --include="*.json" --include="*.sh" . | grep -v docs/superpowers/
```

Expected: zero results (excluding the spec/plan docs).

- [ ] **Step 2: Grep for leftover "KNOWLEDGE_" env vars in repo**

```bash
grep -r "KNOWLEDGE_" --include="*.md" --include="*.sh" . | grep -v docs/superpowers/
```

Expected: zero results.

- [ ] **Step 3: Grep for old storage path in repo**

```bash
grep -r "claude/knowledge" --include="*.md" --include="*.sh" --include="*.json" . | grep -v docs/superpowers/
```

Expected: zero results.

- [ ] **Step 4: Grep for old settings key in repo**

```bash
grep -r '"knowledge"' --include="*.md" --include="*.sh" --include="*.json" . | grep -v docs/superpowers/
```

Expected: zero results (or only content-type references like `knowledge/index.md` which are correct).

- [ ] **Step 5: Verify skill listing**

```bash
ls recall/skills/ | sort
```

Expected: `branch-abandon  branch-status  promote  recall-add  recall-changelog  recall-help  recall-init  recall-search  recall-status  session-bootstrap  task-abandon  task-complete  task-create  task-switch`

- [ ] **Step 6: Commit verification results (optional)**

No commit needed — this is a verification task.
