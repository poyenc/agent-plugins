---
name: recall-reorg
description: Re-organize recall knowledge/workflow topics into their best shape — unify topic filenames, frontmatter, and titles, merge overlapping topics, compact stale content, extract shared general principles into their own topics, and rewrite the index coherently. Use whenever the user says "re-org the recall topics", "clean up recall", "make the recall coherent", "extract a general topic", "tidy the knowledge index", or when recall files have drifted (mismatched names, duplicated content, oversized files, a stale index). Keeps recall well-managed as a whole rather than fixing one file at a time.
---

# /recall-reorg [--project|--branch|--all]

Re-organize recall topics so the whole store stays coherent and well-managed: one
naming scheme, single-purpose topics, no duplication or stale bulk, and an index
that faithfully mirrors the files.

This is a *whole-store* operation. Fixing one file at a time can't spot duplicated
principles or index drift — those are only visible when every topic is read
together. So the skill always analyzes the full scope before proposing changes.

## Arguments
- (default): the current branch's overlay only (`branches/<slug>/knowledge/` +
  `workflows/`). Smallest, safest scope — the files you're actively growing.
- `--project`: project level only (`knowledge/` + `workflows/`); leave branch
  overlays untouched.
- `--project-and-branch`: project level **and** the current branch's overlay together.
- `--all`: every project under the recall root. Broad and slow — confirm first.

## The target shape (invariants this skill enforces)

These are what "best shape" means — check the store against them, and every change
should move toward them:

1. **One identity per topic.** The filename slug, the frontmatter `name`, and the
   H1 title stem all agree (kebab-case). A reader who sees any one can guess the
   others. Semantic prefixes already in use stay consistent (`feedback-`,
   `crossfeed-`, `team-`, …) — a prefix groups related topics, so don't invent a
   new prefix when an existing one fits.
2. **Valid frontmatter.** Every topic has `name`, a specific one-line `description`
   (this is what future sessions match on — vague descriptions defeat recall), and
   `metadata.type` (feedback / project / reference / …, following what the store
   already uses).
3. **Single purpose.** Each topic covers one idea. If two topics say the same
   thing, merge them; if one topic bundles several unrelated ideas, that's a split
   candidate — but see the size policy below before splitting.
4. **Faithful index.** `index.md` lists every topic exactly once, grouped under
   `## ` headers, each entry `[name](file.md) — one-line hook`. No entry points at
   a missing file; no file is missing from the index. Group headers reflect how the
   topics actually cluster, not historical accident.
5. **Within size limits.** No topic exceeds `topic-max-lines` (from `directives.md`,
   default 200) — but reach that by compaction first, not reflexive splitting.

## Size policy: compact before you split

When a topic is over the limit, **do not split it first.** Splitting fragments one
idea across files and grows the index. Recover size in this order, stopping as soon
as you're under the limit:

