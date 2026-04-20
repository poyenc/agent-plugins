#!/usr/bin/env bash
# scripts/detect-merged.sh — Multi-strategy merged branch detection
# Usage: detect-merged.sh --project-dir DIR --target-branch BRANCH
# Output: one branch name per line (original names, not sanitized)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

PROJECT_DIR="" TARGET_BRANCH=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-dir)    PROJECT_DIR="$2"; shift 2 ;;
        --target-branch)  TARGET_BRANCH="$2"; shift 2 ;;
        *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
done

if [ -z "$PROJECT_DIR" ]; then
    echo "Usage: detect-merged.sh --project-dir DIR --target-branch BRANCH" >&2
    exit 1
fi

if [ -z "$TARGET_BRANCH" ]; then
    echo "Usage: detect-merged.sh --project-dir DIR --target-branch BRANCH" >&2
    exit 1
fi

BRANCHES_DIR="$PROJECT_DIR/branches"
[ -d "$BRANCHES_DIR" ] || exit 0

MERGED=()

# Collect branch names from active (non-archived) branch directories
declare -A TRACKED_BRANCHES
for meta_file in "$BRANCHES_DIR"/*/meta.md; do
    [ -f "$meta_file" ] || continue
    branch_name="$(read_meta_field "$meta_file" "Branch")"
    if [ -z "$branch_name" ]; then
        continue
    fi
    if [ "$(is_default_branch "$branch_name")" = "yes" ]; then
        continue
    fi
    TRACKED_BRANCHES["$branch_name"]="$(dirname "$meta_file")"
done

# Strategy 1: git branch --merged
GIT_MERGED="$(git branch --merged "$TARGET_BRANCH" 2>/dev/null | sed 's/^[* ]*//' || true)"
for branch_name in "${!TRACKED_BRANCHES[@]}"; do
    if echo "$GIT_MERGED" | grep -qxF "$branch_name"; then
        MERGED+=("$branch_name")
        unset "TRACKED_BRANCHES[$branch_name]"
    fi
done

# Strategy 2: gh pr list (for remaining undetected branches)
if command -v gh &>/dev/null && [ ${#TRACKED_BRANCHES[@]} -gt 0 ]; then
    for branch_name in "${!TRACKED_BRANCHES[@]}"; do
        count="$(gh pr list --state merged --head "$branch_name" --json number --jq 'length' 2>/dev/null || echo "0")"
        if [ "$count" -gt 0 ]; then
            MERGED+=("$branch_name")
        fi
    done
fi

# Output merged branches (only if non-empty)
if [ ${#MERGED[@]} -gt 0 ]; then
    printf '%s\n' "${MERGED[@]}"
fi
