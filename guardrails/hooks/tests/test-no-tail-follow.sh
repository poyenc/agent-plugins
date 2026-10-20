#!/usr/bin/env bash
# Tests for no-tail-follow.sh: block `tail` in follow mode (-f/-F/--follow and its unambiguous
# abbreviations) wherever a command line can appear; allow one-shot tail and unrelated commands.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/no-tail-follow.sh"
HOOKS_JSON="$HERE/../hooks.json"
PASS=0; FAIL=0
assert_eq(){ if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; echo "    exp:[$2] act:[$3]"; FAIL=$((FAIL+1)); fi; }

mkjson(){ jq -nc --arg c "$1" '{session_id:"t",tool_name:"Bash",tool_input:{command:$c}}'; }
run(){ printf '%s' "$(mkjson "$1")" | bash "$SCRIPT"; }
decision(){ [ -n "$1" ] || { echo none; return; }; printf '%s' "$1" | jq -r '.decision // "none"' 2>/dev/null; }
blk(){ decision "$(run "$1")"; }   # "block" or "none"

echo "== BLOCK: follow mode in every spelling =="
assert_eq "tail -f file"                         block "$(blk 'tail -f /tmp/x.log')"
assert_eq "tail -F file"                         block "$(blk 'tail -F /tmp/x.log')"
assert_eq "tail --follow file"                   block "$(blk 'tail --follow /tmp/x.log')"
assert_eq "tail --follow=name file"              block "$(blk 'tail --follow=name /tmp/x.log')"
assert_eq "tail -fn5 file (cluster)"             block "$(blk 'tail -fn5 /tmp/x.log')"
assert_eq "tail -qF file (cluster)"              block "$(blk 'tail -qF /tmp/x.log')"
assert_eq "tail -n 20 -f file"                   block "$(blk 'tail -n 20 -f /tmp/x.log')"
assert_eq "tail -f after the file operand"       block "$(blk 'tail /tmp/x.log -f')"
assert_eq "tail -n 5 -f file (value consumed, then -f)" block "$(blk 'tail -n 5 -f /tmp/x.log')"
assert_eq "tail -qn 5 -f file"                   block "$(blk 'tail -qn 5 -f /tmp/x.log')"
assert_eq "tail --lines 5 -f file"               block "$(blk 'tail --lines 5 -f /tmp/x.log')"
assert_eq "tail --bytes=5 -f file"               block "$(blk 'tail --bytes=5 -f /tmp/x.log')"
assert_eq "tail -f --retry"                      block "$(blk 'tail -f --retry /tmp/x.log')"
assert_eq "tail --retry --follow"                block "$(blk 'tail --retry --follow /tmp/x.log')"

echo "== BLOCK: GNU long-option abbreviations of --follow =="
for o in --f --fo --fol --foll --follo; do
  assert_eq "tail $o -n0 file"                   block "$(blk "tail $o -n0 /tmp/x.log")"
done
assert_eq "tail --fol=name file"                 block "$(blk 'tail --fol=name /tmp/x.log')"
assert_eq "tail --foll=descriptor file"          block "$(blk 'tail --foll=descriptor /tmp/x.log')"

echo "== BLOCK: a --pid-bounded follow (it only ends when that process does) =="
assert_eq "tail --pid=123 -f file"               block "$(blk 'tail --pid=123 -f /tmp/x.log')"
assert_eq "tail -f --pid 123 file"               block "$(blk 'tail -f --pid 123 /tmp/x.log')"

echo "== BLOCK: any consumer, compound commands, bash -c, env prefix =="
assert_eq "tail -F | grep -m1"                   block "$(blk 'tail -F /tmp/x.log | grep -m1 DONE')"
assert_eq "tail -f | head -1"                    block "$(blk 'tail -f /tmp/x.log | head -1')"
assert_eq "tail -f | sed -n /X/q"                block "$(blk "tail -f /tmp/x.log | sed -n '/X/q'")"
assert_eq "cd && tail -f"                        block "$(blk 'cd /tmp && tail -f x.log')"
assert_eq "bash -c body"                         block "$(blk "bash -c 'tail -F /tmp/x.log | grep -m1 X'")"
assert_eq "env prefix assignment"                block "$(blk 'LC_ALL=C tail -f /tmp/x.log')"
assert_eq "command substitution"                 block "$(blk 'echo "$(tail -f /tmp/x.log)"')"

