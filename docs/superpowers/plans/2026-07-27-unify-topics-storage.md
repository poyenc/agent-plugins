# Unify recall storage into topics/ + settings.yaml — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collapse recall's per-level `knowledge/` + `workflows/` + `directives.md` + `user.md` into one uniform `topics/` directory plus one reserved `settings.yaml`, fix `session-start.sh` to inline index content instead of file paths, and migrate the real on-disk store to the new layout.

**Architecture:** Every plugin script/skill that hardcodes the old layout is updated to the new one. `topics/` replaces `knowledge/` + `workflows/` at every level (project/branch/task) with no type-based subdivision — one flat directory of topic files plus one `index.md`, grouped only by thematic `## ` headers. `settings.yaml` is the sole reserved, script-parsed file per level (project + branch), holding what used to be `directives.md`'s YAML block plus `user.md`'s key=values. `meta.md` is untouched. Task level drops its flat-file (`knowledge.md`) stage entirely — tasks now get `topics/index.md` from creation, same shape as project/branch. A one-time migration script converts the real store at `~/.local/share/claude/recall/`.

**Tech Stack:** Bash (existing hook/script style — `set -euo pipefail`, no external deps beyond `python3`/`git`), Markdown (SKILL.md files), YAML (settings.yaml, hand-written — no yq/python-yaml dependency needed since scripts only ever append/grep simple `key: value` lines)

**Spec:** `docs/superpowers/specs/2026-07-27-unify-topics-storage-design.md`

## Global Constraints

- No `tags`/keyword frontmatter field, no naming/prefix enforcement, no duplicate detection, no contradiction checking, no `UserPromptSubmit` hook, no auto-triggered `/recall-reorg` — all explicitly out of scope per the spec.
- `topics/` has no type-based grouping, no required filename prefix, no inline type badge in the index — grouping is thematic `## ` headers only, decided per-project (per spec, "New storage model" section and "Alternatives Considered").
- `settings.yaml` is the only reserved/script-parsed file besides `meta.md` — no other reserved filenames anywhere in `topics/` (per spec, "settings.yaml" section).
- `settings.yaml` is never injected by `session-start.sh` — it is read on-demand by whichever skill needs a value when it runs (per spec, "session-start.sh behavior" section and "Alternatives Considered").
- No line-count truncation on inlined `topics/index.md` content in `session-start.sh` (per spec, "session-start.sh behavior" section).
- Migration script only mechanically converts structure/config; free-form prose from `directives.md`/`user.md` is dumped into a flagged staging file (`topics/_migration-needs-review.md`), never auto-split into named topics (per spec, "Migration" section, step 4).
- `git mv` for renames where the store is under git (matches existing `/recall-reorg` convention); plain `mv` for the real on-disk store at `~/.local/share/claude/recall/` (not a git repo by default).

---

### Task 1: Update `session-start.sh` — inline `topics/index.md`, drop `settings.yaml`/`user.md` injection and the path checklist

**Files:**
- Modify: `recall/hooks/scripts/session-start.sh` (full rewrite; helper functions `emit_file` and `compact_meta` are kept, `strip_user_boilerplate`, `compact_directives`, `collect_read`, and `has_real_content` are deleted since nothing calls them once `settings.yaml`/`user.md` injection and the path checklist are removed)

**Interfaces:**
- Consumes: nothing from other tasks (this is the first task; standalone).
- Produces: the new `session-start.sh` behavior other tasks' manual smoke-tests will exercise — `topics/index.md` inlined per level (project/branch/task), no `settings.yaml`/`user.md`/`directives.md` output, no "Session Start checklist" section.

This task changes `session-start.sh` to match the new storage layout end-to-end. Since the plugin has no automated test harness (verified: no `*.bats`/test runner exists in the repo), verification is done by running the script directly against fixture directories created in the steps below and inspecting stdout.

- [ ] **Step 1: Create a fixture directory tree to test against**

```bash
mkdir -p /tmp/recall-test/testproj/topics
mkdir -p /tmp/recall-test/testproj/branches/feature--foo/topics
mkdir -p /tmp/recall-test/testproj/branches/feature--foo/tasks/mytask/topics

cat > /tmp/recall-test/testproj/topics/index.md << 'EOF'
# testproj — project knowledge

## Working agreements
- [feedback-no-force-push](feedback-no-force-push.md) — never force-push without approval
EOF

cat > /tmp/recall-test/testproj/settings.yaml << 'EOF'
auto-save:
  auto: [hardware findings]
  default: auto
confidence-min: observed
maintenance:
  status-max-lines: 150
  topic-max-lines: 200
WORKSPACE: /home/user/workspace/repo/testproj
EOF

cat > /tmp/recall-test/testproj/branches/feature--foo/meta.md << 'EOF'
**Parent:** `main`
**Created:** 2026-07-01
**Status:** active
**Mode:** full
**Active Task:** mytask
EOF

cat > /tmp/recall-test/testproj/branches/feature--foo/topics/index.md << 'EOF'
## Branch findings
- [wip-note](wip-note.md) — branch-specific WIP status
EOF

cat > /tmp/recall-test/testproj/branches/feature--foo/tasks/mytask/status.md << 'EOF'
**Status:** active
**Created:** 2026-07-01

## Goal
Fix the foo bug
EOF

cat > /tmp/recall-test/testproj/branches/feature--foo/tasks/mytask/topics/index.md << 'EOF'
- [root-cause](root-cause.md) — the foo bug is caused by X
EOF
```

- [ ] **Step 2: Read the current file, then overwrite it with the full new content**

Read `recall/hooks/scripts/session-start.sh` first (required before Write). Then overwrite the entire file (all 337 lines) with the following complete replacement — this keeps the top of the file (root/branch/project resolution, `emit_file` helper) unchanged, drops `strip_user_boilerplate`/`compact_directives`/`collect_read`/`has_real_content` (nothing calls them anymore), keeps `compact_meta` and `emit_task_summary` unchanged, and rewrites everything from "No knowledge base yet" onward:

