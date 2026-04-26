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

# Collapse user.md to inline format: env: K=V K=V | prefs: a, b, c
strip_user_boilerplate() {
    local in_code=0 env_vars="" prefs="" notes="" section=""
    while IFS= read -r line; do
        # Track sections
        if [[ "$line" =~ ^##[[:space:]]+(.*) ]]; then
            section="${BASH_REMATCH[1],,}"; continue
        fi
        [[ "$line" =~ ^#\  ]] && continue
        [[ "$line" =~ ^Copy\ this\ file ]] && continue
        [[ "$line" =~ ^Add\ any\ personal ]] && continue
        if [[ "$line" =~ ^\`\`\` ]]; then
            in_code=$(( 1 - in_code )); continue
        fi
        [[ -z "$line" ]] && continue
        case "$section" in
            environment*)
                # Collect KEY=VALUE assignments, skip bash comments
                if [[ "$line" =~ ^[A-Z_]+= ]]; then
                    env_vars+="${line} "
                fi
                ;;
            preference*)
                # Strip leading "- " and collect
                local pref="${line#- }"
                prefs+="${prefs:+, }${pref}"
                ;;
            note*)
                notes+="${notes:+; }${line#- }"
                ;;
            *)
                # Unknown section — pass through as prefs
                if [[ "$line" =~ ^-\  ]]; then
                    local item="${line#- }"
                    prefs+="${prefs:+, }${item}"
                fi
                ;;
        esac
    done
    [ -n "$env_vars" ] && echo "env: ${env_vars% }"
    [ -n "$prefs" ] && echo "prefs: $prefs"
    [ -n "$notes" ] && echo "notes: $notes"
}

# Collapse YAML config block: auto-save → single line, other keys → single line, strip headings/fences/blanks
compact_directives() {
    local in_yaml=0 in_auto_save=0 auto_save_parts="" other_keys="" in_maintenance=0 maintenance_parts=""
    while IFS= read -r line; do
        [[ "$line" =~ ^#+\  ]] && continue
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ ^\`\`\` ]]; then
            if [ $in_yaml -eq 0 ]; then in_yaml=1; else
                # End of YAML — flush accumulated config
                [ -n "$auto_save_parts" ] && echo "auto-save: $auto_save_parts"
                [ -n "$maintenance_parts" ] && echo "maintenance: $maintenance_parts"
                [ -n "$other_keys" ] && echo "${other_keys# }"
                auto_save_parts=""; maintenance_parts=""; other_keys=""; in_yaml=0
            fi
            continue
        fi
        if [ $in_yaml -eq 1 ]; then
            if [[ "$line" =~ ^auto-save: ]]; then in_auto_save=1; continue; fi
            if [ $in_auto_save -eq 1 ]; then
                if [[ "$line" =~ ^[[:space:]]+(auto|ask|never|default):[[:space:]]*(.*) ]]; then
                    auto_save_parts+="${BASH_REMATCH[1]}=${BASH_REMATCH[2]} "
                    continue
                else
                    in_auto_save=0
                fi
            fi
            # Handle maintenance: nested block
            if [[ "$line" =~ ^maintenance: ]]; then in_maintenance=1; continue; fi
            if [ $in_maintenance -eq 1 ]; then
                if [[ "$line" =~ ^[[:space:]]+([-a-z]+):[[:space:]]*(.*) ]]; then
                    local mkey="${BASH_REMATCH[1]}"
                    mkey="${mkey%-lines}"
                    maintenance_parts+="${mkey}=${BASH_REMATCH[2]} "
                    continue
                else
                    in_maintenance=0
                fi
            fi
            # Accumulate other config keys on one line
            other_keys+=" $line"
        else
            echo "$line"
        fi
    done
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

# Collect file paths for session-start reading checklist
PROJECT_READS=""
BRANCH_READS=""
TASK_READS=""
collect_read() {
    local filepath="$1" scope="$2"  # scope: project, branch, or task
    if [ -f "$filepath" ] && has_real_content "$filepath"; then
        case "$scope" in
            project) PROJECT_READS="${PROJECT_READS}   - ${filepath}\n" ;;
            branch)  BRANCH_READS="${BRANCH_READS}   - ${filepath}\n" ;;
            task)    TASK_READS="${TASK_READS}   - ${filepath}\n" ;;
        esac
    fi
}

# Check if file has content beyond headings, HTML comments, and whitespace
has_real_content() {
    grep -qP '^(?!#|\s*$|<!--)' "$1" 2>/dev/null
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

# --- Project-level knowledge (directives and user inline, indexes as refs) ---
emit_file "$PROJECT_DIR/directives.md"       "Project Directives ($PROJECT)" "compact_directives"
emit_file "$PROJECT_DIR/user.md"             "User Profile ($PROJECT)" "strip_user_boilerplate"
if [ -d "$PROJECT_DIR/knowledge" ]; then
    collect_read "$PROJECT_DIR/knowledge/index.md" "project"
else
    collect_read "$PROJECT_DIR/knowledge.md" "project"
fi
if [ -d "$PROJECT_DIR/workflows" ]; then
    collect_read "$PROJECT_DIR/workflows/index.md" "project"
else
    collect_read "$PROJECT_DIR/workflows.md" "project"
fi

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

emit_file "$BRANCH_DIR/meta.md"              "Branch: $BRANCH" "compact_meta"
collect_read "$BRANCH_DIR/directives.md"      "branch"
if [ -d "$BRANCH_DIR/knowledge" ]; then
    collect_read "$BRANCH_DIR/knowledge/index.md" "branch"
else
    collect_read "$BRANCH_DIR/knowledge.md" "branch"
fi
if [ -d "$BRANCH_DIR/workflows" ]; then
    collect_read "$BRANCH_DIR/workflows/index.md" "branch"
else
    collect_read "$BRANCH_DIR/workflows.md" "branch"
fi
collect_read "$BRANCH_DIR/user.md"            "branch"

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
        if [ -d "$TASK_DIR/knowledge" ]; then
            collect_read "$TASK_DIR/knowledge/index.md" "task"
        else
            collect_read "$TASK_DIR/knowledge.md" "task"
        fi
        if [ -d "$TASK_DIR/workflows" ]; then
            collect_read "$TASK_DIR/workflows/index.md" "task"
        else
            collect_read "$TASK_DIR/workflows.md" "task"
        fi
    fi
fi

# --- Maintenance alerts ---
if [ -n "${TASK_DIR:-}" ] && [ -d "${TASK_DIR:-}" ]; then
    _max_s=$(sed -n 's/^[[:space:]]*status-max-lines:[[:space:]]*//p' \
             "$PROJECT_DIR/directives.md" 2>/dev/null)
    _max_k=$(sed -n 's/^[[:space:]]*task-knowledge-split-lines:[[:space:]]*//p' \
             "$PROJECT_DIR/directives.md" 2>/dev/null)
    # Check for compact-needed marker
    if [ -f "$TASK_DIR/status.md" ] && head -1 "$TASK_DIR/status.md" | grep -q 'maintenance:.*compact needed'; then
        echo "Maintenance: status.md marked for compaction. Compact before starting new work."
    elif [ -f "$TASK_DIR/status.md" ]; then
        _sl=$(wc -l < "$TASK_DIR/status.md")
        [ "$_sl" -gt "${_max_s:-150}" ] 2>/dev/null && \
            echo "Maintenance: status.md ${_sl} lines (limit ${_max_s:-150}). Compact before starting new work: move details to knowledge topics."
    fi
    if [ -f "$TASK_DIR/knowledge.md" ] && ! head -1 "$TASK_DIR/knowledge.md" | grep -q 'split into'; then
        _kl=$(wc -l < "$TASK_DIR/knowledge.md")
        [ "$_kl" -gt "${_max_k:-150}" ] 2>/dev/null && \
            echo "Maintenance: knowledge.md ${_kl} lines (limit ${_max_k:-150}). Split into knowledge/ directory."
    fi
fi

# --- Session Start checklist ---
_step=1
_has_checklist=""
if [ -n "$PROJECT_READS" ]; then
    [ -z "$_has_checklist" ] && echo "## Session Start" && _has_checklist=1
    echo "${_step}. Read project knowledge and workflows:"
    printf '%b' "$PROJECT_READS"
    _step=$((_step + 1))
fi
if [ -n "$BRANCH_READS" ]; then
    [ -z "$_has_checklist" ] && echo "## Session Start" && _has_checklist=1
    echo "${_step}. Read branch knowledge and workflows:"
    printf '%b' "$BRANCH_READS"
    _step=$((_step + 1))
fi
if [ -n "$TASK_READS" ]; then
    [ -z "$_has_checklist" ] && echo "## Session Start" && _has_checklist=1
    echo "${_step}. Read active task knowledge and workflows:"
    printf '%b' "$TASK_READS"
    _step=$((_step + 1))
fi
if [ -n "$_has_checklist" ]; then
    echo "${_step}. From each index, read topic files relevant to the user's request (use the index file's directory as base path)."
    echo ""
fi

cat << 'RULES'
Recall-save: Save only [VERIFIED]/[OBSERVED] facts; hypotheses → status.md. Fix vague/stale/contradicted content on read.
RULES