1. **Delete disproven content — UNLESS it's a deliberately-kept lead record.**
   Sections that record a hypothesis later shown false ("suspected X — turned out to
   be Y"), a "false claim but fixed" note, or a workaround that's since been removed
   are normally deleted outright: recall stores what is *true now*, and git history
   holds the story of how you got there (the `feedback-delete-stale-not-append-fix`
   principle — remove the wrong content in place, don't staple a correction on).

   **But watch for the deliberately-kept exception.** A falsified hypothesis is often
   retained *on purpose* so it isn't re-investigated — look for signals like "kept as
   a falsified-lead record", "do NOT re-pursue", "so it is not re-hunted", or a whole
   topic whose stated job is to hold the dead leads for one bug. That content is
   *true and load-bearing* ("this path is a dead end") even though it reads as stale.
   Do NOT delete it. When a topic is superseded-but-kept, the right move is usually to
   **archive** it (defer to `/promote`'s archive step or flag it), not to gut it.
   When unsure whether stale-looking content is dead weight or a kept lead, surface
   it in the plan as a question rather than deleting — the whole point is to not
   destroy a record someone deliberately preserved.
2. **Loss-lessly compact.** Tighten prose, drop redundant restatements, collapse
   long transcripts/logs to the one line that carries the finding, remove filler —
   without dropping any load-bearing fact.
3. **Split only if still over.** If a topic is genuinely multiple distinct ideas
   that all remain true and can't be compacted further, split the `###`
   subsections into sibling topics and update the index. Splitting is the last
   resort, not the reflex.

## Extraction: factor shared principles into their own topic

When several topics repeat the same general principle inside their specifics, pull
that principle into its own single-purpose topic and have the specific topics
cross-link it with `[[name]]`. This keeps each topic focused and gives the shared
idea one authoritative home.

Extraction is *within a level* (de-duplicating sibling topics). Moving
branch-general knowledge *up* to project level is a different operation — that's
`/promote`. When you spot branch-overlay topics that are actually project-general,
don't move them here: flag them as promote-candidates and tell the user to run
`/promote`.

## Steps

1. **Resolve scope.** Resolve storage root and project dir (see
   `${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh`). Determine the target directories from
   the argument; the default is the current branch's overlay
   (`branches/<sanitized-branch>/knowledge/` + `workflows/`). If the default scope
   is requested but you're on a default branch (main/master/develop) with no branch
   overlay, say so and suggest `--project`. Read `directives.md` for
   `topic-max-lines` and `confidence-min`.

2. **Snapshot first.** This edits many files at once, so make it reversible: tar the
   target recall dir to `<recall-root>/_backup_reorg_<YYYYMMDD_HHMMSS>.tar.gz`
   before any write. Report the path.

3. **Analyze — script the mechanics first, then delegate only the judgment.**
   A real overlay can be 50+ topics plus a 20 KB+ index. Do NOT hand a subagent
   "read every file and report" — that overflows its context and it dies mid-pass.
   Instead, split the work:

   **3a. Scripted inventory (cheap, deterministic, no LLM judgment).** Run
   `${CLAUDE_PLUGIN_ROOT}/scripts/reorg-inventory.sh <knowledge-dir> <topic-max-lines>`
   for each target dir (the `knowledge/` and `workflows/` of every scope in play). It
   parses every topic and reports the mechanical facts: per file — filename vs
   frontmatter `name`, H1 presence, `metadata.type`, line count, frontmatter
   validity, and index membership; then index drift both ways (dead links, files
   missing from the index); then two greps — a staleness/dead-end marker list and a
   separate "deliberately-kept signals" list (`kept as`, `do not re-pursue`, `not
   re-hunted`, `retained for`, …). The second list is the guardrail for size policy
   §1: those files are dead-lead records to preserve, not delete. This resolves
   identity/frontmatter/index/size mechanically and spotlights the handful of files
   that need real reading.

   **3b. Delegate the judgment (per `feedback-delegate-recall-cleanup`).** Hand a
   subagent ONLY the script output plus the *specific* flagged files to read closely
   — overlap/merge assessment, whether stale-looking content is dead weight vs. a
   deliberately-kept lead record, extraction opportunities, size-recovery routing.
   Give it a bounded file list, not "the whole directory". If the scope is small
   (say < ~15 topics) doing 3b inline is fine.

   The change-set the analysis returns flags:
   - identity mismatches (filename ≠ name ≠ title) and missing/vague frontmatter
   - duplicate or overlapping topics (merge candidates)
   - repeated general principles across topics (extraction candidates)
   - oversized topics, tagged with the recovery route (delete-stale / compact /
     split) per the size policy
   - stale content: disproven hypotheses, "false claim but fixed" notes, removed
     workarounds (deletion candidates) — but separated from deliberately-kept
     falsified-lead records, which are NOT deletion candidates (see size policy §1)
   - index drift: entries with no file, files with no entry, mis-grouped entries,
     entries whose hook no longer matches the topic
   - branch-overlay topics that look project-general (promote-candidates → defer to
     `/promote`, don't move here). Flag these whenever branch overlay is in scope —
     you can recognize project-general content without project level loaded; if
     unsure of overlap, note it as a candidate rather than skipping it.

4. **Plan, gated per category.** Present the plan grouped into these categories and
   get a separate confirmation for each before applying it — so a "yes" to renames
   never silently also merges or deletes:
   1. Identity fixes (renames / retitles / frontmatter)
   2. Merges (and the extractions that factor shared principles into new topics)
   3. Compaction & stale-deletion (what gets deleted vs. losslessly tightened)
   4. Splits (only the ones that survived the size policy)
   5. Index rewrite (final grouping + hooks)
   6. Promote-candidates (informational — handed to `/promote`, not applied here)

   Follow the store's own recall-write discipline: only keep `[VERIFIED]`/
   `[OBSERVED]` facts; if compaction would drop a fact below `confidence-min`,
   surface it rather than silently deleting.

5. **Execute confirmed categories.** Apply each category the user approved, in the
   order above (identity → merge/extract → compact/delete → split → index).
   `git mv` renames when the store is under git so history is preserved; otherwise
   plain move. Rewrite `index.md` last, so it reflects the final file set.

6. **Verify.** Confirm the result is actually in best shape before reporting done:
   - every `index.md` link resolves to an existing file
   - every topic file appears in its index exactly once
   - no two topics share a `name`; filename == `name` == title stem everywhere
   - all frontmatter valid (`name`, specific `description`, `metadata.type`)
   - no topic over `topic-max-lines`
   - every `[[cross-link]]` resolves to a real topic
   Report a concise diff: renamed, merged, extracted, compacted (lines saved),
   deleted, split, and the promote-candidates left for `/promote`.

## Notes
- The recall store may be a different git repo than the working tree — resolve and
  operate on the recall root, not the project you happen to be in.
- If nothing is out of shape, say so and stop — don't churn files to look busy.
