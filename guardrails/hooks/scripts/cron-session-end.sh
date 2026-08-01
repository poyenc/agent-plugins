#!/usr/bin/env bash
# SessionEnd hook: clean up the cron counter file for this session.
set -euo pipefail

session_id=$(jq -r '.session_id // ""')

[ -n "$session_id" ] || exit 0

rm -f "${CLAUDE_CODE_TMPDIR:-/tmp}/guardrails-plugin/cron-count-${session_id}"
