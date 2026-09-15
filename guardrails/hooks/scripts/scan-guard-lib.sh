#!/usr/bin/env bash
# Shared plumbing for the blind-scan guardrails (no-blind-find.sh, no-blind-search.sh): quote-aware
# segmentation + word tokenization (honoring backslash escapes), whole-tree root detection with
# quote provenance, command-word anchoring past wrappers/keywords, `bash -c` recursion, and the
# block-payload emitter. Each hook sources this, defines a per-tool segment MATCHER that inspects
# (cmdbase, rest...), and drives it with `scan_command`. The matchers own all tool-specific policy;
# this file owns only the parsing that must stay identical across both hooks.

HOME_VAL="${HOME:-/dev/null/no-home}"

# Break a command line into top-level segments on ; & | ( ) and newlines that are OUTSIDE quotes.
# Single quotes are fully literal; inside double quotes a backslash escapes the next char (so \"
# does not close the quote); an unquoted backslash escapes the next char too.
split_segments() {
  local s="$1" n=${#1} i c q='' out='' bound=1
  for (( i=0; i<n; i++ )); do
    c="${s:i:1}"
    if [ "$q" = "'" ]; then out+="$c"; [ "$c" = "'" ] && q=''; bound=0; continue; fi
    if [ "$q" = '"' ]; then
      if [ "$c" = '\' ]; then out+="$c"; i=$((i+1)); [ "$i" -lt "$n" ] && out+="${s:i:1}"; bound=0; continue; fi
      out+="$c"; [ "$c" = '"' ] && q=''; bound=0; continue
    fi
    case "$c" in
      '#') if [ "$bound" = 1 ]; then
             # unquoted "#" at a word boundary starts a shell comment -> ignore through the newline
             # (separators inside the comment are NOT command breaks). The newline still ends the
             # segment.
             while [ "$i" -lt "$n" ] && [ "${s:i:1}" != $'\n' ]; do i=$((i+1)); done
             [ "$i" -lt "$n" ] && out+=$'\n'; bound=1
           else out+="$c"; bound=0; fi ;;
      \') q="'"; out+="$c"; bound=0 ;;
      \") q='"'; out+="$c"; bound=0 ;;
      \\) out+="$c"; i=$((i+1)); [ "$i" -lt "$n" ] && out+="${s:i:1}"; bound=0 ;;
      ';'|'&'|'|'|'('|')'|$'\n') out+=$'\n'; bound=1 ;;
      ' '|$'\t') out+="$c"; bound=1 ;;
      *) out+="$c"; bound=0 ;;
    esac
  done
  printf '%s\n' "$out"
}

# Split a segment into WORDS, quote-aware (same escaping rules as above). Whitespace inside quotes
# stays within the word, so a quoted pattern like "a / b" is ONE operand. Quotes are PRESERVED in
# each word so is_root can read provenance. One word per output line.
tokenize() {
  local s="$1" n=${#1} i c q='' cur='' started=0
  for (( i=0; i<n; i++ )); do
    c="${s:i:1}"
    if [ "$q" = "'" ]; then cur+="$c"; started=1; [ "$c" = "'" ] && q=''; continue; fi
    if [ "$q" = '"' ]; then
      if [ "$c" = '\' ]; then cur+="$c"; started=1; i=$((i+1)); [ "$i" -lt "$n" ] && cur+="${s:i:1}"; continue; fi
      cur+="$c"; started=1; [ "$c" = '"' ] && q=''; continue
    fi
    case "$c" in
      \') q="'"; cur+="$c"; started=1 ;;
      \") q='"'; cur+="$c"; started=1 ;;
      \\) cur+="$c"; started=1; i=$((i+1)); [ "$i" -lt "$n" ] && cur+="${s:i:1}" ;;
      ' '|$'\t') [ "$started" = 1 ] && { printf '%s\n' "$cur"; cur=''; started=0; } ;;
      *) cur+="$c"; started=1 ;;
    esac
  done
  [ "$started" = 1 ] && printf '%s\n' "$cur"
  return 0
}

