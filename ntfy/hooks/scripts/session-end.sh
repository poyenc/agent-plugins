#!/usr/bin/env bash
# SessionEnd hook -- clean up the marker file for this session.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/marker.sh"

payload=$(cat)

session_id=$(ntfy_payload_session_id "$payload")

[ -n "$session_id" ] || exit 0

ntfy_marker_disable "$session_id"
exit 0