```bash
#!/usr/bin/env bash
# hooks/scripts/session-start.sh — Inject branch-aware knowledge into session context

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/../../scripts/lib.sh"

if [ -f "$LIB" ]; then
    source "$LIB"
    ROOT="$(resolve_storage_root)"
else
    ROOT="${RECALL_ROOT:-$HOME/.local/share/claude/recall}"
fi

BRANCH="$(git branch --show-current 2>/dev/null || echo "DETACHED")"
if [ -f "$LIB" ]; then
    PROJECT="$(detect_project_name)" || PROJECT="unknown"
else
    PROJECT="$(basename "$(git remote get-url origin 2>/dev/null | sed 's|.git$||; s|/$||')")"
    [ -z "$PROJECT" ] && PROJECT="unknown"
fi
PROJECT_DIR="$ROOT/$PROJECT"

# --- Helpers ---

# Emit a file's content inline with a header, skip if missing/empty
# Optional $3: filter command applied via pipe (e.g. "grep -v '^#'")
emit_file() {
    local filepath="$1" label="$2" filter="${3:-}"
    if [ -f "$filepath" ] && [ -s "$filepath" ]; then
        echo "=== $label ==="
        if [ -n "$filter" ]; then
            eval "$filter" < "$filepath"
        else
            cat "$filepath"
        fi
        echo ""
    fi
}

# Collapse meta.md to a single-line compact format
compact_meta() {
    local parts=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^\*\*(Branch|HEAD|Project):\*\* ]]; then continue; fi
        if [[ "$line" =~ ^\*\*([^:]+):\*\*[[:space:]]*\`?([^\`]*)\`? ]]; then
            local key="${BASH_REMATCH[1]}" val="${BASH_REMATCH[2]}"
            # Lowercase key, remove spaces
            key="$(echo "$key" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')"
            parts+="${key}=${val} "
        fi
    done
    [ -n "$parts" ] && echo "${parts% }"
}

# Emit task as 2 lines: header with status, goal on next line
emit_task_summary() {
    local task_dir="$1" task_name="$2"
    local status_file="$task_dir/status.md"
    [ -f "$status_file" ] || return
    local goal status
    goal="$(sed -n '/^## Goal/,/^##/{/^## Goal/d;/^##/d;/^\s*$/d;p;q}' "$status_file" 2>/dev/null)"
    status="$(grep -oP '^\*\*Status:\*\*\s*\K.+' "$status_file" 2>/dev/null | head -1)"
    local line="Task: $task_name"
    [ -n "$status" ] && line+=" | $status"
    line+=" | details=$status_file"
    echo "$line"
    [ -n "$goal" ] && echo "Goal: $goal"
}

# --- No knowledge base yet — emit minimal context ---
if [ ! -d "$PROJECT_DIR" ]; then
    echo "RECALL_BRANCH=$BRANCH"
    echo "RECALL_PROJECT=$PROJECT"
    echo "RECALL_ROOT=$ROOT"
    echo ""
    echo "No recall knowledge base found for project '$PROJECT'."
    echo "Run /recall-init to set one up, or /recall-help for commands."
    exit 0
fi

# --- Emit session variables ---
echo "RECALL_BRANCH=$BRANCH"
echo "RECALL_PROJECT=$PROJECT"
echo "RECALL_ROOT=$ROOT"
echo ""

# --- Project-level topics (inlined in full, not a path checklist) ---
emit_file "$PROJECT_DIR/topics/index.md" "Project Knowledge ($PROJECT)"

# --- Stop here for detached HEAD or default branches ---
if [ "$BRANCH" = "DETACHED" ]; then
    echo "Detached HEAD — project-level knowledge loaded only."
    exit 0
fi

if [ -f "$LIB" ]; then
    IS_DEFAULT="$(is_default_branch "$BRANCH")"
else
    case "$BRANCH" in
        main|master|develop) IS_DEFAULT="yes" ;;
        *) IS_DEFAULT="no" ;;
    esac
fi

if [ "$IS_DEFAULT" = "yes" ]; then
    echo "Default branch ($BRANCH) — project-level knowledge loaded only."
    echo "Run detect-merged to check for branches ready to promote."
    exit 0
fi

# --- Branch-level topics ---
SANITIZED="$(echo "$BRANCH" | sed 's|/|--|g')"
BRANCH_DIR="$PROJECT_DIR/branches/$SANITIZED"

if [ ! -d "$BRANCH_DIR" ]; then
    echo "New branch '$BRANCH' detected — no branch knowledge yet."
    cat << SETUP

## Branch Setup Required
Assess branch type from name pattern:
- Lightweight (hotfix/*, fix/*, typo/*, docs/*): --mode lightweight
- Full (everything else): --mode full, ask user for epic/goal
Run: ${CLAUDE_PLUGIN_ROOT}/scripts/create-branch-dir.sh --project-dir ${PROJECT_DIR} --branch ${BRANCH} --parent <parent_branch> --mode <mode>
SETUP
    exit 0
fi

emit_file "$BRANCH_DIR/meta.md" "Branch: $BRANCH" "compact_meta"
emit_file "$BRANCH_DIR/topics/index.md" "Branch Knowledge ($BRANCH)"

# --- Active task topics ---
if [ -f "$BRANCH_DIR/meta.md" ]; then
    ACTIVE_TASK=""
    if [ -f "$LIB" ]; then
        ACTIVE_TASK="$(read_meta_field "$BRANCH_DIR/meta.md" "Active Task")"
    else
        ACTIVE_TASK="$(grep -oP '^\*\*Active Task:\*\*\s*`\K[^`]+' "$BRANCH_DIR/meta.md" 2>/dev/null | head -1)"
    fi

    if [ -n "$ACTIVE_TASK" ] && [ "$ACTIVE_TASK" != "none" ]; then
        TASK_DIR="$BRANCH_DIR/tasks/$ACTIVE_TASK"
        emit_task_summary "$TASK_DIR" "$ACTIVE_TASK"
        emit_file "$TASK_DIR/topics/index.md" "Task Knowledge ($ACTIVE_TASK)"
    fi
fi

# --- Maintenance alerts (settings.yaml read on-demand here, not injected) ---
if [ -n "${TASK_DIR:-}" ] && [ -d "${TASK_DIR:-}" ]; then
    _max_s=$(sed -n 's/^[[:space:]]*status-max-lines:[[:space:]]*//p' \
             "$PROJECT_DIR/settings.yaml" 2>/dev/null)
    # Check for compact-needed marker
    if [ -f "$TASK_DIR/status.md" ] && head -1 "$TASK_DIR/status.md" | grep -q 'maintenance:.*compact needed'; then
        echo "Maintenance: status.md marked for compaction. Compact before starting new work."
    elif [ -f "$TASK_DIR/status.md" ]; then
        _sl=$(wc -l < "$TASK_DIR/status.md")
        [ "$_sl" -gt "${_max_s:-150}" ] 2>/dev/null && \
            echo "Maintenance: status.md ${_sl} lines (limit ${_max_s:-150}). Compact before starting new work: move details to knowledge topics."
    fi
fi

cat << 'RULES'
Recall-save: Save only [VERIFIED]/[OBSERVED] facts; hypotheses → status.md. Fix vague/stale/contradicted content on read.
RULES
```

- [ ] **Step 3: Verify the file is syntactically valid bash**

```bash
bash -n recall/hooks/scripts/session-start.sh
```

Expected: no output, exit code 0.

- [ ] **Step 4: Run against the fixture tree — default branch (main) case**

```bash
cd /tmp/recall-test/testproj  # not a real git repo, so simulate via RECALL_ROOT + a temp git init
git init -q /tmp/recall-test/testproj 2>/dev/null || true
cd /tmp/recall-test/testproj
git checkout -q -b main 2>/dev/null || git branch -q -m main 2>/dev/null || true
git remote add origin https://example.com/testproj.git 2>/dev/null || true
RECALL_ROOT=/tmp/recall-test /home/AMD/poyechen/workspace/repo/agent-plugins/recall/hooks/scripts/session-start.sh
```

Expected output contains:
```
RECALL_BRANCH=main
RECALL_PROJECT=testproj
RECALL_ROOT=/tmp/recall-test

=== Project Knowledge (testproj) ===
# testproj — project knowledge

## Working agreements
- [feedback-no-force-push](feedback-no-force-push.md) — never force-push without approval

Default branch (main) — project-level knowledge loaded only.
Run detect-merged to check for branches ready to promote.
```
Confirm: no `Project Directives`, no `User Profile`, no "Session Start" checklist section appear anywhere in the output.

- [ ] **Step 5: Run against the fixture tree — feature branch with active task**

```bash
cd /tmp/recall-test/testproj
git checkout -q -b feature/foo
RECALL_ROOT=/tmp/recall-test /home/AMD/poyechen/workspace/repo/agent-plugins/recall/hooks/scripts/session-start.sh
```

Expected output contains, in order:
```
RECALL_BRANCH=feature/foo
RECALL_PROJECT=testproj
RECALL_ROOT=/tmp/recall-test

=== Project Knowledge (testproj) ===
...(same as step 4)...

=== Branch: feature/foo ===
parent=main created=2026-07-01 status=active mode=full active-task=mytask

=== Branch Knowledge (feature/foo) ===
## Branch findings
- [wip-note](wip-note.md) — branch-specific WIP status

Task: mytask | active | details=/tmp/recall-test/testproj/branches/feature--foo/tasks/mytask/status.md
Goal: Fix the foo bug

=== Task Knowledge (mytask) ===
- [root-cause](root-cause.md) — the foo bug is caused by X

Recall-save: Save only [VERIFIED]/[OBSERVED] facts; hypotheses → status.md. Fix vague/stale/contradicted content on read.
```
Confirm: no `settings.yaml` content appears anywhere in the output (it exists on disk in the fixture but must not be injected).

- [ ] **Step 6: Clean up fixture and commit**

```bash
rm -rf /tmp/recall-test
cd /home/AMD/poyechen/workspace/repo/agent-plugins
git add recall/hooks/scripts/session-start.sh
git commit -m "feat(recall): inline topics/index.md at session start, drop settings.yaml/user.md injection and path checklist"
```

---

### Task 2: Update `lib.sh` and `create-branch-dir.sh` for the new layout

**Files:**
- Modify: `recall/scripts/create-branch-dir.sh:46-56`
- No changes needed to `recall/scripts/lib.sh` (verified: contains no hardcoded `knowledge/`/`workflows/`/`directives.md`/`user.md` paths — all its functions are directory-agnostic path helpers)

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `create-branch-dir.sh` now creates `topics/index.md` (not `knowledge/index.md` + `workflows/index.md`) and `settings.yaml` (empty, not `directives.md`) for full-mode branches. Later tasks (skills) assume a branch created by this script has this shape.

- [ ] **Step 1: Read the current file** (already read in full above; re-read before editing per tool requirement)

```bash
cat -n /home/AMD/poyechen/workspace/repo/agent-plugins/recall/scripts/create-branch-dir.sh
```

- [ ] **Step 2: Replace the full-mode block**

Change:
```bash
if [ "$MODE" = "full" ]; then
    touch "$BRANCH_DIR/directives.md"

    mkdir -p "$BRANCH_DIR/knowledge"
    touch "$BRANCH_DIR/knowledge/index.md"

    mkdir -p "$BRANCH_DIR/workflows"
    touch "$BRANCH_DIR/workflows/index.md"

    mkdir -p "$BRANCH_DIR/tasks"
fi
```
to:
```bash
if [ "$MODE" = "full" ]; then
    touch "$BRANCH_DIR/settings.yaml"

    mkdir -p "$BRANCH_DIR/topics"
    touch "$BRANCH_DIR/topics/index.md"

    mkdir -p "$BRANCH_DIR/tasks"
fi
```

- [ ] **Step 3: Verify syntax**

```bash
bash -n recall/scripts/create-branch-dir.sh
```

Expected: no output, exit 0.

- [ ] **Step 4: Functional test — create a branch dir and inspect the result**

```bash
mkdir -p /tmp/recall-test2
cd /tmp/recall-test2 && git init -q .
recall/scripts/create-branch-dir.sh --project-dir /tmp/recall-test2/proj --branch feature/bar --parent main --mode full
find /tmp/recall-test2/proj -type f | sort
```

Expected files:
```
/tmp/recall-test2/proj/branches/feature--bar/meta.md
/tmp/recall-test2/proj/branches/feature--bar/settings.yaml
/tmp/recall-test2/proj/branches/feature--bar/topics/index.md
```
Confirm: no `directives.md`, no `knowledge/`, no `workflows/` under the branch dir.

- [ ] **Step 5: Test lightweight mode still works (no topics/ created)**

```bash
recall/scripts/create-branch-dir.sh --project-dir /tmp/recall-test2/proj --branch hotfix/baz --parent main --mode lightweight
find /tmp/recall-test2/proj/branches/hotfix--baz -type f
```

Expected: only `/tmp/recall-test2/proj/branches/hotfix--baz/meta.md` (lightweight mode creates no `topics/`/`settings.yaml`, matching existing behavior where only `meta.md` is written outside the `if [ "$MODE" = "full" ]` block).

- [ ] **Step 6: Clean up and commit**

```bash
rm -rf /tmp/recall-test2
cd /home/AMD/poyechen/workspace/repo/agent-plugins
git add recall/scripts/create-branch-dir.sh
git commit -m "feat(recall): create-branch-dir.sh creates topics/ + settings.yaml instead of knowledge/workflows/directives.md"
```

---

### Task 3: Update `create-task-dir.sh` to create `topics/index.md` (drop the flat-file stage)

**Files:**
- Modify: `recall/scripts/create-task-dir.sh:28-38`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: task directories now have `topics/index.md` from creation (empty file), never a flat `knowledge.md`. Task 6 (recall-add), Task 7 (task-complete/task-abandon), and Task 8 (task-switch) all assume this shape and no longer need flat-vs-split branching logic.

- [ ] **Step 1: Read the current file** (already read in full above; re-read before editing)

- [ ] **Step 2: Add topics/index.md creation**

Change:
```bash
mkdir -p "$TASK_DIR"

cat > "$TASK_DIR/status.md" << EOF
**Status:** active
**Created:** $TODAY

## Goal
$GOAL
EOF

write_meta_field "$BRANCH_DIR/meta.md" "Active Task" "$TASK"
```
to:
```bash
mkdir -p "$TASK_DIR/topics"

cat > "$TASK_DIR/status.md" << EOF
**Status:** active
**Created:** $TODAY

## Goal
$GOAL
EOF

touch "$TASK_DIR/topics/index.md"

write_meta_field "$BRANCH_DIR/meta.md" "Active Task" "$TASK"
```

- [ ] **Step 3: Verify syntax**

```bash
bash -n recall/scripts/create-task-dir.sh
```

Expected: no output, exit 0.

- [ ] **Step 4: Functional test**

```bash
mkdir -p /tmp/recall-test3/branch-dir
recall/scripts/create-task-dir.sh --branch-dir /tmp/recall-test3/branch-dir --task mytask --goal "test goal"
find /tmp/recall-test3/branch-dir -type f | sort
cat /tmp/recall-test3/branch-dir/tasks/mytask/status.md
```

Expected files: `/tmp/recall-test3/branch-dir/tasks/mytask/status.md`, `/tmp/recall-test3/branch-dir/tasks/mytask/topics/index.md` (empty). `status.md` content shows Status/Created/Goal as before. Note: `write_meta_field` will fail silently here since `meta.md` doesn't exist in this isolated fixture — that's expected and unrelated to this change (verify by checking the exit code is still 0 despite this, matching pre-existing behavior since `write_meta_field` uses `>>` append which creates the file if missing).

```bash
cat /tmp/recall-test3/branch-dir/meta.md
```
Expected: file now exists with one line `**Active Task:** \`mytask\`` (via `write_meta_field`'s append-if-missing branch — pre-existing behavior, unaffected by this task's change).

- [ ] **Step 5: Clean up and commit**

```bash
rm -rf /tmp/recall-test3
cd /home/AMD/poyechen/workspace/repo/agent-plugins
git add recall/scripts/create-task-dir.sh
git commit -m "feat(recall): create-task-dir.sh creates topics/index.md, drop flat knowledge.md stage"
```

---

### Task 4: Update `reorg-inventory.sh` comments/usage text for `topics/` terminology

**Files:**
- Modify: `recall/scripts/reorg-inventory.sh:2-11`

**Interfaces:**
- Consumes: nothing (this script's actual logic — parsing `*.md` files in a directory arg, checking frontmatter/index membership — is directory-name-agnostic; it already works unchanged against a `topics/` directory since it takes the directory as a CLI argument).
- Produces: no behavior change; comment/usage text only, so `/recall-reorg` (Task 9) can reference accurate wording.

This script requires no functional changes — it operates on whatever directory path is passed as `$1`, so pointing it at `topics/` instead of `knowledge/`/`workflows/` works with zero code changes. Only the header comment and usage string mention the old terminology.

- [ ] **Step 1: Read the current file** (already read in full above; re-read before editing)

- [ ] **Step 2: Update the header comment and usage string**

Change lines 2-11 from:
```bash
# scripts/reorg-inventory.sh — mechanical inventory for /recall-reorg (step 3a).
# Read-only. Parses every topic in a knowledge/ or workflows/ dir and reports the
# facts that need no judgment: identity (filename vs frontmatter name vs H1 title),
# metadata.type, line count, frontmatter validity, index membership (both ways),
# oversize, and a staleness-marker grep. Feed the output to the analysis step so a
# subagent only has to read the handful of files that are actually flagged.
#
# Usage: reorg-inventory.sh <knowledge-dir> [topic-max-lines]
#   <knowledge-dir>  dir containing topic *.md files and an index.md
#   [topic-max-lines] size limit (default 200)
```
to:
```bash
# scripts/reorg-inventory.sh — mechanical inventory for /recall-reorg (step 3a).
# Read-only. Parses every topic in a topics/ dir and reports the
# facts that need no judgment: identity (filename vs frontmatter name vs H1 title),
# metadata.type, line count, frontmatter validity, index membership (both ways),
# oversize, and a staleness-marker grep. Feed the output to the analysis step so a
# subagent only has to read the handful of files that are actually flagged.
#
# Usage: reorg-inventory.sh <topics-dir> [topic-max-lines]
#   <topics-dir>  dir containing topic *.md files and an index.md
#   [topic-max-lines] size limit (default 200)
```

Also update line 15's error message string to match:
```bash
DIR="${1:?usage: reorg-inventory.sh <topics-dir> [topic-max-lines]}"
```

- [ ] **Step 3: Verify syntax**

```bash
bash -n recall/scripts/reorg-inventory.sh
```

Expected: no output, exit 0.

- [ ] **Step 4: Functional smoke test — run against a topics/ directory with one clean topic and one flagged topic**

```bash
mkdir -p /tmp/recall-test4/topics
cat > /tmp/recall-test4/topics/index.md << 'EOF'
- [good-topic](good-topic.md) — a well-formed topic
EOF
cat > /tmp/recall-test4/topics/good-topic.md << 'EOF'
---
name: good-topic
description: a well-formed topic
metadata:
  type: feedback
---

# good-topic

Some content.
EOF
cat > /tmp/recall-test4/topics/orphan-topic.md << 'EOF'
No frontmatter here, and not in the index.
EOF
recall/scripts/reorg-inventory.sh /tmp/recall-test4/topics 200
```

Expected output includes `good-topic.md` with no flags, and `orphan-topic.md` flagged with `NO-FRONTMATTER`, `NO-NAME`, `NO-TYPE`, `NOT-IN-INDEX`, `NO-H1` under `=== FLAGGED FILES ===`, and under `=== INDEX DRIFT ===` it lists `orphan-topic.md` as "missing from index".

- [ ] **Step 5: Clean up and commit**

```bash
rm -rf /tmp/recall-test4
cd /home/AMD/poyechen/workspace/repo/agent-plugins
git add recall/scripts/reorg-inventory.sh
git commit -m "docs(recall): update reorg-inventory.sh comments to topics/ terminology"
```

---

### Task 5: Rewrite `recall-init` SKILL.md for the new layout

**Files:**
- Modify: `recall/skills/recall-init/SKILL.md`

**Interfaces:**
- Consumes: nothing from other tasks (skills are agent-read instructions, not code with call interfaces — but this task defines the canonical `settings.yaml` content other tasks reference).
- Produces: the canonical `settings.yaml` schema (keys: `auto-save.auto/ask/never/default`, `promotion`, `stale-branch-days`, `default-branch`, `confidence-min`, `maintenance.status-max-lines/status-final-lines/topic-max-lines`, plus any `WORKSPACE`/`CONTAINER`-style user env keys) that Tasks 6-9's skill updates reference when they say "read `confidence-min` from settings.yaml" etc. Note `task-knowledge-split-lines` is dropped from this schema (per the resolved task-level-uniformity decision — no more flat-file stage to split from).

- [ ] **Step 1: Read the current file** (already read in full above; re-read before editing)

- [ ] **Step 2: Replace steps 3-6 and the Size Maintenance section**

Replace the entire file content from `3. Create the project directory` through the end of the `### Size Maintenance` section with:

```markdown
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
```

The `### Quality Maintenance` section that follows is unchanged (it already says "knowledge file" generically, no path references).

- [ ] **Step 3: Verify no stale references remain**

```bash
grep -n "directives\.md\|workflows/\|knowledge/\|user\.md\|task-knowledge-split-lines" recall/skills/recall-init/SKILL.md
```

Expected: no output (all references removed).

- [ ] **Step 4: Commit**

```bash
git add recall/skills/recall-init/SKILL.md
git commit -m "docs(recall): rewrite recall-init for topics/ + settings.yaml layout"
```

---

### Task 6: Rewrite `recall-add` SKILL.md — target `topics/`, read `settings.yaml`, no flat-file case

**Files:**
- Modify: `recall/skills/recall-add/SKILL.md`

**Interfaces:**
- Consumes: `settings.yaml` schema from Task 5 (`confidence-min`, `maintenance.topic-max-lines`).
- Produces: nothing consumed by later tasks directly, but establishes the pattern (`<level>/topics/<topic>.md`, update `<level>/topics/index.md`) that Task 9 (`/recall-reorg`) and Task 10 (`/promote`) reference as "how topics are saved."

- [ ] **Step 1: Read the current file** (already read in full above; re-read before editing)

- [ ] **Step 2: Replace the full Steps section**

Replace entirely with:

```markdown
## Steps

1. Determine scope:
   - If `--project`: target is `<project>/topics/<topic>.md`
   - If `--branch`: target is `<branch>/topics/<topic>.md`
   - If neither: agent assesses — task-specific → `<task>/topics/<topic>.md`, branch-general → branch overlay, project-general → project level
2. Check confidence:
   - Read `confidence-min` from the target level's `settings.yaml`
   - Only write [VERIFIED] or [OBSERVED] facts. Reject hypotheses with guidance to use status.md
3. If topic file exists: read it, append the new finding with evidence citation
4. If topic file doesn't exist: create it, add entry to the relevant `topics/index.md`
5. Briefly explain: "Saved to <scope>/topics/<topic>.md — <reason>."
6. **Size check**: After writing, check file line count against `maintenance.topic-max-lines` (from the target level's `settings.yaml`).
   - Topic file over the limit: split `###` subsections into sibling topic files, update the parent index.
```

- [ ] **Step 3: Verify no stale references remain**

```bash
grep -n "directives\.md\|knowledge/\|knowledge\.md\|workflows/" recall/skills/recall-add/SKILL.md
```

Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add recall/skills/recall-add/SKILL.md
git commit -m "docs(recall): rewrite recall-add to target topics/, drop flat task-knowledge case"
```

---

### Task 7: Rewrite `recall-search`, `recall-status`, `recall-changelog` SKILL.md files

**Files:**
- Modify: `recall/skills/recall-search/SKILL.md`
- Modify: `recall/skills/recall-status/SKILL.md`
- Modify: `recall/skills/recall-changelog/SKILL.md`

**Interfaces:**
- Consumes: `topics/` layout from Tasks 2-6.
- Produces: nothing consumed by later tasks (leaf skills).

These three are grouped in one task because each is a small, independent search-path update with no shared code — but doing them together avoids three near-empty tasks for near-identical one-line changes.

- [ ] **Step 1: Read all three files** (already read in full above; re-read before editing)

- [ ] **Step 2: Update `recall-search/SKILL.md`'s Steps section**

Replace:
```markdown
2. Use Grep tool to search for `<query>` across:
   - `<project>/knowledge/` (project-level topics)
   - `<project>/branches/*/knowledge/` (all active branch overlays)
   - `<project>/branches/*/tasks/*/knowledge.md` (flat task knowledge)
   - `<project>/branches/*/tasks/*/knowledge/*.md` (split task knowledge)
   - `<project>/archive/*/knowledge/` (archived branch knowledge)
```
with:
```markdown
2. Use Grep tool to search for `<query>` across:
   - `<project>/topics/` (project-level topics)
   - `<project>/branches/*/topics/` (all active branch overlays)
   - `<project>/branches/*/tasks/*/topics/` (task-level topics)
   - `<project>/archive/*/topics/` (archived branch knowledge)
```

- [ ] **Step 3: Update `recall-status/SKILL.md`'s Steps section**

Replace:
```markdown
   - Show project-level stats: topic count in knowledge/ and workflows/, directives summary.
```
with:
```markdown
   - Show project-level stats: topic count in topics/, settings.yaml summary.
```
Replace the output format block's line:
```
  Topics:   <N> project + <M> branch overlay
  Workflows: <N> project + <M> branch overlay
```
with a single line (no separate workflows count, since workflow-type findings are just topics now):
```
  Topics:   <N> project + <M> branch overlay
```

- [ ] **Step 4: Update `recall-changelog/SKILL.md`'s Steps section**

Replace:
```markdown
2. Find all knowledge and workflow files modified in the last N days:
```
with:
```markdown
2. Find all topic files modified in the last N days:
```
(The `find` command itself is unchanged — it already globs `*.md` recursively under the project dir, which still works since `topics/` files have the same `.md` extension.)

- [ ] **Step 5: Verify no stale references remain**

```bash
grep -rn "knowledge/\|workflows/\|knowledge\.md\|directives\.md" recall/skills/recall-search/SKILL.md recall/skills/recall-status/SKILL.md recall/skills/recall-changelog/SKILL.md
```

Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add recall/skills/recall-search/SKILL.md recall/skills/recall-status/SKILL.md recall/skills/recall-changelog/SKILL.md
git commit -m "docs(recall): update recall-search/status/changelog for topics/ layout"
```

---

### Task 8: Rewrite `task-complete`, `task-abandon`, `task-switch` SKILL.md files (drop flat-file branching)

**Files:**
- Modify: `recall/skills/task-complete/SKILL.md`
- Modify: `recall/skills/task-abandon/SKILL.md`
- Modify: `recall/skills/task-switch/SKILL.md`

**Interfaces:**
- Consumes: Task 3's task creation (`topics/index.md` always exists, no flat `knowledge.md` case), Task 5's `settings.yaml` schema.
- Produces: nothing consumed by later tasks (leaf skills), except establishing that task-level compaction always targets `topics/` (relevant context for Task 9/10 if they ever cross-reference task-level compaction, which they currently don't).

- [ ] **Step 1: Read all three files** (already read in full above; re-read before editing)

- [ ] **Step 2: Update `task-complete/SKILL.md`**

Replace:
```markdown
2. **Knowledge review** — before marking complete:
   - Read the task's knowledge (knowledge.md if flat file, or knowledge/index.md + relevant topic files if split into directory).
   - Review the conversation for any unsaved findings (task completion review trigger).
   - For each finding, apply auto-save rules (auto/ask/never from directives config).
   - Ask: "Promote any of this task's knowledge to branch level?" List candidates.
2.5. **Compact status.md** — if status.md exceeds maintenance.status-final-lines (from directives.md) or has `<!-- maintenance: compact needed -->` marker:
   a. Copy status.md to status.pre-compact.md as backup.
   b. Extract detailed content (experiment logs, raw data, debugging traces) into knowledge topics. Use task-level knowledge by default; use branch-level if the finding is general.
   c. Rewrite status.md in compact format: Goal (unchanged), Baseline, Current State (2-3 sentences), Applied Changes (one line each), Next Steps.
   d. If task knowledge now exceeds maintenance.task-knowledge-split-lines, split into knowledge/ directory with per-topic files + index.md. Leave a 2-line redirect at the original knowledge.md path.
   e. Verify compacted status.md has all required sections (Goal, Status, Current State). Then delete status.pre-compact.md.
```
with:
```markdown
2. **Knowledge review** — before marking complete:
   - Read the task's `topics/index.md` and relevant topic files.
   - Review the conversation for any unsaved findings (task completion review trigger).
   - For each finding, apply auto-save rules (auto/ask/never from the branch's settings.yaml).
   - Ask: "Promote any of this task's knowledge to branch level?" List candidates.
2.5. **Compact status.md** — if status.md exceeds maintenance.status-final-lines (from the branch's settings.yaml) or has `<!-- maintenance: compact needed -->` marker:
   a. Copy status.md to status.pre-compact.md as backup.
   b. Extract detailed content (experiment logs, raw data, debugging traces) into topic files under `topics/`. Use task-level topics by default; use branch-level if the finding is general.
   c. Rewrite status.md in compact format: Goal (unchanged), Baseline, Current State (2-3 sentences), Applied Changes (one line each), Next Steps.
   d. Verify compacted status.md has all required sections (Goal, Status, Current State). Then delete status.pre-compact.md.
```
(Step d's directory-split sub-step is removed entirely — there's no flat file to split from anymore.)

- [ ] **Step 3: Update `task-abandon/SKILL.md`**

Replace:
```markdown
4. Review task knowledge for salvageable findings:
   - Read knowledge (knowledge.md if flat file, or knowledge/index.md + relevant topic files if split into directory).
   - Negative results ("approach X doesn't work because Y") → offer to promote to branch knowledge
   - Verified technical facts → offer to promote to branch knowledge
   - Everything else → leave in place
4.5. **Compact status.md** — if status.md exceeds maintenance.status-final-lines (from directives.md) or has `<!-- maintenance: compact needed -->` marker:
   a. Copy status.md to status.pre-compact.md as backup.
   b. Extract detailed content into knowledge topics. Consolidate "what failed and why" into a negative-results knowledge topic.
   c. Rewrite status.md in compact format (same as task-complete).
   d. If task knowledge now exceeds maintenance.task-knowledge-split-lines, split into knowledge/ directory.
   e. Verify, then delete status.pre-compact.md.
```
with:
```markdown
4. Review task knowledge for salvageable findings:
   - Read `topics/index.md` + relevant topic files.
   - Negative results ("approach X doesn't work because Y") → offer to promote to branch knowledge
   - Verified technical facts → offer to promote to branch knowledge
   - Everything else → leave in place
4.5. **Compact status.md** — if status.md exceeds maintenance.status-final-lines (from the branch's settings.yaml) or has `<!-- maintenance: compact needed -->` marker:
   a. Copy status.md to status.pre-compact.md as backup.
   b. Extract detailed content into topic files. Consolidate "what failed and why" into a negative-results topic.
   c. Rewrite status.md in compact format (same as task-complete).
   d. Verify, then delete status.pre-compact.md.
```

- [ ] **Step 4: Update `task-switch/SKILL.md`**

Replace:
```markdown
5. Read the new task's status.md, knowledge (knowledge.md if flat file, or knowledge/index.md if split into directory), and workflows.md.
```
with:
```markdown
5. Read the new task's status.md and topics/index.md.
```

- [ ] **Step 5: Verify no stale references remain**

```bash
grep -rn "knowledge/\|knowledge\.md\|workflows\.md\|directives\.md\|task-knowledge-split-lines" recall/skills/task-complete/SKILL.md recall/skills/task-abandon/SKILL.md recall/skills/task-switch/SKILL.md
```

Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add recall/skills/task-complete/SKILL.md recall/skills/task-abandon/SKILL.md recall/skills/task-switch/SKILL.md
git commit -m "docs(recall): update task-complete/abandon/switch for topics/ layout, drop flat-file case"
```

---

### Task 9: Rewrite `recall-reorg` SKILL.md for unified `topics/` scope

**Files:**
- Modify: `recall/skills/recall-reorg/SKILL.md`

**Interfaces:**
- Consumes: Task 4's `reorg-inventory.sh` (now called with a single `topics/` dir per scope instead of separately with `knowledge/` and `workflows/`).
- Produces: nothing consumed by later tasks (leaf skill).

- [ ] **Step 1: Read the current file** (already read in full above; re-read before editing)

- [ ] **Step 2: Update the frontmatter description**

Change:
```yaml
description: Re-organize recall knowledge/workflow topics into their best shape — unify topic filenames, frontmatter, and titles, merge overlapping topics, compact stale content, extract shared general principles into their own topics, and rewrite the index coherently. Use whenever the user says "re-org the recall topics", "clean up recall", "make the recall coherent", "extract a general topic", "tidy the knowledge index", or when recall files have drifted (mismatched names, duplicated content, oversized files, a stale index). Keeps recall well-managed as a whole rather than fixing one file at a time.
```
to:
```yaml
description: Re-organize recall topics into their best shape — unify topic filenames, frontmatter, and titles, merge overlapping topics, compact stale content, extract shared general principles into their own topics, and rewrite the index coherently. Use whenever the user says "re-org the recall topics", "clean up recall", "make the recall coherent", "extract a general topic", "tidy the knowledge index", or when recall files have drifted (mismatched names, duplicated content, oversized files, a stale index). Keeps recall well-managed as a whole rather than fixing one file at a time.
```

- [ ] **Step 3: Update the Arguments section**

Change:
```markdown
## Arguments
- (default): the current branch's overlay only (`branches/<slug>/knowledge/` +
  `workflows/`). Smallest, safest scope — the files you're actively growing.
- `--project`: project level only (`knowledge/` + `workflows/`); leave branch
  overlays untouched.
- `--project-and-branch`: project level **and** the current branch's overlay together.
- `--all`: every project under the recall root. Broad and slow — confirm first.
```
to:
```markdown
## Arguments
- (default): the current branch's overlay only (`branches/<slug>/topics/`).
  Smallest, safest scope — the files you're actively growing.
- `--project`: project level only (`topics/`); leave branch overlays untouched.
- `--project-and-branch`: project level **and** the current branch's overlay together.
- `--all`: every project under the recall root. Broad and slow — confirm first.
```

- [ ] **Step 4: Update invariant 5 (size limits) to reference settings.yaml**

Change:
```markdown
5. **Within size limits.** No topic exceeds `topic-max-lines` (from `directives.md`,
   default 200) — but reach that by compaction first, not reflexive splitting.
```
to:
```markdown
5. **Within size limits.** No topic exceeds `topic-max-lines` (from `settings.yaml`,
   default 200) — but reach that by compaction first, not reflexive splitting.
```

- [ ] **Step 5: Update Step 1 (Resolve scope)**

Change:
```markdown
1. **Resolve scope.** Resolve storage root and project dir (see
   `${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh`). Determine the target directories from
   the argument; the default is the current branch's overlay
   (`branches/<sanitized-branch>/knowledge/` + `workflows/`). If the default scope
   is requested but you're on a default branch (main/master/develop) with no branch
   overlay, say so and suggest `--project`. Read `directives.md` for
   `topic-max-lines` and `confidence-min`.
```
to:
```markdown
1. **Resolve scope.** Resolve storage root and project dir (see
   `${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh`). Determine the target directories from
   the argument; the default is the current branch's overlay
   (`branches/<sanitized-branch>/topics/`). If the default scope
   is requested but you're on a default branch (main/master/develop) with no branch
   overlay, say so and suggest `--project`. Read `settings.yaml` for
   `topic-max-lines` and `confidence-min`.
```

- [ ] **Step 6: Update Step 3a (scripted inventory)**

Change:
```markdown
   **3a. Scripted inventory (cheap, deterministic, no LLM judgment).** Run
   `${CLAUDE_PLUGIN_ROOT}/scripts/reorg-inventory.sh <knowledge-dir> <topic-max-lines>`
   for each target dir (the `knowledge/` and `workflows/` of every scope in play). It
   parses every topic and reports the mechanical facts: per file — filename vs
```
to:
```markdown
   **3a. Scripted inventory (cheap, deterministic, no LLM judgment).** Run
   `${CLAUDE_PLUGIN_ROOT}/scripts/reorg-inventory.sh <topics-dir> <topic-max-lines>`
   for the `topics/` dir of every scope in play. It
   parses every topic and reports the mechanical facts: per file — filename vs
```

- [ ] **Step 7: Verify no stale references remain**

```bash
grep -n "knowledge/\|workflows/\|directives\.md" recall/skills/recall-reorg/SKILL.md
```

Expected: no output.

- [ ] **Step 8: Commit**

```bash
git add recall/skills/recall-reorg/SKILL.md
git commit -m "docs(recall): update recall-reorg for unified topics/ scope"
```

---

### Task 10: Rewrite `promote` and `branch-abandon` SKILL.md files

**Files:**
- Modify: `recall/skills/promote/SKILL.md`
- Modify: `recall/skills/branch-abandon/SKILL.md`

**Interfaces:**
- Consumes: `topics/` layout from Tasks 2, 6, 9.
- Produces: nothing consumed by later tasks (leaf skills).

- [ ] **Step 1: Read both files** (already read in full above; re-read before editing)

- [ ] **Step 2: Update `promote/SKILL.md`**

Change:
```markdown
3. **For each branch to promote:**
   a. Read all knowledge/ and workflows/ topic files from the branch overlay.
   b. For each finding, classify:
      - **Promote** (general): architectural patterns, hardware behavior, debugging techniques, performance patterns, API insights, conventions
      - **Archive** (branch-specific): branch commit hashes, WIP status, temporary workarounds, task configs, unverified hypotheses
   c. For promotable content:
      - If a matching project-level topic exists → append to it
      - If no matching topic → create new topic file, add to project index.md
      - After appending, if the topic file exceeds maintenance.topic-max-lines (from directives.md), split ### subsections into sibling topic files and update the project index.md.
```
to:
```markdown
3. **For each branch to promote:**
   a. Read all topic files from the branch overlay's `topics/`.
   b. For each finding, classify:
      - **Promote** (general): architectural patterns, hardware behavior, debugging techniques, performance patterns, API insights, conventions
      - **Archive** (branch-specific): branch commit hashes, WIP status, temporary workarounds, task configs, unverified hypotheses
   c. For promotable content:
      - If a matching project-level topic exists → append to it
      - If no matching topic → create new topic file, add to project `topics/index.md`
      - After appending, if the topic file exceeds maintenance.topic-max-lines (from the project's settings.yaml), split ### subsections into sibling topic files and update the project `topics/index.md`.
```

- [ ] **Step 3: Update `branch-abandon/SKILL.md`**

Change:
```markdown
3. Review all branch-level knowledge and workflow overlays:
   - General insights (architectural patterns, hardware behavior, debugging techniques) → promote to project level
   - Negative results ("don't do X because Y") → promote to project `knowledge/lessons-learned.md`
   - Branch-specific details → archive only
```
to:
```markdown
3. Review all branch-level topics:
   - General insights (architectural patterns, hardware behavior, debugging techniques) → promote to project level
   - Negative results ("don't do X because Y") → promote to project `topics/lessons-learned.md`
   - Branch-specific details → archive only
```

- [ ] **Step 4: Verify no stale references remain**

```bash
grep -n "knowledge/\|workflows/\|directives\.md" recall/skills/promote/SKILL.md recall/skills/branch-abandon/SKILL.md
```

Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add recall/skills/promote/SKILL.md recall/skills/branch-abandon/SKILL.md
git commit -m "docs(recall): update promote/branch-abandon for topics/ layout"
```

---

### Task 11: Update `recall/README.md` and root `README.md`

**Files:**
- Modify: `recall/README.md`
- Modify: `README.md` (repo root — check for stale references; likely no change needed since it only summarizes the plugin at a high level)

**Interfaces:**
- Consumes: the full new layout established in Tasks 1-10 (this is documentation, describes the end state).
- Produces: nothing (leaf documentation task).

- [ ] **Step 1: Read both files** (already read in full above; re-read before editing)

- [ ] **Step 2: Check root README.md for stale references**

```bash
grep -n "knowledge/\|workflows/\|directives\.md\|user\.md" README.md
```
Expected: no output (root README only describes the plugin at a summary level, no path details) — confirm and skip editing this file if so.

- [ ] **Step 3: Update `recall/README.md`'s "How It Works" storage diagram**

Change:
```markdown
## How It Works

Knowledge is organized in three layers: **project > branch > task**. Each layer only contains what's new at that level — no duplication. The agent reads all layers at session start and merges them.

```
~/.local/share/claude/recall/<project>/
  directives.md           # agent behavior rules + configuration
  knowledge/              # project-level topics (loaded conditionally)
  workflows/              # project-level procedures (loaded conditionally)
  user.md                 # personal preferences (container, worktree, etc.)
  branches/
    <branch>/
      meta.md             # branch metadata, active task, parent info
      knowledge/          # branch overlay (only NEW findings)
      workflows/          # branch overlay (only NEW procedures)
      tasks/
        <task>/
          status.md       # task progress, hypotheses, next steps
          knowledge.md    # task-specific findings
```
```
to:
```markdown
## How It Works

Knowledge is organized in three layers: **project > branch > task**. Each layer only contains what's new at that level — no duplication. The agent reads all layers at session start and merges them.

```
~/.local/share/claude/recall/<project>/
  settings.yaml           # machine-parsed config (auto-save rules, size limits, env values)
  topics/                 # project-level topics — facts, workflows, conventions, all uniform
    index.md              # single index, grouped by thematic headers
  branches/
    <branch>/
      meta.md             # branch metadata, active task, parent info
      settings.yaml       # branch-level config overrides (rarely used)
      topics/             # branch overlay (only NEW findings)
        index.md
      tasks/
        <task>/
          status.md       # task progress, hypotheses, next steps
          topics/         # task-specific findings
            index.md
```

Topics are not split by type (no separate "workflows" folder or required prefix) —
a procedure and a hardware fact live side by side in the same `topics/` directory,
grouped in the index only by whatever thematic heading fits the project's actual
content.
```

- [ ] **Step 4: Update the "Knowledge Maintenance" and "Maintenance configuration" sections**

Change:
```markdown
| Trigger | Action |
|---------|--------|
| `status.md` grows past limit | Marker added; compacted at task completion or next session start |
| `knowledge.md` grows past limit | Split into `knowledge/` directory with per-topic files |
| Knowledge topic grows past limit | Split into sibling topic files |
| Agent reads a knowledge file | Fixes obvious errors (stale paths, duplicates) inline (max 2 per read) |
| Cross-file issues found | Flagged with `<!-- quality-review: ... -->` for later |

### Maintenance configuration

Size limits are configured in `directives.md`:

```yaml
maintenance:
  status-max-lines: 150      # soft limit — marks file for compaction
  status-final-lines: 100    # hard limit — target size after compaction
  topic-max-lines: 200       # max lines per knowledge topic file
  task-knowledge-split-lines: 150  # when to split flat knowledge.md into directory
```
```
to:
```markdown
| Trigger | Action |
|---------|--------|
| `status.md` grows past limit | Marker added; compacted at task completion or next session start |
| Topic file grows past limit | Split into sibling topic files |
| Agent reads a topic file | Fixes obvious errors (stale paths, duplicates) inline (max 2 per read) |
| Cross-file issues found | Flagged with `<!-- quality-review: ... -->` for later |

### Maintenance configuration

Size limits are configured in `settings.yaml`:

```yaml
maintenance:
  status-max-lines: 150      # soft limit — marks file for compaction
  status-final-lines: 100    # hard limit — target size after compaction
  topic-max-lines: 200       # max lines per topic file
```
```

- [ ] **Step 5: Update the "Configuration" section**

Change:
```markdown
## Configuration

Settings live in `directives.md` under `## Configuration`:
```
to:
```markdown
## Configuration

Settings live in `settings.yaml`:
```
(The YAML block below it is unchanged — same keys.)

- [ ] **Step 6: Verify no stale references remain**

```bash
grep -n "directives\.md\|user\.md\|knowledge/\|workflows/\|knowledge\.md\|task-knowledge-split-lines" recall/README.md
```

Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add recall/README.md
git commit -m "docs(recall): update README for topics/ + settings.yaml layout"
```

---

### Task 12: Write and run the migration script for the real on-disk store

**Files:**
- Create: `recall/scripts/migrate-to-topics.sh`

**Interfaces:**
- Consumes: the real store at `~/.local/share/claude/recall/` (or `$RECALL_ROOT` if set) — the existing `knowledge/`+`workflows/`+`directives.md`+`user.md` layout Tasks 1-11 have retired.
- Produces: every project/branch/task directory under the store converted to `topics/`+`settings.yaml`; a `topics/_migration-needs-review.md` staging file per level that had free-form prose to migrate; old files removed.

This is a one-time script per the spec ("run once, by hand... it is not part of ongoing plugin operation"), but it's still committed to the plugin repo (in `scripts/`) as a durable, reviewable artifact, matching how `create-branch-dir.sh` etc. live in the same directory. It is not invoked by any skill or hook.

- [ ] **Step 1: Write the script**

```bash
cat > /home/AMD/poyechen/workspace/repo/agent-plugins/recall/scripts/migrate-to-topics.sh << 'SCRIPT'
#!/usr/bin/env bash
# scripts/migrate-to-topics.sh — one-time migration of an existing recall store
# from the old knowledge/+workflows/+directives.md+user.md layout to the new
# unified topics/+settings.yaml layout. Run once, by hand, against a real store.
#
# Usage: migrate-to-topics.sh <recall-root> [--dry-run]
#   <recall-root>  e.g. ~/.local/share/claude/recall
#   --dry-run      print planned actions without touching any file

set -euo pipefail

ROOT="${1:?usage: migrate-to-topics.sh <recall-root> [--dry-run]}"
DRY_RUN="${2:-}"

[ -d "$ROOT" ] || { echo "error: not a directory: $ROOT" >&2; exit 1; }

run() {
    if [ "$DRY_RUN" = "--dry-run" ]; then
        echo "[dry-run] $*"
    else
        "$@"
    fi
}

# Merge workflows/index.md content into knowledge/index.md, rename knowledge/ -> topics/
migrate_level_dir() {
    local level_dir="$1"
    local kd="$level_dir/knowledge" wd="$level_dir/workflows" td="$level_dir/topics"

    [ -d "$kd" ] || [ -d "$wd" ] || return 0
    echo "=== $level_dir ==="

    if [ -d "$kd" ]; then
        run mkdir -p "$td"
        for f in "$kd"/*.md; do
            [ -f "$f" ] || continue
            base="$(basename "$f")"
            if [ "$base" = "index.md" ]; then
                run cp "$f" "$td/index.md"
            else
                run mv "$f" "$td/$base"
            fi
        done
        run rmdir "$kd" 2>/dev/null || true
    else
        run mkdir -p "$td"
        run touch "$td/index.md"
    fi

    if [ -d "$wd" ]; then
        for f in "$wd"/*.md; do
            [ -f "$f" ] || continue
            base="$(basename "$f")"
            if [ "$base" = "index.md" ]; then
                if [ -s "$f" ]; then
                    echo "  appending $f content into $td/index.md"
                    if [ "$DRY_RUN" != "--dry-run" ]; then
                        { echo ""; cat "$f"; } >> "$td/index.md"
                    fi
                fi
            else
                run mv "$f" "$td/$base"
            fi
        done
        run rmdir "$wd" 2>/dev/null || true
    fi
}

# Extract directives.md's YAML block into settings.yaml; dump prose to staging file
migrate_directives() {
    local level_dir="$1"
    local df="$level_dir/directives.md" sf="$level_dir/settings.yaml"
    [ -f "$df" ] || return 0
    [ -s "$df" ] || { run rm -f "$df"; return 0; }
    echo "=== migrating directives.md: $df ==="

    # Split at the first line that isn't part of a recognized YAML key (heuristic:
    # lines starting with a lowercase key: or leading whitespace+key: belong to YAML;
    # a line starting with "- " or "#" at column 0 (after the YAML block) is prose)
    python3 - "$df" "$sf" "$level_dir" "$DRY_RUN" << 'PY'
import sys, re
df, sf, level_dir, dry_run = sys.argv[1:5]
lines = open(df).read().splitlines()
yaml_lines = []
prose_lines = []
in_yaml = True
for line in lines:
    if in_yaml and (re.match(r'^[a-zA-Z][a-zA-Z0-9_.-]*:', line) or re.match(r'^\s+\S', line) or line.strip() == ''):
        yaml_lines.append(line)
    else:
        in_yaml = False
        prose_lines.append(line)

if dry_run == "--dry-run":
    print(f"[dry-run] would write {len(yaml_lines)} YAML lines to {sf}")
    if prose_lines:
        print(f"[dry-run] would append {len(prose_lines)} prose lines to {level_dir}/topics/_migration-needs-review.md")
else:
    with open(sf, 'a') as out:
        out.write('\n'.join(yaml_lines).rstrip('\n') + '\n')
    if prose_lines:
        staging = f"{level_dir}/topics/_migration-needs-review.md"
        with open(staging, 'a') as out:
            out.write("\n<!-- migrated from directives.md prose — split into properly named topics -->\n")
            out.write('\n'.join(prose_lines).rstrip('\n') + '\n')
PY
    run rm -f "$df"
}

# Convert user.md's KEY=VALUE lines into settings.yaml keys; dump prose to staging file
migrate_user() {
    local level_dir="$1"
    local uf="$level_dir/user.md" sf="$level_dir/settings.yaml"
    [ -f "$uf" ] || return 0
    [ -s "$uf" ] || { run rm -f "$uf"; return 0; }
    echo "=== migrating user.md: $uf ==="

    python3 - "$uf" "$sf" "$level_dir" "$DRY_RUN" << 'PY'
import sys, re
uf, sf, level_dir, dry_run = sys.argv[1:5]
lines = open(uf).read().splitlines()
kv_lines = []
prose_lines = []
for line in lines:
    if re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', line):
        key, _, val = line.partition('=')
        kv_lines.append(f"{key}: {val}")
    elif line.strip():
        prose_lines.append(line)

if dry_run == "--dry-run":
    print(f"[dry-run] would append {len(kv_lines)} settings keys to {sf}")
    if prose_lines:
        print(f"[dry-run] would append {len(prose_lines)} prose lines to {level_dir}/topics/_migration-needs-review.md")
else:
    if kv_lines:
        with open(sf, 'a') as out:
            out.write('\n'.join(kv_lines) + '\n')
    if prose_lines:
        staging = f"{level_dir}/topics/_migration-needs-review.md"
        with open(staging, 'a') as out:
            out.write("\n<!-- migrated from user.md prose — split into properly named topics -->\n")
            out.write('\n'.join(prose_lines) + '\n')
PY
    run rm -f "$uf"
}

migrate_one_level() {
    local level_dir="$1"
    migrate_level_dir "$level_dir"
    migrate_directives "$level_dir"
    migrate_user "$level_dir"
}

# Walk every project, its branches (active + archived), and their tasks
for project_dir in "$ROOT"/*/; do
    [ -d "$project_dir" ] || continue
    project_dir="${project_dir%/}"
    [[ "$(basename "$project_dir")" == _backup_* ]] && continue

    migrate_one_level "$project_dir"

    for branches_root in "$project_dir/branches" "$project_dir/archive"; do
        [ -d "$branches_root" ] || continue
        for branch_dir in "$branches_root"/*/; do
            [ -d "$branch_dir" ] || continue
            branch_dir="${branch_dir%/}"
            migrate_one_level "$branch_dir"
            [ -d "$branch_dir/tasks" ] || continue
            for task_dir in "$branch_dir/tasks"/*/; do
                [ -d "$task_dir" ] || continue
                task_dir="${task_dir%/}"
                # Task-level: flat knowledge.md -> topics/<slug>.md if present, else ensure topics/index.md
                if [ -f "$task_dir/knowledge.md" ] && [ -s "$task_dir/knowledge.md" ]; then
                    echo "=== flagging flat task knowledge.md for manual split: $task_dir/knowledge.md ==="
                    run mkdir -p "$task_dir/topics"
                    run mv "$task_dir/knowledge.md" "$task_dir/topics/_migration-needs-review.md"
                elif [ ! -d "$task_dir/topics" ]; then
                    run mkdir -p "$task_dir/topics"
                    run touch "$task_dir/topics/index.md"
                fi
            done
        done
    done
done

echo ""
echo "Migration complete. Review any topics/_migration-needs-review.md files created above"
echo "and split their content into properly named, single-purpose topics."
SCRIPT
chmod +x /home/AMD/poyechen/workspace/repo/agent-plugins/recall/scripts/migrate-to-topics.sh
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n recall/scripts/migrate-to-topics.sh
```

Expected: no output, exit 0.

- [ ] **Step 3: Dry-run against a COPY of the real store (never touch the original without a backup)**

```bash
cp -r "$HOME/.local/share/claude/recall" /tmp/recall-migration-test
recall/scripts/migrate-to-topics.sh /tmp/recall-migration-test --dry-run 2>&1 | tee /tmp/migration-dry-run.log
```

Review `/tmp/migration-dry-run.log`. Expected: entries for each of `rocm-libraries`, `snippet`, `rocisa-attn`, `fmha_sp3` at project level, plus their `branches/*` and `archive/*` subdirectories, plus the one known real flat task file `rocm-libraries/branches/gfx1260-hipblaslt-dev/tasks/import-custom6-kernel/knowledge.md` flagged for manual split. No file operations actually performed (dry-run mode).

- [ ] **Step 4: Run for real against the copy (not dry-run) and inspect the result**

```bash
recall/scripts/migrate-to-topics.sh /tmp/recall-migration-test
find /tmp/recall-migration-test/rocm-libraries -maxdepth 1
find /tmp/recall-migration-test/rocm-libraries/topics -maxdepth 1 | head -5
cat /tmp/recall-migration-test/rocm-libraries/settings.yaml
```

Expected:
- `/tmp/recall-migration-test/rocm-libraries` no longer has `knowledge/`, `workflows/`, `directives.md`, or `user.md` — only `topics/`, `settings.yaml`, `branches/`, `archive/` (if present).
- `/tmp/recall-migration-test/rocm-libraries/topics/index.md` contains the original 54 lines from `knowledge/index.md` (rocm-libraries had an empty `workflows/index.md`, so nothing appended).
- `/tmp/recall-migration-test/rocm-libraries/settings.yaml` contains the original YAML block (auto-save, promotion, stale-branch-days, etc.) plus `WORKSPACE: /home/AMD/poyechen/workspace/repo/rocm-libraries` (migrated from `user.md`).

- [ ] **Step 5: Inspect the rocisa-attn case specifically (has real prose in both directives.md and user.md)**

```bash
cat /tmp/recall-migration-test/rocisa-attn/settings.yaml
cat /tmp/recall-migration-test/rocisa-attn/topics/_migration-needs-review.md
```

Expected: `settings.yaml` contains the YAML config block plus `WORKSPACE`/`FFM_CONTAINER`/`REFERENCE_REPO` keys (note: `REFERENCE_REPO`'s original value has a trailing parenthetical comment `(MI300/gfx942/wave64 SP3 harness, template to adapt)` — confirm it's preserved verbatim in the value, even though it makes the YAML value a full sentence rather than a clean path; this is expected since the script does no value-cleanup, only key=value -> key: value reformatting). `_migration-needs-review.md` contains the 74-line HARD RULE prose block from `directives.md` and the "Working preferences" section from `user.md`, each under its own migration-source comment marker.

- [ ] **Step 6: Verify the one real flat task file was flagged, not silently dropped**

```bash
find /tmp/recall-migration-test/rocm-libraries/branches/gfx1260-hipblaslt-dev/tasks/import-custom6-kernel -type f
```

Expected: `status.md` (untouched) and `topics/_migration-needs-review.md` (containing the original 78-line knowledge.md content verbatim — confirm with `diff` against the original):
```bash
diff /tmp/recall-migration-test/rocm-libraries/branches/gfx1260-hipblaslt-dev/tasks/import-custom6-kernel/topics/_migration-needs-review.md "$HOME/.local/share/claude/recall/rocm-libraries/branches/gfx1260-hipblaslt-dev/tasks/import-custom6-kernel/knowledge.md"
```
Expected: no output (files identical).

- [ ] **Step 7: Clean up the test copy, commit the script (do NOT run it against the real store yet — that is a user decision, not an automatic step of this plan)**

```bash
rm -rf /tmp/recall-migration-test /tmp/migration-dry-run.log
cd /home/AMD/poyechen/workspace/repo/agent-plugins
git add recall/scripts/migrate-to-topics.sh
git commit -m "feat(recall): add one-time migration script from knowledge/workflows/directives/user.md to topics/+settings.yaml"
```

- [ ] **Step 8: Report to the user that the migration script is ready but not yet run against their real store**

Tell the user: "The migration script `recall/scripts/migrate-to-topics.sh` is committed and verified against a copy of your real store (dry-run + full-run both inspected). It has NOT been run against your actual `~/.local/share/claude/recall/` yet — that's a destructive, one-time operation on your real data. Run it yourself when ready: `recall/scripts/migrate-to-topics.sh ~/.local/share/claude/recall --dry-run` first to preview, then without `--dry-run` to apply. Afterward, review each `topics/_migration-needs-review.md` file it created and split the flagged prose into properly named topics — that step is intentionally manual per the spec."

---

## Post-plan verification (run after all tasks complete)

- [ ] Re-run Task 1's fixture test end-to-end one more time against the final state of `session-start.sh` to confirm no regressions from later tasks (later tasks don't touch `session-start.sh`, so this is a final sanity check, not expected to find anything new).
- [ ] Run `grep -rn "knowledge/\|workflows/\|directives\.md\|user\.md" recall/ --include="*.sh" --include="*.md" | grep -v "_migration-needs-review\|migrate-to-topics.sh\|recall-reorg-workspace"` — expected: no output. (The `recall-reorg-workspace/` eval fixtures are historical benchmark artifacts, explicitly excluded — not part of the active plugin surface.)
