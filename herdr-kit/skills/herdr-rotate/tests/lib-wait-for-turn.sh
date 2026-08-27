#!/usr/bin/env bash
# Shared with smoke-live.sh; sourced there and by test-wait-for-turn.sh so the real logic gets
# deterministic, mocked regression coverage instead of only manual live verification.
#
# `agent wait --until idle/done` returns immediately if the target is ALREADY idle when
# called (e.g. right after `agent start`, or between back-to-back prompts) — it doesn't
# track turns. So after firing a prompt, first poll for a CONFIRMED transition into
# "working"/"blocked" before blocking on the real completion. Checking merely "!= idle" is
# not enough: a "done" from an EARLIER turn is a settled, non-idle state too, and would
# satisfy that weaker check without the new turn ever having started.
wait_for_turn(){
  local who="$1" settle_timeout="$2" total_timeout="$3" st="" saw_turn=0
  local deadline=$(( SECONDS + settle_timeout ))
  while [ "$SECONDS" -lt "$deadline" ]; do
    st=$(herdr agent get "$who" 2>/dev/null | jq -r '.result.agent.agent_status // empty')
    case "$st" in working|blocked) saw_turn=1; break ;; esac
    command sleep 1
  done
  # If the transition into working/blocked is never confirmed, the prompt may never have
  # actually been picked up (send succeeded but the agent didn't act on it) -- falling through
  # to `agent wait` below would then just observe a STALE idle/done from a previous turn and
  # report success without this turn ever having happened. Fail here instead of risking that.
  [ "$saw_turn" = 1 ] || { echo "FAIL: $who never confirmed starting a new turn (status: ${st:-unknown}) within ${settle_timeout}s"; exit 1; }
  herdr agent wait "$who" --until idle --until done --timeout "$total_timeout" >/dev/null 2>&1 \
    || { echo "FAIL: agent wait for $who did not confirm idle/done within ${total_timeout}ms"; exit 1; }
}