echo "== BLOCK: quoted command line passed to another command =="
assert_eq "ssh host \"tail -F file\" | grep -m1" block "$(blk 'ssh host "tail -F /tmp/x.log" | grep -m1 DONE')"
assert_eq "ssh host 'tail -f file'"              block "$(blk "ssh host 'tail -f /tmp/x.log'")"
assert_eq "ssh host with a command carrying cd"  block "$(blk "ssh host 'cd /w && tail -F x.log'")"
assert_eq "sbatch --wrap \"tail -f file\""         block "$(blk 'sbatch --wrap "tail -f /tmp/x.log"')"
assert_eq "docker exec c sh -c \"tail -F file\""   block "$(blk 'docker exec c sh -c "tail -F /tmp/x.log"')"
assert_eq "nested: ssh host bash -c ..."         block "$(blk "ssh host \"bash -c 'tail -F /tmp/x.log | grep -m1 X'\"")"

echo "== BLOCK: unquoted command carriers and wrappers (argv is the command) =="
assert_eq "ssh host tail -f file"                block "$(blk 'ssh host tail -f /tmp/x.log')"
assert_eq "ssh -o X=y host tail -F file"         block "$(blk 'ssh -o StrictHostKeyChecking=no host tail -F /tmp/x.log')"
assert_eq "docker exec c tail -f file"           block "$(blk 'docker exec c tail -f /tmp/x.log')"
assert_eq "docker exec -it c tail -f file"       block "$(blk 'docker exec -it c tail -f /tmp/x.log')"
assert_eq "kubectl exec pod -- tail -f file"     block "$(blk 'kubectl exec pod -- tail -f /tmp/x.log')"
assert_eq "watch tail -f file"                   block "$(blk 'watch tail -f /tmp/x.log')"
assert_eq "xargs tail -f"                        block "$(blk 'echo /tmp/x.log | xargs tail -f')"
assert_eq "sudo -u root tail -f file"            block "$(blk 'sudo -u root tail -f /tmp/x.log')"
assert_eq "env -u X tail -f file"                block "$(blk 'env -u X tail -f /tmp/x.log')"
assert_eq "nohup tail -f file"                   block "$(blk 'nohup tail -f /tmp/x.log')"
assert_eq "timeout 5 tail -f file"               block "$(blk 'timeout 5 tail -f /tmp/x.log')"
assert_eq "path to the binary"                   block "$(blk '/usr/bin/tail -f /tmp/x.log')"

echo "== BLOCK: lexical -- a segment that merely names the words (documented false positive) =="
assert_eq "grep for the string tail -F"          block "$(blk "grep -rn 'tail -F' scripts")"
assert_eq "echo mentioning tail -f"              block "$(blk "echo 'do not run tail -f here'")"

echo "== nesting depth: a quoted command line is scanned to a bounded depth =="
nest(){ local s='tail -f /tmp/x.log' i; for (( i=0; i<$1; i++ )); do s="bash -c $(printf '%q' "$s")"; done; printf '%s' "$s"; }
assert_eq "8 levels of bash -c: still blocked"   block "$(blk "$(nest 8)")"
assert_eq "9 levels of bash -c: beyond the bound fails open" none "$(blk "$(nest 9)")"

