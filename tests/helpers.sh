#!/usr/bin/env bash
# tests/helpers.sh — Minimal test framework for knowledge-management scripts

set -euo pipefail

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TEST_TMPDIR=""

setup_test_env() {
    TEST_TMPDIR="$(mktemp -d)"
    export KNOWLEDGE_ROOT="$TEST_TMPDIR/knowledge"
    # Create a fake git repo for testing
    mkdir -p "$TEST_TMPDIR/repo"
    git -C "$TEST_TMPDIR/repo" init -q
    git -C "$TEST_TMPDIR/repo" remote add origin "https://github.com/example/my-project.git"
    git -C "$TEST_TMPDIR/repo" commit --allow-empty -m "init" -q
}

teardown_test_env() {
    [ -n "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

assert_eq() {
    local expected="$1" actual="$2" msg="${3:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$expected" = "$actual" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "FAIL: $msg"
        echo "  expected: '$expected'"
        echo "  actual:   '$actual'"
    fi
}

assert_file_exists() {
    local path="$1" msg="${2:-$path should exist}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -f "$path" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "FAIL: $msg — file not found: $path"
    fi
}

assert_dir_exists() {
    local path="$1" msg="${2:-$path should exist}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -d "$path" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "FAIL: $msg — dir not found: $path"
    fi
}

assert_file_contains() {
    local path="$1" pattern="$2" msg="${3:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -qP "$pattern" "$path" 2>/dev/null; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "FAIL: $msg — pattern '$pattern' not found in $path"
    fi
}

report_results() {
    echo ""
    echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"
    [ "$TESTS_FAILED" -eq 0 ] && exit 0 || exit 1
}

trap teardown_test_env EXIT
