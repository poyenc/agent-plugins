#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"
source "$SCRIPT_DIR/../scripts/lib.sh"

setup_test_env

REPO="$TEST_TMPDIR/repo"
# Ensure default branch is named "main" regardless of system config
git -C "$REPO" branch -M main -q 2>/dev/null || true

PROJECT_DIR="$TEST_TMPDIR/knowledge/my-project"
mkdir -p "$PROJECT_DIR/branches"

# Create a feature branch, commit, merge it
git -C "$REPO" checkout -b feature/merged-one -q
git -C "$REPO" commit --allow-empty -m "feature work" -q
git -C "$REPO" checkout main -q
git -C "$REPO" merge feature/merged-one -q --no-edit

# Create matching knowledge directory
mkdir -p "$PROJECT_DIR/branches/feature--merged-one"
cat > "$PROJECT_DIR/branches/feature--merged-one/meta.md" << 'EOF'
**Branch:** `feature/merged-one`
**Parent:** `main`
**Status:** active
EOF

# Create an unmerged branch with knowledge dir
git -C "$REPO" checkout -b feature/not-merged -q
git -C "$REPO" commit --allow-empty -m "wip" -q
git -C "$REPO" checkout main -q

mkdir -p "$PROJECT_DIR/branches/feature--not-merged"
cat > "$PROJECT_DIR/branches/feature--not-merged/meta.md" << 'EOF'
**Branch:** `feature/not-merged`
**Parent:** `main`
**Status:** active
EOF

# Run detection
RESULT="$(cd "$REPO" && "$SCRIPT_DIR/../scripts/detect-merged.sh" \
    --project-dir "$PROJECT_DIR" --target-branch "main")"

# Should detect merged-one
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$RESULT" | grep -q "feature/merged-one"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: should detect feature/merged-one as merged"
    echo "  output: '$RESULT'"
fi

# Should NOT detect not-merged
TESTS_RUN=$((TESTS_RUN + 1))
if ! echo "$RESULT" | grep -q "feature/not-merged"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: should not detect feature/not-merged as merged"
fi

# Empty output when no branches dir
EMPTY_PROJECT="$TEST_TMPDIR/knowledge/empty-project"
mkdir -p "$EMPTY_PROJECT"
EMPTY_RESULT="$(cd "$REPO" && "$SCRIPT_DIR/../scripts/detect-merged.sh" \
    --project-dir "$EMPTY_PROJECT" --target-branch "main" 2>/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
if [ -z "$EMPTY_RESULT" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: should produce empty output when no branches dir"
fi

report_results
