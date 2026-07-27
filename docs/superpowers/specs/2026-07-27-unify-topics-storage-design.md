# Unify recall storage into a single topics/ layer + settings.yaml

**Date:** 2026-07-27
**Status:** Proposed

## Problem

The agent frequently fails to notice that relevant knowledge already exists in recall,
and re-asks the user things already saved as topics. Root-causing this surfaced two
compounding issues:

1. **session-start.sh only prints index file *paths* as a "go read this" checklist,
   not the index *content*.** Low-density instructions like this are exactly what gets
   compacted away first in a long conversation, and the agent frequently skips the
   Read step. The agent then genuinely doesn't know a topic exists.
2. **Knowledge is split across four constructs per level** (project / branch / task):
   `knowledge/`, `workflows/`, `directives.md`, `user.md`. In practice almost nobody
   uses this split as designed — across the whole store, 409 of 427 topic files are
   under `knowledge/` and only 18 under `workflows/`. `directives.md` and `user.md`
   end up as dumping grounds for free-form prose rules that are really knowledge
   topics in disguise (e.g. `rocisa-attn/directives.md` has grown to 74 lines of
   hard-rule prose alongside its YAML config; `rocisa-attn/user.md` has a whole
   "Working preferences" prose section). This split multiplies the number of indexes
   the agent would need to separately notice and read, and made issue (1) worse.

This design fixes both by inlining index content at session start (instead of paths)
and by collapsing the four per-level constructs down to one uniform `topics/`
directory plus one reserved machine-config file.

## Explicitly out of scope

Deferred to a future design/session — not addressed here:
- Topic naming/prefix conventions, duplicate detection at save time
- Contradiction checking when updating an existing topic
- `UserPromptSubmit` per-turn keyword matching against topics
- A `tags`/keyword frontmatter field for improved matching
- Auto-triggered `/recall-reorg`

## New storage model

Per level (project / branch / task), the layout becomes:

```
<level>/
  topics/
    index.md            # single index; thematic ## headers grouped by content,
                         # decided per-project — no type-based grouping or badges
    <topic-name>.md      # every topic: facts, workflows, conventions, env info —
                         # all one uniform shape (frontmatter: name, description,
                         # metadata.type), no folder split by type
  settings.yaml          # the ONLY reserved/special file — pure machine-parsed
                         # behavioral config, no prose
  meta.md                # (branch/task only) — unchanged, machine-managed lifecycle
                         # state via write_meta_field/read_meta_field
```

Removed: `knowledge/`, `workflows/`, `directives.md`, `user.md`.

### topics/ (replaces knowledge/ + workflows/)

- No subtype distinction: no separate directory for workflows, no required filename
  prefix, no inline type badge in the index. A workflow topic (e.g. what used to be
  `workflows/npibox-lifecycle.md`) lives in `topics/` exactly like a hardware-fact
  topic — grouped in the index only by whatever thematic `## ` header fits the
  project's actual content, same as today's indexes already do organically (e.g.
  snippet's index groups by "Working-agreement feedback", "Debugging discipline",
  "Agent-team discipline" — themes, not types).
- `metadata.type` in frontmatter (feedback / project / reference / workflow / ...)
  still exists per-topic for any future script that wants to filter by type, but the
  index and directory structure do not organize around it.

### settings.yaml (replaces directives.md's YAML block + user.md's key=values)

The only reserved, script-parsed file per level. Contains purely machine-read
behavioral knobs — no free-form prose:

```yaml
auto-save:
  auto: [hardware findings, build errors, debugging root causes, API behaviors]
  ask: [coding conventions, architecture decisions]
  never: [temporary workarounds, debugging session logs]
  default: auto
promotion: auto
stale-branch-days: 30
default-branch: develop
confidence-min: observed
maintenance:
  status-max-lines: 150
  status-final-lines: 100
  topic-max-lines: 200
  task-knowledge-split-lines: 150
# migrated from user.md:
WORKSPACE: /home/user/workspace/repo/project
CONTAINER: some-container-name
```

Read on-demand by whichever skill needs a value at the moment it runs:
`recall-add` reads `confidence-min` when saving, `recall-reorg` reads
`maintenance.topic-max-lines` when reorganizing, `/promote` reads
`stale-branch-days` when checking for merged branches. **Not** injected by
session-start — none of this is something the agent's general reasoning needs
continuously in context; it's only relevant at the moment a specific skill runs.

### user.md — retired

- Key=value lines (`WORKSPACE=`, `CONTAINER=`, `FFM_CONTAINER=`, etc.) move into
  `settings.yaml` as regular keys.
- Free-form prose sections (e.g. rocisa-attn's "Working preferences" — autonomy
  envelope, decision-making rules) move into `topics/` as ordinary topics, since
  they are knowledge content, not machine config.

### directives.md — retired

- The YAML config block moves into `settings.yaml` verbatim (same keys, same
  values), just relocated and renamed.
- Any free-form prose bullets that had accumulated below the YAML block (as in
  rocisa-attn) move into `topics/` as ordinary topics.

### meta.md — unchanged

