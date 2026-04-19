#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

BRANCH_DIR="" TASK="" GOAL=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --branch-dir) BRANCH_DIR="$2"; shift 2 ;;
        --task)       TASK="$2"; shift 2 ;;
        --goal)       GOAL="$2"; shift 2 ;;
        *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
done

[ -z "$BRANCH_DIR" ] || [ -z "$TASK" ] && {
    echo "Usage: create-task-dir.sh --branch-dir DIR --task NAME --goal 'description'" >&2
    exit 1
}

TASK_DIR="$BRANCH_DIR/tasks/$TASK"
TODAY="$(date +%Y-%m-%d)"

if [ -f "$TASK_DIR/status.md" ]; then
    exit 0
fi

mkdir -p "$TASK_DIR"

cat > "$TASK_DIR/status.md" << EOF
# Task: $TASK

**Status:** active
**Created:** $TODAY
**Branch:** $BRANCH_DIR

## Goal
$GOAL

## Progress

## Next Steps

## Hypotheses
EOF

write_meta_field "$BRANCH_DIR/meta.md" "Active Task" "$TASK"