# Is WORD (quotes preserved) a whole-tree root, honoring shell quoting?
#   unquoted : /  ~  $HOME  ${HOME}  <literal home>
#   "double" : /  $HOME  ${HOME}  <literal home>     (~ does not expand in quotes)
#   'single' : /  <literal home>                      ($HOME / ~ are literal, not roots)
# A single trailing slash is tolerated; deeper paths are not roots.
is_root() {
  local w="$1" quote=''
  # Strip a trailing slash sitting OUTSIDE the quotes first ("$HOME"/ -> "$HOME"), then the quote
  # layer, then a trailing slash that was INSIDE the quotes ("$HOME/" -> $HOME).
  [ "$w" != "/" ] && w="${w%/}"
  case "$w" in
    \'*\') quote="'"; w="${w:1:${#w}-2}" ;;
    \"*\") quote='"'; w="${w:1:${#w}-2}" ;;
  esac
  [ "$w" != "/" ] && w="${w%/}"
  case "$w" in /|"$HOME_VAL") return 0 ;; esac
  [ "$quote" != "'" ] && case "$w" in '$HOME'|'${HOME}') return 0 ;; esac
  [ -z "$quote" ] && case "$w" in '~') return 0 ;; esac
  return 1
}

# Resolve a quote-preserved token to its effective shell ARGUMENT value: remove quotes and apply
# backslash escapes, honoring single/double-quote rules. Best-effort but enough to classify a
# token's role (is it really an option "-x" / a "--" terminator?) after the shell strips quoting --
# so a quoted option like "-i" or a mixed/escaped form is not mistaken for a positional operand.
# is_root still reads the RAW token for quote provenance; only role classification uses this.
dequote_full() {
  local s="$1" n=${#1} i c q='' out=''
  for (( i=0; i<n; i++ )); do
    c="${s:i:1}"
    if [ "$q" = "'" ]; then [ "$c" = "'" ] && q='' || out+="$c"; continue; fi
    if [ "$q" = '"' ]; then
      if [ "$c" = '\' ]; then
        # Inside "" bash strips a backslash ONLY before $ ` " \ or newline; elsewhere it stays literal.
        case "${s:i+1:1}" in
          '$'|'`'|'"'|'\') i=$((i+1)); out+="${s:i:1}" ;;
          $'\n') i=$((i+1)) ;;
          *) out+="$c" ;;
        esac
        continue
      fi
      [ "$c" = '"' ] && q='' || out+="$c"; continue
    fi
    case "$c" in
      \') q="'" ;;
      \") q='"' ;;
      \\) i=$((i+1)); [ "$i" -lt "$n" ] && out+="${s:i:1}" ;;
      *) out+="$c" ;;
    esac
  done
  printf '%s' "$out"
}

# Does STRING contain an UNQUOTED here-doc / here-string operator ("<<")? The lines that follow such
# an operator are DATA, not commands, and this heuristic parser has no here-doc state -- so the
# caller fails the WHOLE command open when one is present (a real scan buried elsewhere in the
# command is MISSED, never a here-doc's data mis-blocked). Documented fail-open.
_has_heredoc() {
  local s="$1" n=${#1} i c q=''
  for (( i=0; i<n; i++ )); do
    c="${s:i:1}"
    if [ "$q" = "'" ]; then [ "$c" = "'" ] && q=''; continue; fi
    if [ "$q" = '"' ]; then
      if [ "$c" = '\' ]; then i=$((i+1)); continue; fi
      [ "$c" = '"' ] && q=''; continue
    fi
    case "$c" in
      \') q="'" ;;
      \") q='"' ;;
      \\) i=$((i+1)) ;;
      '<') [ $((i+1)) -lt "$n" ] && [ "${s:i+1:1}" = '<' ] && return 0 ;;
    esac
  done
  return 1
}

