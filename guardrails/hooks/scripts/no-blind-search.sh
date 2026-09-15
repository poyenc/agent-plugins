#!/usr/bin/env bash
# PreToolUse(Bash): block a recursive content/name search (grep -r/-R, rg, fd) or recursive listing
# (ls -R) whose path is a whole tree -- "/", "~", "$HOME", "${HOME}", or the literal home path
# (through wrappers and `bash -c` bodies too).
#
# Unlike find, these tools mix a PATTERN operand with PATH operands and carry many value-taking
# options, so telling a real path from a pattern (or from an option's value) needs per-flag arity.
# Rather than guess -- which risks mis-blocking legitimate commands -- this hook is deliberately
# CONSERVATIVE and needs no arity table: it blocks ONLY the plainest form and FAILS OPEN the moment
# any other/unknown option appears (that option might take a value and shift the operands).
#
#   grep : block iff every flag is a pure recursion flag (-r / -R / --recursive), at least one is
#          present, and a whole-tree root sits in a PATH slot (operand index >= 1; operand 0 is the
#          pattern). Any other flag (including bundles like -rn, or -e/-f/--include/...) -> fail open.
#   rg   : recursive by default; block iff there are NO flags at all and a root sits at operand
#          index >= 1. Any flag (e.g. -i, -g, --files, -r) -> fail open.
#   fd   : recursive by default; same rule as rg.
#   ls   : block iff every flag is a pure recursion flag (-R / --recursive), at least one is present,
#          and any operand (index >= 0; ls has no pattern operand) is a whole-tree root.
#
# So it catches the common `grep -r foo /`, `rg foo /`, `fd foo /`, `ls -R /`, but MISSES (never
# mis-blocks) anything carrying extra flags: `grep -rn foo /`, `grep -r --include=x foo /`,
# `rg -i foo /`, `rg --files /`, `rg -g x foo /`, `fd -e txt /`, `ls -Ra /`, ... -- an acceptable
# fail-open, since an agent naively over-broadening a search still trips the common forms and is not
# adversarially evading its own guardrail.
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/scan-guard-lib.sh"

cmd=$(jq -r '.tool_input.command // ""')
[ -n "$cmd" ] || exit 0

# Split rest into FLAGS[] and positional OPERANDS[] (dropping redirections, honoring --). No arity
# modeling on purpose: a flag is any leading-"-" token (except a lone "-"); its mere presence may
# make the tool rule below fail open. Sets FLAGS/OPERANDS in the caller's scope (dynamic scope).
_collect() {
  FLAGS=(); OPERANDS=()
  local -a a=("$@")
  local ddash=0 j=0 t bt
  while [ "$j" -lt "${#a[@]}" ]; do
    t="${a[$j]}"
    # A redirection operator is only a redirection UNQUOTED, so match it on the raw token (a quoted
    # ">" is a literal filename). Everything else is classified on the DEQUOTED value, since the
    # shell strips quotes before the tool sees argv -- so a quoted `"-i"`/`"--"` is an option/
    # terminator, not a positional operand. OPERANDS keep the RAW token so is_root reads provenance.
    if [[ "$t" =~ ^[0-9]*(\>\>?|\<|\&\>) ]]; then
      [[ "$t" =~ (\>\>?|\<|\&\>)$ ]] && j=$((j+1))     # separate redirect target -> skip it too
      j=$((j+1)); continue
    fi
    bt="$(dequote_full "$t")"
    if [ "$ddash" = 0 ] && [ "$bt" = "--" ]; then ddash=1; j=$((j+1)); continue; fi
    if [ "$ddash" = 0 ] && [ "$bt" != "-" ] && [[ "$bt" == -* ]]; then FLAGS+=("$t"); j=$((j+1)); continue; fi
    OPERANDS+=("$t"); j=$((j+1))
  done
}

# Is any operand at index >= START a whole-tree root?  Reads OPERANDS (dynamic scope).
_root_from() {
  local start="$1" idx
  for idx in "${!OPERANDS[@]}"; do
    [ "$idx" -ge "$start" ] || continue
    is_root "${OPERANDS[$idx]}" && return 0
  done
  return 1
}

# Are ALL flags drawn from the given allowed (pure recursion) set, with at least one present?
# Reads FLAGS (dynamic scope). $@ = the allowed flag tokens.
_only_recursion() {
  local -a allowed=("$@")
  local f a ok
  [ "${#FLAGS[@]}" -gt 0 ] || return 1
  for f in "${FLAGS[@]}"; do
    ok=0
    for a in "${allowed[@]}"; do [ "$f" = "$a" ] && { ok=1; break; }; done
    [ "$ok" = 1 ] || return 1
  done
  return 0
}

# grep/rg/fd share a positional-pattern grammar (root path at operand index >= 1); ls has no pattern
# (any operand may be a path, so index >= 0). Any unknown flag, or an operand with an unresolved
# expansion, fails the segment open.
search_seg() {
  local cmdbase="$1"; shift
  local -a FLAGS OPERANDS
  _collect "$@"
  local o; for o in "${OPERANDS[@]}"; do has_unresolved_expansion "$o" && return 1; done
  local start=1
  case "$cmdbase" in
    grep)  _only_recursion -r -R --recursive || return 1 ;;
    rg|fd) [ "${#FLAGS[@]}" -eq 0 ] || return 1 ;;
    ls)    _only_recursion -R --recursive || return 1; start=0 ;;
    *)     return 1 ;;
  esac
  _root_from "$start" && return 0
  return 1
}

scan_command "$cmd" search_seg || exit 0
emit_block
