#!/usr/bin/env bash
# PreToolUse(Bash): block the word `srun` anywhere in the command. This deliberately uses a
# lexical match rather than shell parsing, so mentions such as `grep -R srun .` are blocked too.
# Use salloc once, then plain `ssh <node> <command>` to reuse the allocation without srun's
# single-shared-shell / one-job-step-at-a-time limitations.
set -euo pipefail

cmd=$(jq -r '.tool_input.command // ""')

[ -n "$cmd" ] || exit 0

if echo "$cmd" | grep -qFw 'srun'; then
  printf '{"decision":"block","reason":"srun is banned. Use `salloc --gres=... --time=<D-HH:MM:SS>` once to get a node, then reuse it with plain `ssh <node> <command>` for every subsequent command -- each ssh call is its own independent session instead of serializing through one shared interactive shell, so nothing blocks on a prior command finishing and you can run several in parallel. Release with `scancel <job-id>` when done."}'
fi
