#!/usr/bin/env bash
# scripts/migrate.sh — Migrate from old knowledge structure to new
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

OLD_ROOT="${1:-$HOME/.claude/notes}"
NEW_ROOT="$(resolve_storage_root)"

echo "Migration: $OLD_ROOT -> $NEW_ROOT"
echo ""

for project_dir in "$OLD_ROOT"/*/; do
    if [ ! -d "$project_dir" ]; then
        continue
    fi
    project="$(basename "$project_dir")"
    new_project="$NEW_ROOT/$project"

    echo "Project: $project"

    if [ -d "$new_project/knowledge" ]; then
        echo "  Already migrated (knowledge/ dir exists). Skipping."
        continue
    fi

    mkdir -p "$new_project"

    # Migrate knowledge.md -> knowledge/general.md
    if [ -f "$project_dir/knowledge.md" ]; then
        mkdir -p "$new_project/knowledge"
        cp "$project_dir/knowledge.md" "$new_project/knowledge/general.md"
        cat > "$new_project/knowledge/index.md" << EOF
# Knowledge Topics

- [general.md](general.md) -- Migrated from monolithic knowledge.md. Split into focused topics as needed.
EOF
        echo "  Migrated knowledge.md -> knowledge/general.md"
    else
        mkdir -p "$new_project/knowledge"
        echo "# Knowledge Topics" > "$new_project/knowledge/index.md"
    fi

    # Migrate workflows.md -> workflows/general.md
    if [ -f "$project_dir/workflows.md" ]; then
        mkdir -p "$new_project/workflows"
        cp "$project_dir/workflows.md" "$new_project/workflows/general.md"
        cat > "$new_project/workflows/index.md" << EOF
# Workflow Topics

- [general.md](general.md) -- Migrated from monolithic workflows.md. Split into focused topics as needed.
EOF
        echo "  Migrated workflows.md -> workflows/general.md"
    else
        mkdir -p "$new_project/workflows"
        echo "# Workflow Topics" > "$new_project/workflows/index.md"
    fi

    # Create directives.md with default config
    if [ ! -f "$new_project/directives.md" ]; then
        cat > "$new_project/directives.md" << 'EOF'
# Project Directives

## Configuration

```yaml
auto-save:
  auto: [hardware findings, build errors, debugging root causes, API behaviors]
  ask: [coding conventions, architecture decisions]
  never: [temporary workarounds, debugging session logs]
  default: auto
promotion: auto
stale-branch-days: 30
default-branch: develop
confidence-min: observed
```
EOF
        echo "  Created directives.md with default config"
    fi

    # Copy user.md if exists
    if [ -f "$project_dir/user.md" ]; then
        cp "$project_dir/user.md" "$new_project/user.md"
        echo "  Copied user.md"
    fi

    # Migrate tasks into branches
    if [ -d "$project_dir/tasks" ]; then
        for task_dir in "$project_dir/tasks"/*/; do
            if [ ! -d "$task_dir" ]; then
                continue
            fi
            task="$(basename "$task_dir")"

            branch=""
            if [ -f "$task_dir/status.md" ]; then
                branch="$(grep -oP '^\*\*Branch:\*\*\s*\`\K[^\`]+' "$task_dir/status.md" 2>/dev/null || true)"
            fi

            if [ -z "$branch" ]; then
                echo "  Task '$task': no branch found in status.md, placing under 'unknown' branch"
                branch="unknown"
            fi

            sanitized="$(sanitize_branch_name "$branch")"
            branch_dir="$new_project/branches/$sanitized"

            if [ ! -f "$branch_dir/meta.md" ]; then
                "$SCRIPT_DIR/create-branch-dir.sh" \
                    --project-dir "$new_project" \
                    --branch "$branch" \
                    --parent "unknown" \
                    --mode "full" 2>/dev/null || true
            fi

            new_task_dir="$branch_dir/tasks/$task"
            mkdir -p "$new_task_dir"
            for f in status.md knowledge.md workflows.md; do
                if [ -f "$task_dir/$f" ]; then
                    cp "$task_dir/$f" "$new_task_dir/$f"
                fi
            done
            echo "  Migrated task '$task' -> branches/$sanitized/tasks/$task"
        done
    fi

    echo ""
done

echo "Migration complete. Old files preserved at $OLD_ROOT"
echo "Review the new structure at $NEW_ROOT and split general.md topics as needed."
