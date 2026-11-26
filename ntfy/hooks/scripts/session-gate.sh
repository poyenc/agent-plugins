# Preamble shared by the ntfy hooks that send notifications. Source it as the first step after
# `set -euo pipefail`. At source time it reads the hook payload from stdin into $payload and ends the
# calling hook (exit 0) unless notifications are enabled for the session; otherwise it exports
# NTFY_TITLE from the marker (see scripts/marker.sh).
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/marker.sh"

payload=$(cat)
ntfy_require_enabled "$(ntfy_payload_session_id "$payload")"
