#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"
source "$SCRIPT_DIR/../scripts/lib.sh"

setup_test_env

PROJECT_DIR="$TEST_TMPDIR/knowledge/my-project"
mkdir -p "$PROJECT_DIR"

# --- Full mode branch creation ---
"$SCRIPT_DIR/../scripts/create-branch-dir.sh" \
    --project-dir "$PROJECT_DIR" --branch "feature/auth" --parent "develop" --mode "full"

BRANCH_DIR="$PROJECT_DIR/branches/feature--auth"
assert_dir_exists "$BRANCH_DIR" "branch dir created"
assert_file_exists "$BRANCH_DIR/meta.md" "meta.md created"
assert_file_exists "$BRANCH_DIR/directives.md" "directives.md created"
assert_file_exists "$BRANCH_DIR/knowledge/index.md" "knowledge/index.md created"
assert_file_exists "$BRANCH_DIR/workflows/index.md" "workflows/index.md created"
assert_file_contains "$BRANCH_DIR/meta.md" '^\*\*Branch:\*\*.*feature/auth' "meta has branch name"
assert_file_contains "$BRANCH_DIR/meta.md" '^\*\*Parent:\*\*.*develop' "meta has parent"
assert_file_contains "$BRANCH_DIR/meta.md" '^\*\*Mode:\*\*.*full' "meta has mode"
assert_file_contains "$BRANCH_DIR/meta.md" '^\*\*Project:\*\*' "meta has project path"

# --- Lightweight mode ---
"$SCRIPT_DIR/../scripts/create-branch-dir.sh" \
    --project-dir "$PROJECT_DIR" --branch "fix/typo" --parent "main" --mode "lightweight"

LW_DIR="$PROJECT_DIR/branches/fix--typo"
assert_dir_exists "$LW_DIR" "lightweight branch dir created"
assert_file_exists "$LW_DIR/meta.md" "lightweight meta.md created"
assert_file_contains "$LW_DIR/meta.md" '^\*\*Mode:\*\*.*lightweight' "lightweight mode set"

TESTS_RUN=$((TESTS_RUN + 1))
if [ ! -d "$LW_DIR/knowledge" ] && [ ! -d "$LW_DIR/workflows" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: lightweight branch should not have knowledge/workflows dirs"
fi

# --- Idempotent ---
"$SCRIPT_DIR/../scripts/create-branch-dir.sh" \
    --project-dir "$PROJECT_DIR" --branch "feature/auth" --parent "develop" --mode "full" 2>/dev/null
assert_file_exists "$BRANCH_DIR/meta.md" "idempotent: meta.md still exists"

report_results
