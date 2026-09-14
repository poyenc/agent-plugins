#!/usr/bin/env bash
# rotate-common.sh — shared backbone for herdr-rotate-<kind>. Sourced, not executed.
# The caller sets `set -euo pipefail`. All herdr access is via the `herdr` command.

note() { printf 'herdr-rotate: %s\n' "$*" >&2; }
die()  { printf 'herdr-rotate: ERROR: %s\n' "$*" >&2; exit 1; }

guard() { [ "${HERDR_ENV:-}" = 1 ]; }

# A pane's live column width, or empty if herdr can't report it. A pane appears in its own
# `edges` layout list; pick that entry's rect width. Best-effort only (see log_pane_diag).
pane_width() {
  herdr pane edges --pane "$1" 2>/dev/null \
    | jq -r --arg p "$1" '.result.edges.layout.panes[]? | select(.pane_id==$p) | .rect.width' 2>/dev/null \
    | head -n1
}

# Failure-path diagnostics ONLY (never the happy path): dump a captured pane render plus the
# pane's live width to the rotation log, so a detection or exit failure can be diagnosed from the
# log alone -- without launching a throwaway agent to re-probe a picker that, by the time anything
# downstream notices the miss, has already been closed. The render is passed in by the caller,
# captured at the moment of the miss; width is read fresh here and degrades to "unknown" rather
# than ever failing the rotation over a diagnostic. The trailing marker delimits the raw render
# (which carries no `herdr-rotate:` prefix of its own) from the normal log flow that resumes after.
log_pane_diag() {
  local pane="$1" ctx="$2" render="$3" w
  # `|| true` INSIDE the substitution, not `w=$(...) || w=`: the per-kind scripts run under
  # `set -euo pipefail`, and pane_width is a herdr|jq|head pipeline -- a failed/malformed
  # `herdr pane edges` makes it exit nonzero (pipefail), which as a bare `w=$(...)` assignment
  # would abort the whole rotation. A diagnostic must never do that -- degrade to "unknown".
  w=$(pane_width "$pane" || true); [ -n "$w" ] || w=unknown
  note "$ctx (pane $pane, width $w) -- captured render for diagnosis:"
  printf '%s\n' "$render" >&2
  note "(end captured render for $pane)"
}

# "wG:p4" + "claude" -> "claude-wgp4" (lowercase, keep [a-z0-9], clamp 32).
derive_name() {
  local kind="$1" pane="$2" suffix
  suffix=$(printf '%s' "$pane" | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9')
  printf '%s' "${kind}-${suffix}" | cut -c1-32
}

# herdr agent-name grammar.
valid_name() { [[ "$1" =~ ^[a-z][a-z0-9_-]{0,31}$ ]]; }

# Strips resume/continue/session flags so a "fresh" relaunch doesn't silently resume old
# conversation history -- semantics verified against each CLI's own --help and differ by kind:
#   claude: -c/--continue (boolean); -r/--resume [value] (OPTIONAL value -- only consumed if
#     the next token doesn't look like a flag, since claude's own parser resolves the ambiguity
#     the same way, and a bare leftover here would otherwise be misread as the positional
#     prompt); --session-id <uuid> (required value).
#   pi: --continue/-c (boolean); --resume/-r (BOOLEAN -- pi's --help shows no <value> for this,
#     unlike claude, so this must NEVER consume the next token); --session/--session-id <id>
#     and --fork <path|id> (required value each; forking also carries old context forward).
#   codex: resume/fork are SUBCOMMANDS (a leading positional, not a flag) -- `codex resume
#     [SESSION_ID] [PROMPT]` / `codex fork [SESSION_ID] [PROMPT]`. Handled separately, before
#     this loop, since it's positional. codex's own -c/--config is UNRELATED to any of this
#     (this very script uses it for -c model_reasoning_effort=...) and must never be touched.
strip_context_flags() {
  local kind="$1"; shift
  local -a args=("$@")
  if [ "$kind" = codex ]; then
    case "${args[0]:-}" in
      resume|fork)
        args=("${args[@]:1}")
        [ -n "${args[0]:-}" ] && [[ "${args[0]}" != -* ]] && args=("${args[@]:1}")
        ;;
    esac
  fi
  local n=${#args[@]} i=0 tok
  while [ "$i" -lt "$n" ]; do
    tok="${args[$i]}"
    case "$kind:$tok" in
      claude:--continue|claude:-c)              i=$((i+1)) ;;
      claude:--session-id)                       i=$((i+2)) ;;
      claude:--session-id=*)                     i=$((i+1)) ;;
      claude:--resume|claude:-r)
        i=$((i+1))
        [ "$i" -lt "$n" ] && [[ "${args[$i]}" != -* ]] && i=$((i+1))
        ;;
      claude:--resume=*)                          i=$((i+1)) ;;
      claude:-r?*)                                 i=$((i+1)) ;;   # attached short form: -r<session-id>, no space
      pi:--continue|pi:-c|pi:--resume|pi:-r)      i=$((i+1)) ;;
      pi:--session|pi:--session-id|pi:--fork)     i=$((i+2)) ;;
      pi:--session=*|pi:--session-id=*|pi:--fork=*) i=$((i+1)) ;;
      codex:--last)                               i=$((i+1)) ;;
      *:--)
        # End-of-options marker: nothing after this is a flag to any of these CLIs, so stop
        # pattern-matching and copy the rest through verbatim (same "not auto-stripped"
        # tradeoff as a positional prompt -- see SKILL.md Known limitations).
        while [ "$i" -lt "$n" ]; do printf '%s\0' "${args[$i]}"; i=$((i+1)); done
        ;;
      *) printf '%s\0' "$tok"; i=$((i+1)) ;;
    esac
  done
}

