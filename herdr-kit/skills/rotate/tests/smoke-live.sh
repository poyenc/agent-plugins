#!/usr/bin/env bash
# Manual live smoke test — run inside a herdr session. Rotates a throwaway target agent per
# kind, using a second throwaway agent as a stand-in orchestrator so the target's ping-back
# (an agent-to-agent `herdr agent prompt`) has somewhere real to land — bash alone cannot
# receive it, only another live agent can. Everything runs in workspace wG.
# Usage: smoke-live.sh <kind> [-- <launch-args...>]
set -euo pipefail
[ "${HERDR_ENV:-}" = 1 ] || { echo "not in herdr"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"; ROT="$HERE/../../scripts/herdr-rotate"
kind="${1:?kind}"; shift || true; [ "${1:-}" = "--" ] && shift
case "$kind" in
  claude) LAUNCH=(--model haiku --effort medium --verbose --dangerously-skip-permissions) ;;
  pi)     LAUNCH=(--model amd-gateway/gpt-5.6-terra --thinking high) ;;
  codex)  LAUNCH=(-m gpt-5.6-sol -c model_reasoning_effort=low --dangerously-bypass-approvals-and-sandbox) ;;   # never glm-5.2: known hang issue in codex
  *) echo "unknown kind"; exit 1 ;;
esac
[ $# -gt 0 ] && LAUNCH=("$@")
target="smoke-$kind"
orch="smoke-orch-$kind"

# shellcheck source=SCRIPTDIR/lib-wait-for-turn.sh
source "$HERE/lib-wait-for-turn.sh"

tab=$(herdr tab create --workspace wG --cwd "$PWD" --label "$target" --no-focus)
tpane=$(printf '%s' "$tab" | jq -r .result.root_pane.pane_id)
tabid=$(printf '%s' "$tab" | jq -r .result.tab.tab_id)
opane=$(herdr pane split "$tpane" --direction right --no-focus --cwd "$PWD" | jq -r .result.pane.pane_id)
cleanup(){ herdr tab close "$tabid" >/dev/null 2>&1 || true; }
trap cleanup EXIT

herdr agent start "$target" --kind "$kind" --pane "$tpane" --timeout 120000 -- "${LAUNCH[@]}" >/dev/null
herdr agent start "$orch" --kind claude --pane "$opane" --timeout 120000 -- --model haiku --dangerously-skip-permissions >/dev/null

before=$(herdr pane process-info --pane "$tpane" | jq -c --arg k "$kind" '.result.process_info.foreground_processes[]|select(.name==$k).argv')
herdr agent prompt "$target" "This is a rotation smoke test, not a real task. Skim README.md in this directory and note one fact about it out loud, then remember the codeword ZEBRA-42. Reply OK when done." >/dev/null 2>&1 \
  || { echo "FAIL: marker-establishing prompt send failed"; exit 1; }
wait_for_turn "$target" 15 180000

# Phase 1: send the handoff, addressed to the stand-in orchestrator's pane (not this script's).
# --kickoff off is finish-only now; handoff rejects it.
HERDR_PANE_ID="$opane" "$ROT" handoff "$target"

# Phase 2: wait for the ping to land in the orchestrator's own conversation/output, then
# extract "<target>[@<session-prefix>]: <path>" from it. This is test-harness scraping only, to
# stand in for a live LLM's own turn -- a real orchestrating agent just reads the path (and the
# tag, to pass as finish's target) out of its own incoming message, no pane-reading needed for
# the ping itself (detect_override's pane reads are a separate, unrelated mechanism). Keep the
# FULL tag (pane@prefix, if any) for finish -- stripping it down would skip the staleness check
# finish is meant to exercise.
tag=""
path=""
deadline=$(( SECONDS + 480 ))
while [ "$SECONDS" -lt "$deadline" ]; do
  out=$(herdr agent read "$orch" --source visible --lines 200 2>/dev/null || true)
  ping_line=$(printf '%s' "$out" | grep -oE "${tpane}(@[^: ]+)?:[[:space:]]*/[^\"'[:space:]]+" | tail -n1) || true
  if [ -n "$ping_line" ]; then
    # Split on ": " (colon-SPACE), not just the first colon -- the tag itself is now a pane
    # id (e.g. "wG:p4"), which contains a colon of its own with no following space.
    tag=$(printf '%s' "$ping_line" | sed -E 's/:[[:space:]]+.*$//')
    path=$(printf '%s' "$ping_line" | sed -E 's/^.*:[[:space:]]+//')
    break
  fi
  command sleep 3
done
[ -n "$path" ] || { echo "FAIL: no ping with a path arrived at the orchestrator within timeout"; exit 1; }
[ -s "$path" ] || { echo "FAIL: pinged path does not exist / is empty: $path"; exit 1; }

"$ROT" finish "$tag" "$path" --kickoff off

after=$(herdr pane process-info --pane "$tpane" | jq -c --arg k "$kind" '.result.process_info.foreground_processes[]|select(.name==$k).argv')
herdr agent prompt "$target" "What codeword did I ask you to remember? Reply NO_MARKER if none." >/dev/null 2>&1 \
  || { echo "FAIL: freshness-check prompt send failed"; exit 1; }
wait_for_turn "$target" 15 60000
recall=$(herdr agent read "$target" --source visible --lines 60)   # room for the model's own reasoning text before its final answer
# The echoed prompt itself contains the literal string "NO_MARKER" -- only the text AFTER it
# (the agent's actual reply) counts, or a naive fresh-vs-stale check would trivially pass.
reply=$(printf '%s' "$recall" | awk '/What codeword did I ask you to remember/{found=1; next} found')
fails=0
[ "$before" = "$after" ] || { echo "FAIL argv: $before != $after"; fails=1; }
# Both checks matter: a reply that still contains ZEBRA-42 anywhere (even alongside NO_MARKER,
# e.g. "ZEBRA-42, not NO_MARKER") means the old context leaked through and must fail, not just
# a bare substring match on NO_MARKER.
if printf '%s' "$reply" | grep -q ZEBRA-42; then
  echo "FAIL freshness: reply still mentions the old codeword ZEBRA-42"; fails=1
elif ! printf '%s' "$reply" | grep -q NO_MARKER; then
  echo "FAIL freshness: reply did not report NO_MARKER"; fails=1
fi
[ "$fails" = 0 ] && echo "SMOKE PASS ($kind)" || { echo "SMOKE FAIL ($kind)"; exit 1; }
