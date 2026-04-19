#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"
source "$SCRIPT_DIR/../scripts/lib.sh"

setup_test_env

BRANCH_DIR="$TEST_TMPDIR/knowledge/my-project/branches/feature--auth"
mkdir -p "$BRANCH_DIR/tasks"
cat > "$BRANCH_DIR/meta.md" << 'EOF'
**Branch:** `feature/auth`
**Parent:** `develop`
**Created:** 2026-04-19
**Status:** active
**Mode:** full
**Active Task:** none
**HEAD:** abc123
**Project:** /tmp/test/knowledge/my-project
EOF

# --- Create a task ---
"$SCRIPT_DIR/../scripts/create-task-dir.sh" \
    --branch-dir "$BRANCH_DIR" --task "add-login" --goal "Implement login form with JWT authentication"

TASK_DIR="$BRANCH_DIR/tasks/add-login"
assert_dir_exists "$TASK_DIR" "task dir created"
assert_file_exists "$TASK_DIR/status.md" "status.md created"
assert_file_contains "$TASK_DIR/status.md" '# Task: add-login' "status has task name"
assert_file_contains "$TASK_DIR/status.md" '^\*\*Status:\*\*.*active' "status is active"
assert_file_contains "$TASK_DIR/status.md" '^\*\*Branch:\*\*' "status has branch path"
assert_file_contains "$TASK_DIR/status.md" 'JWT authentication' "status has goal"
assert_file_contains "$TASK_DIR/status.md" '## Hypotheses' "status has hypotheses section"

# --- meta.md updated with active task ---
assert_file_contains "$BRANCH_DIR/meta.md" '^\*\*Active Task:\*\*.*add-login' "meta updated with active task"

# --- Idempotent ---
"$SCRIPT_DIR/../scripts/create-task-dir.sh" \
    --branch-dir "$BRANCH_DIR" --task "add-login" --goal "different goal" 2>/dev/null
assert_file_contains "$TASK_DIR/status.md" 'JWT authentication' "idempotent: goal not overwritten"

report_results