# Does a role-bearing WORD contain an UNRESOLVED shell expansion ($var, ${...}, $'...', $(...),
# backticks) that is NOT a modeled whole-tree root? Such a word's runtime value -- and therefore its
# role (option? pattern? path?) -- is unknowable to this static parser, so the caller fails open
# rather than assign it a positional role (e.g. `opt=-i; rg "$opt" /` becomes `rg -i /` at runtime,
# where `/` is the PATTERN, not a path). A `$` inside SINGLE quotes is literal and does NOT count.
# The modeled `$HOME`/`${HOME}` roots ARE resolvable, so they are excluded and still classify.
has_unresolved_expansion() {
  local raw="$1"
  is_root "$raw" && return 1
  local n=${#raw} i c q=''
  for (( i=0; i<n; i++ )); do
    c="${raw:i:1}"
    if [ "$q" = "'" ]; then [ "$c" = "'" ] && q=''; continue; fi
    if [ "$q" = '"' ]; then
      if [ "$c" = '\' ]; then i=$((i+1)); continue; fi
      case "$c" in \") q='' ;; '$'|'`') return 0 ;; esac
      continue
    fi
    case "$c" in
      \\) i=$((i+1)) ;;
      \') q="'" ;;
      \") q='"' ;;
      '$'|'`') return 0 ;;
    esac
  done
  return 1
}

# Does STRING contain a physical newline INSIDE quotes, or a backslash-line-continuation? Such a
# newline belongs to a single argument (or joins a logical line), NOT a command separator -- but
# scan_command re-splits its segment stream on newlines, so a scanner-looking line buried in quoted
# multiline DATA would be mis-read as its own command. Fail the whole command open. Documented.
_has_quoted_newline() {
  local s="$1" n=${#1} i c q=''
  for (( i=0; i<n; i++ )); do
    c="${s:i:1}"
    if [ "$q" = "'" ]; then [ "$c" = $'\n' ] && return 0; [ "$c" = "'" ] && q=''; continue; fi
    if [ "$q" = '"' ]; then
      if [ "$c" = '\' ]; then [ "${s:i+1:1}" = $'\n' ] && return 0; i=$((i+1)); continue; fi
      [ "$c" = $'\n' ] && return 0
      [ "$c" = '"' ] && q=''; continue
    fi
    case "$c" in
      \') q="'" ;;
      \") q='"' ;;
      \\) [ "${s:i+1:1}" = $'\n' ] && return 0; i=$((i+1)) ;;
    esac
  done
  return 1
}

# Does STRING mutate HOME anywhere -- a `HOME=...` assignment (standalone, command prefix, `export`ed,
# or an `env HOME=...` wrapper), or `unset HOME`? If so a later `$HOME`/`${HOME}` no longer means the
# real home tree, but this static parser captured HOME_VAL up front and carries no per-segment env
# state -- so fail the whole command open (same class as the `cd / && find .` cwd-state fail-open).
# Conservative: any dequoted token spelled `HOME=...` counts (even quoted data), since over-matching
# only reduces detection, which the contract accepts.
_mutates_home() {
  local s="$1" seg tok is_unset
  while IFS= read -r seg; do
    [ -n "$seg" ] || continue
    local -a w=(); mapfile -t w < <(tokenize "$seg")
    [ "${#w[@]}" -gt 0 ] || continue
    is_unset=0; [ "$(dequote_full "${w[0]}")" = unset ] && is_unset=1
    for tok in "${w[@]}"; do
      tok="$(dequote_full "$tok")"
      case "$tok" in HOME=*) return 0 ;; esac
      [ "$is_unset" = 1 ] && [ "$tok" = HOME ] && return 0
    done
  done < <(split_segments "$s")
  return 1
}

# Walk STRING's top-level segments; for each, resolve the real command word (skipping wrappers and
# shell control keywords) and hand (cmdbase, rest...) to MATCHER_FN. A `bash -c`/`sh -c` body is
# recursed with the SAME matcher; a shell `-n` (no-exec) among the shell options bails (the body is
# only syntax-checked, never run). $3 = recursion depth (guards nesting).
scan_command() {
  local s="$1" mfn="$2" depth="${3:-0}" seg
  [ "$depth" -gt 8 ] && return 1
  # Whole-command fail-open prechecks: forms this segment/word framing can't analyze safely.
  _has_heredoc "$s" && return 1
  _has_quoted_newline "$s" && return 1
  _mutates_home "$s" && return 1
  while IFS= read -r seg; do
    [ -n "$seg" ] || continue
    _scan_segment "$seg" "$mfn" "$depth" && return 0
  done < <(split_segments "$s")
  return 1
}

