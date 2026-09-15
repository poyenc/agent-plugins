#!/usr/bin/env bash
# Tests for no-blind-search.sh: block the PLAIN form of a recursive search (grep -r/-R, rg, fd) or
# recursive listing (ls -R) rooted at a WHOLE tree (/, ~, $HOME, or the literal home path), and FAIL
# OPEN (allow) the moment any other/unknown flag appears -- so a legitimate command is never
# mis-blocked. Also exercises the shared plumbing via grep/rg. `find` is no-blind-find.sh's job.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/no-blind-search.sh"
PASS=0; FAIL=0
assert_eq(){ if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; echo "    exp:[$2] act:[$3]"; FAIL=$((FAIL+1)); fi; }

mkjson(){ jq -nc --arg c "$1" '{session_id:"t",tool_name:"Bash",tool_input:{command:$c}}'; }
run(){ printf '%s' "$(mkjson "$1")" | bash "$SCRIPT"; }
decision(){ [ -n "$1" ] || { echo none; return; }; printf '%s' "$1" | jq -r '.decision // "none"' 2>/dev/null; }
valid_json(){ [ -n "$1" ] || { echo ok; return; }; printf '%s' "$1" | jq -e . >/dev/null 2>&1 && echo ok || echo bad; }
blk(){ decision "$(run "$1")"; }   # "block" or "none"

echo "== BLOCK: plain recursive grep / rg / fd / ls -R rooted at / =="
assert_eq "grep -r x /"             block "$(blk 'grep -r x /')"
assert_eq "grep -R pattern /"       block "$(blk 'grep -R pattern /')"
assert_eq "grep --recursive x /"    block "$(blk 'grep --recursive x /')"
assert_eq "rg foo /"                block "$(blk 'rg foo /')"
assert_eq "fd bar /"                block "$(blk 'fd bar /')"
assert_eq "ls -R /"                 block "$(blk 'ls -R /')"
assert_eq "rg x / src (/ is one of several path operands)" block "$(blk 'rg x / src')"

echo "== BLOCK: rooted at ~ / \$HOME / literal home =="
assert_eq "rg x ~"                  block "$(blk 'rg x ~')"
assert_eq "rg x \$HOME"             block "$(blk 'rg x $HOME')"
assert_eq "fd y ~"                  block "$(blk 'fd y ~')"
assert_eq "grep -r z <literal \$HOME>" block "$(blk "grep -r z $HOME")"
assert_eq 'grep -r x "$HOME" (quoted home)'  block "$(blk 'grep -r x "$HOME"')"
assert_eq 'rg x ${HOME} (braced home)'       block "$(blk 'rg x ${HOME}')"
assert_eq 'grep -r x "$HOME"/ (trailing slash)' block "$(blk 'grep -r x "$HOME"/')"

echo "== BLOCK: redirection after the root doesn't hide it =="
assert_eq "grep -r x / 2>/dev/null"  block "$(blk 'grep -r x / 2>/dev/null')"
assert_eq "ls -R / >out"             block "$(blk 'ls -R / >out')"

echo "== ALLOW: narrower / legitimate searches =="
assert_eq "grep -r x src/"          none "$(blk 'grep -r x src/')"
assert_eq "rg foo (no path)"        none "$(blk 'rg foo')"
assert_eq "fd bar (no path)"        none "$(blk 'fd bar')"
assert_eq "ls -R ./dir"             none "$(blk 'ls -R ./dir')"
assert_eq "ls / (non-recursive listing)"  none "$(blk 'ls /')"
assert_eq "non-recursive grep reading a file under /var" none "$(blk 'grep pattern /var/log/syslog')"

echo "== ALLOW: a whole-tree token that is the PATTERN, not a path =="
assert_eq "rg / (/ is the search pattern)"   none "$(blk 'rg /')"
assert_eq "fd ~ (~ is the pattern)"          none "$(blk 'fd ~')"
assert_eq "grep -r / (/ is the pattern)"     none "$(blk 'grep -r /')"
assert_eq "grep -- -r / (-r is a pattern after --, not recursive)" none "$(blk 'grep -- -r /')"
assert_eq "grep -r 'a / b' . (mid-pattern slash, path is .)" none "$(blk 'grep -r "a / b" .')"

