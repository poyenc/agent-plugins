# guardrails

Behavioral guardrails for coding agents: hooks that block or limit tool-usage patterns that
degrade session quality (wasteful waits, runaway crons, memory clobbering, oversized reads,
blocking inter-agent calls, blind filesystem scans). Each hook is a small script under
`hooks/scripts/`, wired in `hooks/hooks.json`; tests for covered hooks live under `hooks/tests/`.

## Bash command hooks (`PreToolUse` → `Bash`)

| Hook | What it does |
|------|--------------|
| **[no-sleep](hooks/scripts/no-sleep.sh)** | Blocks `sleep` used for waiting/polling — steers to `run_in_background` or a long-interval cron instead. |
| **[no-timeout-ssh](hooks/scripts/no-timeout-ssh.sh)** | Blocks wrapping ssh-family connections in `timeout` (which kills the session, not just the command). |
| **[no-srun](hooks/scripts/no-srun.sh)** | Blocks the word `srun` anywhere in the command (a lexical match, not just as the invoked program — so e.g. `grep -R srun .` is blocked too) — steers to `salloc` once for the allocation, then plain `ssh <node> <command>` per call instead of serializing through one shared interactive shell. |
| **[herdr-prompt-guard](hooks/scripts/herdr-prompt-guard.sh)** | Governs `herdr agent prompt`: blocks the blocking `--wait` form, hints `--callback` on plain fire-and-forget sends. |
| **[no-herdr-wait](hooks/scripts/no-herdr-wait.sh)** | Blocks direct `herdr pane wait-output` / `herdr agent wait` invocations — both block the caller's own turn until a match/state (indefinitely without `--timeout`), and `--timeout` has been observed not to reliably enforce that deadline either. Steers to `run_in_background` + polling with short `herdr pane read`/`herdr agent read` calls, or ScheduleWakeup/CronCreate for a longer interval. |
| **[no-blind-find](hooks/scripts/no-blind-find.sh)** | Blocks `find` whose search root is a whole tree — `/`, `~`, `$HOME`, or the literal home path. `find`'s grammar (`find [-H/-L/-P/-D/-O] PATH… EXPRESSION`) is unambiguous: the leading path operands *are* the roots, so this hook needs no arity guessing and never mis-blocks a legitimate `find`. A deeper path (`~/proj`, `/home/u/proj`, `src/`) is fine. |
| **[no-blind-search](hooks/scripts/no-blind-search.sh)** | Blocks a recursive content/name search (`grep -r/-R`, `rg`, `fd`) or recursive listing (`ls -R`) whose path is a whole tree. These tools mix a *pattern* operand with *path* operands and carry many value-taking options, so distinguishing them safely would need a per-flag arity table. It deliberately doesn't: it blocks only the **plainest** form (a pure recursion flag — or none, for the recursive-by-default `rg`/`fd` — plus a whole-tree root in a path slot) and **fails open the moment any other flag appears**. So it catches `grep -r foo /`, `rg foo /`, `fd foo /`, `ls -R /`, but MISSES (never mis-blocks) anything carrying extra flags: `grep -rn foo /`, `rg -i foo /`, `rg --files /`, `fd -e txt /`, `ls -Ra /`, … — an acceptable fail-open, since a naively over-broad search still trips the common forms and the agent isn't adversarially evading its own guardrail. |

The blind-scan hooks and [no-herdr-wait](hooks/scripts/no-herdr-wait.sh) share [`scan-guard-lib.sh`](hooks/scripts/scan-guard-lib.sh) (quote-aware segmentation/tokenization, command-word anchoring, `bash -c` recursion via `scan_command`; the blind-scan hooks additionally use its whole-tree root detection with quote provenance). To stay on the never-mis-block side, `scan_command` **fails open** for every consumer (misses a real scan/invocation rather than risk blocking a legitimate command) on: a wrapper carrying any option (`sudo -u root find /`, `env -u X find /`, `command -v find /` — the option might consume the next word as its value); an unquoted here-doc/here-string (`cat <<EOF … find / … EOF` — the body is data, not a command); a physical newline inside quotes or a backslash-continued line (`find /` buried in quoted multiline data is not a command); `eval`; and aliases — none of these are specific to any one consumer, since the shared segment/word framing can't see through them regardless of what the matcher is looking for.

Root classification (resolving whether an operand is a whole-tree path) is specific to the two blind-scan hooks, not part of the shared `scan_command`, and each hook calls its own extra prechecks before scanning: a `HOME` reassignment in an earlier segment (`HOME=/tmp/x; rg y "$HOME"` — the runtime home is no longer the real one, via `_mutates_home`); a cwd change that makes a narrow scan whole-tree (`cd / && find .` — the parser carries no cwd state); and command substitution / variable expansion / process substitution on a role-bearing operand (`rg "$opt" /`, `find "$pred" /`, via `has_unresolved_expansion` — the runtime value, and therefore the role, is unknowable). None of these have any bearing on a command-identity matcher like `no-herdr-wait.sh`, which classifies literal command words, not paths — a `HOME` reassignment, cwd change, or unresolved expansion elsewhere in the command does not exempt it. Quoted or escaped options/predicates (`rg "-i" /`, `bash "-n" -c …`, a pre-`-c` `--`, `find "-newer" /`) are dequoted and classified correctly by every consumer.

## Other tool hooks

| Hook | Trigger | What it does |
|------|---------|--------------|
| **[no-memory-write](hooks/scripts/no-memory-write.sh)** | `PreToolUse` → `Write`/`Edit` | Blocks writes to Claude Code's built-in memory directory. |
| **[read-guard](hooks/scripts/read-guard.sh)** | `PreToolUse` → `Read` | Blocks a single `Read` from returning more than a configurable byte budget. |
| **[no-named-agent](hooks/scripts/no-named-agent.sh)** | `PreToolUse` → `Agent` | Blocks naming a spawned agent (named, SendMessage-addressable agents change coordination semantics). |
| **[cron-guard](hooks/scripts/cron-guard.sh)** | `PreToolUse` → `CronCreate` | Blocks creating a cron when the agent exceeds the max concurrent count or uses a too-short interval. |

## Cron accounting

The cron guard needs a live count of active crons per session; these keep it:

| Hook | Trigger | What it does |
|------|---------|--------------|
| **[cron-track-create](hooks/scripts/cron-track-create.sh)** | `PostToolUse` → `CronCreate` | Increments the session's active-cron counter. |
| **[cron-track-delete](hooks/scripts/cron-track-delete.sh)** | `PostToolUse` → `CronDelete` | Decrements it. |
| **[cron-session-end](hooks/scripts/cron-session-end.sh)** | `SessionEnd` | Cleans up the counter file for the session. |

## Tests

Hooks with tests have a `hooks/tests/test-*.sh` that feeds synthetic `tool_input` JSON and
asserts the block/allow decision (currently: the read guard, the Herdr prompt guard, the Herdr
wait guard, the two blind-scan hooks, and the srun guard). Run one, or all available:

```sh
for t in hooks/tests/test-*.sh; do bash "$t"; done
```
