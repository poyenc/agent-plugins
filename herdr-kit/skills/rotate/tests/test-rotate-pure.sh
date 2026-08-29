#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../../scripts/rotate-common.sh"
PASS=0; FAIL=0
assert_eq(){ if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; echo "    exp:[$2] act:[$3]"; FAIL=$((FAIL+1)); fi; }
rc(){ if "$@"; then echo 0; else echo 1; fi; }

assert_eq "derive wG:p4"     "claude-wgp4" "$(derive_name claude wG:p4)"
assert_eq "derive w9:p12 pi" "pi-w9p12"    "$(derive_name pi w9:p12)"
assert_eq "valid name ok"    "0" "$(rc valid_name claude-wgp4)"
assert_eq "valid name upper" "1" "$(rc valid_name Bad)"
assert_eq "valid name slash" "1" "$(rc valid_name a/b)"
assert_eq "valid name empty" "1" "$(rc valid_name '')"
HERDR_ENV=1; assert_eq "guard in"  "0" "$(rc guard)"
HERDR_ENV=0; assert_eq "guard out" "1" "$(rc guard)"

mapfile -d '' -t k < <(strip_context_flags claude --model opus --continue --verbose)
assert_eq "claude: strip --continue" "--model opus --verbose" "${k[*]}"
mapfile -d '' -t k < <(strip_context_flags claude --session-id abc --add-dir /x)
assert_eq "claude: strip --session-id+val" "--add-dir /x" "${k[*]}"
mapfile -d '' -t k < <(strip_context_flags claude --session-id=zzz --model haiku)
assert_eq "claude: strip --session-id= inline" "--model haiku" "${k[*]}"
# claude's -r/--resume takes an OPTIONAL value -- only consume the next token if it isn't
# itself a flag (a bare leftover would otherwise be misread by claude as the positional prompt).
mapfile -d '' -t k < <(strip_context_flags claude --resume abc123 --model haiku)
assert_eq "claude: strip --resume + its value" "--model haiku" "${k[*]}"
mapfile -d '' -t k < <(strip_context_flags claude --resume --model haiku)
assert_eq "claude: strip valueless --resume (next token is a flag)" "--model haiku" "${k[*]}"
mapfile -d '' -t k < <(strip_context_flags claude --resume=abc123 --model haiku)
assert_eq "claude: strip --resume= inline" "--model haiku" "${k[*]}"
mapfile -d '' -t k < <(strip_context_flags claude -r12345678-1234-1234-1234-123456789abc --model haiku)
assert_eq "claude: strip attached -rVALUE (no space)" "--model haiku" "${k[*]}"

# After a "--" end-of-options marker, nothing is a flag any more to any of these CLIs -- must
# stop pattern-matching there and copy the rest through verbatim.
mapfile -d '' -t k < <(strip_context_flags claude --model opus -- --resume should-survive)
assert_eq "claude: -- stops flag stripping" "--model opus -- --resume should-survive" "${k[*]}"

# pi's --resume/-r is a BOOLEAN (no value at all, unlike claude) -- must never consume the
# next token, or a real flag like --model would be silently eaten.
mapfile -d '' -t k < <(strip_context_flags pi --resume --model amd-gateway/x)
assert_eq "pi: --resume never eats the next flag" "--model amd-gateway/x" "${k[*]}"
mapfile -d '' -t k < <(strip_context_flags pi --continue --thinking high)
assert_eq "pi: strip --continue" "--thinking high" "${k[*]}"
mapfile -d '' -t k < <(strip_context_flags pi --session-id abc --model amd-gateway/x)
assert_eq "pi: strip --session-id+val" "--model amd-gateway/x" "${k[*]}"
mapfile -d '' -t k < <(strip_context_flags pi --fork abc --model amd-gateway/x)
assert_eq "pi: strip --fork+val (also carries old context)" "--model amd-gateway/x" "${k[*]}"

# codex's resume/fork are SUBCOMMANDS (a leading positional), not flags -- codex resume
# [SESSION_ID] [PROMPT]. codex's own -c/--config is unrelated and must survive untouched.
mapfile -d '' -t k < <(strip_context_flags codex resume abc-session-id -m glm-5.2)
assert_eq "codex: strip resume subcommand + its session id" "-m glm-5.2" "${k[*]}"
mapfile -d '' -t k < <(strip_context_flags codex resume --last -m glm-5.2)
assert_eq "codex: strip resume + --last" "-m glm-5.2" "${k[*]}"
mapfile -d '' -t k < <(strip_context_flags codex fork abc-session-id -m glm-5.2)
assert_eq "codex: strip fork subcommand + its session id" "-m glm-5.2" "${k[*]}"
mapfile -d '' -t k < <(strip_context_flags codex -m glm-5.2 -c model_reasoning_effort=high)
assert_eq "codex: -c/--config survives (unrelated to resume)" "-m glm-5.2 -c model_reasoning_effort=high" "${k[*]}"

