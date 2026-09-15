#!/usr/bin/env bash
# Tests for no-blind-find.sh: block `find` rooted at a WHOLE tree (/, ~, $HOME, or the literal home
# path), while leaving narrower/legitimate finds alone. Also exercises the shared plumbing in
# scan-guard-lib.sh (segmentation, tokenization, quote provenance, command-word anchoring, comments,
# bash -c recursion) through the find matcher. Recursive grep/rg/fd/ls live in no-blind-search.sh.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/no-blind-find.sh"
PASS=0; FAIL=0
assert_eq(){ if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; echo "    exp:[$2] act:[$3]"; FAIL=$((FAIL+1)); fi; }

mkjson(){ jq -nc --arg c "$1" '{session_id:"t",tool_name:"Bash",tool_input:{command:$c}}'; }
run(){ printf '%s' "$(mkjson "$1")" | bash "$SCRIPT"; }
decision(){ [ -n "$1" ] || { echo none; return; }; printf '%s' "$1" | jq -r '.decision // "none"' 2>/dev/null; }
valid_json(){ [ -n "$1" ] || { echo ok; return; }; printf '%s' "$1" | jq -e . >/dev/null 2>&1 && echo ok || echo bad; }
blk(){ decision "$(run "$1")"; }   # "block" or "none"

echo "== BLOCK: find rooted at / =="
assert_eq "find /"                  block "$(blk 'find /')"
assert_eq "find / -name foo"        block "$(blk 'find / -name foo')"
assert_eq "sudo find / -type f"     block "$(blk 'sudo find / -type f')"
assert_eq "compound: cd /tmp && find / -name x" block "$(blk 'cd /tmp && find / -name x')"
assert_eq "newline-split before find /" block "$(blk $'a=1\nfind / -name x')"

echo "== BLOCK: rooted at ~ / \$HOME / literal home =="
assert_eq "find ~"                  block "$(blk 'find ~')"
assert_eq "find \$HOME"             block "$(blk 'find $HOME')"
assert_eq "find <literal \$HOME>"   block "$(blk "find $HOME")"

echo "== ALLOW: narrower / legitimate finds =="
assert_eq "find ."                  none "$(blk 'find .')"
assert_eq "find ./src"              none "$(blk 'find ./src')"
assert_eq "find ~/workspace/repo/x" none "$(blk 'find ~/workspace/repo/x')"
assert_eq "find <home>/proj (subdir)" none "$(blk "find $HOME/proj")"

echo "== ALLOW: false-positive guards =="
assert_eq "find . -newer / (/ is a -newer operand, not the search root)" none "$(blk 'find . -newer /')"
assert_eq "echo / (not find)"                            none "$(blk 'echo /')"

echo "== the find hook ignores grep/rg/fd/ls (those are no-blind-search.sh's job) =="
assert_eq "grep -r x / (not find -> find hook allows)"   none "$(blk 'grep -r x /')"
assert_eq "rg foo / (not find)"                          none "$(blk 'rg foo /')"
assert_eq "ls -R / (not find)"                           none "$(blk 'ls -R /')"

echo "== compound commands: a blind find in ANY sub-command is blocked =="
assert_eq "a || find / -name x"             block "$(blk 'a || find / -name x')"
assert_eq "subshell (find /)"               block "$(blk '(find /)')"
assert_eq "compound: find ~/p ; echo / (neither is a blind find)" none "$(blk 'find ~/p ; echo /')"

echo "== command-word anchoring: a find word that isn't the command is ignored =="
assert_eq "echo find / (find is an argument to echo)"    none "$(blk 'echo find /')"
assert_eq "echo \"before; find /; after\" (quoted ; not a break)" none "$(blk 'echo "before; find /; after"')"

echo "== quoting / redirection / multiple-path forms of a REAL whole-tree find are still blocked =="
assert_eq "find / 2>/dev/null (redirection after root)"  block "$(blk 'find / 2>/dev/null')"
assert_eq "find <home>/ (trailing slash on whole home)"  block "$(blk "find $HOME/")"

