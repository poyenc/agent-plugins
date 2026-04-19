#!/usr/bin/env bash
# tests/test-integration.sh — End-to-end scenario tests

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"
source "$SCRIPT_DIR/../scripts/lib.sh"

setup_test_env

REPO="$TEST_TMPDIR/repo"
export KNOWLEDGE_ROOT="$TEST_TMPDIR/knowledge"

# Ensure default branch is named "main" regardless of system config
git -C "$REPO" branch -M main -q 2>/dev/null || true

# === Scenario 1: Full lifecycle ===
echo "=== Scenario 1: Full lifecycle ==="

PROJECT_DIR="$KNOWLEDGE_ROOT/my-project"
mkdir -p "$PROJECT_DIR/knowledge" "$PROJECT_DIR/workflows"
echo "# Knowledge Topics" > "$PROJECT_DIR/knowledge/index.md"
echo "# Workflow Topics" > "$PROJECT_DIR/workflows/index.md"
cat > "$PROJECT_DIR/directives.md" << 'EOF'
# Directives
## Configuration
```yaml
auto-save:
  default: auto
promotion: auto
stale-branch-days: 30
default-branch: main
confidence-min: observed
```
EOF

assert_file_exists "$PROJECT_DIR/directives.md" "project directives created"
assert_file_exists "$PROJECT_DIR/knowledge/index.md" "project knowledge index created"

# Create a feature branch
cd "$REPO"
git checkout -b feature/auth -q

"$SCRIPT_DIR/../scripts/create-branch-dir.sh" \
    --project-dir "$PROJECT_DIR" --branch "feature/auth" --parent "main" --mode "full"

BRANCH_DIR="$PROJECT_DIR/branches/feature--auth"
assert_dir_exists "$BRANCH_DIR" "branch dir created"
assert_file_contains "$BRANCH_DIR/meta.md" 'feature/auth' "branch name in meta"

# Create a task
"$SCRIPT_DIR/../scripts/create-task-dir.sh" \
    --branch-dir "$BRANCH_DIR" --task "add-login" --goal "Implement login endpoint"

assert_dir_exists "$BRANCH_DIR/tasks/add-login" "task dir created"
assert_file_contains "$BRANCH_DIR/meta.md" 'add-login' "active task updated"

# Create a second task
"$SCRIPT_DIR/../scripts/create-task-dir.sh" \
    --branch-dir "$BRANCH_DIR" --task "add-signup" --goal "Implement signup endpoint"

assert_dir_exists "$BRANCH_DIR/tasks/add-signup" "second task created"
assert_file_contains "$BRANCH_DIR/meta.md" 'add-signup' "active task is latest"

# === Scenario 2: Lightweight branch ===
echo "=== Scenario 2: Lightweight branch ==="

"$SCRIPT_DIR/../scripts/create-branch-dir.sh" \
    --project-dir "$PROJECT_DIR" --branch "fix/typo" --parent "main" --mode "lightweight"

LW_DIR="$PROJECT_DIR/branches/fix--typo"
assert_file_exists "$LW_DIR/meta.md" "lightweight meta exists"
assert_file_contains "$LW_DIR/meta.md" 'lightweight' "lightweight mode"

TESTS_RUN=$((TESTS_RUN + 1))
if [ ! -d "$LW_DIR/knowledge" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: lightweight should not have knowledge dir"
fi

# === Scenario 3: Merge detection ===
echo "=== Scenario 3: Merge detection ==="

git checkout main -q
git merge feature/auth -q --no-edit 2>/dev/null

MERGED="$(cd "$REPO" && "$SCRIPT_DIR/../scripts/detect-merged.sh" \
    --project-dir "$PROJECT_DIR" --target-branch "main")"

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$MERGED" | grep -q "feature/auth"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: should detect feature/auth as merged"
    echo "  output: '$MERGED'"
fi

# === Scenario 4: Branch name sanitization edge cases ===
echo "=== Scenario 4: Sanitization edge cases ==="

assert_eq "user--org--feature--deep" \
    "$(sanitize_branch_name "user/org/feature/deep")" \
    "sanitize: deep nesting"

assert_eq "simple-branch" \
    "$(sanitize_branch_name "simple-branch")" \
    "sanitize: no slash"

# === Scenario 5: write_meta_field updates correctly ===
echo "=== Scenario 5: write_meta_field ==="

write_meta_field "$BRANCH_DIR/meta.md" "Active Task" "new-task"
assert_file_contains "$BRANCH_DIR/meta.md" 'new-task' "write_meta_field updated active task"

write_meta_field "$BRANCH_DIR/meta.md" "Active Task" "none"
assert_file_contains "$BRANCH_DIR/meta.md" 'none' "write_meta_field set to none"

report_results
