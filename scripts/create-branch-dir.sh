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

[ -z "$PROJECT_DIR" ] || [ -z "$BRANCH" ] || [ -z "$PARENT" ] && {
    echo "Usage: create-branch-dir.sh --project-dir DIR --branch NAME --parent PARENT [--mode full|lightweight]" >&2
    exit 1
}

SANITIZED="$(sanitize_branch_name "$BRANCH")"
BRANCH_DIR="$PROJECT_DIR/branches/$SANITIZED"
HEAD="$(git rev-parse HEAD 2>/dev/null || echo "unknown")"
TODAY="$(date +%Y-%m-%d)"

if [ -f "$BRANCH_DIR/meta.md" ]; then
    exit 0
fi

mkdir -p "$BRANCH_DIR"

cat > "$BRANCH_DIR/meta.md" << EOF
**Branch:** \`$BRANCH\`
**Parent:** \`$PARENT\`
**Created:** $TODAY
**Status:** active
**Mode:** $MODE
**Active Task:** none
**HEAD:** $HEAD
**Project:** $PROJECT_DIR
EOF

if [ "$MODE" = "full" ]; then
    cat > "$BRANCH_DIR/directives.md" << 'EOF'
# Branch Directives
<!-- Branch-level agent behavior rules. Inherits from project-level directives. -->
EOF

    mkdir -p "$BRANCH_DIR/knowledge"
    cat > "$BRANCH_DIR/knowledge/index.md" << 'EOF'
# Branch Knowledge Topics
<!-- New knowledge discovered on this branch. Project-level knowledge is inherited automatically. -->
EOF

    mkdir -p "$BRANCH_DIR/workflows"
    cat > "$BRANCH_DIR/workflows/index.md" << 'EOF'
# Branch Workflow Topics
<!-- New workflows specific to this branch. Project-level workflows are inherited automatically. -->
EOF

    mkdir -p "$BRANCH_DIR/tasks"
fi
