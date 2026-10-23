#!/usr/bin/env bash
# PreToolUse(Bash): a run_in_background:true call must wrap its command in the shell's own
# `timeout` utility. The Bash tool's own `timeout` field is milliseconds and is enforced for
# foreground calls, but verified live to be accepted and silently NOT enforced for background
# calls (a background call declaring timeout:3000 ran to completion ~15s later, exit 0) -- so
# without a shell-level wrapper, a hung background command runs past any declared duration with
# no enforcement at all. This hook's job is parity with that foreground enforcement -- a bounded
# duration, same cap semantics as a foreground call -- not an exhaustive reimplementation of GNU
# timeout's full option/signal grammar, and not an absolute guarantee against a command that
# deliberately ignores every signal it's given (owner-scoped decision: parity only).
#
# Recognizes `timeout DURATION command...` where DURATION is the very next token after
# `timeout` -- no options (`-k`, `-s`, `--foreground`, etc.) are parsed or skipped. A command
# using any option there isn't recognized as a wrapper and is treated the same as "no wrapper"
# (a false block, safe direction -- drop the option and use a plain `timeout N ...`). DURATION
# itself is a plain non-negative integer or decimal, with an optional s/m/h/d suffix, or
# inf/infinity (case-insensitive); GNU timeout's signed and scientific-notation forms are not
# recognized, same safe-direction fallback. A duration of 0, or inf/infinity, is rejected
# outright -- GNU timeout treats both as "no limit", which defeats the purpose of wrapping a
# backgrounded command.
#
# A `timeout` prefix only bounds the EXEC of the command itself, not other shell work the shell
# does before exec even starts: `timeout 600 first; second` (a second top-level command),
# `timeout 0.05 echo \`second\`` (a backtick substitution evaluated before `timeout` runs at
# all), and `timeout 0.05 cat </tmp/fifo` (the shell opens the redirection target before exec --
# verified live: this did NOT time out against an unread FIFO, an outer KILL safety timeout had
# to stop it after 1.003s) all pass a naive "starts with timeout" check while the real unbounded
# work happens outside what `timeout` ever supervises. This check is not optional -- without it
# the duration check above means nothing, since any command could be "wrapped" while hiding
# unbounded work in a piece `timeout` never actually bounds. Owner-scoped decision: deliberately
# conservative over clever -- blocks on any LITERAL occurrence of a shell separator,
# substitution, or redirection character (`;` `&` `|` `(` `)` `` ` `` `<` `>` or a real newline)
# anywhere in the command string, with NO quote-awareness at all. This means a command that
# merely MENTIONS one of those characters inside a quoted string (`echo "a;b"`, a `bash -c
# '...'` body containing `;`) false-blocks exactly the same as a real occurrence would --
# intentional: complex work (sequencing, substitutions, redirections) belongs in a script
# invoked as one simple command (e.g. `timeout 300 bash script.sh`), not inlined with characters
# or escape-hatch quoting this hook tries to see through.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/timeout-cap-lib.sh
source "$HERE/lib/timeout-cap-lib.sh"

# $1 = the token immediately after `timeout`. On success, prints "inf" (case-insensitive
# inf/infinity) or the duration in seconds (awk, handles the s/m/h/d suffix). Prints nothing if
# $1 isn't one of these recognized forms -- not this function's job to decide anything then, the
# caller falls through to the generic "not a real wrapper" block.
parse_duration_simple() {
  local token="$1"
  if [[ "$token" =~ ^[Ii][Nn][Ff]([Ii][Nn][Ii][Tt][Yy])?$ ]]; then
    printf 'inf'
    return 0
  fi
  if [[ "$token" =~ ^([0-9]+(\.[0-9]+)?)([smhd]?)$ ]]; then
    local num="${BASH_REMATCH[1]}" unit="${BASH_REMATCH[3]}"
    awk -v n="$num" -v u="$unit" 'BEGIN {
      mult = (u == "m") ? 60 : (u == "h") ? 3600 : (u == "d") ? 86400 : 1
      printf "%.17g", n * mult
    }'
  fi
}

payload=$(cat)

run_in_background=$(printf '%s' "$payload" | jq -r '.tool_input.run_in_background // false')
[ "$run_in_background" = "true" ] || exit 0

cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""')
[ -n "$cmd" ] || exit 0

cap_s=$(safe_cap "${GUARDRAILS_MAX_BG_TIMEOUT_SECONDS:-600}" 600)

case "$cmd" in
  *';'*|*'&'*|*'|'*|*'('*|*')'*|*'`'*|*'<'*|*'>'*|*$'\n'*)
    printf '{"decision":"block","reason":"This backgrounded command contains a shell separator, substitution, or redirection character (; & | ( ) ` < or >) or a newline -- a timeout prefix only bounds the exec of the command ITSELF, not shell work the shell does before exec (a backtick substitution, or opening a redirection target like an unread FIFO or pipe, both run before timeout even starts and are not bounded by it -- verified live: timeout 0.05 cat </tmp/fifo on an unread FIFO did not time out). Put complex work in a script and invoke it as one simple command instead, e.g. timeout 300 bash script.sh , with a duration <= %s seconds."}\n' "$cap_s"
    exit 0
    ;;
esac

if [[ "$cmd" =~ ^[[:space:]]*timeout[[:space:]]+([^[:space:]]+)[[:space:]]+.+$ ]]; then
  token="${BASH_REMATCH[1]}"
  parsed=$(parse_duration_simple "$token")

  if [ -n "$parsed" ]; then
    if [ "$parsed" = "inf" ]; then
      printf '{"decision":"block","reason":"timeout %s specifies an unbounded duration (GNU timeout: inf/infinity means no limit) -- that defeats the whole point of wrapping a backgrounded command. Use a real duration <= %s seconds."}\n' "$token" "$cap_s"
    else
      verdict=$(awk -v d="$parsed" -v cap="$cap_s" 'BEGIN {
        if (d == 0) { print "zero"; exit }
        if (d > cap + 0) { printf "over:%.6g\n", d; exit }
        print "ok"
      }')
      case "$verdict" in
        zero)
          printf '{"decision":"block","reason":"timeout %s disables the timeout entirely (GNU timeout: a duration of 0 means no limit) -- that defeats the whole point of wrapping a backgrounded command. Use a real duration <= %s seconds."}\n' "$token" "$cap_s"
          ;;
        over:*)
          total="${verdict#over:}"
          printf '{"decision":"block","reason":"This backgrounded command declares timeout:%s (%s seconds), above the %s second cap for an unattended background run. Lower it, or if the work genuinely needs longer, split it into checkpoints you can each background separately."}\n' "$token" "$total" "$cap_s"
          ;;
      esac
    fi
    exit 0
  fi
fi

printf '{"decision":"block","reason":"Backgrounded commands must be wrapped in the shell'"'"'s own timeout command -- the tool'"'"'s own timeout field is accepted but NOT enforced for run_in_background:true calls (verified live: a declared timeout:3000ms call still ran to completion ~15s later). Wrap the whole command, e.g. timeout 300 bash script.sh , with a duration <= %s seconds."}\n' "$cap_s"