echo "== ALLOW (documented fail-open): any extra/unknown flag makes it fail open =="
assert_eq "grep -rn foo / (bundled -rn -> fail open)"      none "$(blk 'grep -rn foo /')"
assert_eq "grep -ri foo / (bundled -ri)"                  none "$(blk 'grep -ri foo /')"
assert_eq "grep -r --include=*.c foo / (extra option)"    none "$(blk 'grep -r --include=*.c foo /')"
assert_eq "grep -r --regexp=x / (pattern via flag)"       none "$(blk 'grep -r --regexp=x /')"
assert_eq "grep -r -e x / (pattern via -e)"               none "$(blk 'grep -r -e x /')"
assert_eq "rg -i foo / (extra flag)"                      none "$(blk 'rg -i foo /')"
assert_eq "rg -g *.rs foo / (value-taking -g)"            none "$(blk 'rg -g *.rs foo /')"
assert_eq "rg -r x / . (rg -r is --replace)"              none "$(blk 'rg -r x / .')"
assert_eq "rg --files / (path-only mode is still a flag)" none "$(blk 'rg --files /')"
assert_eq "fd -e txt / (value-taking -e)"                 none "$(blk 'fd -e txt /')"
assert_eq "ls -R -I / . (value-taking -I)"                none "$(blk 'ls -R -I / .')"
assert_eq "ls -Ra / (bundled -Ra)"                        none "$(blk 'ls -Ra /')"

echo "== quoted options are classified as options (shell strips quotes) -> no false-block =="
assert_eq 'rg "-i" / (quoted flag; / is the pattern)'       none "$(blk 'rg "-i" /')"
assert_eq 'rg "--" / . (quoted --; / is the pattern, . the path)' none "$(blk 'rg "--" / .')"
assert_eq "rg -'i' / (mixed quoting of a flag)"             none "$(blk "rg -'i' /")"
# ... but a REAL unquoted -- still ends options, so a root path operand after it blocks:
assert_eq "rg -- foo / (-- then pattern foo, / is the path)" block "$(blk 'rg -- foo /')"

echo "== an operand from an unresolved expansion has an unknowable role -> fail open =="
assert_eq 'opt=-i; rg "$opt" / (runtime -i makes / the pattern)' none "$(blk 'opt=-i; rg "$opt" /')"
assert_eq "rg \$'-i' / (ANSI-C-quoted expansion)"               none "$(blk "rg \$'-i' /")"
assert_eq 'rg "$pat" / (var could be anything -> fail open)'    none "$(blk 'rg "$pat" /')"
# ... but the MODELED $HOME/${HOME} roots are resolvable and still block:
assert_eq 'rg x "$HOME" (modeled root still blocks)'            block "$(blk 'rg x "$HOME"')"
assert_eq 'rg x ${HOME} (modeled root still blocks)'           block "$(blk 'rg x ${HOME}')"

echo "== an unquoted here-doc operator fails the whole command open =="
assert_eq "cat <<'EOF' ... grep -r x / ... EOF (here-doc data)" none "$(blk $'cat <<'\''EOF'\''\ngrep -r x /\nEOF')"

echo "== a HOME reassignment earlier in the command fails the whole command open =="
assert_eq 'HOME=/tmp/ph; rg needle "$HOME" (runtime home is narrow)' none "$(blk 'HOME=/tmp/ph; rg needle "$HOME"')"
assert_eq 'XDG_CONFIG_HOME=/c HOME=/tmp/ph; rg x "$HOME" (HOME not first assignment)' none "$(blk 'XDG_CONFIG_HOME=/c HOME=/tmp/ph; rg x "$HOME"')"
assert_eq 'rg needle "$HOME" (no HOME mutation, still blocks)'      block "$(blk 'rg needle "$HOME"')"