# flag: the canonical (long) spelling to write. Trailing args: other accepted spellings of the
# SAME flag (e.g. codex's -m is also accepted as --model) -- matched only to find an EXISTING
# occurrence to replace; the replacement itself always writes the canonical "$flag $val" form,
# never the spelling that was found, and never a second, duplicate occurrence alongside the
# original. If the flag repeats in the input, only the LAST occurrence (the one a real CLI's own
# last-flag-wins parsing would actually apply) is touched -- earlier occurrences are left exactly
# as the user wrote them.
replace_or_append_flag() {
  local -n _arr="$1"; local flag="$2" val="$3"; shift 3
  local -a aliases=("$flag" "$@")
  local n=${#_arr[@]} j a skip
  local boundary=$n last_idx=-1 last_skip=0
  j=0
  while [ "$j" -lt "$n" ]; do
    # Past "--", nothing is a flag any more (see strip_context_flags) -- stop matching so an
    # override can't be inserted into, or mistakenly match, positional data on the far side.
    if [ "${_arr[$j]}" = "--" ]; then boundary=$j; break; fi
    skip=1
    for a in "${aliases[@]}"; do
      if [ "${_arr[$j]}" = "$a" ]; then last_idx=$j; last_skip=2; skip=2; break
      elif [[ "${_arr[$j]}" == "$a="* ]]; then last_idx=$j; last_skip=1; break
      # A short single-dash alias (e.g. codex's -m) also accepts an ATTACHED value with no
      # separator (-mVALUE) -- long --flags don't (they require --flag=VALUE), so this only
      # applies to exactly "-X" spellings.
      elif [ "${#a}" -eq 2 ] && [[ "$a" == -[^-]* ]] && [[ "${_arr[$j]}" == "$a"?* ]]; then
        last_idx=$j; last_skip=1; break
      fi
    done
    # A "space"-mode match consumes its value token too -- advance past it so the value is
    # never independently re-scanned as if it were another occurrence of the flag.
    j=$((j+skip))
  done
  local -a out=()
  if [ "$last_idx" -ge 0 ]; then
    out=("${_arr[@]:0:$last_idx}" "$flag" "$val" "${_arr[@]:$((last_idx+last_skip))}")
  else
    out=("${_arr[@]:0:$boundary}" "$flag" "$val" "${_arr[@]:$boundary}")
  fi
  _arr=("${out[@]}")
}

# The inverse of replace_or_append_flag: removes EVERY occurrence of $flag (any of the given
# alias spellings), together with each occurrence's own value token, instead of replacing one.
# Exists for claude's "Default" model entry (see detect_override's own DETECTED_MODEL_DEFAULT
# comment): Default carries no fixed identifier of its own (only a lossy family alias), so the
# only way to correctly preserve "follow whatever Default resolves to" on relaunch is a BARE
# argv with no --model at all -- neither replaying a stale explicit value nor synthesizing a new,
# lossy one is correct there. Same matching conventions as replace_or_append_flag (space form,
# attached "=", short-form attached value, stops at a literal "--"), same nameref/single-use
# reasoning. Removes ALL occurrences, not just the last one: unlike a value that's meant to be
# replaced in place, a flag being entirely removed should not leave an earlier stale duplicate
# behind either.
remove_flag() {
  local -n _flags_arr="$1"; local target_flag="$2"; shift 2
  local -a aliases=("$target_flag" "$@")
  local n=${#_flags_arr[@]} j a skip
  local -a out=()
  j=0
  while [ "$j" -lt "$n" ]; do
    if [ "${_flags_arr[$j]}" = "--" ]; then out+=("${_flags_arr[@]:$j}"); break; fi
    skip=0
    for a in "${aliases[@]}"; do
      if [ "${_flags_arr[$j]}" = "$a" ]; then skip=2; break
      elif [[ "${_flags_arr[$j]}" == "$a="* ]]; then skip=1; break
      elif [ "${#a}" -eq 2 ] && [[ "$a" == -[^-]* ]] && [[ "${_flags_arr[$j]}" == "$a"?* ]]; then
        skip=1; break
      fi
    done
    if [ "$skip" -eq 0 ]; then out+=("${_flags_arr[$j]}"); j=$((j+1)); else j=$((j+skip)); fi
  done
  _flags_arr=("${out[@]}")
}

# Same last-occurrence-only, replace-in-place behavior as replace_or_append_flag, for codex's
# "-c key=value" kv encoding. -c/--config are two spellings of the SAME flag (confirmed via
# `codex --help`: "-c, --config <key=value>" documented as one entry), so this recognizes all
# four forms codex's own CLI accepts as real, semantically-correct spellings: the two-token
# "-c key=value" / "--config key=value", and the ATTACHED single-token "-ckey=value" (no space)
# / "--config=key=value" (long-flag "=" form) -- confirmed live against the installed codex
# binary. (A short-flag "-c=key=value" form is NOT included: clap does not strip "=" for short
# options, so that token's value would literally be "=key=value", setting the wrong TOML key --
# not a real alternate spelling.) Each form also tolerates TOML's own optional whitespace around
# "=" AND around the whole assignment (e.g. "key = value", " key=value ", confirmed live) -- the
# match only needs to detect an EXISTING occurrence to replace; whatever it looked like, the
# replacement is always written in the canonical "-c key=value" form, no whitespace. An
# attached-form match is spliced out alone (skip=1), not as a pair, since there's no separate
# value token to remove.
replace_or_append_kv() {
  # shellcheck disable=SC2178
  local -n _arr="$1"; local key="$2" val="$3"
  local n=${#_arr[@]} j
  local boundary=$n last_idx=-1 last_skip=0
  for (( j=0; j<n; j++ )); do
    if [ "${_arr[$j]}" = "--" ]; then boundary=$j; break; fi
    if { [ "${_arr[$j]}" = "-c" ] || [ "${_arr[$j]}" = "--config" ]; } && [ $((j+1)) -lt "$n" ] && [[ "${_arr[$((j+1))]}" =~ ^[[:space:]]*${key}[[:space:]]*=[[:space:]]* ]]; then
      last_idx=$j; last_skip=2
    elif [[ "${_arr[$j]}" =~ ^-c[[:space:]]*${key}[[:space:]]*=[[:space:]]* ]] || [[ "${_arr[$j]}" =~ ^--config=[[:space:]]*${key}[[:space:]]*=[[:space:]]* ]]; then
      last_idx=$j; last_skip=1
    fi
  done
  local -a out=()
  if [ "$last_idx" -ge 0 ]; then
    out=("${_arr[@]:0:$last_idx}" "-c" "$key=$val" "${_arr[@]:$((last_idx+last_skip))}")
  else
    out=("${_arr[@]:0:$boundary}" "-c" "$key=$val" "${_arr[@]:$boundary}")
  fi
  _arr=("${out[@]}")
}

# Shared. Requires globals MODEL_FLAG, EFFORT_FLAG, EFFORT_STYLE (set by per-kind script).
# MODEL_FLAG_ALIASES (optional, set by per-kind script): other accepted spellings of
# MODEL_FLAG, e.g. codex's -m is also accepted as --model.
apply_override() {
  local m="$1" e="$2"
  [ -n "$m" ] && replace_or_append_flag BASE_FLAGS "$MODEL_FLAG" "$m" "${MODEL_FLAG_ALIASES[@]}"
  if [ -n "$e" ]; then
    case "$EFFORT_STYLE" in
      flag) replace_or_append_flag BASE_FLAGS "$EFFORT_FLAG" "$e" ;;
      kv)   replace_or_append_kv   BASE_FLAGS "$EFFORT_FLAG" "$e" ;;
      *) die "unknown EFFORT_STYLE: $EFFORT_STYLE" ;;
    esac
  fi
}

capture_argv() {
  local pane="$1" kind="$2" json
  json=$(herdr pane process-info --pane "$pane" 2>/dev/null) \
    || die "process-info failed for pane $pane"
  local -a raw
  mapfile -d '' -t raw < <(printf '%s' "$json" | jq -j --arg k "$kind" '
    .result.process_info.foreground_processes[] | select(.name==$k) | .argv[] | . + "\u0000"')
  [ "${#raw[@]}" -gt 0 ] || die "no $kind process on pane $pane"
  # How many leading argv entries are the launcher rather than real flags. Normally just argv[0]
  # (the bin: "claude"/"codex"/"pi"). But an interpreter-launched CLI reports its true cmdline:
  # pi on Linux now preserves argv (writes /proc/self/comm instead of clobbering argv via
  # process.title), so its argv is `node /abs/dist/cli.js <flags>` -- argv[0] is the interpreter
  # and argv[1] the script path. Both must be dropped, or the replay becomes `pi /abs/dist/cli.js
  # ...` and the CLI treats the script path as an initial prompt. A clobbered pi (older builds, or
  # macOS) reports just ["pi"], so drop stays 1 and BASE_FLAGS is empty as before.
  # Interpreters that exec as `<interp> <script> <flags>` (script directly after the binary).
  # Deliberately excludes deno, which launches as `deno run <script>` -- a subcommand between the
  # two would make drop=2 strip a flag instead of the script.
  local drop=1
  case "${raw[0]##*/}" in
    node|nodejs|bun|ts-node|tsx) [ "${#raw[@]}" -gt 1 ] && drop=2 ;;
  esac
  mapfile -d '' -t BASE_FLAGS < <(strip_context_flags "$kind" "${raw[@]:$drop}")
}

# Only a "kind":"id" agent_session (currently claude) is a real per-session identifier; pi's is
# a filesystem path (its first bytes are not distinct across sessions) and codex has none at
# all. Returns empty for anything else, so the "@session" correlation is honestly skipped there
# instead of silently doing nothing useful.
session_id_for() {
  printf '%s' "$1" | jq -r 'if .kind=="id" then .value else "" end'
}

