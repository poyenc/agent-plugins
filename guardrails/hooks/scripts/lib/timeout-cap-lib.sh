#!/usr/bin/env bash
# Shared, unit-agnostic numeric validation for a "foreground command must declare a short
# timeout" guard. Used by no-long-foreground.sh for both its Claude Code branch (milliseconds)
# and its pi branch (seconds) -- the two differ in which env-var name holds the cap and what
# unit the number means, not in how a cap or a declared .tool_input.timeout value is validated,
# and both harnesses put the field at that same JSON path.
#
# Source this file, don't execute it: `source "$(dirname "${BASH_SOURCE[0]}")/lib/timeout-cap-lib.sh"`

# $1 = operator-configured cap string, $2 = fallback default.
# Prints $1 if it is a safe non-negative integer literal (no leading zero beyond a bare "0",
# <=15 digits to stay clear of 64-bit overflow in a later `[ -gt ]` comparison -- same
# convention as read-guard.sh's GUARDRAILS_MAX_READ_BYTES), else prints $2.
safe_cap() {
  local value="$1" default="$2"
  if [[ "$value" =~ ^(0|[1-9][0-9]{0,14})$ ]]; then
    printf '%s' "$value"
  else
    printf '%s' "$default"
  fi
}

# $1 = JSON payload. Prints "true" if .tool_input.timeout is present and not JSON null, else
# "false". A JSON `false`/`""`/other present-but-wrong-type value still counts as "declared" --
# it is malformed, not absent, and the caller must route it to timeout_value's fail-open path
# below, not to the "no timeout declared" block.
timeout_declared() {
  local payload="$1"
  printf '%s' "$payload" | jq -r '(.tool_input | has("timeout")) and (.tool_input.timeout != null)' 2>/dev/null
}

# $1 = JSON payload. Prints .tool_input.timeout as a plain non-negative integer string if and
# only if it is a valid JSON number, a non-negative integer, and within the same 15-digit
# overflow-safe bound as safe_cap. Otherwise prints nothing. A schema-violating value (string,
# bool, negative, non-integer float, too large) is this function's business to detect, not to
# coerce -- the caller fails open on empty output, since enforcing the Bash tool's own schema
# is not this hook's job.
timeout_value() {
  local payload="$1"
  local is_ok
  is_ok=$(printf '%s' "$payload" | jq -r '
    (.tool_input.timeout | type) == "number"
      and (.tool_input.timeout == (.tool_input.timeout | floor))
      and (.tool_input.timeout >= 0)
  ' 2>/dev/null)
  [ "$is_ok" = "true" ] || return 0
  local val
  val=$(printf '%s' "$payload" | jq -r '.tool_input.timeout | floor')
  [[ "$val" =~ ^(0|[1-9][0-9]{0,14})$ ]] && printf '%s' "$val"
}
