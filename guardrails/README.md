# guardrails

Behavioral guardrails for coding agents: hooks that block or limit tool-usage patterns that
degrade session quality (wasteful waits, runaway crons, memory clobbering, oversized reads,
blocking inter-agent calls, blind filesystem scans). Each hook is a small script under
`hooks/scripts/`, wired in `hooks/hooks.json`; tests for covered hooks live under `hooks/tests/`.

## Bash command hooks (`PreToolUse` → `Bash`)

| Hook | What it does |
|------|--------------|
| **[no-sleep](hooks/scripts/no-sleep.sh)** | Blocks `sleep` used for waiting/polling — steers to `run_in_background` or a long-interval cron on Claude Code; on pi, to the `Agent` tool or `schedule_prompt` when available, else running the command directly. |
| **[no-timeout-ssh](hooks/scripts/no-timeout-ssh.sh)** | Blocks wrapping ssh-family connections in `timeout` (which kills the session, not just the command). |
| **[no-srun](hooks/scripts/no-srun.sh)** | Blocks the word `srun` anywhere in the command (a lexical match, not just as the invoked program — so e.g. `grep -R srun .` is blocked too) — steers to `salloc` once for the allocation, then plain `ssh <node> <command>` per call instead of serializing through one shared interactive shell. Also warns that anything running longer than a few minutes shouldn't go through a foreground `ssh` call either — the Bash tool's own per-call timeout cuts it off regardless of the SLURM time limit — and should be submitted with `sbatch` (returns immediately) plus `squeue`/`sacct`/`sstat`/`seff` polling instead. |
| **[herdr-prompt-guard](hooks/scripts/herdr-prompt-guard.sh)** | Blocks any direct `herdr agent prompt` call — `--wait` stalls the caller's own turn, and a plain send has no reply path — steering to the herdr-kit `message` skill instead (`--callback` when a reply is needed). |
| **[no-herdr-wait](hooks/scripts/no-herdr-wait.sh)** | Blocks direct `herdr pane wait-output` / `herdr agent wait` invocations — both block the caller's own turn until a match/state (indefinitely without `--timeout`), and `--timeout` has been observed not to reliably enforce that deadline either. Steers to `run_in_background` + polling with short `herdr pane read`/`herdr agent read` calls, or ScheduleWakeup/CronCreate for a longer interval. |
| **[no-blind-find](hooks/scripts/no-blind-find.sh)** | Blocks `find` whose search root is a whole tree — `/`, `~`, `$HOME`, or the literal home path. `find`'s grammar (`find [-H/-L/-P/-D/-O] PATH… EXPRESSION`) is unambiguous: the leading path operands *are* the roots, so this hook needs no arity guessing and never mis-blocks a legitimate `find`. A deeper path (`~/proj`, `/home/u/proj`, `src/`) is fine. |
| **[no-blind-search](hooks/scripts/no-blind-search.sh)** | Blocks a recursive content/name search (`grep -r/-R`, `rg`, `fd`) or recursive listing (`ls -R`) whose path is a whole tree. These tools mix a *pattern* operand with *path* operands and carry many value-taking options, so distinguishing them safely would need a per-flag arity table. It deliberately doesn't: it blocks only the **plainest** form (a pure recursion flag — or none, for the recursive-by-default `rg`/`fd` — plus a whole-tree root in a path slot) and **fails open the moment any other flag appears**. So it catches `grep -r foo /`, `rg foo /`, `fd foo /`, `ls -R /`, but MISSES (never mis-blocks) anything carrying extra flags: `grep -rn foo /`, `rg -i foo /`, `rg --files /`, `fd -e txt /`, `ls -Ra /`, … — an acceptable fail-open, since a naively over-broad search still trips the common forms and the agent isn't adversarially evading its own guardrail. |
| **[no-docker-on-login-node](hooks/scripts/no-docker-on-login-node.sh)** | On an Alola login node only (matched against the current machine's real `hostname`, `*-alola-login-*`) — blocks a direct `docker` invocation (run/build/exec/start/…, no subcommand carve-out), including a bare wrapper (`sudo docker ...`). The login node is a shared dispatch resource, not a place to run jobs; a job hung there blocks every other user. `ssh <node> 'docker ...'` is unaffected — the scanner resolves the command word as `ssh`, not `docker`. **Accepted miss**: a wrapper carrying any option (`sudo -E docker ...`, `env -i docker ...`, `nice -n 10 docker ...`) fails the whole segment open, same limitation the blind-scan hooks already document — not a special case introduced here. No-op on any other host, since this plugin is enabled globally across every session. |
| **[no-tail-follow](hooks/scripts/no-tail-follow.sh)** | Blocks `tail` in follow mode (`-f`, `-F`, `--follow` and its GNU abbreviations like `--fol`, including inside a short-option cluster like `-fn5`, and including a `--pid`-bounded follow) — a follow-mode tail does not exit by itself, so the command never completes (even when piped into `grep -m`/`head`, since `tail` keeps running until its next write). Lexical within a command segment, so it applies after any prefix: wrappers with options (`sudo -u x`, `env -u X`, `watch`), command carriers (`ssh host tail -f f`, `docker exec c tail -f f`, `kubectl exec p -- tail -f f`), and every multi-word argument (`bash -c` bodies, `ssh host "tail -F f"`, `sbatch --wrap "…"`) scanned to a nesting depth of 8. A segment that merely names the words (`echo 'tail -f x'`, `grep 'tail -F' d`) is blocked too. `tail --retry` alone is allowed (tail ignores it and exits). It does not fail open on a here-doc or a newline inside quotes (unlike the command-word hooks): a real follow beside them is caught, and heredoc data that names `tail -f` is blocked as well. Steers to the harness instead of watching or polling: `run_in_background` (completion notification) and a scheduled check (`ScheduleWakeup`/`CronCreate` on Claude Code; the `Agent` tool and `schedule_prompt` on pi). |
| **[no-long-foreground](hooks/scripts/no-long-foreground.sh)** | Blocks a Bash call that can block the turn for a long time with no declared timeout, or a timeout above a configurable cap — either lets the turn block for the harness default (minutes) or for however long the declared timeout is. Harness-aware (see "pi support" below): on Claude Code, a `run_in_background:true` call is always allowed (the caller is notified when it finishes instead of blocking — verified live that the Bash tool's `timeout` field, milliseconds, is accepted but silently NOT enforced on a background call, so capping background runtime is not this hook's job); a foreground call needs `timeout <= GUARDRAILS_MAX_FOREGROUND_TIMEOUT_MS` (default 30000 ms), else steers to `run_in_background:true` plus `CronCreate`/`ScheduleWakeup`. On pi, every call is foreground by construction (pi's Bash tool has no `run_in_background` field or background mode at all) and `timeout` is already in seconds; needs `timeout <= GUARDRAILS_MAX_FOREGROUND_TIMEOUT_SECONDS` (default 30 s), else steers to delegating the command to the `Agent` tool plus `schedule_prompt`. Shares its numeric cap/declared-value validation with both branches via [`lib/timeout-cap-lib.sh`](hooks/scripts/lib/timeout-cap-lib.sh). |
| **[bg-timeout-cap](hooks/scripts/bg-timeout-cap.sh)** | Blocks a `run_in_background:true` Bash call that isn't wrapped in the shell's own `timeout` utility with a bounded duration — the Bash tool's own `timeout` field is accepted but NOT enforced for background calls (verified live: a declared `timeout:3000`ms call still ran to completion ~15s later), so this is what makes a declared duration real at all. Scope is parity with foreground `timeout` enforcement, nothing more: recognizes `timeout DURATION command...` where `DURATION` is the very next token after `timeout` — no GNU timeout options (`-k`, `-s`, `--foreground`, etc.) are parsed or skipped at all; a command using one isn't recognized as a wrapper and is treated the same as no wrapper (a false block, safe direction — drop the option and use a plain `timeout N ...`). `DURATION` is a plain non-negative integer or decimal with an optional `s`/`m`/`h`/`d` suffix, or `inf`/`infinity` (case-insensitive); GNU's signed/scientific-notation forms aren't recognized, same safe-direction fallback. A duration of `0`, or `inf`/`infinity`, is rejected outright since GNU timeout treats both as "no limit". A `timeout` prefix only bounds the EXEC of the command itself, not other shell work the shell does before exec starts — a second top-level command (`;`/`&`/`|`), a backtick substitution evaluated before `timeout` even runs, or a redirection whose target the shell opens before exec (verified live: `timeout 0.05 cat </tmp/fifo` did NOT time out against an unread FIFO) — so a command containing `;`, `&`, `|`, `(`, `)`, `` ` ``, `<`, `>`, or a real newline is blocked outright. Owner-scoped decision: deliberately conservative over clever, a plain LITERAL character scan with NO quote-awareness at all, so a quoted occurrence (`echo "a;b"`, a `bash -c '...; ...'` body) false-blocks exactly the same as a real one. Complex work (sequencing, substitutions, redirections) belongs in a script invoked as one simple command instead (`timeout 300 bash script.sh`). Default cap `GUARDRAILS_MAX_BG_TIMEOUT_SECONDS=600` (10 min). The agent chooses its own duration (no auto-wrapping) and is told to split long work into separate backgrounded checkpoints instead of raising the cap. **No-op on pi** — pi's Bash tool has no `run_in_background` field at all, so this hook never sees a `true` value there; pi's own unbounded-blocking risk is handled by `no-long-foreground`'s pi branch instead. |

The blind-scan hooks, `herdr-prompt-guard`, [no-herdr-wait](hooks/scripts/no-herdr-wait.sh), [no-docker-on-login-node](hooks/scripts/no-docker-on-login-node.sh), and (for segmentation and tokenization only — it matches lexically, not by command word, and does not inherit the here-doc / quoted-newline fail-open) [no-tail-follow](hooks/scripts/no-tail-follow.sh) share [`scan-guard-lib.sh`](hooks/scripts/scan-guard-lib.sh) (quote-aware segmentation/tokenization, command-word anchoring, `bash -c` recursion via `scan_command`; the blind-scan hooks additionally use its whole-tree root detection with quote provenance). To stay on the never-mis-block side, `scan_command` **fails open** for every consumer (misses a real scan/invocation rather than risk blocking a legitimate command) on: a wrapper carrying any option (`sudo -u root find /`, `env -u X find /`, `command -v find /` — the option might consume the next word as its value); an unquoted here-doc/here-string (`cat <<EOF … find / … EOF` — the body is data, not a command); a physical newline inside quotes or a backslash-continued line (`find /` buried in quoted multiline data is not a command); `eval`; and aliases — none of these are specific to any one consumer, since the shared segment/word framing can't see through them regardless of what the matcher is looking for.

Root classification (resolving whether an operand is a whole-tree path) is specific to the two blind-scan hooks, not part of the shared `scan_command`, and each hook calls its own extra prechecks before scanning: a `HOME` reassignment in an earlier segment (`HOME=/tmp/x; rg y "$HOME"` — the runtime home is no longer the real one, via `_mutates_home`); a cwd change that makes a narrow scan whole-tree (`cd / && find .` — the parser carries no cwd state); and command substitution / variable expansion / process substitution on a role-bearing operand (`rg "$opt" /`, `find "$pred" /`, via `has_unresolved_expansion` — the runtime value, and therefore the role, is unknowable). None of these have any bearing on a command-identity matcher like `herdr-prompt-guard`, `no-herdr-wait.sh`, or `no-docker-on-login-node.sh`, which classify literal command words, not paths — a `HOME` reassignment, cwd change, or unresolved expansion elsewhere in the command does not exempt any of them. Quoted or escaped options/predicates (`rg "-i" /`, `bash "-n" -c …`, a pre-`-c` `--`, `find "-newer" /`) are dequoted and classified correctly by every consumer.

## Other tool hooks

| Hook | Trigger | What it does |
|------|---------|--------------|
| **[no-memory-access](hooks/scripts/no-memory-access.sh)** | `PreToolUse` → `Read`/`Write`/`Edit` | Blocks all access — read and write — to Claude Code's built-in memory directory. Project memory goes stale as a project's state and decisions change, and since it's injected into context rather than deliberately read, a stale entry skews the agent's judgment without any visible signal that it happened. |
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

## pi support

The Bash command guardrails above (`no-sleep`, `no-timeout-ssh`, `no-srun`, `herdr-prompt-guard`,
`no-herdr-wait`, `no-blind-find`, `no-blind-search`, `no-docker-on-login-node`, `no-tail-follow`,
`no-long-foreground`) also apply to pi
agents via
[`pi-extensions/bash-guardrails.ts`](pi-extensions/bash-guardrails.ts), a pi extension that
hooks pi's `tool_call` event (pi's equivalent of Claude Code's `PreToolUse`) and shells out to
the exact same scripts under `hooks/scripts/`. It reads the Bash-matched script list straight
out of `hooks/hooks.json` at load time, so a new Claude-side Bash guard applies to pi
automatically with no separate list to maintain.

Each script is invoked with pi's actual tool input (not just `{command}`), plus a `"harness":"pi"`
marker — a genuine Claude Code `PreToolUse` call never carries that marker, so a script can't
confuse the two. Most scripts ignore both and only read `.tool_input.command`, so they behave
identically on both harnesses. A script whose policy genuinely differs per harness — today only
`no-long-foreground`, since pi's Bash tool has no `run_in_background` field and its `timeout` is
seconds, not milliseconds — reads the marker and branches.

Activate it once per machine:

```sh
bash pi-extensions/install.sh
```

This symlinks the extensions into pi's auto-loaded global extensions directory
(`~/.pi/agent/extensions/` by default, or `$PI_CODING_AGENT_DIR/extensions` if set) and takes
effect on the next pi session. Apart from the Bash-tool guardrails and the schedule guard
below, the `Read`/`Write`/`Edit`/`Agent` guards are Claude-Code-specific and have no pi
equivalent yet.

### Scheduled prompts

[`pi-extensions/schedule-prompt-guard.ts`](pi-extensions/schedule-prompt-guard.ts) gives the
`schedule_prompt` tool (the `pi-schedule-prompt` package) the same limits
[cron-guard](hooks/scripts/cron-guard.sh) enforces on `CronCreate`, with the same environment
variables: a minimum interval between runs (`GUARDRAILS_MIN_CRON_MINUTES`, default 5) and a
maximum number of concurrent enabled recurring jobs in the session (`GUARDRAILS_MAX_CRONS`,
default 1). A recurring job (`type` `cron` or `interval`) plays the role of `CronCreate`; a
one-shot job (`type` `once`) plays the role of `ScheduleWakeup` — always allowed and never
counted, where cron-guard bans a one-shot `CronCreate` because that alternative exists.

It checks `add` (interval and count), `update` with a new schedule (interval) and `enable` of a
recurring job (its stored schedule's interval, and count), so neither limit can be bypassed by editing or re-enabling a job. Sibling calls that pi runs in parallel are counted too, until their result arrives, so two adds in one step cannot both slip under the cap. Jobs
are read from `<cwd>/.pi/schedule-prompts.json` on every call; a missing or unreadable store, or
a schedule it cannot parse, fails open. For a cron schedule only the seconds and minutes fields
are read to find the tightest gap between runs.

`herdr-prompt-guard` now blocks every direct `herdr agent prompt` invocation unconditionally
(not just `--wait`), so pi and Claude Code behave identically here — no gap to document.

## Tests

Hooks with tests have a `hooks/tests/test-*.sh` that feeds synthetic `tool_input` JSON and
asserts the block/allow decision (currently: the read guard, the Herdr prompt guard, the Herdr
wait guard, the two blind-scan hooks, the srun guard, the memory-access guard, and the
docker-on-login-node guard). Run one, or all available:

```sh
for t in hooks/tests/test-*.sh; do bash "$t"; done
```

The pi extensions have their own tests under `pi-extensions/tests/` (Node 22+):

```sh
for t in pi-extensions/tests/test-*.mjs; do node --experimental-strip-types "$t"; done
```