# replace_or_append_flag: an existing occurrence (any accepted spelling) is replaced in place
# with the CANONICAL two-token form ("$flag" "$val") -- never preserving the original spelling,
# and never appended as a second, duplicate occurrence alongside the original. This also removes
# any dependency on the target CLI implementing last-flag-wins parsing for a repeated flag: after
# this call there is exactly one occurrence, so there is nothing left for the CLI's own parser to
# disambiguate.
arr=(--model opus --verbose); replace_or_append_flag arr --model sonnet
assert_eq "replace space form (already canonical)" "--model sonnet --verbose" "${arr[*]}"
arr=(--model=opus --verbose); replace_or_append_flag arr --model sonnet
assert_eq "replace inline form, normalized to canonical two-token form" "--model sonnet --verbose" "${arr[*]}"
arr=(--verbose); replace_or_append_flag arr --effort high
assert_eq "append flag (canonical, none existed)" "--verbose --effort high" "${arr[*]}"
# Codex's -m also accepts an ATTACHED value (-mVALUE, no separator) -- must be replaced in
# place, normalized to the canonical "--model VALUE" two-token form (not left as "-mVALUE",
# and not left alongside a newly-appended --model, which codex rejects as "the argument
# '--model <MODEL>' cannot be used multiple times").
arr=(-mgpt-5.6-sol --verbose); replace_or_append_flag arr --model gpt-new -m
assert_eq "replace codex attached -mVALUE, normalized to canonical" "--model gpt-new --verbose" "${arr[*]}"

# A repeated flag in the ORIGINAL argv (the user's own doing, not ours) must have only its LAST
# occurrence replaced -- that's the one a real CLI parser actually applies (last-flag-wins), so
# it's the only one that needs to become correct. Earlier occurrence(s) are left completely
# untouched: touching them isn't necessary to make the override take effect, and the minimum
# edit is preferred over rewriting everything that happens to match.
arr=(--model sonnet --verbose --model opus); replace_or_append_flag arr --model haiku
assert_eq "only the LAST occurrence of a repeated flag is replaced" "--model sonnet --verbose --model haiku" "${arr[*]}"
arr=(-mold1 --model old2 -mold3); replace_or_append_flag arr --model new -m
assert_eq "last occurrence wins across mixed alias spellings too" "-mold1 --model old2 --model new" "${arr[*]}"

# A flag's own VALUE token must never be re-scanned as if it were another occurrence of the
# flag, even when that value happens to look like one of the accepted alias spellings -- the
# scan must skip past a matched "space"-mode pair's value token, not re-examine it independently.
arr=(--model -m --verbose); replace_or_append_flag arr --model new -m
assert_eq "a value token that looks like an alias spelling is not re-matched as another occurrence" "--model new --verbose" "${arr[*]}"

arr=(-m glm-5.2 -c model_reasoning_effort=none); replace_or_append_kv arr model_reasoning_effort low
assert_eq "replace kv" "-m glm-5.2 -c model_reasoning_effort=low" "${arr[*]}"
arr=(-m glm-5.2); replace_or_append_kv arr model_reasoning_effort high
assert_eq "append kv" "-m glm-5.2 -c model_reasoning_effort=high" "${arr[*]}"
arr=(-c model_reasoning_effort=low -c model_reasoning_effort=mid); replace_or_append_kv arr model_reasoning_effort high
assert_eq "kv: only the LAST occurrence of a repeated key is replaced" "-c model_reasoning_effort=low -c model_reasoning_effort=high" "${arr[*]}"

# Codex's real CLI also accepts an ATTACHED "-ckey=value" form (no space) -- confirmed against
# the installed codex binary. Must be recognized as an existing occurrence to replace, not left
# alongside a newly-appended duplicate "-c key=value" pair.
arr=(-cmodel_reasoning_effort=low --verbose)
replace_or_append_kv arr model_reasoning_effort high
assert_eq "replace_or_append_kv recognizes codex's attached -cKEY=VALUE form" "-c model_reasoning_effort=high --verbose" "${arr[*]}"

