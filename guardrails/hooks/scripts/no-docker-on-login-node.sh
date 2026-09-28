#!/usr/bin/env bash
# PreToolUse(Bash): on an Alola login node ONLY, block any direct `docker` invocation (through
# wrappers and `bash -c` bodies) -- run/build/exec/start/create, all of it. The login node is a
# shared dispatch resource, not a place to run jobs: a job hung there blocks every other user, not
# just this one. A narrower carve-out (a container without --device passthrough, since it carries
# its own correct toolchain) was tried and reversed the same day -- no container execution on the
# login node at all, allocate a compute node first. `ssh <node> 'docker ...'` is NOT matched here:
# `scan_command` resolves the real command word as `ssh`, and ssh isn't in its bash-c-style
# recursion list, so `docker` text nested only inside ssh's remote-command argument is never
# inspected -- this falls out of the existing scanner for free, no special-casing needed. Gated on
# the CURRENT machine's real hostname (Alola's `*-alola-login-*` naming convention), since this
# plugin is enabled globally across every session/host, not just Alola work.
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/scan-guard-lib.sh"

hn=$(hostname 2>/dev/null) || exit 0
case "${hn,,}" in
  *-alola-login-*) ;;
  *) exit 0 ;;
esac

cmd=$(jq -r '.tool_input.command // ""')
[ -n "$cmd" ] || exit 0

# Is this segment's real command literally `docker`? No subcommand distinction -- run, build,
# exec, start, create are all banned alike; the reversed exception already ruled out any
# narrower carve-out.
docker_seg() {
  local cmdbase="$1"
  [ "$cmdbase" = docker ]
}

scan_command "$cmd" docker_seg || exit 0

printf '{"decision":"block","reason":"docker is banned on the login node (this is one) -- it is a shared dispatch resource, not a place to run jobs; a job hung here blocks every other user, not just you. Use `salloc` once to get a compute node, then reuse it with plain `ssh <node> <command>` for every subsequent command (including docker). No container execution on the login node at all, allocate first."}'
