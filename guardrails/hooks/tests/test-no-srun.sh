#!/usr/bin/env bash
# Tests for no-srun.sh: block any Bash command containing the word `srun`, steering to
# `salloc` once + reusable plain `ssh <node> <command>` instead. This is a lexical "word
# anywhere" match (not a command-aware parse), so a `srun` mention inside e.g. `grep -R srun .`
# is intentionally blocked too -- see the hook's own comment and the guardrails README.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/no-srun.sh"
PASS=0; FAIL=0
assert_eq(){ if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; echo "    exp:[$2] act:[$3]"; FAIL=$((FAIL+1)); fi; }

mkjson(){ jq -nc --arg c "$1" '{session_id:"t",tool_name:"Bash",tool_input:{command:$c}}'; }
run(){ printf '%s' "$(mkjson "$1")" | bash "$SCRIPT"; }
decision(){ [ -n "$1" ] || { echo none; return; }; printf '%s' "$1" | jq -r '.decision // "none"' 2>/dev/null; }
valid_json(){ [ -n "$1" ] || { echo ok; return; }; printf '%s' "$1" | jq -e . >/dev/null 2>&1 && echo ok || echo bad; }
blk(){ decision "$(run "$1")"; }   # "block" or "none"

echo "== BLOCK: bare and simple forms =="
assert_eq "srun --pty bash -i"       block "$(blk 'srun --pty bash -i')"
assert_eq "srun (no args)"           block "$(blk 'srun')"
assert_eq "compound: echo hi && srun --pty bash" block "$(blk 'echo hi && srun --pty bash')"

echo "== BLOCK: separator/adjacency forms a naive shell-token class misses =="
assert_eq "srun>/tmp/job.log (redirection, no space)"   block "$(blk 'srun>/tmp/job.log')"
assert_eq "srun</dev/null (input redirection, no space)" block "$(blk 'srun</dev/null')"
assert_eq "/usr/bin/srun --pty bash (path-qualified)"    block "$(blk '/usr/bin/srun --pty bash')"
assert_eq '"srun" --pty bash (quoted)'                   block "$(blk '"srun" --pty bash')"

echo "== ALLOW: the documented alternative and unrelated commands =="
assert_eq "salloc --gres=... --time=..."          none "$(blk 'salloc --gres=gpu:gfx942:1 --time=1-0')"
assert_eq "plain ssh to a node"                    none "$(blk 'ssh ctr-cx66-mi300x-01 nvidia-smi')"
assert_eq "empty command"                          none "$(blk '')"

echo "== ALLOW: word-boundary false-positive guards =="
assert_eq "./srunner.sh (srun is a substring, not the word)" none "$(blk './srunner.sh')"
assert_eq "my_srun --help (underscore-joined, not the word)" none "$(blk 'my_srun --help')"

echo "== documented behavior: a lexical mention of srun anywhere is intentionally blocked =="
assert_eq "grep -R srun . (word 'srun' present, lexical match by design)" block "$(blk 'grep -R srun .')"

echo "== block payload is valid JSON and explains the fix =="
out=$(run 'srun --pty bash')
assert_eq "block payload parses as JSON" ok "$(valid_json "$out")"
assert_eq "reason mentions salloc"  yes "$(printf '%s' "$out" | jq -r .reason | grep -qi 'salloc' && echo yes || echo no)"
assert_eq "reason mentions ssh"     yes "$(printf '%s' "$out" | jq -r .reason | grep -qi 'ssh' && echo yes || echo no)"

echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
