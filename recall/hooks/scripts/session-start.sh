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

# --- Helper: emit a file's content with a header, skip if missing/empty ---
emit_file() {
    local filepath="$1" label="$2"
    if [ -f "$filepath" ] && [ -s "$filepath" ]; then
        echo "=== $label ==="
        cat "$filepath"
        echo ""
    fi
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

# --- Project-level knowledge (always loaded) ---
emit_file "$PROJECT_DIR/directives.md"       "Project Directives ($PROJECT)"
emit_file "$PROJECT_DIR/user.md"             "User Profile ($PROJECT)"
emit_file "$PROJECT_DIR/knowledge/index.md"  "Project Knowledge Index ($PROJECT)"
emit_file "$PROJECT_DIR/workflows/index.md"  "Project Workflows Index ($PROJECT)"

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

# --- Branch-level knowledge ---
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

emit_file "$BRANCH_DIR/meta.md"              "Branch Meta ($BRANCH)"
emit_file "$BRANCH_DIR/directives.md"        "Branch Directives ($BRANCH)"
emit_file "$BRANCH_DIR/knowledge/index.md"   "Branch Knowledge Index ($BRANCH)"
emit_file "$BRANCH_DIR/workflows/index.md"   "Branch Workflows Index ($BRANCH)"
emit_file "$BRANCH_DIR/user.md"              "Branch User Notes ($BRANCH)"

# --- Active task knowledge ---
if [ -f "$BRANCH_DIR/meta.md" ]; then
    ACTIVE_TASK=""
    if [ -f "$LIB" ]; then
        ACTIVE_TASK="$(read_meta_field "$BRANCH_DIR/meta.md" "Active Task")"
    else
        ACTIVE_TASK="$(grep -oP '^\*\*Active Task:\*\*\s*`\K[^`]+' "$BRANCH_DIR/meta.md" 2>/dev/null | head -1)"
    fi

    if [ -n "$ACTIVE_TASK" ] && [ "$ACTIVE_TASK" != "none" ]; then
        TASK_DIR="$BRANCH_DIR/tasks/$ACTIVE_TASK"
        emit_file "$TASK_DIR/status.md"      "Active Task Status ($ACTIVE_TASK)"
        emit_file "$TASK_DIR/knowledge.md"   "Active Task Knowledge ($ACTIVE_TASK)"
        emit_file "$TASK_DIR/workflows.md"   "Active Task Workflows ($ACTIVE_TASK)"
    fi
fi

cat << 'RULES'

## Recall Rules
- Follow auto-save categories in directives above (auto/ask/never). Default: auto.
- Only save [VERIFIED] or [OBSERVED] facts. Hypotheses → status.md.
- Load topic files from indexes on demand — don't read everything upfront.
- Before completing a task, review conversation for unsaved findings.
RULES