echo "== quote provenance: single-quoted \$HOME/~ and double-quoted ~ are LITERAL dirs, not roots =="
assert_eq "find '\$HOME' (single-quoted -> literal dir named \$HOME)"  none "$(blk "find '\$HOME'")"
assert_eq "find '~' (single-quoted -> literal dir named ~)"           none "$(blk "find '~'")"
assert_eq 'find "~" (~ does not expand inside quotes)'                none "$(blk 'find "~"')"
assert_eq 'find "$HOME" (double-quoted $HOME DOES expand)'            block "$(blk 'find "$HOME"')"
assert_eq 'find ${HOME} (unquoted braced home)'                      block "$(blk 'find ${HOME}')"

echo "== backslash-escaped quote inside a double-quoted string is not a mis-split =="
assert_eq 'echo "before\"; find /; after" (escaped quote, no find runs)' none "$(blk 'echo "before\"; find /; after"')"

echo "== find pre-path options don't hide the root =="
assert_eq "find -L /"  block "$(blk 'find -L /')"
assert_eq "find -H /"  block "$(blk 'find -H /')"
assert_eq "find -P /"  block "$(blk 'find -P /')"
assert_eq "find -L ~/proj (pre-opt + narrow path)"  none "$(blk 'find -L ~/proj')"

echo "== quoted home followed by a trailing slash is still the home tree =="
assert_eq 'find "$HOME"/ (slash outside the quotes)'  block "$(blk 'find "$HOME"/')"
assert_eq 'find "$HOME/" (slash inside the quotes)'   block "$(blk 'find "$HOME/"')"
assert_eq 'find "$HOME"/proj (subdir, still allow)'   none  "$(blk 'find "$HOME"/proj')"

echo "== bash -c / sh -c bodies are recursed into =="
assert_eq "bash -c 'find /'"            block "$(blk "bash -c 'find /'")"
assert_eq "bash -c 'find .' (narrow)"   none  "$(blk "bash -c 'find .'")"
assert_eq "bash script.sh (no -c)"      none  "$(blk 'bash script.sh')"
assert_eq "bash -lc 'find /' (clustered -c)"  block "$(blk "bash -lc 'find /'")"
assert_eq "bash -c -- 'find /'"         block "$(blk "bash -c -- 'find /'")"
assert_eq "bash -n -c 'find /' (no-exec)"     none "$(blk "bash -n -c 'find /'")"
assert_eq "bash -nc 'find /' (clustered -n)"  none "$(blk "bash -nc 'find /'")"
assert_eq "bash -c 'find /' _ -n (-n is the body's \$1, not no-exec)" block "$(blk "bash -c 'find /' _ -n")"

echo "== shell control keywords before find are seen through =="
assert_eq "if find /; then echo hi; fi"       block "$(blk 'if find /; then echo hi; fi')"
assert_eq "! find /"                          block "$(blk '! find /')"
assert_eq "if false; then :; else find /; fi" block "$(blk 'if false; then :; else find /; fi')"
assert_eq "exec find /"                        block "$(blk 'exec find /')"
assert_eq "if find .; then :; fi (narrow, allow)" none "$(blk 'if find .; then :; fi')"

echo "== shell comments are not executable segments (no spurious block) =="
assert_eq "echo ok # note; find / (whole tail is a comment)"     none  "$(blk 'echo ok # note; find /')"
assert_eq "echo a#b find / (# not at a word boundary != comment)" none "$(blk 'echo a#b find /')"
assert_eq "find / # trailing comment (the find itself is real)"  block "$(blk 'find / # trailing comment')"
assert_eq "comment line, then a real find on the NEXT line"      block "$(blk $'echo ok # c\nfind /')"

echo "== quoted shell options: a quoted -n / a pre-c -- are honored (not a false-block) =="
assert_eq 'bash "-n" -c '"'"'find /'"'"' (quoted -n = no-exec)'  none  "$(blk "bash \"-n\" -c 'find /'")"
assert_eq 'bash -- -c '"'"'find /'"'"' (pre-c -- => -c is a filename)' none "$(blk "bash -- -c 'find /'")"
assert_eq "bash -o noexec -c 'find /' (long-form no-exec)"       none  "$(blk "bash -o noexec -c 'find /'")"
assert_eq "bash /dev/null -c 'find /' (script name before -c)"   none  "$(blk "bash /dev/null -c 'find /'")"
assert_eq 'bash "\-c" '"'"'find /'"'"' (\- literal in "" => script name, not -c)' none "$(blk 'bash "\-c" '"'"'find /'"'"'')"
assert_eq 'bash -c '"'"'echo ";find /"'"'"' (inner quotes preserved on re-parse => echo, no scan)' none "$(blk "bash -c 'echo \";find /\"'")"

