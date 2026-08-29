#!/usr/bin/env bash
# Manual live smoke test -- run inside a herdr session. Self-rotates a throwaway target
# agent via herdr-rotate-self. Everything runs in workspace wG.
# Usage: smoke-live.sh <kind> [-- <launch-args...>]
set -euo pipefail
[ "${HERDR_ENV:-}" = 1 ] || { echo "not in herdr"; exit 1; }
[ "${HERDR_WORKSPACE_ID:-}" = wG ] || { echo "must run in workspace wG"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"; SELF="$HERE/../../scripts/herdr-rotate-self"

kind="${1:?kind}"; shift || true; [ "${1:-}" = "--" ] && shift
case "$kind" in
  claude) LAUNCH=(--model haiku --effort medium --verbose --dangerously-skip-permissions) ;;
  pi)     LAUNCH=(--model amd-gateway/gpt-5.6-terra --thinking high) ;;
  codex)  LAUNCH=(-m gpt-5.6-sol -c model_reasoning_effort=low --dangerously-bypass-approvals-and-sandbox) ;;   # never glm-5.2: known hang issue
  *) echo "unknown kind"; exit 1 ;;
esac
[ $# -gt 0 ] && LAUNCH=("$@")
target="smokeself-$kind"

# shellcheck source=SCRIPTDIR/../../herdr-rotate/tests/lib-wait-for-turn.sh
source "$HERE/../../herdr-rotate/tests/lib-wait-for-turn.sh"

tab=$(herdr tab create --workspace wG --cwd "$PWD" --label "$target" --no-focus)
tpane=$(printf '%s' "$tab" | jq -r .result.root_pane.pane_id)
tabid=$(printf '%s' "$tab" | jq -r .result.tab.tab_id)
handoff_path=""
cleanup(){ herdr tab close "$tabid" >/dev/null 2>&1 || true; [ -n "$handoff_path" ] && rm -f "$handoff_path"; }
trap cleanup EXIT

herdr agent start "$target" --kind "$kind" --pane "$tpane" --timeout 120000 -- "${LAUNCH[@]}" >/dev/null

before_session=$(herdr agent get "$target" | jq -c '.result.agent.agent_session // {}')

herdr agent prompt "$target" "This is a rotation smoke test, not a real task. Remember the codeword ZEBRA-77. Reply OK when done." >/dev/null 2>&1 \
  || { echo "FAIL: marker-establishing prompt send failed"; exit 1; }
wait_for_turn "$target" 15 180000

handoff_path="/tmp/smoke-self-handoff-$$.md"
herdr agent prompt "$target" "Write a one-line handoff to $handoff_path (just 'smoke test handoff' is fine), then run $SELF $handoff_path --kickoff off, then say nothing else." >/dev/null 2>&1 \
  || { echo "FAIL: self-rotation instruction send failed"; exit 1; }

deadline=$(( SECONDS + 180 ))
after_session=""
while [ "$SECONDS" -lt "$deadline" ]; do
  st=$(herdr agent get "$tpane" 2>/dev/null | jq -r '.result.agent.agent_status // empty') || st=""
  case "$st" in idle|done)
    after_session=$(herdr agent get "$tpane" | jq -c '.result.agent.agent_session // {}')
    [ "$after_session" != "$before_session" ] && [ "$after_session" != "{}" ] && break
    after_session=""
    ;;
  esac
  command sleep 3
done
[ -n "$after_session" ] || { echo "FAIL: pane never showed a fresh session within timeout"; exit 1; }

herdr agent prompt "$target" "What codeword did I ask you to remember? Reply NO_MARKER if none." >/dev/null 2>&1 \
  || { echo "FAIL: freshness-check prompt send failed"; exit 1; }
wait_for_turn "$target" 15 60000
recall=$(herdr agent read "$target" --source visible --lines 60)
reply=$(printf '%s' "$recall" | awk '/What codeword did I ask you to remember/{found=1; next} found')
fails=0
if printf '%s' "$reply" | grep -q ZEBRA-77; then
  echo "FAIL freshness: reply still mentions the old codeword ZEBRA-77"; fails=1
elif ! printf '%s' "$reply" | grep -q NO_MARKER; then
  echo "FAIL freshness: reply did not report NO_MARKER"; fails=1
fi
[ "$fails" = 0 ] && echo "SMOKE PASS self-rotate ($kind)" || { echo "SMOKE FAIL self-rotate ($kind)"; exit 1; }
