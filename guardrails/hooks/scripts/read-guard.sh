#!/usr/bin/env bash
# PreToolUse(Read): block a single Read call from returning more than a configurable byte
# limit of text file content. Each call is evaluated independently -- no cross-call tracking
# (an agent that chunks a large file into many small reads that each pass is not caught here;
# the block message below is the mitigation for that gap, not additional enforcement).
set -euo pipefail

max_bytes="${GUARDRAILS_MAX_READ_BYTES:-65536}"

payload=$(cat)

file_path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // ""')
offset=$(printf '%s' "$payload" | jq -r '.tool_input.offset // ""')
limit=$(printf '%s' "$payload" | jq -r '.tool_input.limit // ""')

[ -n "$file_path" ] || exit 0

# Images/PDFs/notebooks aren't the "read a huge text file" problem this hook targets, and
# byte-range slicing by line doesn't apply to them anyway -- always skip, regardless of size.
ext="${file_path##*.}"
ext=$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')
case "$ext" in
  png|jpg|jpeg|gif|webp|svg|bmp|pdf|ipynb) exit 0 ;;
esac

if [ -z "$offset" ] && [ -z "$limit" ]; then
  # Neither given -- treat as intent to read the whole file. This intentionally ignores that
  # Read itself may internally truncate large default reads based on
  # CLAUDE_CODE_FILE_READ_MAX_OUTPUT_TOKENS (a token-based limit with no reliable byte/line
  # equivalent computable here) -- the point is to catch *intent* to pull in a whole large file.
  size=$(stat -c%s -- "$file_path" 2>/dev/null) || exit 0
else
  start="${offset:-1}"
  [[ "$start" =~ ^[0-9]+$ ]] || exit 0
  if [ -n "$limit" ]; then
    [[ "$limit" =~ ^[0-9]+$ ]] || exit 0
    end=$((start + limit - 1))
  else
    end=$(wc -l < "$file_path" 2>/dev/null) || exit 0
  fi
  size=$(sed -n "${start},${end}p" -- "$file_path" 2>/dev/null | wc -c) || exit 0
fi

[[ "$size" =~ ^[0-9]+$ ]] || exit 0

if (( size > max_bytes )); then
  printf '{"decision":"block","reason":"This Read call would return %s bytes of file content, exceeding the %s-byte limit. Splitting this into multiple smaller Read calls on the same file is still a violation of this same per-call rule -- it does not reduce total context usage. Delegate reading/summarizing this file to a subagent instead, and have it report back only the relevant excerpt or summary."}\n' \
    "$size" "$max_bytes"
fi