# <target> is normally a name or pane id. A trailing "@<session-prefix>" (as embedded in the
# handoff ping's tag) additionally asserts that the pane's live agent_session still matches —
# catching a stale ping from an earlier rotation, or a pane whose occupant already changed.
# (Only meaningful for claude targets — see session_id_for.)
resolve() {
  local target="$1" expected_session=""
  case "$target" in *@*) expected_session="${target##*@}"; target="${target%@*}" ;; esac
  local row
  row=$(herdr agent list 2>/dev/null \
        | jq -r --arg t "$target" '
            first(.result.agents[] | select(.name==$t or .pane_id==$t))
            | [.agent, .pane_id, (.name // ""), (.agent_session // {} | tojson)] | @tsv') || die "agent list failed"
  [ -n "$row" ] || die "target not found: $target"
  # @tsv fields are tab-delimited; IFS=$'\t' read collapses an EMPTY middle field (e.g. an
  # unnamed agent) because tab is treated as IFS whitespace regardless of this assignment —
  # mapfile -d preserves empty fields correctly instead.
  local -a fields
  mapfile -d $'\t' -t fields <<<"$row"
  [ "${#fields[@]}" -eq 4 ] || die "target not found: $target"
  fields[3]="${fields[3]%$'\n'}"   # <<< appends a trailing newline to the last field
  ROTATE_KIND="${fields[0]}" ROTATE_PANE="${fields[1]}" ROTATE_NAME="${fields[2]}"
  [ -n "$ROTATE_KIND" ] && [ -n "$ROTATE_PANE" ] || die "target not found: $target"
  ROTATE_SESSION=$(session_id_for "${fields[3]}")
  if [ -n "$expected_session" ] && [ "${ROTATE_SESSION:0:8}" != "$expected_session" ]; then
    die "target $target's session changed (expected ${expected_session}, now ${ROTATE_SESSION:0:8}) — stale ping or pane occupant changed; not proceeding"
  fi
  if [ -z "$ROTATE_NAME" ]; then
    if [ -n "${OVERRIDE_NAME:-}" ]; then ROTATE_NAME="$OVERRIDE_NAME"
    else ROTATE_NAME=$(derive_name "$ROTATE_KIND" "$ROTATE_PANE"); fi
    note "agent unnamed; assigned name: $ROTATE_NAME"
  fi
}

# Re-checks the pane's live session against what resolve() observed, immediately before the
# destructive step below — closes the window where a wait/detection delay lets a stale ping
# race past the earlier check in resolve(). No-op if resolve() couldn't get a session id (pi,
# codex): there is nothing to compare against, so no false confidence either way.
revalidate_session() {
  local pane="$1" expected="$2"
  [ -n "$expected" ] || return 0
  local current
  current=$(herdr agent list 2>/dev/null | jq -r --arg p "$pane" '
    first(.result.agents[] | select(.pane_id==$p)) | (.agent_session // {} | tojson)') \
    || die "agent list failed"
  current=$(session_id_for "$current")
  [ "$current" = "$expected" ] || die "pane $pane's session changed just before exit (expected ${expected:0:8}, now ${current:0:8}) — not proceeding"
}

# Bounded wait for the target to settle to idle/done before we touch its UI. The target's ping
# fires mid-turn (from its own Bash tool call), so acting immediately on receipt could race the
# tail end of that same turn. Dies on timeout rather than proceeding — the next step is
# destructive (/quit) and should never run against a target that isn't confirmed settled.
wait_settled() {
  local pane="$1" st="" deadline=$(( SECONDS + ${ROTATE_SETTLE_POLL_SECS:-150} ))
  while [ "$SECONDS" -lt "$deadline" ]; do
    st=$(herdr agent get "$pane" 2>/dev/null | jq -r '.result.agent.agent_status // empty') || st=""
    case "$st" in idle|done) return 0 ;; esac
    command sleep 1
  done
  die "target on $pane did not settle within ${ROTATE_SETTLE_POLL_SECS:-150}s (status: ${st:-unknown}) — not proceeding with a destructive step against a possibly still-active session"
}

# %s slots: default handoff path, orchestrator pane id, target's own name (twice: instruction + literal tag).
HANDOFF_PROMPT='Write a handoff so a fresh agent can continue this work with zero prior context — if you have a handoff skill available, invoke it now; that skill knows how to write one properly (including a team handoff, if you have live teammates), so do not duplicate its judgment here. If you do not have one, capture at minimum: the objective and what "done" looks like; task status and the exact next action; key files/branch/commands by reference, not pasted; dead ends already ruled out; and the operating rules and decisions made this session with their why — strip secrets. A default save path is %s (create the directory with mkdir -m 700 -p if needed) — use it, or your own path if more fitting; the file you actually write is authoritative.

SEPARATE FROM THE DOCUMENT — a real action YOU must take yourself, right now, after the file is written (this is not something to describe inside the handoff, and not a step for whoever reads it next): run this exact shell command yourself via your Bash tool: `herdr agent prompt %s "%s: <absolute-path-of-the-file-you-wrote>"` — replace the placeholder with the real absolute path, keep "%s: " as a literal prefix (it identifies this rotation), and put nothing else in the message. Do not just print or mention this command — execute it. Then stop — do not continue the task after that; you are about to be replaced.'

# Fires the handoff prompt and returns immediately — does not wait or poll. Completion is
# reported back by the target pinging $HERDR_PANE_ID (the orchestrator), tagged with the
# target's name + this rotation's live session-id prefix (see resolve()'s "@" handling), so
# neither a concurrent rotation of another agent nor a stale ping from an earlier rotation of
# THIS agent can be mistaken for the current one. Dies loudly if the send itself fails — a
# silently-dropped prompt would otherwise leave the orchestrator waiting on a ping forever.
send_handoff() {
  local pane="$1" name="$2" session="$3"
  # Tag by PANE, not name: if the agent is currently unnamed, $name is only the name it will
  # get on relaunch (derive_name/--name) -- it doesn't exist as a resolvable live agent yet.
  # The pane id always does, whether or not the agent is named, so finish's resolve() (which
  # matches on name OR pane_id) can always find it from the ping.
  local tag="$pane"
  [ -n "$session" ] && tag="${pane}@${session:0:8}"
  local dir="${TMPDIR:-/tmp}/handoff-$(id -un)"
  local default_path="$dir/$(date +%y%m%d-%H%M%S)-handoff-${name}.md"
  local prompt; printf -v prompt "$HANDOFF_PROMPT" "$default_path" "$HERDR_PANE_ID" "$tag" "$tag"
  herdr agent prompt "$pane" "$prompt" >/dev/null 2>&1 || die "failed to send the handoff prompt to $name ($pane)"
  note "handoff requested from $name ($pane); default path $default_path"
  note "when its ping arrives, pass this as the target to finish: ${tag}"
}

# rc 0 iff the agent is confirmed gone AND the pane is back at a shell prompt.
gone() {
  local pane="$1" out read_out
  out=$(herdr agent get "$pane" 2>&1) || true
  if printf '%s' "$out" | jq -e '.result.agent' >/dev/null 2>&1; then return 1; fi
  printf '%s' "$out" | jq -e '.error.code=="agent_not_found"' >/dev/null 2>&1 || return 1
  # Captured into a variable, NOT piped straight into `grep -q`: grep -q exits (and closes its
  # end of the pipe) the instant it finds a match, which is often before `herdr pane read`
  # finishes writing the rest of a multi-line snapshot -- under the caller's `pipefail`, that
  # SIGPIPEs the read and makes the whole pipeline register as FAILED even though the match was
  # genuinely found. Confirmed live once the pane's snapshot grew past a single line (a shell
  # prompt followed by other content): the pipe form intermittently/deterministically returned
  # failure while an equivalent capture-then-grep never did.
  read_out=$(herdr pane read "$pane" --source visible --lines 6 2>/dev/null)
  printf '%s' "$read_out" | grep -qE '[$#❯][[:space:]]*$'
}

exit_agent() {
  local pane="$1"
  herdr agent prompt "$pane" "/quit" >/dev/null 2>&1 || true
  local deadline=$(( SECONDS + ${ROTATE_EXIT_POLL_SECS:-25} ))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if gone "$pane"; then note "agent exited; pane $pane free"; return 0; fi
    # Optional per-kind hook (declared by the per-kind script, e.g. claude's own confirmation
    # menu for a still-running background task) to answer a prompt that's blocking /quit from
    # actually taking effect -- called every round so it can react as soon as such a prompt
    # appears, not just once after this poll loop already gave up.
    declare -F handle_exit_prompt >/dev/null 2>&1 && handle_exit_prompt "$pane"
    command sleep 1
  done
  # handle_exit_prompt (or gone() itself) may have freed the pane on this loop's very last round,
  # after which the deadline-first `while` condition above exits without ever re-observing that --
  # re-check once more here before falling through to a kind fallback or die, so a pane that's
  # actually already free is never mistaken for one that still needs exit_fallback's alternate
  # exit mechanism (which could otherwise send its own exit keystrokes into an already-empty
  # shell).
  if gone "$pane"; then note "agent exited; pane $pane free"; return 0; fi
  if declare -F exit_fallback >/dev/null 2>&1; then
    note "/quit did not settle; trying kind fallback"
    exit_fallback "$pane" && return 0
  fi
  # About to abort a rotation mid-flight over a pane that refused to exit -- capture what's
  # actually on screen (a lingering confirmation prompt, a wedged UI) so the failure is
  # diagnosable from the log instead of only by re-probing a pane that may be gone by then.
  log_pane_diag "$pane" "exit failure: /quit did not free the pane" \
    "$(herdr pane read "$pane" --source visible --lines 40 2>/dev/null || true)"
  die "agent did not exit on pane $pane"
}

relaunch() {
  local name="$1" kind="$2" pane="$3"; shift 3
  herdr agent start "$name" --kind "$kind" --pane "$pane" \
    --timeout "${ROTATE_START_TIMEOUT_MS:-120000}" -- "$@" >/dev/null 2>&1 \
    || die "relaunch failed for $name"
  note "relaunched $name ($kind) in $pane"
}

# Extracts the value following the given flag from an argv array (empty if absent/valueless).
# Returns the LAST occurrence's value, not the first: a repeated flag in a real CLI's own argv
# parsing is resolved by whichever occurrence comes last, so "the value this would actually take
# effect as" and "the first one found scanning forward" are only the same thing when the flag
# isn't repeated at all. Getting this wrong here previously produced a genuine false rejection in
# verify(): intended and actual argv were BYTE-IDENTICAL (both "--model sonnet --model opus"), yet
# verify() failed because it compared the first occurrence of one side against the last of the
# other. Empty if the flag never appears.
# $1=flag, remaining args = argv to search. Recognizes "--flag value" (two tokens) and
# "--flag=value" (one token, pi's own accepted inline form) -- prints the LAST such occurrence's
# value, empty if the flag never appears. Stops at a literal "--": nothing past it is a flag to
# any of these CLIs (see strip_context_flags), so positional data on the far side (e.g. an
# initial-prompt argument) must never be misread as a later occurrence of this flag.
value_of_flag() {
  local flag="$1"; shift
  local -a arr=("$@")
  local n=${#arr[@]} j val=""
  for (( j=0; j<n; j++ )); do
    [ "${arr[$j]}" = "--" ] && break
    if [ "${arr[$j]}" = "$flag" ] && [ $((j+1)) -lt "$n" ]; then val="${arr[$((j+1))]}"
    elif [[ "${arr[$j]}" == "$flag="* ]]; then val="${arr[$j]#$flag=}"
    fi
  done
  printf '%s' "$val"
}

# Same as value_of_flag, but also matches alias spellings of the SAME flag (e.g. codex's -m is
# also accepted as --model) -- returns whichever occurrence comes LAST across ALL of them
# combined, same last-flag-wins reasoning as value_of_flag itself (a real CLI parser doesn't
# care which alias a repeated flag used, only the order). Also recognizes a short single-dash
# alias's ATTACHED form (-mVALUE, no separator), matching replace_or_append_flag's own
# understanding of what codex's -m accepts.
# $1=flag, "--"-terminated list of aliases, then argv to search.
value_of_flag_any() {
  local -a flags=("$1"); shift
  while [ "${1:-}" != "--" ]; do flags+=("$1"); shift; done
  shift
  local -a arr=("$@")
  local n=${#arr[@]} j val="" f
  for (( j=0; j<n; j++ )); do
    [ "${arr[$j]}" = "--" ] && break
    for f in "${flags[@]}"; do
      if [ "${arr[$j]}" = "$f" ] && [ $((j+1)) -lt "$n" ]; then val="${arr[$((j+1))]}"; break
      elif [[ "${arr[$j]}" == "$f="* ]]; then val="${arr[$j]#$f=}"; break
      elif [ "${#f}" -eq 2 ] && [[ "$f" == -[^-]* ]] && [[ "${arr[$j]}" == "$f"?* ]]; then val="${arr[$j]#$f}"; break
      fi
    done
  done
  printf '%s' "$val"
}

# Extracts the LAST value assigned to a kv-encoded flag (codex's "-c/--config key=value"
# convention, e.g. reasoning effort) -- empty if the key never appears. Mirrors
# replace_or_append_kv's own understanding of this encoding, including all four forms recognized
# there ("-c key=value", "--config key=value", "-ckey=value", "--config=key=value") and its
# whitespace tolerance around "=" and around the whole assignment -- see that function's comment
# for why "-c=key=value" is deliberately excluded. $1=key, remaining args = argv to search.
value_of_kv() {
  local key="$1"; shift
  local -a arr=("$@")
  local n=${#arr[@]} j val=""
  for (( j=0; j<n; j++ )); do
    [ "${arr[$j]}" = "--" ] && break
    if { [ "${arr[$j]}" = "-c" ] || [ "${arr[$j]}" = "--config" ]; } && [ $((j+1)) -lt "$n" ] && [[ "${arr[$((j+1))]}" =~ ^[[:space:]]*${key}[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      val="${BASH_REMATCH[1]}"
    elif [[ "${arr[$j]}" =~ ^-c[[:space:]]*${key}[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      val="${BASH_REMATCH[1]}"
    elif [[ "${arr[$j]}" =~ ^--config=[[:space:]]*${key}[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      val="${BASH_REMATCH[1]}"
    fi
  done
  # The capture above is greedy to end-of-string, so it also swallows any TRAILING whitespace
  # after the value (e.g. `key = "low" `, confirmed live) -- trim it before quote-stripping, or a
  # trailing space left inside the quotes would make the pattern below fail to match and leave
  # the quotes (and that space) in place. Standard bash idiom: strip everything up to and
  # including the last non-whitespace char to isolate just the trailing whitespace run, then
  # remove that suffix from val.
  val="${val%"${val##*[![:space:]]}"}"
  # TOML permits (but doesn't require) quoting a string value with either single or double
  # quotes (confirmed live: `codex -c 'k = "v"'` and `codex -c "k='v'"` both accepted) -- strip
  # one matching pair so callers doing a plain string comparison (verify(), resolve_and_prepare's
  # differs-from-default gate) see the SAME value regardless of which of these equivalent
  # spellings the launch argv happened to use.
  case "$val" in
    \"*\") val="${val#\"}"; val="${val%\"}" ;;
    \'*\') val="${val#\'}"; val="${val%\'}" ;;
  esac
  printf '%s' "$val"
}

verify() {
  local name="$1" pane="$2" kind="$3"; shift 3
  [ "${1:-}" = "--" ] && shift
  local -a intended=( "$@" )
  local deadline=$(( SECONDS + ${ROTATE_VERIFY_POLL_SECS:-30} )) st=""
  while [ "$SECONDS" -lt "$deadline" ]; do
    st=$(herdr agent get "$name" 2>/dev/null | jq -r '.result.agent.agent_status // empty')
    case "$st" in idle|done) break ;; esac
    command sleep 1
  done
  case "$st" in idle|done) ;; *) note "verify: agent not ready ($st)"; return 1 ;; esac

  # pi's argv is not a reliable source to verify against across platforms: on macOS (and older
  # builds) pi rewrites its process title on startup (process.title = APP_NAME), overwriting the
  # /proc/pid/cmdline memory `herdr pane process-info` reads from, so capture_argv sees only the
  # bare binary name. (Linux fork builds now preserve argv via /proc/self/comm -- see
  # capture_argv -- but a bare `pi` launch still carries no model/effort, and this branch must
  # stay correct on the clobbered platforms too.) So pi verifies the live model/effort via the
  # same screen-reading detector used to capture them, rather than comparing argv. Flags beyond
  # model/effort are not verified here.
  if [ "$kind" = pi ] && declare -F detect_override >/dev/null 2>&1; then
    local want_model want_effort
    want_model=$(value_of_flag "$MODEL_FLAG" "${intended[@]}")
    want_effort=$(value_of_flag "$EFFORT_FLAG" "${intended[@]}")
    # If neither the original argv nor a live pre-exit detection ever produced a model/effort
    # value, "intended" has nothing to compare the fresh session against -- pi has no OTHER
    # verifiable signal (see the argv note above), so this would otherwise be a vacuous pass.
    # Fail closed instead of reporting success with nothing actually checked.
    if [ -z "$want_model" ] || [ -z "$want_effort" ]; then
      note "verify: pi has no intended model/effort to check against (neither captured nor detected) -- pi cannot verify anything else for this kind, so treating as unverified rather than reporting a vacuous pass"
      return 1
    fi
    # Explicit check, not a bare statement: verify() itself is called as `verify ... || vrc=$?`
    # by run_finish, which per POSIX/bash disables set -e for this WHOLE call chain (not just
    # verify's own top-level exit code) -- a close_modal failure inside detect_override would
    # otherwise be silently swallowed here instead of failing verification.
    detect_override "$pane" || { note "verify: live detection failed to complete cleanly (e.g. a picker wouldn't close) -- treating as unverified"; return 1; }
    if [ "$DETECTED_MODEL" != "$want_model" ]; then
      note "verify: live model '$DETECTED_MODEL' != intended '$want_model'"; return 1
    fi
    if [ "$DETECTED_EFFORT" != "$want_effort" ]; then
      note "verify: live effort '$DETECTED_EFFORT' != intended '$want_effort'"; return 1
    fi
    note "verify OK (pi: live model/effort matched; other flags are not verifiable for this kind)"
    return 0
  fi

  # Only model/effort are ever verified here, the same scope as pi's branch above. Earlier
  # revisions of this check compared the ENTIRE argv (an exact-suffix match tolerating a leading
  # "prefix"), reasoning that a herdr-level default config always lands there -- confirmed live,
  # but for the wrong reason: what was actually observed is this operator's own shell alias
  # (`alias claude='claude --dangerously-skip-permissions --verbose'` in ~/.bashrc, likewise for
  # codex) expanding ahead of whatever this script passes, not anything herdr itself injects.
  # Since that prefix is arbitrary local shell configuration, not a knowable, stable schema, this
  # tool's job is to pass the launch flags through and confirm ITS OWN overrides took effect --
  # not to gate a successful relaunch on the presence/shape of flags it doesn't manage.
  local -a BASE_FLAGS=()
  capture_argv "$pane" "$kind"
  local want_model want_effort actual_model actual_effort
  want_model=$(value_of_flag_any "$MODEL_FLAG" "${MODEL_FLAG_ALIASES[@]}" -- "${intended[@]}")
  actual_model=$(value_of_flag_any "$MODEL_FLAG" "${MODEL_FLAG_ALIASES[@]}" -- "${BASE_FLAGS[@]}")
  if [ "$EFFORT_STYLE" = kv ]; then
    want_effort=$(value_of_kv "$EFFORT_FLAG" "${intended[@]}")
    actual_effort=$(value_of_kv "$EFFORT_FLAG" "${BASE_FLAGS[@]}")
  else
    want_effort=$(value_of_flag "$EFFORT_FLAG" "${intended[@]}")
    actual_effort=$(value_of_flag "$EFFORT_FLAG" "${BASE_FLAGS[@]}")
  fi
  # Only fail when this tool actually asked for a specific model/effort and the live session
  # doesn't show it -- a rotation that never specified either has nothing of ours to confirm,
  # and that's a legitimate outcome, not a signal to block on (unlike pi's branch above, which
  # fails closed only because it has no OTHER verification signal at all for that kind).
  if [ -n "$want_model" ] && [ "$actual_model" != "$want_model" ]; then
    note "verify: actual model '$actual_model' != intended '$want_model'"; return 1
  fi
  if [ -n "$want_effort" ] && [ "$actual_effort" != "$want_effort" ]; then
    note "verify: actual effort '$actual_effort' != intended '$want_effort'"; return 1
  fi

  note "verify OK"; return 0
}

# Propagates its own failure -- callers must not report a rotation "complete" if the new agent
# was never actually told to resume.
kickoff() {
  local pane="$1" path="$2" msg="${3:-}"
  # "off" is a literal sentinel value of the SAME flag, not a separate --no-kickoff flag --
  # see parse_args()'s own comment for why this collapses three states into one flag cleanly
  # while keeping "omitted entirely" meaning "send the default message" (today's behavior,
  # unchanged).
  if [ "$msg" = off ]; then note "kickoff skipped (--kickoff off)"; return 0; fi
  local text
  if [ -n "$msg" ]; then text="$msg"
  # Deliberately doesn't say "read it fully" or otherwise imply exhaustively consuming the
  # handoff and its references up front -- confirmed live that framing nudges the fresh agent
  # into proactively reading everything the handoff mentions, landing it near the compaction
  # threshold before it does any actual work. Wording aligned with the same fix made to the
  # standalone `handoff` skill's own kickoff-prompt template (same root cause, same fix): one
  # instruction, not an instruction plus its own countermand.
  else text="Continue the work described in the handoff at ${path}, without proactively reading the files it references -- open each one only when a task step actually needs it. Then pick up the task list where it leaves off."; fi
  herdr agent prompt "$pane" "$text" >/dev/null 2>&1
}

# Parses --name/--model/--effort/--kickoff; leftover positionals -> POSITIONAL[]. KICKOFF's
# three logical states (default / custom message / suppressed) live in this ONE variable:
# empty (flag omitted entirely) -> default kickoff message; literal "off" -> suppressed;
# anything else -> that exact custom message. No separate NO_KICKOFF flag/variable -- kickoff()
# itself special-cases the "off" literal instead.
parse_args() {
  OVERRIDE_NAME="" OVERRIDE_MODEL="" OVERRIDE_EFFORT="" KICKOFF=""
  POSITIONAL=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --name)    [ $# -ge 2 ] || die "--name needs a value";    OVERRIDE_NAME="$2";   shift 2 ;;
      --model)   [ $# -ge 2 ] || die "--model needs a value";   OVERRIDE_MODEL="$2";  shift 2 ;;
      --effort)  [ $# -ge 2 ] || die "--effort needs a value";  OVERRIDE_EFFORT="$2"; shift 2 ;;
      --kickoff)
        [ $# -ge 2 ] || die "--kickoff needs a value (a message, or 'off' to suppress it)"
        # An explicitly empty value ("--kickoff ''") is otherwise indistinguishable from
        # omitting the flag entirely (both would leave KICKOFF=""), which would silently pass
        # handoff's own rejection check instead of being rejected like every other --kickoff
        # use -- reject it here, at parse time, uniformly for both handoff and finish.
        [ -n "$2" ] || die "--kickoff needs a non-empty value (a message, or 'off' to suppress it)"
        KICKOFF="$2"; shift 2 ;;
      --) shift ;;
      -*) die "unknown option: $1" ;;
      *) POSITIONAL+=("$1"); shift ;;
    esac
  done
}

# Resolves + validates; shared by both entry points below. settle=1 (finish only) waits for the
# target to reach idle/done first: its ping fires mid-turn (from its own Bash tool call), so
# acting immediately on receipt could race the tail end of that same turn. handoff doesn't need
# this — it's fine (by design) to interrupt a busy target to ask it for a handoff.
resolve_and_validate() {
  local expected_kind="$1" target="$2" settle="${3:-0}" expected_pane="${4:-}"
  resolve "$target"
  # finish only: it already resolved once (bare, unlocked) to pick a lock file, then acquired
  # the lock, before calling here. If $target is a mutable NAME and its live pane changed in
  # between, the lock we're holding no longer corresponds to what we're about to act on --
  # check this BEFORE any of the live interaction below (wait_settled/capture_argv/
  # detect_override all send real input to $ROTATE_PANE), not after it.
  if [ -n "$expected_pane" ] && [ "$ROTATE_PANE" != "$expected_pane" ]; then
    die "pane for $target changed while acquiring the lock (was $expected_pane, now $ROTATE_PANE) — not proceeding"
  fi
  [ "$ROTATE_KIND" = "$expected_kind" ] || die "target is $ROTATE_KIND, not $expected_kind"
  valid_name "$ROTATE_NAME" || die "invalid agent name: $ROTATE_NAME"
  declare -F validate_override >/dev/null 2>&1 && validate_override "$OVERRIDE_MODEL" "$OVERRIDE_EFFORT"
  # Self-rotation (target == caller's own pane): fine for handoff (this bash call is already
  # the caller's last action for the turn -- HANDOFF_PROMPT tells it to stop after pinging, so
  # there's nothing left to wait out), but finish can never work self-targeted: exit_agent
  # below sends /quit then waits for the pane to actually go empty, which requires THIS very
  # command's own process to have exited first -- a deadlock, not a race. Reject it outright
  # rather than let it hang later once already past exit_agent.
  if [ "$ROTATE_PANE" = "${HERDR_PANE_ID:-}" ]; then
    if [ "$settle" = 1 ]; then
      die "self-rotation is not supported: finish would need to exit this very agent's own pane while running as a command inside it, which can never complete -- run finish from a different orchestrating agent instead"
    fi
    note "self-rotation (target is this pane): skipping settle-wait, nothing to wait out"
  elif [ "$settle" = 1 ]; then
    wait_settled "$ROTATE_PANE"
  fi
}

# finish only: resolve_and_validate(), then capture the target's argv and apply any model/effort
# override. This live interaction (capture_argv/detect_override sends /status, /model into the
# pane) matters ONLY for finish, whose BASE_FLAGS is what actually gets relaunched -- handoff
# never uses this result (nothing is persisted between handoff and finish; the caller repeats
# any override), so handoff calls resolve_and_validate() directly instead of this and skips the
# live probing entirely. It used to run there too, for no benefit: the result was discarded the
# moment the function returned, yet a detect_override cleanup timeout (set -e) could still abort
# the whole handoff step before the handoff prompt was ever sent, over work nothing used.
resolve_and_prepare() {
  resolve_and_validate "$@"
  capture_argv "$ROTATE_PANE" "$ROTATE_KIND"
  # The default already present in the ORIGINAL captured argv, before any override -- used only
  # to decide whether a live-detected value represents an actual change (see below). Read via
  # the same alias-aware helpers verify() uses, so a launch that used an alias spelling (e.g.
  # codex's -m) is still correctly recognized as "already has a model."
  local default_model default_effort
  default_model=$(value_of_flag_any "$MODEL_FLAG" "${MODEL_FLAG_ALIASES[@]}" -- "${BASE_FLAGS[@]}")
  if [ "$EFFORT_STYLE" = kv ]; then default_effort=$(value_of_kv "$EFFORT_FLAG" "${BASE_FLAGS[@]}")
  else default_effort=$(value_of_flag "$EFFORT_FLAG" "${BASE_FLAGS[@]}"); fi
  # detect_override sends real commands into the target's UI (/status, /settings, /model...) --
  # doing that while the target is mid-turn would race whatever it's currently doing, possibly
  # landing our keystrokes in the wrong place. finish already confirmed idle via wait_settled
  # above, but re-check explicitly rather than assume.
  local target_status="" target_idle=0
  target_status=$(herdr agent get "$ROTATE_PANE" 2>/dev/null | jq -r '.result.agent.agent_status // empty') || target_status=""
  case "$target_status" in idle|done) target_idle=1 ;; esac
  if { [ -z "$OVERRIDE_MODEL" ] || [ -z "$OVERRIDE_EFFORT" ]; } && declare -F detect_override >/dev/null 2>&1; then
    if [ "$target_idle" = 1 ]; then
      # Reset here, in the SHARED caller, rather than trust every per-kind detect_override to do
      # it -- only claude's own implementation ever sets this (see its own comment), so a stale
      # "1" left over from an EARLIER call in this same process (this matters for anything that
      # calls resolve_and_prepare more than once per process, e.g. a test suite running many
      # cases sequentially) would otherwise silently suppress a genuine no-baseline promotion for
      # whatever kind is being rotated THIS time, including one (codex/pi) whose own
      # detect_override never touches this variable at all.
      DETECTED_MODEL_DEFAULT=0
      # A bare statement here would abort this whole script under set -e on failure, with
      # nothing reaching the diagnostic below -- pi's detect_override can genuinely fail (a
      # stuck picker it couldn't confirm closed; see herdr-rotate-pi's own close_modal), and
      # that shouldn't be fatal here: unlike claude, pi has no OTHER verifiable signal at this
      # call site (this whole block is best-effort auto-detection, not the pi-specific preflight
      # in run_finish that already requires a model/effort to exist before anything destructive
      # runs), so tolerate it and fall through with nothing detected. codex's own detect_override
      # never returns 1 at all (confirmed by reading its source -- every failure path there is
      # `return 0`), so it's unaffected either way. claude's is NOT tolerated: an already-stuck
      # modal there is a real problem the caller should still see (test 5f2 expects this to keep
      # aborting before /quit).
      if [ "$ROTATE_KIND" = pi ]; then
        detect_override "$ROTATE_PANE" || note "detect_override failed for pi (e.g. a picker it couldn't confirm closed) -- continuing without a live-detected value"
      else
        detect_override "$ROTATE_PANE"
      fi
      if [ "$ROTATE_KIND" = pi ]; then
        # pi has no argv-derived default to gate against across platforms: on clobbered builds
        # (macOS/older) capture_argv yields nothing, and even on a Linux fork build (which now
        # preserves argv -- see capture_argv) a bare `pi` launch carries no model/effort. So
        # default_model/default_effort may be empty, and the differs-from-default gate below would
        # then never promote ANYTHING for pi, leaving OVERRIDE_MODEL/OVERRIDE_EFFORT empty and
        # tripping run_finish's pi preflight (which requires both). detect_override is pi's live
        # source of truth here (same reasoning as verify()'s pi branch and that preflight), so any
        # detected value is promoted unconditionally instead.
        [ -z "$OVERRIDE_MODEL" ] && [ -n "$DETECTED_MODEL" ] && OVERRIDE_MODEL="$DETECTED_MODEL" && note "detected live model: $DETECTED_MODEL"
        [ -z "$OVERRIDE_EFFORT" ] && [ -n "$DETECTED_EFFORT" ] && OVERRIDE_EFFORT="$DETECTED_EFFORT" && note "detected live effort: $DETECTED_EFFORT"
      else
        # A detected value becomes an override if it DIFFERS from what launch already had, OR if
        # launch had NOTHING explicit to compare it against in the first place (a bare launch,
        # e.g. plain `claude`/`codex` with no --model/--effort at all, inheriting whatever the
        # account default happened to be at that moment -- the common case, not a rare one). An
        # explicit --model/--effort passed to finish always applies regardless (handled above;
        # this block only ever fires when OVERRIDE_MODEL/OVERRIDE_EFFORT is still empty).
        #
        # An earlier revision required default_model/default_effort to be non-empty before ever
        # promoting a detected value ("nothing to compare an implicit default against, so this is
        # 'can't tell, don't touch,' not 'a change happened'") -- confirmed live that this makes
        # detect_override's ENTIRE reason for existing (carrying a mid-session /model switch into
        # the rotation) silently inert for any bare-launched session, which is the ordinary case,
        # not an edge case: default_model is empty there by construction, so "differs from an
        # empty baseline" was never true, and a real live switch (e.g. sonnet -> opus mid-run) was
        # dropped on every single rotation, replaying the original bare launch instead. This is
        # exactly pi's OWN already-established reasoning just above for its identical "no baseline
        # available" situation (pi has no argv-derived model/effort baseline to gate against --
        # clobbered on macOS/older builds, and absent from a bare launch even on a Linux fork build
        # that now preserves argv; see the pi branch above) -- reached here instead via a launch
        # that happened to omit the flag, but the right response is the same: trust detection rather
        # than silently do nothing.
        # Exact match only when a baseline DOES exist, for every kind including claude -- no
        # substring/containment tolerance. An earlier version of this check treated a short alias
        # ("sonnet") as equivalent to a full identifier containing it ("claude-sonnet-5"),
        # reasoning both are valid --model spellings for claude (confirmed via `claude --help`) --
        # but ANY containment check, in either direction, also silently equates two genuinely
        # DIFFERENT specific identifiers whenever one happens to be a substring/prefix of the
        # other (e.g. "claude-sonnet-4-5" vs "claude-sonnet-5", or "claude-opus-4" vs
        # "claude-opus-4-1") -- there is no way to tell "same model, different spelling" apart
        # from "different model, coincidentally overlapping name" using string containment alone.
        # A false "unchanged" here silently drops a genuine user model change; a false "changed"
        # only costs an unnecessary (but still correct) flag rewrite -- given that asymmetry,
        # exact match is the safer default even though it means a launch using a bare alias will
        # no longer be recognized as "unchanged" against a live session now showing
        # detect_override's more specific identifier for that same model.
        # DETECTED_MODEL_DEFAULT (claude only; reset to 0 by the shared caller above before every
        # detect_override call, so a stale "1" from an earlier rotation in this same process can
        # never leak into a kind whose own detect_override never touches it): "1" means
        # DETECTED_MODEL came from claude's Default-row fallback (a bare, lossy family alias like
        # "opus", never a concrete dated/[1m] identifier -- see that fallback's own comment in
        # herdr-rotate-claude). Checked FIRST, before comparing against default_model at all:
        # Default carries no fixed identifier of its own, so the only way to correctly preserve
        # "follow whatever Default resolves to" on relaunch is a BARE argv with no --model flag,
        # regardless of whether the ORIGINAL launch happened to have an explicit one. Neither
        # replaying that stale explicit value (the original reported bug: an old pinned model
        # silently outlives a live switch back to Default) nor synthesizing a new, lossy
        # "--model <family alias>" (loses precision AND permanently pins away from Default going
        # forward) is correct here -- the flag must be removed entirely, not rewritten.
        if [ -z "$OVERRIDE_MODEL" ] && [ -n "$DETECTED_MODEL" ] && [ "${DETECTED_MODEL_DEFAULT:-0}" = 1 ]; then
          if [ -n "$default_model" ]; then
            remove_flag BASE_FLAGS "$MODEL_FLAG" "${MODEL_FLAG_ALIASES[@]}"
            note "live model resolves via claude's own 'Default' entry -- removing the stale explicit '$MODEL_FLAG $default_model' so relaunch follows Default like the live session does"
          else
            note "live model resolves via claude's own 'Default' entry (currently '$DETECTED_MODEL', a lossy family alias) and launch had no explicit --model -- nothing to change; a bare relaunch already follows the same Default resolution"
          fi
        elif [ -z "$OVERRIDE_MODEL" ] && [ -n "$DETECTED_MODEL" ]; then
          if [ -n "$default_model" ]; then
            if [ "$DETECTED_MODEL" != "$default_model" ]; then
              OVERRIDE_MODEL="$DETECTED_MODEL"
              note "detected live model changed from launch ('$default_model' -> '$DETECTED_MODEL')"
            fi
          else
            OVERRIDE_MODEL="$DETECTED_MODEL"
            note "detected live model (launch had no explicit --model to compare against): '$DETECTED_MODEL'"
          fi
        fi
        if [ -z "$OVERRIDE_EFFORT" ] && [ -n "$DETECTED_EFFORT" ] \
           && { [ -z "$default_effort" ] || [ "$DETECTED_EFFORT" != "$default_effort" ]; }; then
          OVERRIDE_EFFORT="$DETECTED_EFFORT"
          if [ -n "$default_effort" ]; then
            note "detected live effort changed from launch ('$default_effort' -> '$DETECTED_EFFORT')"
          else
            note "detected live effort (launch had no explicit --effort to compare against): '$DETECTED_EFFORT'"
          fi
        fi
      fi
      # Failure-path note: detection ran but yielded no live model, so the relaunch silently
      # replays whatever model the ORIGINAL launch argv carried (nothing, for a bare launch)
      # instead of a freshly-read one -- surface it so a stale-model rotation is traceable from
      # the log. Empty OVERRIDE_MODEL here means neither an explicit finish --model nor a promoted
      # detection filled it; empty DETECTED_MODEL means detection itself came back with nothing (a
      # matched-baseline detection leaves DETECTED_MODEL non-empty, so this stays quiet on that
      # happy path). The per-kind detect_override already logged the unparsed render above, if any.
      [ -z "$OVERRIDE_MODEL" ] && [ -z "$DETECTED_MODEL" ] && note "no live model detected on $ROTATE_PANE -- relaunch replays the original launch argv"
    else
      note "target not idle (status: ${target_status:-unknown}); skipping live model/effort detection to avoid racing its current turn"
    fi
  fi
  apply_override "$OVERRIDE_MODEL" "$OVERRIDE_EFFORT"
}

# Entry 1/2. Per-kind scripts set MODEL_FLAG/EFFORT_FLAG/EFFORT_STYLE (+ optional
# validate_override / exit_fallback) then call this. Sends the handoff prompt and returns —
# it is NOT a blocking call. The invoking agent must wait for the target's ping (its own next
# incoming turn, since the prompt is addressed to $HERDR_PANE_ID) before calling run_finish.
run_handoff() {
  local expected_kind="$1"; shift
  guard || { note "not in herdr (HERDR_ENV != 1); no-op"; exit 0; }
  parse_args "$@"
  [ "${#POSITIONAL[@]}" -eq 1 ] || die "usage: herdr-rotate-$expected_kind handoff <name-or-pane> [--name N] [--model M] [--effort E]"
  [ -n "$KICKOFF" ] && die "--kickoff only applies to finish (the kickoff prompt is sent there, after relaunch) — pass it to finish instead"
  resolve_and_validate "$expected_kind" "${POSITIONAL[0]}"
  send_handoff "$ROTATE_PANE" "$ROTATE_NAME" "$ROTATE_SESSION"
  note "rotation paused for $ROTATE_NAME ($ROTATE_KIND) in $ROTATE_PANE — waiting on its ping"
}

# Entry 2/2. Re-resolves and re-applies the SAME overrides given to run_handoff (nothing is
# persisted between the two calls — the caller is expected to repeat them), then exits,
# relaunches, verifies, and kicks off the fresh session.
run_finish() {
  local expected_kind="$1"; shift
  guard || { note "not in herdr (HERDR_ENV != 1); no-op"; exit 0; }
  parse_args "$@"
  [ "${#POSITIONAL[@]}" -eq 2 ] || die "usage: herdr-rotate-$expected_kind finish <name-or-pane> <handoff-path> [--name N] [--model M] [--effort E] [--kickoff MSG|off]"
  local target="${POSITIONAL[0]}" handoff_path="${POSITIONAL[1]}"
  [ -f "$handoff_path" ] && [ -s "$handoff_path" ] || die "handoff file missing/empty: $handoff_path"

  # Resolve just far enough to get the canonical pane, then lock BEFORE any further live
  # interaction (settle-wait, argv capture, model/effort detection) -- otherwise two concurrent
  # `finish` calls on the same pane could interleave those live pokes before either one reaches
  # the lock below. resolve_and_prepare re-resolves from scratch once locked; the extra `agent
  # list` round-trip here is a small price for closing that window.
  resolve "$target"
  local locked_pane="$ROTATE_PANE"

  # Exclusive per-pane lock for everything from here on (through kickoff): without it, two
  # concurrent `finish` calls on the same pane could interleave exit/relaunch so a delayed
  # /quit lands on the replacement agent instead of the one it was meant for. Held for the
  # rest of this process's lifetime (released automatically when it exits) -- never blocks: a
  # pane already mid-finish means stop, not queue behind it. Always /tmp, never
  # ${TMPDIR:-/tmp}: two `finish` invocations launched with different TMPDIR values must still
  # land on the SAME lock file to actually mutex each other.
  # This directory's path is predictable and /tmp is world-writable -- if anything already
  # exists there, validate it BEFORE touching it at all (no mkdir -p, no chmod): mkdir -p
  # silently succeeds through a pre-existing symlink-to-a-directory, and a chmod before the
  # check would already have mutated an attacker-planted target's permissions by the time the
  # check rejects it. Only actually create it (owned, mode 700 from the start) when nothing is
  # there yet.
  # ROTATE_LOCK_ROOT exists only so the test suite can point this at an isolated, private
  # directory instead of the real one -- production never sets it (defaults to /tmp), so real
  # concurrent `finish` invocations still always land on the SAME namespace regardless of their
  # individual environment (the reason this isn't ${TMPDIR:-/tmp} either -- see below).
  local lock_dir="${ROTATE_LOCK_ROOT:-/tmp}/herdr-rotate-lock-$(id -un)"
  if [ -e "$lock_dir" ] || [ -L "$lock_dir" ]; then   # -e alone is false for a dangling symlink
    [ -L "$lock_dir" ] && die "refusing to use $lock_dir: it is a symlink, not a plain directory"
    [ -d "$lock_dir" ] || die "refusing to use $lock_dir: not a directory"
    [ "$(stat -c %U "$lock_dir" 2>/dev/null)" = "$(id -un)" ] || die "refusing to use $lock_dir: not owned by the current user"
  else
    mkdir -m 700 -p "$lock_dir"
  fi
  local lock_file="$lock_dir/$(printf '%s' "$locked_pane" | tr -c 'A-Za-z0-9' '_').lock"
  # -e follows symlinks, so it's false for a DANGLING symlink -- test -L unconditionally first,
  # not gated behind -e, or a dangling symlink here would sail through to the exec below and
  # get its target created/truncated.
  [ -L "$lock_file" ] && die "refusing to use $lock_file: it is a symlink"
  [ -e "$lock_file" ] && [ ! -f "$lock_file" ] && die "refusing to use $lock_file: exists but is not a plain regular file"
  exec {ROTATE_LOCK_FD}>"$lock_file"
  flock -n "$ROTATE_LOCK_FD" || die "another rotation is already in progress for pane $locked_pane (lock: $lock_file) — not proceeding"

  resolve_and_prepare "$expected_kind" "$target" 1 "$locked_pane"
  local -a intended=( "${BASE_FLAGS[@]}" )

  # Two failure modes that agent start would otherwise only surface AFTER the old agent has
  # already exited -- check both now, while it's still safe to just stop.
  local f i=0
  for f in "${BASE_FLAGS[@]}"; do
    # Report only the index, never the value itself: the offending argument could be a
    # multiline system prompt or a raw ESC/OSC sequence, either of which would leak into logs
    # (or corrupt the terminal) if printed verbatim here.
    [[ "$f" =~ [[:cntrl:]] ]] && die "captured/override flag at index $i contains a control character (herdr would reject this on relaunch) — not proceeding (value withheld from this message)"
    i=$((i+1))
  done
  local collision
  collision=$(herdr agent list 2>/dev/null | jq -r --arg n "$ROTATE_NAME" --arg p "$ROTATE_PANE" \
    'first(.result.agents[] | select(.name==$n and .pane_id!=$p)) | .pane_id // empty') || die "agent list failed"
  [ -z "$collision" ] || die "name '$ROTATE_NAME' is already used by a live agent in $collision — pick a different --name"

  # Pi has no other way to verify a rotation (see verify()'s pi branch) -- if neither the
  # original argv nor live detection ever produced a model/effort value, there is nothing to
  # confirm the fresh session against, so this must be caught HERE, before anything
  # destructive, not left to be discovered by verify() after the old agent is already gone.
  if [ "$ROTATE_KIND" = pi ]; then
    local pi_want_model pi_want_effort
    pi_want_model=$(value_of_flag "$MODEL_FLAG" "${intended[@]}")
    pi_want_effort=$(value_of_flag "$EFFORT_FLAG" "${intended[@]}")
    if [ -z "$pi_want_model" ] || [ -z "$pi_want_effort" ]; then
      die "pi's launch is missing an explicit model or effort value (neither captured from the original argv nor detected live) -- pi cannot verify anything else for this kind, so refusing before exit/relaunch rather than discovering this after the old agent is already gone"
    fi
  fi

  revalidate_session "$ROTATE_PANE" "$ROTATE_SESSION"

  # Single-use per-handoff token, checked in two phases around exit_agent (see below for why).
  # Canonicalize the path first (realpath, falling back to the literal path if the file can't
  # be resolved for some reason) so /dir/file, /dir/./file, and a symlink to the same file all
  # collapse onto ONE token instead of bypassing each other; hash it rather than sanitizing the
  # path into a filename, which risks collisions and can exceed filesystem name-length limits.
  # Keyed on canonical path PLUS the file's actual CONTENT, not path alone: a stable, reused
  # filename (the handoff prompt explicitly allows choosing one instead of the timestamped
  # default) legitimately gets overwritten with fresh content for a later, unrelated rotation,
  # and must be treated as new when that happens -- content is what actually changed, so it's
  # what's hashed (inode/mtime/size are metadata: a `touch` alone changes them on a file whose
  # content is byte-for-byte unchanged, which would wrongly let an exact replay through).
  local token_dir="$lock_dir/consumed" token_file canon_path content_hash
  mkdir -m 700 -p "$token_dir"
  chmod 700 "$token_dir" 2>/dev/null || true
  canon_path=$(realpath -e -- "$handoff_path" 2>/dev/null) || canon_path="$handoff_path"
  content_hash=$(sha1sum -- "$canon_path" 2>/dev/null | cut -d' ' -f1) || content_hash=""
  token_file="$token_dir/$(printf '%s\n%s' "$canon_path" "$content_hash" | sha1sum | cut -d' ' -f1).used"

  # Phase 1 -- CHECK ONLY, before exit_agent: a SEQUENTIAL replay of the same ping after an
  # earlier finish already completed and released the pane lock (most exploitable for
  # pi/codex, which have no session id to catch a stale ping via revalidate_session above)
  # must be rejected before it ever /quits the NEW agent now occupying this pane -- it must
  # not touch exit_agent at all.
  [ -e "$token_file" ] && die "this handoff ($handoff_path) has already been used to finish a rotation — not proceeding (replayed ping?)"

  exit_agent "$ROTATE_PANE"

  # Phase 2 -- CLAIM, only after exit_agent actually confirms the old agent gone: an earlier
  # failure (bad argv, collision, stale session, or exit_agent itself timing out because the
  # agent never went idle) must not burn the token -- in every one of those cases the target
  # is untouched, so a corrected retry with the same handoff path would otherwise be locked
  # out for no reason. mkdir is the atomic claim; a lost race here (another finish call for
  # the same handoff slipped past phase 1 first) is indistinguishable from a genuine replay
  # and must fail the same way.
  mkdir "$token_file" 2>/dev/null || die "this handoff ($handoff_path) has already been used to finish a rotation — not proceeding (replayed ping?)"

  relaunch "$ROTATE_NAME" "$ROTATE_KIND" "$ROTATE_PANE" "${BASE_FLAGS[@]}"
  local vrc=0
  verify "$ROTATE_NAME" "$ROTATE_PANE" "$ROTATE_KIND" -- "${intended[@]}" || vrc=$?
  [ "$vrc" -eq 0 ] || die "relaunched but argv verification FAILED — inspect $ROTATE_NAME (kickoff withheld)"
  if kickoff "$ROTATE_PANE" "$handoff_path" "$KICKOFF"; then
    note "rotation complete: $ROTATE_NAME ($ROTATE_KIND) in $ROTATE_PANE"
  else
    die "relaunched and verified $ROTATE_NAME ($ROTATE_KIND) in $ROTATE_PANE, but the kickoff prompt failed to send — the new agent is running with the right flags but hasn't been told to resume; send it the kickoff manually"
  fi
}