echo "== a physical newline inside quoted data is not a command separator -> fail open =="
assert_eq "single-quoted multiline data containing grep -r x /"      none "$(blk $'printf %s '\''a\ngrep -r x /\nb'\''')"

echo "== ALLOW: non-scanner commands / the find hook's tools are ignored here =="
assert_eq "cat /etc/hosts (not a scanner)"   none "$(blk 'cat /etc/hosts')"
assert_eq "echo / (not a scanner)"           none "$(blk 'echo /')"
assert_eq "find / (find is no-blind-find.sh's job)" none "$(blk 'find /')"

echo "== compound commands: a plain blind search in ANY sub-command is blocked =="
assert_eq "echo hi ; grep -r TODO /"        block "$(blk 'echo hi ; grep -r TODO /')"
assert_eq "piped: cat x | grep -r y /"      block "$(blk 'cat x | grep -r y /')"
assert_eq "while grep -r x /; do :; done"   block "$(blk 'while grep -r x /; do :; done')"

echo "== compound commands: scanner + root in DIFFERENT sub-commands must NOT cross-match =="
assert_eq "grep -r x src/ ; ls /  (grep on src/, ls / non-recursive)" none "$(blk 'grep -r x src/ ; ls /')"
assert_eq "grep -r x src/ && echo /  (echo / is not a scan)"          none "$(blk 'grep -r x src/ && echo /')"
assert_eq "rg x ./here ; cat /  (cat / is not a scan)"                none "$(blk 'rg x ./here ; cat /')"

echo "== quote-aware segmentation: a separator inside a quoted pattern is not a command break =="
assert_eq "grep -r 'a;b' / (quoted ';' in pattern, / is the path)" block "$(blk 'grep -r "a;b" /')"

echo "== command-word anchoring: a scanner word inside a string is not a command =="
assert_eq "printf 'grep -r x /' (scanner text inside a string)"    none "$(blk "printf 'grep -r x /'")"
assert_eq "echo grep -r x / (grep is an argument to echo)"         none "$(blk 'echo grep -r x /')"

echo "== quote provenance: single-quoted \$HOME is a literal dir, double-quoted expands =="
assert_eq "grep -r x '\$HOME' (single-quoted -> literal dir)" none  "$(blk "grep -r x '\$HOME'")"
assert_eq 'grep -r x "$HOME" (double-quoted -> home tree)'   block "$(blk 'grep -r x "$HOME"')"

echo "== bash -c / sh -c bodies are recursed into =="
assert_eq "sh -c 'grep -r x /'"         block "$(blk "sh -c 'grep -r x /'")"
assert_eq "bash -c 'rg foo /'"          block "$(blk "bash -c 'rg foo /'")"
assert_eq "sh -ec 'grep -r x /' (clustered -c)"  block "$(blk "sh -ec 'grep -r x /'")"
assert_eq "bash -c 'grep -r x .' (narrow)"       none "$(blk "bash -c 'grep -r x .'")"
assert_eq "bash -n -c 'grep -r x /' (no-exec)"   none "$(blk "bash -n -c 'grep -r x /'")"

echo "== documented FAIL-OPEN: cmd-subst / wrapper value-options are MISSED =="
assert_eq 'echo "$(grep -r x /)" (double-quoted cmd-subst)' none "$(blk 'echo "$(grep -r x /)"')"
assert_eq "sudo -u root grep -r x / (wrapper value-option)" none "$(blk 'sudo -u root grep -r x /')"

echo "== block payload is valid JSON and explains the fix =="
out=$(run 'grep -r x /')
assert_eq "block payload parses as JSON" ok "$(valid_json "$out")"
assert_eq "reason mentions narrowing / asking" yes "$(printf '%s' "$out" | jq -r .reason | grep -qiE 'narrow|specific|ask' && echo yes || echo no)"

echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
