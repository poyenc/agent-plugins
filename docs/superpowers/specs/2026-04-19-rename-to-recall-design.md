# Rename knowledge-management to recall

**Date:** 2026-04-19
**Status:** Proposed

## Summary

Rename the `knowledge-management` plugin to `recall` across the entire surface: plugin directory, skill names, storage paths, environment variables, settings keys, and documentation. No backward compatibility. A migration script handles existing user data and config.

## Decisions

| Decision | Answer |
|----------|--------|
| Plugin directory | `knowledge-management/` -> `recall/` |
| Skill folders | `knowledge-*` -> `recall-*` (6 skills renamed) |
| Prose style | "the recall system" for the system name; "knowledge" when describing content type |
| Storage root default | `~/.local/share/claude/knowledge/` -> `~/.local/share/claude/recall/` |
| Storage subdirs | `knowledge/` subdirs inside data store stay as `knowledge/` (describes content type) |
| Env vars | `KNOWLEDGE_*` -> `RECALL_*` |
| Settings key | `knowledge.root` -> `recall.root` |
| CLAUDE.md section | `## Knowledge Management` -> `## Recall` |
| Backward compat | None |
| Migration | Script that moves data, updates settings.json and CLAUDE.md (not committed) |

## Change Manifest

### A. Directory rename

```
knowledge-management/ -> recall/
```

All 22 files move with their directory.

### B. Skill folder renames (inside `recall/skills/`)

| Old | New |
|-----|-----|
| `knowledge-add/` | `recall-add/` |
| `knowledge-changelog/` | `recall-changelog/` |
| `knowledge-help/` | `recall-help/` |
| `knowledge-init/` | `recall-init/` |
| `knowledge-search/` | `recall-search/` |
| `knowledge-status/` | `recall-status/` |

Unchanged: `branch-abandon`, `branch-status`, `promote`, `session-bootstrap`, `task-abandon`, `task-complete`, `task-create`, `task-switch`.

### C. Plugin metadata text edits

| File (post-move path) | Field | Old | New |
|------------------------|-------|-----|-----|
| `recall/.claude-plugin/plugin.json` | `name` | `"knowledge-management"` | `"recall"` |
| `recall/.claude-plugin/plugin.json` | `description` | `"...knowledge management for Claude Code..."` | `"...recall system for Claude Code..."` |
| `.claude-plugin/marketplace.json` | `name` | `"knowledge-management"` | `"recall"` |
| `.claude-plugin/marketplace.json` | `source` | `"./knowledge-management"` | `"./recall"` |
| `.claude-plugin/marketplace.json` | `description` | `"...knowledge management..."` | `"...recall..."` |
| `README.md` | table row | `knowledge-management` link | `recall` link |
| `README.md` | settings | `"knowledge-management@agent-plugins"` | `"recall@agent-plugins"` |

### D. Script text edits

**`recall/scripts/lib.sh`:**
- Line 2 comment: `knowledge-management plugin` -> `recall plugin`
- `knowledge` settings key -> `recall` in `resolve_storage_root()`
- Default path: `$HOME/.local/share/claude/knowledge` -> `$HOME/.local/share/claude/recall`

**`recall/hooks/scripts/session-start.sh`:**
- `KNOWLEDGE_BRANCH` -> `RECALL_BRANCH`
- `KNOWLEDGE_PROJECT` -> `RECALL_PROJECT`
- `KNOWLEDGE_ROOT` -> `RECALL_ROOT`
- Default path fallback: `claude/knowledge` -> `claude/recall`

### E. SKILL.md text edits (14 files)

**All 6 renamed skill files** (`recall-add`, `recall-changelog`, `recall-help`, `recall-init`, `recall-search`, `recall-status`):
- Frontmatter `name:` field: `knowledge-*` -> `recall-*`
- Heading: `/knowledge-*` -> `/recall-*`
- Any command references in body text

**`session-bootstrap/SKILL.md`:**
- "the knowledge management system" -> "the recall system"
- All `KNOWLEDGE_*` env var references -> `RECALL_*`
- All `/knowledge-*` command references -> `/recall-*`
- "skip knowledge management for this session" -> "skip recall for this session"

**`recall-help/SKILL.md`:**
- System title: `Knowledge Management System` -> `Recall System`
- All command names in help text block
- Descriptive text: "The system automatically tracks..." stays (describes behavior, not the name)

**Other skills** (`task-switch`, `task-create`, `task-complete`, `task-abandon`, `branch-abandon`, `branch-status`, `promote`):
- Grep for any `/knowledge-*` command references -> `/recall-*`
- These files do not reference `KNOWLEDGE_*` env vars or the plugin name

### F. Environment variable rename

| Old | New | Set in |
|-----|-----|--------|
| `KNOWLEDGE_BRANCH` | `RECALL_BRANCH` | `hooks/scripts/session-start.sh` |
| `KNOWLEDGE_PROJECT` | `RECALL_PROJECT` | `hooks/scripts/session-start.sh` |
| `KNOWLEDGE_ROOT` | `RECALL_ROOT` | `hooks/scripts/session-start.sh`, `lib.sh` |

Consumer: `session-bootstrap/SKILL.md` reads these from hook output.

### G. Settings key rename

In `~/.claude/settings.json`:
```json
// Old
{ "knowledge": { "root": "~/my-notes" } }
{ "enabledPlugins": { "knowledge-management@agent-plugins": true } }

// New
{ "recall": { "root": "~/my-notes" } }
{ "enabledPlugins": { "recall@agent-plugins": true } }
```

### H. recall/README.md updates

- Heading: `# recall`
- Tagline: use "recall" as the system name, "knowledge" for content type
- Quick Start CLAUDE.md example: `## Recall` section, `/recall-status`
- Command table: all `/knowledge-*` -> `/recall-*`
- Storage path example: `~/.local/share/claude/recall/`
- Settings override example: `"recall": { "root": "~/my-notes" }`
- Tree diagram: storage paths (keep `knowledge/` subdirs as-is)

### I. Migration script

**Location:** `recall/scripts/migrate-to-recall.sh`

**Behavior:**
1. Move `~/.local/share/claude/knowledge/` -> `~/.local/share/claude/recall/` (if source exists and target doesn't)
2. Update `~/.claude/settings.json`:
   - Rename key `"knowledge"` -> `"recall"` (if present)
   - Replace `"knowledge-management@agent-plugins"` -> `"recall@agent-plugins"` in `enabledPlugins`
3. Update `~/.claude/CLAUDE.md`:
   - `## Knowledge Management` -> `## Recall`
   - `/knowledge-status` -> `/recall-status`
   - `~/.local/share/claude/knowledge/` -> `~/.local/share/claude/recall/`
4. Print summary of changes made
5. Does NOT commit (these files are outside the repo)

**Safety:**
- Check target doesn't already exist before moving
- Create backup of settings.json before modifying
- Dry-run mode with `--dry-run` flag
- Idempotent: running twice is safe

## Files NOT changed

- `hooks/hooks.json` — uses `${CLAUDE_PLUGIN_ROOT}`, no literal plugin name
- Scripts `create-branch-dir.sh`, `create-task-dir.sh`, `detect-merged.sh` — use `${CLAUDE_PLUGIN_ROOT}` or relative paths, no literal plugin name
- Storage subdirectories named `knowledge/` inside the data store (these describe content type, not the tool)

## Out of scope

- Renaming the `knowledge/` subdirectories inside the on-disk data store
- Backward compatibility shims
- Version bumping (can be done separately)
