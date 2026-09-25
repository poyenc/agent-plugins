#!/usr/bin/env bash
# PreToolUse(Bash): block any direct `herdr agent prompt` invocation (through wrappers and
# `bash -c` bodies) -- both the blocking `--wait` form and a plain fire-and-forget send routinely
# leave the sender with no reply path (or, for --wait, stall the sender's own turn). All
# inter-agent messaging goes through the herdr-kit `message` skill instead, which builds the same
# underlying call with a reply envelope and never blocks. Uses the shared quote-aware command
# scanner so only an actual `herdr agent prompt` INVOCATION is matched -- not a mention of those
# words in a comment, a search, or a message body being sent through the message skill itself.
# No-op outside herdr.
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/scan-guard-lib.sh"

[ "${HERDR_ENV:-}" = 1 ] || exit 0

cmd=$(jq -r '.tool_input.command // ""')
[ -n "$cmd" ] || exit 0

# Is this segment's real command `herdr`, with `agent` immediately followed by `prompt` somewhere
# among its arguments? That pair is always adjacent in real CLI grammar (`herdr agent prompt ...`).
agent_prompt_seg() {
  local cmdbase="$1"; shift
  [ "$cmdbase" = herdr ] || return 1
  local -a rest=("$@")
  local k
  for (( k=0; k<${#rest[@]}-1; k++ )); do
    if [ "$(dequote_full "${rest[$k]}")" = agent ] && [ "$(dequote_full "${rest[$((k+1))]}")" = prompt ]; then
      return 0
    fi
  done
  return 1
}

scan_command "$cmd" agent_prompt_seg || exit 0

printf '{"decision":"block","reason":"Do not run `herdr agent prompt` directly. Use the herdr-kit `message` skill instead -- `send` (or `reply`) builds the same call and returns immediately; add `--callback` when you need a reply routed back to you as your own next incoming turn. A raw `--wait` additionally blocks your own turn until the target settles (indefinitely when no --timeout is set), stalling you and everything queued behind you; a raw plain send has no reply path at all. If you are trying to deliver a bare slash-command (e.g. `/model`) to control the target'\''s own CLI rather than converse with it, use the message skill'\''s `command` action instead -- `send`/`reply` would wrap it in an envelope and corrupt it."}'