# Last-occurrence-wins must hold across a MIX of the two-token and attached forms too.
arr=(-c model_reasoning_effort=low -cmodel_reasoning_effort=mid); replace_or_append_kv arr model_reasoning_effort high
assert_eq "kv: last occurrence wins across mixed two-token/attached forms" "-c model_reasoning_effort=low -c model_reasoning_effort=high" "${arr[*]}"

# codex's -c/--config are two spellings of the SAME flag (confirmed via `codex --help`: "-c,
# --config <key=value>" documented as one entry) -- both the two-token "--config key=value" and
# the attached "--config=key=value" (long-flag "=" form) must be recognized as an existing
# occurrence to replace, not left alongside a newly-appended duplicate "-c key=value" pair.
arr=(--config model_reasoning_effort=low --verbose)
replace_or_append_kv arr model_reasoning_effort high
assert_eq "replace_or_append_kv recognizes codex's --config key=value form" "-c model_reasoning_effort=high --verbose" "${arr[*]}"
arr=(--config=model_reasoning_effort=low --verbose)
replace_or_append_kv arr model_reasoning_effort high
assert_eq "replace_or_append_kv recognizes codex's --config=key=value form" "-c model_reasoning_effort=high --verbose" "${arr[*]}"
arr=(-c model_reasoning_effort=low --config model_reasoning_effort=mid --config=model_reasoning_effort=high)
replace_or_append_kv arr model_reasoning_effort max
assert_eq "kv: last occurrence wins across -c/--config/--config= all mixed" \
  "-c model_reasoning_effort=low --config model_reasoning_effort=mid -c model_reasoning_effort=max" "${arr[*]}"

# dedupe_idempotent_flags: a locally-aliased CLI name (e.g. `alias claude='claude
# --dangerously-skip-permissions --verbose'`) re-expands ahead of the same flags on every
# relaunch, so a captured argv that has already been through N rotations carries N copies of
# whatever the alias adds -- this must collapse back to one copy, regardless of N. Deliberately
# an ALLOWLIST (IDEMPOTENT_FLAGS), not shape-inference -- see the function's own comment for the
# two corruption modes a prior shape-based version had and was rejected in review for.
#
# Operates on the global BASE_FLAGS directly (no nameref parameter, single-use helper -- see the
# function's own comment for why a nameref here was a real footgun), so every case below sets
# BASE_FLAGS itself rather than an arbitrarily-named local array.
IDEMPOTENT_FLAGS=(--dangerously-skip-permissions --verbose)

BASE_FLAGS=(--dangerously-skip-permissions --verbose --model opus --effort high)
dedupe_idempotent_flags
assert_eq "single copy (no alias yet) is left alone" \
  "--dangerously-skip-permissions --verbose --model opus --effort high" "${BASE_FLAGS[*]}"

BASE_FLAGS=(--dangerously-skip-permissions --verbose --dangerously-skip-permissions --verbose --model opus --effort high)
dedupe_idempotent_flags
assert_eq "two copies collapse to one, trailing flags untouched" \
  "--dangerously-skip-permissions --verbose --model opus --effort high" "${BASE_FLAGS[*]}"

BASE_FLAGS=(--dangerously-skip-permissions --verbose --dangerously-skip-permissions --verbose --dangerously-skip-permissions --verbose --dangerously-skip-permissions --verbose --dangerously-skip-permissions --verbose --model opus --effort high)
dedupe_idempotent_flags
assert_eq "five copies (matches the live-observed count) collapse to one" \
  "--dangerously-skip-permissions --verbose --model opus --effort high" "${BASE_FLAGS[*]}"

BASE_FLAGS=(--verbose --model opus)
dedupe_idempotent_flags
assert_eq "a single boolean flag with no repetition at all is left alone" "--verbose --model opus" "${BASE_FLAGS[*]}"

# A flag NOT on the allowlist must never be touched, no matter how it repeats -- this is the
# whole point of an allowlist over shape-inference: a same-flag-different-value repeat (e.g.
# --add-dir given twice on purpose)...
BASE_FLAGS=(--add-dir /a --add-dir /b --model opus)
dedupe_idempotent_flags
assert_eq "unlisted flag, different values: left untouched" \
  "--add-dir /a --add-dir /b --model opus" "${BASE_FLAGS[*]}"
# ...and even an EXACT repeat of an unlisted flag (e.g. a counted -v -v -v verbosity flag, where
# the repetition itself is meaningful) must survive untouched -- a prior shape-based version of
# this function collapsed exactly this case, silently changing behavior.
BASE_FLAGS=(-v -v -v --model opus)
dedupe_idempotent_flags
assert_eq "unlisted flag, exact repeat with meaningful count: left untouched" \
  "-v -v -v --model opus" "${BASE_FLAGS[*]}"

