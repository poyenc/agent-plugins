# Single definition of the per-session notification marker (a file whose existence means "notify";
# its content is the optional notification title). Every ntfy script that reads or writes the marker
# sources this file; none spells out the path itself. Defines:
#   ntfy_payload_session_id <payload>         session_id from a hook payload (empty if absent or malformed)
#   ntfy_marker_enable <session_id> [title]   turn notifications on (the title may be empty)
#   ntfy_marker_disable <session_id>          turn notifications off
#   ntfy_require_enabled <session_id>
#       ends the calling script (exit 0) unless notifications are enabled for that session;
#       otherwise exports NTFY_TITLE from the marker when it holds a title.

# Internal: the marker location and content format live only in this file.
ntfy_marker_dir() { printf '%s' "${CLAUDE_CODE_TMPDIR:-/tmp}/ntfy-plugin/active"; }

ntfy_marker_path() { printf '%s/notify-enabled-%s' "$(ntfy_marker_dir)" "$1"; }

ntfy_payload_session_id() {
    printf '%s' "$1" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null || true
}

ntfy_marker_enable() {
    mkdir -p "$(ntfy_marker_dir)"
    printf '%s' "${2:-}" > "$(ntfy_marker_path "$1")"
}

ntfy_marker_disable() { rm -f "$(ntfy_marker_path "$1")"; }

ntfy_require_enabled() {
    local marker title
    marker=$(ntfy_marker_path "$1")
    [ -f "$marker" ] || exit 0
    title=$(cat "$marker")
    # `if`, not `[ -n ... ] && export`: an empty title (plain /ntfy-on) must not return non-zero,
    # which would kill a caller running under `set -e`.
    if [ -n "$title" ]; then export NTFY_TITLE="$title"; fi
}
