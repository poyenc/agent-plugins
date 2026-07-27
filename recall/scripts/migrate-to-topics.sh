#!/usr/bin/env bash
# scripts/migrate-to-topics.sh — one-time migration of an existing recall store
# from the old knowledge/+workflows/+directives.md+user.md layout to the new
# unified topics/+settings.yaml layout. Run once, by hand, against a real store.
#
# Usage: migrate-to-topics.sh <recall-root> [--dry-run]
#   <recall-root>  e.g. ~/.local/share/claude/recall
#   --dry-run      print planned actions without touching any file

set -euo pipefail

ROOT="${1:?usage: migrate-to-topics.sh <recall-root> [--dry-run]}"
DRY_RUN="${2:-}"

[ -d "$ROOT" ] || { echo "error: not a directory: $ROOT" >&2; exit 1; }

run() {
    if [ "$DRY_RUN" = "--dry-run" ]; then
        echo "[dry-run] $*"
    else
        "$@"
    fi
}

# Merge workflows/index.md content into knowledge/index.md, rename knowledge/ -> topics/
migrate_level_dir() {
    local level_dir="$1"
    local kd="$level_dir/knowledge" wd="$level_dir/workflows" td="$level_dir/topics"

    [ -d "$kd" ] || [ -d "$wd" ] || return 0
    echo "=== $level_dir ==="

    if [ -d "$kd" ]; then
        run mkdir -p "$td"
        for f in "$kd"/*.md; do
            [ -f "$f" ] || continue
            base="$(basename "$f")"
            if [ "$base" = "index.md" ]; then
                run cp "$f" "$td/index.md"
            else
                run mv "$f" "$td/$base"
            fi
        done
        run rmdir "$kd" 2>/dev/null || true
    else
        run mkdir -p "$td"
        run touch "$td/index.md"
    fi

    if [ -d "$wd" ]; then
        for f in "$wd"/*.md; do
            [ -f "$f" ] || continue
            base="$(basename "$f")"
            if [ "$base" = "index.md" ]; then
                if [ -s "$f" ]; then
                    echo "  appending $f content into $td/index.md"
                    if [ "$DRY_RUN" != "--dry-run" ]; then
                        { echo ""; cat "$f"; } >> "$td/index.md"
                    fi
                fi
            else
                run mv "$f" "$td/$base"
            fi
        done
        run rmdir "$wd" 2>/dev/null || true
    fi
}

# Extract directives.md's YAML block into settings.yaml; dump prose to staging file
migrate_directives() {
    local level_dir="$1"
    local df="$level_dir/directives.md" sf="$level_dir/settings.yaml"
    [ -f "$df" ] || return 0
    [ -s "$df" ] || { run rm -f "$df"; return 0; }
    echo "=== migrating directives.md: $df ==="

    # Split at the first line that isn't part of a recognized YAML key (heuristic:
    # lines starting with a lowercase key: or leading whitespace+key: belong to YAML;
    # a line starting with "- " or "#" at column 0 (after the YAML block) is prose)
    python3 - "$df" "$sf" "$level_dir" "$DRY_RUN" << 'PY'
import sys, re
df, sf, level_dir, dry_run = sys.argv[1:5]
lines = open(df).read().splitlines()
yaml_lines = []
prose_lines = []
in_yaml = True
for line in lines:
    if in_yaml and (re.match(r'^[a-zA-Z][a-zA-Z0-9_.-]*:', line) or re.match(r'^\s+\S', line) or line.strip() == ''):
        yaml_lines.append(line)
    else:
        in_yaml = False
        prose_lines.append(line)

if dry_run == "--dry-run":
    print(f"[dry-run] would write {len(yaml_lines)} YAML lines to {sf}")
    if prose_lines:
        print(f"[dry-run] would append {len(prose_lines)} prose lines to {level_dir}/topics/_migration-needs-review.md")
else:
    with open(sf, 'a') as out:
        out.write('\n'.join(yaml_lines).rstrip('\n') + '\n')
    if prose_lines:
        staging = f"{level_dir}/topics/_migration-needs-review.md"
        with open(staging, 'a') as out:
            out.write("\n<!-- migrated from directives.md prose — split into properly named topics -->\n")
            out.write('\n'.join(prose_lines).rstrip('\n') + '\n')
PY
    run rm -f "$df"
}

# Convert user.md's KEY=VALUE lines into settings.yaml keys; dump prose to staging file
migrate_user() {
    local level_dir="$1"
    local uf="$level_dir/user.md" sf="$level_dir/settings.yaml"
    [ -f "$uf" ] || return 0
    [ -s "$uf" ] || { run rm -f "$uf"; return 0; }
    echo "=== migrating user.md: $uf ==="

    python3 - "$uf" "$sf" "$level_dir" "$DRY_RUN" << 'PY'
import sys, re
uf, sf, level_dir, dry_run = sys.argv[1:5]
lines = open(uf).read().splitlines()
kv_lines = []
prose_lines = []
for line in lines:
    if re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', line):
        key, _, val = line.partition('=')
        kv_lines.append(f"{key}: {val}")
    elif line.strip():
        prose_lines.append(line)

if dry_run == "--dry-run":
    print(f"[dry-run] would append {len(kv_lines)} settings keys to {sf}")
    if prose_lines:
        print(f"[dry-run] would append {len(prose_lines)} prose lines to {level_dir}/topics/_migration-needs-review.md")
else:
    if kv_lines:
        with open(sf, 'a') as out:
            out.write('\n'.join(kv_lines) + '\n')
    if prose_lines:
        staging = f"{level_dir}/topics/_migration-needs-review.md"
        with open(staging, 'a') as out:
            out.write("\n<!-- migrated from user.md prose — split into properly named topics -->\n")
            out.write('\n'.join(prose_lines) + '\n')
PY
    run rm -f "$uf"
}

migrate_one_level() {
    local level_dir="$1"
    migrate_level_dir "$level_dir"
    migrate_directives "$level_dir"
    migrate_user "$level_dir"
}

# Walk every project, its branches (active + archived), and their tasks
for project_dir in "$ROOT"/*/; do
    [ -d "$project_dir" ] || continue
    project_dir="${project_dir%/}"
    [[ "$(basename "$project_dir")" == _backup_* ]] && continue

    migrate_one_level "$project_dir"

    for branches_root in "$project_dir/branches" "$project_dir/archive"; do
        [ -d "$branches_root" ] || continue
        for branch_dir in "$branches_root"/*/; do
            [ -d "$branch_dir" ] || continue
            branch_dir="${branch_dir%/}"
            migrate_one_level "$branch_dir"
            [ -d "$branch_dir/tasks" ] || continue
            for task_dir in "$branch_dir/tasks"/*/; do
                [ -d "$task_dir" ] || continue
                task_dir="${task_dir%/}"
                # Task-level: flat knowledge.md -> topics/<slug>.md if present, else ensure topics/index.md
                if [ -f "$task_dir/knowledge.md" ] && [ -s "$task_dir/knowledge.md" ]; then
                    echo "=== flagging flat task knowledge.md for manual split: $task_dir/knowledge.md ==="
                    run mkdir -p "$task_dir/topics"
                    run mv "$task_dir/knowledge.md" "$task_dir/topics/_migration-needs-review.md"
                elif [ ! -d "$task_dir/topics" ]; then
                    run mkdir -p "$task_dir/topics"
                    run touch "$task_dir/topics/index.md"
                fi
            done
        done
    done
done

echo ""
echo "Migration complete. Review any topics/_migration-needs-review.md files created above"
echo "and split their content into properly named, single-purpose topics."
