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
