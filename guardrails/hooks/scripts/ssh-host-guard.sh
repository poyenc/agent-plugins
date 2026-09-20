#!/usr/bin/env bash
# PreToolUse(Bash): enforce an ssh/scp/rsync destination block/allow list.
#
# Every bareword argument is resolved via `ssh -G <token>` before checking -- this expands
# real ~/.ssh/config Host/Match/Include the same way an actual connection would, so an alias
# whose NAME doesn't match a block pattern at all (e.g. "Host oldnode" -> "HostName
# some-blocked-host") is still caught by its resolved hostname. OpenSSH resolves ~/.ssh/config
# via the real passwd-entry home directory (getpwuid), not $HOME, so this can't be bypassed by
# an env var trick either.
#
# Config (comma-separated glob patterns, matching this plugin's other GUARDRAILS_* env vars --
# no side config file, no baked-in default host list -- this hook is inert until YOU set at
# least GUARDRAILS_HOST_BLOCK):
#   GUARDRAILS_HOST_BLOCK   patterns to deny, e.g. "10.0.*,*.internal.example.com"
#   GUARDRAILS_HOST_ALLOW   patterns to always permit even if also matched by BLOCK
#
# Semantics: matches ALLOW -> permitted (allow always wins) -- else matches BLOCK -> denied --
# else (matches neither) -> permitted (default-allow; an empty ALLOW does NOT mean "allow
# everything", it just means no exceptions to BLOCK; "allow everything" only happens when
# BLOCK is also empty/unset, since there is then nothing to match against).
set -euo pipefail

CONNECT_VERB_RE='(^|[^a-zA-Z0-9_./-])(ssh|scp|rsync)([^a-zA-Z0-9_-]|$)'

cmd="$(jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[ -n "$cmd" ] || exit 0

# Strip heredoc bodies before any pattern matching. A heredoc body is DATA, not command text
# (e.g. `git commit -m "$(cat <<'EOF' ... EOF)"`, this project's own commit-message convention)
# -- prose that happens to mention "ssh" or a blocked-looking pattern must not be scanned as
# if it were a live shell invocation. Best-effort (a `<<DELIM`/`<<-DELIM`/`<<'DELIM'` opener,
# skip lines through the one matching DELIM, honoring `<<-`'s leading-tab stripping); not a
# full shell parser, matching the fail-open bias this plugin's other guardrails already take
# on heredocs (see scan-guard-lib.sh).
cmd="$(printf '%s\n' "$cmd" | awk '
    BEGIN { skip = 0; delim = "" }
    skip {
        line = $0
        if (tabstrip) { gsub(/^\t+/, "", line) }
        if (line == delim) { skip = 0 }
        next
    }
    { print }
    match($0, /<<-?[[:space:]]*['"'"'"]?[A-Za-z_][A-Za-z0-9_]*['"'"'"]?/) {
        seg = substr($0, RSTART, RLENGTH)
        tabstrip = (seg ~ /<<-/)
        delim = seg
        gsub(/<<-?[[:space:]]*/, "", delim)
        gsub(/["'"'"']/, "", delim)
        skip = 1
    }
')"

echo "$cmd" | grep -qE "$CONNECT_VERB_RE" || exit 0

IFS=',' read -r -a allow_pats <<< "${GUARDRAILS_HOST_ALLOW:-}"
IFS=',' read -r -a block_pats <<< "${GUARDRAILS_HOST_BLOCK:-}"
[ "${#allow_pats[@]}" -gt 0 ] && [ -z "${allow_pats[0]}" ] && allow_pats=()
[ "${#block_pats[@]}" -gt 0 ] && [ -z "${block_pats[0]}" ] && block_pats=()
[ "${#block_pats[@]}" -gt 0 ] || exit 0

matches_any() {
    # $1 = candidate hostname, $2.. = glob patterns
    local host="$1"; shift
    local pat
    for pat in "$@"; do
        # shellcheck disable=SC2053 -- intentional glob match, not regex
        case "$host" in $pat) return 0 ;; esac
    done
    return 1
}

bad=""
for tok in $cmd; do
    case "$tok" in
        -*|ssh|scp|rsync) continue ;;
    esac
    # scp/rsync remote spec is [user@]host:path -- extract just the host part before
    # resolving. A ":" with a "/" before it isn't this shape (a local path or URL); a bare
    # "/" with no ":" is a plain local path argument. Either way, skip anything that isn't
    # host-shaped rather than mis-resolving a path as if it were a hostname.
    case "$tok" in
        *:*)
            prefix="${tok%%:*}"
            case "$prefix" in */*) continue ;; esac
            host="${prefix#*@}"
            ;;
        */*) continue ;;
        *) host="${tok#*@}" ;;
    esac
    [ -n "$host" ] || continue
    resolved="$(ssh -G "$host" 2>/dev/null | awk '/^hostname /{print $2; exit}' || true)"
    [ -n "$resolved" ] || continue
    if [ "${#allow_pats[@]}" -gt 0 ] && matches_any "$resolved" "${allow_pats[@]}"; then
        continue
    fi
    if matches_any "$resolved" "${block_pats[@]}"; then
        bad="$bad
$tok -> $resolved"
    fi
done

if [ -n "$(echo "$bad" | tr -d '[:space:]')" ]; then
    reason="Blocked by GUARDRAILS_HOST_BLOCK: $(echo "$bad" | tr '\n' ' ' | sed 's/^ *//; s/ *$//') is not on GUARDRAILS_HOST_ALLOW."
    jq -nc --arg reason "$reason" \
        '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
fi
exit 0