# The repeating unit can appear anywhere, any number of times, and non-adjacently -- only exact
# occurrences of a LISTED token are ever collapsed, regardless of position.
BASE_FLAGS=(--verbose --verbose --verbose --model opus)
dedupe_idempotent_flags
assert_eq "three repeats of a listed flag collapse to one" "--verbose --model opus" "${BASE_FLAGS[*]}"
BASE_FLAGS=(--verbose --model opus --verbose --effort high)
dedupe_idempotent_flags
assert_eq "non-adjacent repeats of a listed flag still collapse" \
  "--verbose --model opus --effort high" "${BASE_FLAGS[*]}"

# A real alias unit with an INTERNAL repeat (e.g. the alias itself lists the same flag twice) is
# exactly the case a shape-based version corrupted (A A B A A B -> A B A A B, a coincidental
# shorter period winning over the real cycle) -- the allowlist approach has no such failure mode
# since every listed-flag occurrence is deduped independently of any inferred "unit".
IDEMPOTENT_FLAGS=(--dangerously-skip-permissions)
BASE_FLAGS=(--dangerously-skip-permissions --dangerously-skip-permissions --verbose --dangerously-skip-permissions --dangerously-skip-permissions --verbose --model opus)
dedupe_idempotent_flags
assert_eq "an alias unit with its own internal repeat collapses correctly, unlisted --verbose untouched" \
  "--dangerously-skip-permissions --verbose --verbose --model opus" "${BASE_FLAGS[*]}"
IDEMPOTENT_FLAGS=(--dangerously-skip-permissions --verbose)

# Nothing past a literal "--" is a flag (see strip_context_flags) -- it must never be touched,
# even if it looks like a listed flag repeating.
BASE_FLAGS=(--dangerously-skip-permissions --verbose --dangerously-skip-permissions --verbose -- --dangerously-skip-permissions --verbose)
dedupe_idempotent_flags
assert_eq "positional data past -- is never touched, even if it looks like a listed repeat" \
  "--dangerously-skip-permissions --verbose -- --dangerously-skip-permissions --verbose" "${BASE_FLAGS[*]}"

BASE_FLAGS=()
dedupe_idempotent_flags
assert_eq "empty array is left alone" "" "${BASE_FLAGS[*]}"

# IDEMPOTENT_FLAGS itself is optional (unset/empty for a kind with no known-idempotent flags,
# same convention as MODEL_FLAG_ALIASES) -- must be a true no-op, not an error, under set -u.
# Tested both genuinely UNSET (the real state for a per-kind script that never sets it, e.g.
# pi/codex today) and explicitly empty, since those are two different variable states in bash.
unset IDEMPOTENT_FLAGS
BASE_FLAGS=(--dangerously-skip-permissions --dangerously-skip-permissions --model opus)
dedupe_idempotent_flags
assert_eq "genuinely-unset IDEMPOTENT_FLAGS is a no-op, not an error" \
  "--dangerously-skip-permissions --dangerously-skip-permissions --model opus" "${BASE_FLAGS[*]}"

IDEMPOTENT_FLAGS=()
BASE_FLAGS=(--dangerously-skip-permissions --dangerously-skip-permissions --model opus)
dedupe_idempotent_flags
assert_eq "explicitly-empty IDEMPOTENT_FLAGS is a no-op, not an error" \
  "--dangerously-skip-permissions --dangerously-skip-permissions --model opus" "${BASE_FLAGS[*]}"
IDEMPOTENT_FLAGS=(--dangerously-skip-permissions --verbose)

# value_of_kv (the read path) must recognize the same --config/--config= forms as the write path
# above, or a codex agent launched with either can't have its effort changes detected at all.
assert_eq "value_of_kv recognizes codex's --config key=value form" "low" \
  "$(value_of_kv model_reasoning_effort codex --config model_reasoning_effort=low)"
assert_eq "value_of_kv recognizes codex's --config=key=value form" "low" \
  "$(value_of_kv model_reasoning_effort codex --config=model_reasoning_effort=low)"
assert_eq "value_of_kv: last occurrence wins across -c/--config/--config= all mixed" "max" \
  "$(value_of_kv model_reasoning_effort -c model_reasoning_effort=low --config model_reasoning_effort=mid --config=model_reasoning_effort=max)"

