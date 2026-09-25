#!/usr/bin/env bash
# PreToolUse(Bash): block `find` (through wrappers and `bash -c` bodies) whose SEARCH ROOT is a
# whole tree -- the root dir "/" or the user's entire home ("~", "$HOME", "${HOME}", or its literal
# path). find's grammar is unambiguous -- `find [-H/-L/-P/-D/-O] PATH... EXPRESSION` -- so the
# leading path operands ARE the roots: there is no pattern/path ambiguity and no value-option can
# masquerade as a path, so this hook needs no arity guessing and never mis-blocks a legitimate find.
# A deeper path (~/proj, /home/u/proj, src/) is fine. Recursive grep/rg/fd/ls -R are handled
# separately in no-blind-search.sh so the two can evolve independently.
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/scan-guard-lib.sh"

cmd=$(jq -r '.tool_input.command // ""')
[ -n "$cmd" ] || exit 0

# A HOME reassignment anywhere makes a later $HOME/${HOME} root-classification ambiguous (this
# parser has no per-segment env state) -- fail the whole command open, same class as scan_command's
# own heredoc/quoted-newline prechecks, but specific to this hook's HOME-based root detection.
_mutates_home "$cmd" && exit 0

# Roots are the leading path operands, up to the first expression token ("-something", "(", "!", …).
# Pre-path options: -H/-L/-P valueless, -D takes a value, -O<level> attached. Options/expression
# delimiters are classified on the DEQUOTED token (a quoted/expanded predicate like `find "-newer" /`
# is still a predicate, so its operand is not a path); is_root reads the RAW token for provenance. A
# path operand whose runtime value is unknowable (unresolved expansion) fails open.
find_seg() {
  local cmdbase="$1"; shift
  [ "$cmdbase" = find ] || return 1
  local -a rest=("$@")
  local k=0 bt
  while [ "$k" -lt "${#rest[@]}" ]; do
    bt="$(dequote_full "${rest[$k]}")"
    case "$bt" in
      -H|-L|-P)    k=$((k+1)) ;;
      -D)          k=$((k+2)) ;;
      -O*)         k=$((k+1)) ;;
      --)          k=$((k+1)) ;;
      -*|'('|'!')  break ;;                                   # expression starts -> paths have ended
      *)           has_unresolved_expansion "${rest[$k]}" && return 1
                   is_root "${rest[$k]}" && return 0
                   k=$((k+1)) ;;
    esac
  done
  return 1
}

scan_command "$cmd" find_seg || exit 0
emit_block
