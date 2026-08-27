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

arr=(--model opus --verbose); replace_or_append_flag arr --model sonnet
assert_eq "replace space form" "--model sonnet --verbose" "${arr[*]}"
arr=(--model=opus --verbose); replace_or_append_flag arr --model sonnet
assert_eq "replace inline form" "--model=sonnet --verbose" "${arr[*]}"
arr=(--verbose); replace_or_append_flag arr --effort high
assert_eq "append flag" "--verbose --effort high" "${arr[*]}"
# Codex's -m also accepts an ATTACHED value (-mVALUE, no separator) -- must be replaced in
# place like the other spellings, not left alongside a newly-appended --model/-m (which codex
# rejects as "the argument '--model <MODEL>' cannot be used multiple times").
arr=(-mgpt-5.6-sol --verbose); replace_or_append_flag arr --model gpt-new -m
assert_eq "replace codex attached -mVALUE" "-mgpt-new --verbose" "${arr[*]}"

arr=(-m glm-5.2 -c model_reasoning_effort=none); replace_or_append_kv arr model_reasoning_effort low
assert_eq "replace kv" "-m glm-5.2 -c model_reasoning_effort=low" "${arr[*]}"
arr=(-m glm-5.2); replace_or_append_kv arr model_reasoning_effort high
assert_eq "append kv" "-m glm-5.2 -c model_reasoning_effort=high" "${arr[*]}"

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
