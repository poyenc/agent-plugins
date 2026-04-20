#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

PROJECT_DIR="" BRANCH="" PARENT="" MODE="full"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-dir) PROJECT_DIR="$2"; shift 2 ;;
        --branch)      BRANCH="$2"; shift 2 ;;
        --parent)      PARENT="$2"; shift 2 ;;
        --mode)        MODE="$2"; shift 2 ;;
        *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
done

if [ -z "$PROJECT_DIR" ] || [ -z "$BRANCH" ] || [ -z "$PARENT" ]; then
    echo "Usage: create-branch-dir.sh --project-dir DIR --branch NAME --parent PARENT [--mode full|lightweight]" >&2
    exit 1
fi

if [[ "$MODE" != "full" && "$MODE" != "lightweight" ]]; then
    echo "Error: --mode must be 'full' or 'lightweight' (got: '$MODE')" >&2
    exit 1
fi

SANITIZED="$(sanitize_branch_name "$BRANCH")"
BRANCH_DIR="$PROJECT_DIR/branches/$SANITIZED"
HEAD="$(git rev-parse HEAD 2>/dev/null || echo "unknown")"
TODAY="$(date +%Y-%m-%d)"

if [ -f "$BRANCH_DIR/meta.md" ]; then
    exit 0
fi

mkdir -p "$BRANCH_DIR"

cat > "$BRANCH_DIR/meta.md" << EOF
**Parent:** \`$PARENT\`
**Created:** $TODAY
**Status:** active
**Mode:** $MODE
**Active Task:** none
EOF

if [ "$MODE" = "full" ]; then
    touch "$BRANCH_DIR/directives.md"

    mkdir -p "$BRANCH_DIR/knowledge"
    touch "$BRANCH_DIR/knowledge/index.md"

    mkdir -p "$BRANCH_DIR/workflows"
    touch "$BRANCH_DIR/workflows/index.md"

    mkdir -p "$BRANCH_DIR/tasks"
fi
