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

# Strip boilerplate from user.md: remove template comments, empty section headers,
# "Copy this file to..." lines, and "Add any personal notes" lines
strip_user_boilerplate() {
    sed -E '/^# User Preferences/d;
            /^Copy this file to/d;
            /^Add any personal notes/d;
            /^## Notes\s*$/d' | \
    sed -E '/^```bash$/,/^```$/{/^# /d}' | \
    sed -E '/^\s*$/N;/^\n\s*$/d'
}

# Collapse YAML config block to compact key=value lines, strip headings/fences/blanks
compact_directives() {
    local in_yaml=0 in_auto_save=0
    while IFS= read -r line; do
        # Skip markdown headings
        [[ "$line" =~ ^#+\  ]] && continue
        # Skip blank lines
        [[ -z "$line" ]] && continue
        # Detect YAML fence boundaries
        if [[ "$line" =~ ^\`\`\` ]]; then
            if [ $in_yaml -eq 0 ]; then in_yaml=1; else in_yaml=0; fi
            continue
        fi
        if [ $in_yaml -eq 1 ]; then
            # auto-save sub-keys: flatten to dotted notation
            if [[ "$line" =~ ^auto-save: ]]; then
                in_auto_save=1; continue
            fi
            if [ $in_auto_save -eq 1 ]; then
                if [[ "$line" =~ ^[[:space:]]+(auto|ask|never|default):[[:space:]]*(.*) ]]; then
                    echo "auto-save.${BASH_REMATCH[1]}: ${BASH_REMATCH[2]}"
                    continue
                else
                    in_auto_save=0
                fi
            fi
            # Other top-level config keys
            echo "$line"
        else
            # Non-YAML content (rules, etc.) — pass through
            echo "$line"
        fi
    done
}

# Strip redundant fields from meta.md (Branch, HEAD, Project are in gitStatus/env)
strip_meta_redundant() {
    grep -vP '^\*\*(Branch|HEAD|Project):\*\*'
}

# Collect a file path for on-demand loading (appends to ON_DEMAND_REFS)
ON_DEMAND_REFS=""
emit_ref() {
    local filepath="$1" label="$2"
    if [ -f "$filepath" ] && has_real_content "$filepath"; then
        if [ -n "$ON_DEMAND_REFS" ]; then
            ON_DEMAND_REFS="${ON_DEMAND_REFS}, ${label}=${filepath}"
        else
            ON_DEMAND_REFS="${label}=${filepath}"
        fi
    fi
}

# Check if file has content beyond headings, HTML comments, and whitespace
has_real_content() {
    grep -qP '^(?!#|\s*$|<!--)' "$1" 2>/dev/null
}

# Emit a compact task summary instead of the full status.md
emit_task_summary() {
    local task_dir="$1" task_name="$2"
    local status_file="$task_dir/status.md"
    [ -f "$status_file" ] || return
    local goal status
    goal="$(sed -n '/^## Goal/,/^##/{/^## Goal/d;/^##/d;/^\s*$/d;p;q}' "$status_file" 2>/dev/null)"
    status="$(grep -oP '^\*\*Status:\*\*\s*\K.+' "$status_file" 2>/dev/null | head -1)"
    echo "=== Active Task: $task_name ==="
    [ -n "$status" ] && echo "Status: $status"
    [ -n "$goal" ] && echo "Goal: $goal"
    echo "Details: $status_file"
    echo ""
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

# --- Project-level knowledge (directives and user inline, indexes as refs) ---
emit_file "$PROJECT_DIR/directives.md"       "Project Directives ($PROJECT)" "compact_directives"
emit_file "$PROJECT_DIR/user.md"             "User Profile ($PROJECT)" "strip_user_boilerplate"
emit_ref  "$PROJECT_DIR/knowledge/index.md"  "Project Knowledge Index"
emit_ref  "$PROJECT_DIR/workflows/index.md"  "Project Workflows Index"

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

emit_file "$BRANCH_DIR/meta.md"              "Branch Meta ($BRANCH)" "strip_meta_redundant"
emit_ref  "$BRANCH_DIR/directives.md"        "Branch Directives"
emit_ref  "$BRANCH_DIR/knowledge/index.md"   "Branch Knowledge Index"
emit_ref  "$BRANCH_DIR/workflows/index.md"   "Branch Workflows Index"
emit_ref  "$BRANCH_DIR/user.md"              "Branch User Notes"

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
        emit_task_summary "$TASK_DIR" "$ACTIVE_TASK"
        emit_ref "$TASK_DIR/knowledge.md"   "Active Task Knowledge"
        emit_ref "$TASK_DIR/workflows.md"   "Active Task Workflows"
    fi
fi

# --- On-demand file references (compact format) ---
if [ -n "$ON_DEMAND_REFS" ]; then
    echo "On-demand: $ON_DEMAND_REFS"
fi

cat << 'RULES'
Recall: save only [VERIFIED]/[OBSERVED] facts; hypotheses → status.md. Load topic files from indexes on demand.
RULES