_scan_segment() {
  local seg="$1" mfn="$2" depth="$3"
  local -a words=()
  mapfile -t words < <(tokenize "$seg")
  [ "${#words[@]}" -gt 0 ] || return 1

  # Real command word, skipping wrappers (their VALUE-options are NOT modeled -- fail-open) and
  # shell control keywords that precede a command.
  local i=0 cmdword=""
  while [ "$i" -lt "${#words[@]}" ]; do
    case "${words[$i]}" in
      if|while|until|then|else|elif|do|'!'|'{') i=$((i+1)); continue ;;
      sudo|command|exec|time|nice|nohup|stdbuf|ionice|xargs|env)
        # A wrapper carrying ANY option can consume the FOLLOWING word as that option's value, which
        # would re-anchor us on the wrong command -- e.g. `env -u find echo /` unsets a var named
        # "find" and runs `echo /`, but naively skipping `-u` anchors "find" and mis-blocks. So fail
        # the segment OPEN when a wrapper has an option; pass through only the no-option form
        # (VAR=val assignments are self-contained and safe to skip).
        i=$((i+1))
        while [ "$i" -lt "${#words[@]}" ]; do
          case "${words[$i]}" in
            -*)  return 1 ;;
            *=*) i=$((i+1)) ;;
            *)   break ;;
          esac
        done
        continue ;;
      -*|*=*) i=$((i+1)); continue ;;
      *) cmdword="${words[$i]}"; break ;;
    esac
  done
  [ -n "$cmdword" ] || return 1
  local cmdbase; cmdbase="$(dequote_full "$cmdword")"; cmdbase="${cmdbase##*/}"
  local -a rest=("${words[@]:$((i+1))}")

  # bash -c BODY / sh -c / ... : recurse the whole check on the -c argument.
  case "$cmdbase" in
    bash|sh|dash|zsh|ksh)
      # Classify shell options on the DEQUOTED token (quoting doesn't change argv), so a quoted
      # `"-n"`/`"-c"` is still recognized. A `-n` (no-exec) means the body is only syntax-checked ->
      # not a scan. A pre-`-c` `--` ends option parsing, so the following `-c` is a script FILENAME
      # and the body is NOT executed -> bail. Reaching the `-c` cluster recurses on the body.
      local k m rk
      for (( k=0; k<${#rest[@]}; k++ )); do
        rk="$(dequote_full "${rest[$k]}")"
        [ "$rk" = "--" ] && return 1
        [[ "$rk" != -* ]] && return 1                  # a script-name operand ends option parsing: a later -c is its arg, not the flag
        [ "$rk" = "-o" ] && return 1                    # `-o <name>` (e.g. `-o noexec`) is value-taking / may be no-exec -> fail open
        [[ "$rk" =~ ^-[a-zA-Z]*n[a-zA-Z]*$ ]] && return 1
        if [[ "$rk" =~ ^-[a-zA-Z]*c$ ]]; then
          m=$((k+1))
          [ "$m" -lt "${#rest[@]}" ] && [ "$(dequote_full "${rest[$m]}")" = "--" ] && m=$((m+1))
          [ "$m" -lt "${#rest[@]}" ] && scan_command "$(dequote_full "${rest[$m]}")" "$mfn" $((depth+1)) && return 0
          return 1
        fi
      done
      return 1 ;;
  esac

  "$mfn" "$cmdbase" "${rest[@]}"
}

# The block-payload reason, shared so both hooks speak with one voice. Built with jq so the quotes
# and backticks in the text always produce valid JSON.
BLOCK_REASON='Refusing a recursive scan rooted at the whole filesystem (/) or your entire home directory. A search that broad usually means you do not yet know where to look -- it is slow, and the answer is almost never "everywhere". Narrow it to the specific directory you actually need (the project/repo/cwd, e.g. `find . -name X` or `grep -r X src/`), or ask the user where to look. If a genuinely system-wide search is truly required, run it yourself outside the agent.'

emit_block() { jq -nc --arg r "$BLOCK_REASON" '{decision:"block",reason:$r}'; }