Same reserved-file treatment as `settings.yaml`: machine-managed branch/task
lifecycle state (Parent, Created, Status, Mode, Active Task), read/written via
`lib.sh`'s `read_meta_field`/`write_meta_field`. Not part of this redesign.

## session-start.sh behavior

Per level (project, then branch if applicable, then active task if applicable):

1. Emit `topics/index.md` content **inlined in full** — the actual index content,
   not a file path in a "go read this" checklist. This is the direct fix for the
   root problem: the agent sees real topic names and one-line hooks in context at
   session start, not an instruction it has to act on and can skip.
2. Emit `meta.md` compactly for branches, as today (`compact_meta` unchanged).
3. **Do not** emit `settings.yaml` or anything derived from it. Behavioral config
   is skill-read-on-demand, not session-start context.
4. Remove the old "Session Start checklist" section entirely (the
   `PROJECT_READS`/`BRANCH_READS`/`TASK_READS` accumulation and the final numbered
   "read these files" printout) — it becomes redundant once index content is
   inlined directly, and keeping it risks the agent re-reading what's already in
   context.

No line-count truncation on the inlined index content — these are already-compact
one-liner indexes (largest observed today: rocm-libraries' combined knowledge +
workflows index, ~150 lines total), not full topic files, so inlining in full is
cheap even for the store's largest projects.

## Migration

A one-time script, run once per existing project directory (and its branches/
tasks/archive subdirectories), handling the mechanical parts only:

1. Move `workflows/*.md` into `knowledge/`, then rename `knowledge/` → `topics/`.
   Merge `workflows/index.md`'s entries into `knowledge/index.md`'s content,
   producing a single `topics/index.md`.
2. Extract `directives.md`'s YAML block into a new `settings.yaml` (same keys).
3. Convert `user.md`'s key=value lines into additional keys in `settings.yaml`.
4. Any leftover free-form prose from `directives.md` (bullets below the YAML
   block) or `user.md` (prose sections) is dumped into a single flagged staging
   file, `topics/_migration-needs-review.md`, with a header note explaining it
   needs to be split into properly named, single-purpose topics.
   **The script does not attempt to auto-split this prose** — deciding topic
   names/scope/boundaries for prose content is a judgment call, and this exact
   kind of ad-hoc-naming problem is what's explicitly deferred to a future
   session. The staging file is a visible TODO, not a silent auto-generated mess.
5. `meta.md` is left untouched.
6. Old files (`workflows/`, `directives.md`, `user.md`) are removed once their
   content has been migrated into the new layout (no dual-layout support is kept
   going forward — see Alternatives Considered).

The migration script is run once, by hand, against the real store
(`~/.local/share/claude/recall/`) after the plugin changes land — it is not part
of ongoing plugin operation.

## Blast radius

Every file in the plugin that hardcodes the old layout (`knowledge/`, `workflows/`,
`directives.md`, `user.md`) needs updating to the new layout (`topics/`,
`settings.yaml`):

- `hooks/scripts/session-start.sh` — injection logic (primary change, see above)
- `scripts/lib.sh` — any path-construction helpers
- `scripts/create-branch-dir.sh` — creates the initial branch-level structure
- `scripts/reorg-inventory.sh` — scans `knowledge-dir` arg; called against `topics/`
  now instead of separately against `knowledge/` and `workflows/`
- `skills/recall-init/SKILL.md` — creates the initial project-level structure
- `skills/recall-add/SKILL.md` — determines target file/directory when saving
- `skills/recall-search/SKILL.md` — search path list
- `skills/recall-status/SKILL.md` — topic/workflow counts reported
- `skills/recall-reorg/SKILL.md` — target directories for reorg scope arguments
- `skills/promote/SKILL.md` — reads branch overlay `knowledge/` and `workflows/`
- `skills/branch-abandon/SKILL.md`, `skills/task-abandon/SKILL.md`,
  `skills/task-complete/SKILL.md`, `skills/task-switch/SKILL.md` — any references
  to the old directory names or `directives.md`/`user.md`
- `README.md` (recall's and possibly the repo root's) — storage layout diagram,
  configuration examples

## Alternatives considered

**Keep both old and new layouts supported indefinitely, no migration script.**
Rejected: would require `session-start.sh` (and every other script above) to
detect and branch on which layout a given project uses, permanently doubling
path-handling logic. Existing stores would also never actually get the benefit of
the unification (single index, no more workflows/directives/user split) unless
someone manually converts them later anyway. A one-time migration script is less
total complexity than permanent dual-layout support.

**Give topics a required type-based grouping or prefix (e.g. `workflow-*.md`).**
Rejected per explicit instruction: no topic is to be treated specially or grouped
by type. Grouping is purely thematic and decided per-project, matching how the
existing indexes already organize content.

**Keep settings.yaml's values in session-start's injected output (as today's
directives.md is).** Rejected: most of the config (`confidence-min`,
`maintenance.*`, `stale-branch-days`, `promotion`, `default-branch`) is only
relevant to a specific skill at the moment it runs, not to the agent's continuous
reasoning. Only `auto-save.auto/ask/never` arguably needs continuous visibility,
but keeping settings.yaml fully out of injection was chosen for simplicity — a
skill reading its own on-demand config is a one-line file read, not a burden.
