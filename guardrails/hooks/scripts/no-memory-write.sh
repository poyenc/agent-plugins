#!/usr/bin/env bash
# PreToolUse(Write|Edit): block writes to Claude Code's built-in memory directory.
set -euo pipefail

file_path=$(jq -r '.tool_input.file_path // ""')

[ -n "$file_path" ] || exit 0

memory_dir="${HOME}/.claude/projects"

case "$file_path" in
  "${memory_dir}"/*/memory/*)
    printf '{"decision":"block","reason":"Writing to the built-in memory system is banned."}'
    ;;
esac
