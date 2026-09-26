#!/usr/bin/env bash
# PreToolUse(Read|Write|Edit): block all access to Claude Code's built-in memory directory, both
# reads and writes. Project memory tends to go stale as a project's state and decisions change --
# and unlike a normal file the agent chose to read, memory content is quietly injected into
# context, so a stale entry skews the agent's judgment without it ever noticing the source. Read,
# Write, and Edit all key off the same `tool_input.file_path`, so one script covers all three.
set -euo pipefail

file_path=$(jq -r '.tool_input.file_path // ""')

[ -n "$file_path" ] || exit 0

memory_dir="${HOME}/.claude/projects"

case "$file_path" in
  "${memory_dir}"/*/memory/*)
    printf '{"decision":"block","reason":"Access to the built-in memory system is banned (read and write). Memory content goes stale as a project'\''s state and decisions change, and -- because it is injected into context rather than deliberately read -- a stale entry skews the agent'\''s judgment without any visible signal that it happened. Keep durable notes in an explicit file the agent reads on purpose instead."}'
    ;;
esac