# TOML permits (but doesn't require) whitespace around "=" and either single or double quotes
# around a string value -- confirmed live against the installed codex binary (`codex -c
# 'model_reasoning_effort = "low"'` and `codex -c "model_reasoning_effort='low'"` both accepted).
# Both the read path (value_of_kv, which also unquotes) and the write path
# (replace_or_append_kv, which only needs to DETECT the existing occurrence) must recognize
# these forms.
assert_eq "value_of_kv tolerates whitespace around = and strips double quotes" "low" \
  "$(value_of_kv model_reasoning_effort -c 'model_reasoning_effort = "low"')"
assert_eq "value_of_kv tolerates whitespace around = and strips single quotes" "low" \
  "$(value_of_kv model_reasoning_effort -c "model_reasoning_effort = 'low'")"
assert_eq "value_of_kv strips single quotes with no surrounding whitespace" "low" \
  "$(value_of_kv model_reasoning_effort -c "model_reasoning_effort='low'")"

arr=(-c 'model_reasoning_effort = "low"')
replace_or_append_kv arr model_reasoning_effort high
assert_eq "replace_or_append_kv recognizes a whitespace-around-= existing occurrence, replacing it (no duplicate)" \
  "-c model_reasoning_effort=high" "${arr[*]}"

# TOML also permits whitespace at the OUTER boundaries of the assignment itself -- leading
# whitespace before the key, and trailing whitespace after the (possibly quoted) value -- both
# confirmed live (`codex -c ' model_reasoning_effort = "low" '`). The trailing case matters most:
# a naive greedy capture of "the rest of the string" as the value would swallow that trailing
# whitespace INSIDE what's compared against the closing quote, making the quote-strip pattern
# fail to match and leaving the quotes (and the space) in the returned value.
assert_eq "value_of_kv tolerates leading whitespace before the key" "low" \
  "$(value_of_kv model_reasoning_effort -c ' model_reasoning_effort=low')"
assert_eq "value_of_kv trims trailing whitespace before stripping quotes" "low" \
  "$(value_of_kv model_reasoning_effort -c 'model_reasoning_effort = "low" ')"
assert_eq "value_of_kv tolerates whitespace on both outer boundaries at once" "low" \
  "$(value_of_kv model_reasoning_effort -c ' model_reasoning_effort = "low" ')"

arr=(-c ' model_reasoning_effort = "low" ')
replace_or_append_kv arr model_reasoning_effort high
assert_eq "replace_or_append_kv recognizes leading whitespace before the key as an existing occurrence" \
  "-c model_reasoning_effort=high" "${arr[*]}"

# Past a "--" end-of-options marker, nothing is a flag any more (see strip_context_flags) --
# neither helper may match against, or insert a new flag into, whatever's on the far side of
# it. A missing flag must be inserted immediately BEFORE the delimiter, not after it (which
# would make it positional input instead of an option).
arr=(--model opus -- --resume should-survive); replace_or_append_flag arr --model sonnet
assert_eq "flag replace does not cross --" "--model sonnet -- --resume should-survive" "${arr[*]}"
arr=(-- some-prompt); replace_or_append_flag arr --model sonnet
assert_eq "flag insert lands before --, not after" "--model sonnet -- some-prompt" "${arr[*]}"
arr=(-- --model sonnet); replace_or_append_flag arr --model haiku
assert_eq "positional --model past -- is left alone" "--model haiku -- --model sonnet" "${arr[*]}"
arr=(-m glm-5.2 -- --config other); replace_or_append_kv arr model_reasoning_effort high
assert_eq "kv insert lands before --, not after" "-m glm-5.2 -c model_reasoning_effort=high -- --config other" "${arr[*]}"

# shared apply_override via descriptors
MODEL_FLAG=--model EFFORT_FLAG=--effort EFFORT_STYLE=flag
BASE_FLAGS=(--verbose); apply_override sonnet high
assert_eq "claude-style override" "--verbose --model sonnet --effort high" "${BASE_FLAGS[*]}"
MODEL_FLAG=-m EFFORT_FLAG=model_reasoning_effort EFFORT_STYLE=kv
BASE_FLAGS=(--verbose); apply_override glm-5.2 low
assert_eq "codex-style override" "--verbose -m glm-5.2 -c model_reasoning_effort=low" "${BASE_FLAGS[*]}"
BASE_FLAGS=(--verbose); apply_override "" ""
assert_eq "no override unchanged" "--verbose" "${BASE_FLAGS[*]}"

echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
