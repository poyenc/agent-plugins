#!/usr/bin/env bash
# PreToolUse(Bash): on an Alola login node ONLY, block a direct `docker` invocation -- run, build,
# exec, start, create, all of it, no subcommand carve-out. A container still runs as a local
# process on the shared login node, consuming its resources and able to hang it, regardless of
# whether the container's own toolchain is correct -- container isolation fixes toolchain
# correctness, not the shared-resource/hang risk, so it is not a safe narrower exception. The
# login node's job is dispatching work to compute nodes, not running it.
#
# `ssh <node> 'docker ...'` is NOT matched here: `scan_command` resolves the real command word as
# `ssh`, and ssh isn't in its bash-c-style recursion list, so `docker` text nested only inside
# ssh's remote-command argument is never inspected -- this falls out of the existing scanner for
# free, no special-casing needed. A wrapper WITHOUT options (bare `sudo docker ...`) is also
# caught, through the same scanner. A wrapper WITH options (`sudo -E docker ...`, `env -i docker
# ...`, `nice -n 10 docker ...`) is NOT caught: scan-guard-lib.sh's shared wrapper handling
# deliberately fails the whole segment open whenever a wrapper carries any option, since it does
# not model which options take a value (same accepted limitation the blind-scan hooks already
# document for e.g. `sudo -u root find /`). Not a special case introduced here.
#
# Gated on the CURRENT machine's real hostname (Alola's `*-alola-login-*` naming convention),
# since this plugin is enabled globally across every session/host, not just Alola work.
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
# exec, start, create are all banned alike.
docker_seg() {
  local cmdbase="$1"
  [ "$cmdbase" = docker ]
}

scan_command "$cmd" docker_seg || exit 0

printf '{"decision":"block","reason":"docker is banned on the login node (this is one) -- it is a shared dispatch resource, not a place to run jobs; a job hung here blocks every other user, not just you. Use `salloc` once to get a compute node, then reuse it with plain `ssh <node> <command>` for every subsequent command (including docker). No container execution on the login node at all, allocate first."}'
