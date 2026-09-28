#!/usr/bin/env bash
# Tests for no-docker-on-login-node.sh: block direct `docker` invocations, but ONLY when the
# current machine's real hostname matches Alola's login-node naming convention. Overrides the
# `hostname` command (via a PATH-shadowing mock function/binary) rather than requiring an actual
# login node to test against.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/no-docker-on-login-node.sh"
PASS=0; FAIL=0
assert_eq(){ if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; echo "    exp:[$2] act:[$3]"; FAIL=$((FAIL+1)); fi; }

mkjson(){ jq -nc --arg c "$1" '{session_id:"t",tool_name:"Bash",tool_input:{command:$c}}'; }
# Runs the hook with `hostname` overridden to print $2, by putting a fake `hostname` earlier on
# PATH (the script calls the real `hostname` binary via PATH, not a bash builtin, so a
# function override wouldn't be seen by it -- needs an actual PATH-shadowing executable).
MOCKDIR=$(mktemp -d)
mkhostname(){ printf '#!/usr/bin/env bash\nprintf %%s "%s"\n' "$1" > "$MOCKDIR/hostname"; chmod +x "$MOCKDIR/hostname"; }
run(){ local cmd="$1" host="$2"; mkhostname "$host"; PATH="$MOCKDIR:$PATH" bash -c "printf '%s' \"\$1\" | bash \"\$2\"" _ "$(mkjson "$cmd")" "$SCRIPT"; }
decision(){ [ -n "$1" ] || { echo none; return; }; printf '%s' "$1" | jq -r '.decision // "none"' 2>/dev/null; }
valid_json(){ [ -n "$1" ] || { echo ok; return; }; printf '%s' "$1" | jq -e . >/dev/null 2>&1 && echo ok || echo bad; }
blk(){ decision "$(run "$1" "$2")"; }

echo "== ALLOW: not a login node, regardless of command =="
assert_eq "docker run, ordinary dev host"      none "$(blk 'docker run --rm myimage' 'my-laptop')"
assert_eq "docker build, a compute node"       none "$(blk 'docker build -t foo .' 'ctr-cx66-mi300x-01')"
assert_eq "docker run, heliosr silicon node"   none "$(blk 'docker run --rm myimage' 'heliosr-1b114-b07-3.mnb.dcgpu')"

echo "== BLOCK: on an Alola login node, any docker subcommand =="
assert_eq "docker run"                 block "$(blk 'docker run --rm myimage' 'ctr2-alola-login-04')"
assert_eq "docker build"               block "$(blk 'docker build -t foo .' 'ctr2-alola-login-01')"
assert_eq "docker exec"                block "$(blk 'docker exec mycontainer pytest' 'ctr2-alola-login-04')"
assert_eq "docker start"               block "$(blk 'docker start mycontainer' 'ctr2-alola-login-04')"
assert_eq "Austin login node (05..08 naming)" block "$(blk 'docker ps' 'smci250-ccs-aus-alola-login-05')"
assert_eq "compound: cd x && docker run"      block "$(blk 'cd /tmp && docker run --rm myimage' 'ctr2-alola-login-04')"
assert_eq "through bash -c"                    block "$(blk "bash -c 'docker run --rm myimage'" 'ctr2-alola-login-04')"
assert_eq "hostname case-insensitivity"        block "$(blk 'docker run --rm myimage' 'CTR2-ALOLA-LOGIN-04')"

echo "== ALLOW on a login node: docker delegated to a real compute node via ssh =="
assert_eq "ssh <node> 'docker run ...' (docker runs remotely, not here)" none \
  "$(blk "ssh ctr-cx66-mi300x-01 'docker run --rm myimage'" 'ctr2-alola-login-04')"
assert_eq "ssh <node> docker exec ... (unquoted remote command)" none \
  "$(blk 'ssh ctr-cx66-mi300x-01 docker exec mycontainer pytest' 'ctr2-alola-login-04')"

echo "== ALLOW on a login node: unrelated commands, mentions, missing input =="
assert_eq "unrelated command"                  none "$(blk 'ls -la' 'ctr2-alola-login-04')"
assert_eq "srun (a different guard's job)"     none "$(blk 'srun --pty bash' 'ctr2-alola-login-04')"
assert_eq "mere mention: grep -r docker ."     none "$(blk 'grep -r docker .' 'ctr2-alola-login-04')"
assert_eq "empty command"                      none "$(blk '' 'ctr2-alola-login-04')"

echo "== block payload is valid JSON and explains the fix =="
out=$(run 'docker run --rm myimage' 'ctr2-alola-login-04')
assert_eq "block payload parses as JSON"       ok  "$(valid_json "$out")"
assert_eq "reason mentions salloc"             yes "$(printf '%s' "$out" | jq -r .reason | grep -qi 'salloc' && echo yes || echo no)"
assert_eq "reason mentions ssh"                yes "$(printf '%s' "$out" | jq -r .reason | grep -qi 'ssh' && echo yes || echo no)"

rm -rf "$MOCKDIR"
echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