echo "== a mixed-quoted command name still resolves (find IS the command) =="
assert_eq 'fi"nd" / (quotes inside the command word)'  block "$(blk 'fi"nd" /')"

echo "== a wrapper option must not re-anchor on its value as the command (no false-block) =="
assert_eq "env -u find echo / (-u's value is a var name, cmd is echo)" none "$(blk 'env -u find echo /')"
assert_eq "command -v find / (looks up find, does not run it)"        none "$(blk 'command -v find /')"
# ... but the no-option wrapper forms and VAR=val assignments still resolve the real command:
assert_eq "env X=1 find / (VAR=val assignment, cmd is find)"          block "$(blk 'env X=1 find /')"
assert_eq "sudo find / (no-option wrapper)"                           block "$(blk 'sudo find /')"

echo "== an unquoted here-doc operator fails the whole command open (data is not a command) =="
assert_eq "cat <<'EOF' ... find / ... EOF (here-doc data, not a scan)" none "$(blk $'cat <<'\''EOF'\''\nfind /\nEOF')"
assert_eq "plain multiline find / (no here-doc, still blocks)"        block "$(blk $'echo hi\nfind /')"

echo "== a quoted/escaped/expanded predicate is not a path: its root-looking operand fails open =="
assert_eq 'find "-newer" / (/ is -newer'"'"'s reference operand, path defaults to .)' none "$(blk 'find "-newer" /')"
assert_eq 'p=-newer; find "$p" / (expanded predicate -> fail open)'  none "$(blk 'p=-newer; find "$p" /')"
assert_eq "find . -newer / (unquoted predicate, / is its operand)"   none "$(blk 'find . -newer /')"

echo "== a HOME reassignment in an earlier segment fails the whole command open =="
assert_eq 'HOME=/tmp/ph; find "$HOME" (runtime home is narrow)'      none "$(blk 'HOME=/tmp/ph; find "$HOME"')"
assert_eq 'export HOME=/tmp/ph; find $HOME (export form)'            none "$(blk 'export HOME=/tmp/ph; find $HOME')"
assert_eq 'A=x HOME=/tmp/ph; find "$HOME" (HOME not the first assignment)' none "$(blk 'A=x HOME=/tmp/ph; find "$HOME"')"
assert_eq 'env HOME=/tmp/ph bash -c '"'"'find "$HOME"'"'"' (env HOME= wrapper)' none "$(blk "env HOME=/tmp/ph bash -c 'find \"\$HOME\"'")"
assert_eq 'unset HOME; find "$HOME" (HOME unset)'                    none "$(blk 'unset HOME; find "$HOME"')"
assert_eq 'find "$HOME" (no HOME mutation, still blocks)'           block "$(blk 'find "$HOME"')"

echo "== a physical newline INSIDE quotes is data, not a command separator -> fail open =="
assert_eq "single-quoted multiline data containing find /"           none "$(blk $'printf %s '\''a\nfind /\nb'\''')"
assert_eq 'backslash-newline inside double quotes (line continuation)' none "$(blk $'printf %s "a\\\nfind / b"')"
assert_eq "unquoted newline really separating echo from find / blocks" block "$(blk $'echo hi\nfind /')"

echo "== documented FAIL-OPEN: wrapper value-options / cmd-subst / cwd-change are MISSED =="
assert_eq "sudo -u root find / (wrapper value-option)"        none "$(blk 'sudo -u root find /')"
assert_eq 'echo "$(find /)" (double-quoted cmd-subst)'        none "$(blk 'echo "$(find /)"')"
assert_eq "cd / && find . (segments have no shared cwd state)" none "$(blk 'cd / && find .')"

echo "== block payload is valid JSON and explains the fix =="
out=$(run 'find /')
assert_eq "block payload parses as JSON" ok "$(valid_json "$out")"
assert_eq "reason mentions narrowing / asking" yes "$(printf '%s' "$out" | jq -r .reason | grep -qiE 'narrow|specific|ask' && echo yes || echo no)"

echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
