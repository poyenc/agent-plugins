#!/usr/bin/env bash
# PreToolUse(AskUserQuestion): block the preview variant -- any question whose options carry a
# non-empty `preview` field (the side-by-side code/mockup box). The question itself looks like a
# plain one, but the substance sits in a pane that disappears once answered, so the user must decide
# on the spot and cannot look at it again. Steer the agent to a plain-text question instead.
set -euo pipefail

has_preview=$(jq -r '[(.tool_input.questions // [])[]?.options[]? | select((.preview // "") != "")] | length')

[ "${has_preview:-0}" -gt 0 ] || exit 0

printf '{"decision":"block","reason":"The AskUserQuestion preview variant (options with a non-empty `preview` field) is banned: the user must decide immediately and cannot look at the preview again afterwards. Ask in plain text instead -- write the question and each option, with any code or detail inline, as a normal message, and stop so the user can answer when ready. Plain AskUserQuestion without a non-empty `preview` is still allowed."}'
