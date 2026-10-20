#!/usr/bin/env bash
# PreToolUse(Bash): block `tail` in follow mode (-f, -F, --follow and its unambiguous GNU
# abbreviations, in any short-option cluster). A follow-mode tail does not exit on its own, so any
# command or pipeline containing it (including `tail -F f | grep -m1 X`, where the consumer exits
# but tail keeps running until its next write) never completes and the caller stalls with no
# completion notice. A `--pid`-bounded follow is blocked too: it only ends when that process does.
#
# Lexical within a command segment, so it applies wherever a command line can appear: the word
# `tail` followed by a follow option is found after ANY prefix -- wrappers with options (sudo -u x,
# env -u X, watch), command carriers whose argv is the command (ssh host tail -f f, docker exec c
# tail -f f, kubectl exec p -- tail -f f). Every multi-word argument (bash -c bodies, ssh "tail
# -F f", sbatch --wrap "...") is scanned the same way, to a bounded nesting depth. The price is
# that a segment merely naming the words (echo 'tail -f x', grep -rn 'tail -F' d) is blocked too.
# It deliberately does NOT fail open on heredocs or quoted newlines (unlike the command-word hooks
# in scan-guard-lib.sh): a heredoc body or multi-line string is scanned like any other text, so a
# real `tail -f x; cat <<EOF ...` is caught, and data that names `tail -f` is blocked as well.
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/scan-guard-lib.sh"

cmd=$(jq -r '.tool_input.command // ""')
[ -n "$cmd" ] || exit 0

MAX_DEPTH=8

# Is this long option a (possibly abbreviated) --follow? GNU getopt accepts every unambiguous
# prefix, and "f" is only ever --follow for tail.
long_is_follow() {
  local name="${1#--}"; name="${name%%=*}"
  [ -n "$name" ] && [[ "follow" == "$name"* ]]
}

# Does this long option (without =value) take its value as the NEXT word? Any prefix of a
# value-taking long option counts (an ambiguous prefix makes tail error out, so it never follows).
long_takes_next_value() {
  local name="${1#--}" opt
  case "$1" in *=*) return 1 ;; esac
  [ -n "$name" ] || return 1
  for opt in lines bytes pid sleep-interval max-unchanged-stats; do
    [[ "$opt" == "$name"* ]] && return 0
  done
  return 1
}

# Classify a short-option cluster (e.g. -fn5, -qF): prints "follow", "value" (the cluster ends in
# a value-taking option -n/-c/-s, so the NEXT word is its value), or "none". tail's value-taking
# short options consume the rest of the cluster as their value, so scanning stops there.
tail_cluster_kind() {
  local cluster="${1#-}" i ch
  for (( i=0; i<${#cluster}; i++ )); do
    ch="${cluster:$i:1}"
    case "$ch" in
      f|F) echo follow; return ;;
      n|c|s) [ "$i" -eq $(( ${#cluster} - 1 )) ] && echo value || echo none; return ;;
    esac
  done
  echo none
}

# Do the words after a `tail` word (up to the end of the segment) enable follow mode? A word
# consumed as the value of -n/-c/-s/--lines/--bytes/--pid/... is not itself an option.
tail_args_follow() {
  local a skip=0
  for a in "$@"; do
    a="$(dequote_full "$a")"
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    [ "$a" = "--" ] && return 1
    case "$a" in
      --*)
        long_is_follow "$a" && return 0
        long_takes_next_value "$a" && skip=1 ;;
      -?*)
        case "$(tail_cluster_kind "$a")" in
          follow) return 0 ;;
          value) skip=1 ;;
        esac ;;
    esac
  done
  return 1
}

scan_line() {
  local s="$1" depth="$2" seg w k a base
  [ "$depth" -gt "$MAX_DEPTH" ] && return 1
  local -a words
  while IFS= read -r seg; do
    [ -n "$seg" ] || continue
    mapfile -t words < <(tokenize "$seg")
    for (( k=0; k<${#words[@]}; k++ )); do
      w="$(dequote_full "${words[$k]}")"
      base="${w##*/}"
      if [ "$base" = tail ] && tail_args_follow "${words[@]:$((k+1))}"; then
        return 0
      fi
      case "$w" in
        *[[:space:]]*) scan_line "$w" $((depth+1)) && return 0 ;;
      esac
    done
  done < <(split_segments "$s")
  return 1
}

scan_line "$cmd" 0 || exit 0

printf '{"decision":"block","reason":"Do not run tail in follow mode (-f, -F, --follow and its abbreviations): it does not exit by itself, so the command never completes and you stall with no completion notice -- even when piped into grep -m or head, because tail keeps running until its next write. Let the harness wake you instead of watching or polling. Run the long job with run_in_background:true (on Claude Code you are notified when it finishes; on pi delegate it to the Agent tool, whose result arrives as a notification). If you need to check progress before it finishes, schedule the check (ScheduleWakeup or CronCreate on Claude Code; schedule_prompt on pi) rather than looping on a command."}'