echo "== ALLOW: one-shot tail and unrelated commands =="
assert_eq "tail -n 50 file"                      none "$(blk 'tail -n 50 /tmp/x.log')"
assert_eq "tail -50 file"                        none "$(blk 'tail -50 /tmp/x.log')"
assert_eq "tail -c 100 file"                     none "$(blk 'tail -c 100 /tmp/x.log')"
assert_eq "tail -n5 file (value cluster)"        none "$(blk 'tail -n5 /tmp/x.log')"
assert_eq "tail -s 1 file (value option)"        none "$(blk 'tail -s 1 /tmp/x.log')"
assert_eq "tail --lines=5 file"                  none "$(blk 'tail --lines=5 /tmp/x.log')"
assert_eq "tail --bytes=5 file"                  none "$(blk 'tail --bytes=5 /tmp/x.log')"
assert_eq "tail --retry alone (ignored by tail, exits)" none "$(blk 'tail --retry /tmp/x.log')"
assert_eq "tail --fox (not a prefix of --follow)" none "$(blk 'tail --fox /tmp/x.log')"
assert_eq "tail -n -f file (-f is the value of -n)" none "$(blk 'tail -n -f /tmp/x.log')"
assert_eq "tail -c -f file"                      none "$(blk 'tail -c -f /tmp/x.log')"
assert_eq "tail -s -f file"                      none "$(blk 'tail -s -f /tmp/x.log')"
assert_eq "tail -qn -f file (cluster ends in -n)" none "$(blk 'tail -qn -f /tmp/x.log')"
assert_eq "tail --lines -f file"                 none "$(blk 'tail --lines -f /tmp/x.log')"
assert_eq "tail --bytes -f file"                 none "$(blk 'tail --bytes -f /tmp/x.log')"
assert_eq "tail --pid -f file"                   none "$(blk 'tail --pid -f /tmp/x.log')"
assert_eq "tail --l -f file (prefix of --lines)" none "$(blk 'tail --l -f /tmp/x.log')"
assert_eq "grep PATTERN file"                    none "$(blk 'grep -m1 DONE /tmp/x.log')"
assert_eq "cat file | tail -n 3"                 none "$(blk 'cat /tmp/x.log | tail -n 3')"
assert_eq "ssh host \"tail -n 50 file\""         none "$(blk 'ssh host "tail -n 50 /tmp/x.log"')"
assert_eq "ssh host tail -n 50 file"             none "$(blk 'ssh host tail -n 50 /tmp/x.log')"
assert_eq "grep for the word tail alone"         none "$(blk "grep -rn 'tail' scripts")"
assert_eq "rm -f file"                           none "$(blk 'rm -f /tmp/x.log')"
assert_eq "tail after -- with a -f-looking file" none "$(blk 'tail -n 5 -- -f')"

echo "== no fail-open on heredocs / quoted newlines: a real follow beside them is caught =="
assert_eq "tail -f x; then a heredoc"            block "$(blk $'tail -f x; cat <<EOF\nhello\nEOF')"
assert_eq "heredoc with an apostrophe, then tail -f" block "$(blk $'cat <<\'EOF\'\ndon\'t do it\nEOF\ntail -f x')"
assert_eq "quoted newline, then tail -F"         block "$(blk $'echo "multi\nline"; tail -F f')"
assert_eq "printf with \\n, then tail -f"         block "$(blk $'printf "a\\nb"; tail -f f')"
assert_eq "here-string beside tail -f"           block "$(blk 'tail -f x <<< "here string"')"
assert_eq "heredoc body that names tail -f (documented false positive)" block "$(blk $'cat <<EOF\ntail -f x\nEOF')"
assert_eq "heredoc with no follow option"        none "$(blk $'cat <<EOF\nplain text, no follow\nEOF')"
assert_eq "multi-line quoted string, no follow"  none "$(blk $'git commit -m "msg\nbody"')"

echo "== block payload is valid JSON, says what to do, names no other skill =="
out=$(run 'tail -F /tmp/x.log | grep -m1 DONE')
assert_eq "payload parses as JSON"               ok "$(printf '%s' "$out" | jq -e . >/dev/null 2>&1 && echo ok || echo bad)"
reason=$(printf '%s' "$out" | jq -r .reason)
assert_eq "reason steers to run_in_background"   yes "$(printf '%s' "$reason" | grep -q 'run_in_background' && echo yes || echo no)"
assert_eq "reason steers to a scheduled check on Claude Code" yes "$(printf '%s' "$reason" | grep -q 'ScheduleWakeup or CronCreate' && echo yes || echo no)"
assert_eq "reason names the pi equivalents"      yes "$(printf '%s' "$reason" | grep -q 'Agent tool' && printf '%s' "$reason" | grep -q 'schedule_prompt' && echo yes || echo no)"
assert_eq "reason does not suggest polling with a one-shot command" no "$(printf '%s' "$reason" | grep -qi 'one-shot' && echo yes || echo no)"
assert_eq "reason names no other skill"          no  "$(printf '%s' "$reason" | grep -qi 'skill' && echo yes || echo no)"

echo "== registration: wired into hooks.json under PreToolUse/Bash =="
assert_eq "hooks.json registers no-tail-follow.sh" 1 \
  "$(jq '[.hooks.PreToolUse[] | select(.matcher=="Bash") | .hooks[] | select(.command | contains("no-tail-follow.sh"))] | length' "$HOOKS_JSON")"

echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
