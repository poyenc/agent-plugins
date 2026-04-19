#!/usr/bin/env bash
# tests/test-lib.sh — Tests for shared library functions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"
source "$SCRIPT_DIR/../scripts/lib.sh"

setup_test_env

# --- sanitize_branch_name ---
assert_eq "poyenc--batch-prefill-v3" "$(sanitize_branch_name "poyenc/batch-prefill-v3")" "sanitize: slash replaced with --"
assert_eq "feature--auth" "$(sanitize_branch_name "feature/auth")" "sanitize: single slash"
assert_eq "main" "$(sanitize_branch_name "main")" "sanitize: no slash unchanged"
assert_eq "a--b--c" "$(sanitize_branch_name "a/b/c")" "sanitize: multiple slashes"

# --- detect_project_name ---
assert_eq "my-project" "$(cd "$TEST_TMPDIR/repo" && detect_project_name)" "detect_project: extracts repo name from origin URL"
git -C "$TEST_TMPDIR/repo" remote set-url origin "git@github.com:org/another-repo.git"
assert_eq "another-repo" "$(cd "$TEST_TMPDIR/repo" && detect_project_name)" "detect_project: handles SSH URL with .git suffix"
git -C "$TEST_TMPDIR/repo" remote set-url origin "https://github.com/example/my-project.git"

# --- resolve_storage_root ---
unset KNOWLEDGE_ROOT
assert_eq "$HOME/.local/share/claude/knowledge" "$(resolve_storage_root)" "storage_root: defaults to XDG data dir"
export KNOWLEDGE_ROOT="$TEST_TMPDIR/custom-root"
assert_eq "$TEST_TMPDIR/custom-root" "$(resolve_storage_root)" "storage_root: uses KNOWLEDGE_ROOT env var"

# --- resolve_project_dir ---
assert_eq "$TEST_TMPDIR/custom-root/my-project" "$(cd "$TEST_TMPDIR/repo" && resolve_project_dir)" "project_dir: storage_root/project_name"

# --- resolve_branch_dir ---
assert_eq "$TEST_TMPDIR/custom-root/my-project/branches/feature--auth" "$(resolve_branch_dir "$TEST_TMPDIR/custom-root/my-project" "feature/auth")" "branch_dir: project/branches/sanitized"

# --- is_default_branch ---
assert_eq "yes" "$(is_default_branch "main")" "is_default: main"
assert_eq "yes" "$(is_default_branch "develop")" "is_default: develop"
assert_eq "yes" "$(is_default_branch "master")" "is_default: master"
assert_eq "no" "$(is_default_branch "feature/auth")" "is_default: feature branch"

# --- read_meta_field ---
mkdir -p "$TEST_TMPDIR/test-branch"
cat > "$TEST_TMPDIR/test-branch/meta.md" << 'METAEOF'
**Branch:** `poyenc/batch-prefill-v3`
**Parent:** `develop`
**Created:** 2026-04-19
**Status:** active
**Mode:** full
**Active Task:** xnack-fix
**HEAD:** a1b2c3d
**Project:** /tmp/test/knowledge/aiter
METAEOF

assert_eq "poyenc/batch-prefill-v3" "$(read_meta_field "$TEST_TMPDIR/test-branch/meta.md" "Branch")" "read_meta: Branch field"
assert_eq "develop" "$(read_meta_field "$TEST_TMPDIR/test-branch/meta.md" "Parent")" "read_meta: Parent field"
assert_eq "xnack-fix" "$(read_meta_field "$TEST_TMPDIR/test-branch/meta.md" "Active Task")" "read_meta: Active Task field"
assert_eq "full" "$(read_meta_field "$TEST_TMPDIR/test-branch/meta.md" "Mode")" "read_meta: Mode field"

# --- read_meta_field with bare (non-backtick) values ---
cat > "$TEST_TMPDIR/test-branch/status.md" << 'STATUSEOF'
**Status:** active
**Branch:** /tmp/test/knowledge/aiter/branches/poyenc--batch-prefill-v3
STATUSEOF

assert_eq "active" "$(read_meta_field "$TEST_TMPDIR/test-branch/status.md" "Status")" "read_meta: bare value (no backticks)"
assert_eq "/tmp/test/knowledge/aiter/branches/poyenc--batch-prefill-v3" "$(read_meta_field "$TEST_TMPDIR/test-branch/status.md" "Branch")" "read_meta: bare path value"

report_results
