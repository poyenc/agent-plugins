#!/usr/bin/env bash
# scripts/lib.sh — Shared functions for knowledge-management plugin

sanitize_branch_name() {
    echo "$1" | sed 's|/|--|g'
}

detect_project_name() {
    local url
    url="$(git remote get-url origin 2>/dev/null)" || return 1
    url="${url%/}"
    basename "${url%.git}"
}

resolve_storage_root() {
    if [ -n "${KNOWLEDGE_ROOT:-}" ]; then
        echo "$KNOWLEDGE_ROOT"
        return
    fi
    local root="" git_root=""
    git_root="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
    for settings_file in "$git_root/.claude/settings.json" "$HOME/.claude/settings.json"; do
        if [ -f "$settings_file" ]; then
            root="$(python3 -c "
import json, os, sys
try:
    d = json.load(open('$settings_file'))
    r = d.get('knowledge', {}).get('root', '')
    if r: print(os.path.expanduser(r))
except: pass
" 2>/dev/null)"
            [ -n "$root" ] && break
        fi
    done
    if [ -n "$root" ]; then
        echo "$root"
    else
        echo "$HOME/.local/share/claude/knowledge"
    fi
}

resolve_project_dir() {
    local root project
    root="$(resolve_storage_root)"
    project="$(detect_project_name)" || return 1
    echo "$root/$project"
}

resolve_branch_dir() {
    local project_dir="$1" branch_name="$2"
    local sanitized
    sanitized="$(sanitize_branch_name "$branch_name")"
    echo "$project_dir/branches/$sanitized"
}

is_default_branch() {
    local branch="$1"
    case "$branch" in
        main|master|develop) echo "yes" ;;
        *) echo "no" ;;
    esac
}

read_meta_field() {
    local file="$1" field="$2"
    local val=""
    val="$(grep -oP "^\*\*${field}:\*\*\s*\`\K[^\`]+" "$file" 2>/dev/null | head -1)"
    if [ -z "$val" ]; then
        val="$(grep -oP "^\*\*${field}:\*\*\s*\K\S.*" "$file" 2>/dev/null | head -1)"
    fi
    echo "$val"
}

write_meta_field() {
    local file="$1" field="$2" value="$3"
    if grep -q "^\*\*${field}:\*\*" "$file" 2>/dev/null; then
        sed -i "s|^\*\*${field}:\*\*.*|**${field}:** \`${value}\`|" "$file"
    else
        echo "**${field}:** \`${value}\`" >> "$file"
    fi
}
