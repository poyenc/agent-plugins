---
name: recall-search
description: Search across all knowledge files including archives.
---

# /recall-search <query>

Search across all knowledge files.

## Arguments
- `<query>`: search terms

## Steps

1. Resolve storage root and project directory.
2. Use Grep tool to search for `<query>` across:
   - `<project>/knowledge/` (project-level topics)
   - `<project>/branches/*/knowledge/` (all active branch overlays)
   - `<project>/branches/*/tasks/*/knowledge.md` (flat task knowledge)
   - `<project>/branches/*/tasks/*/knowledge/*.md` (split task knowledge)
   - `<project>/archive/*/knowledge/` (archived branch knowledge)
3. Group results by location: project, branch (name), task (name), archive (name).
4. Show matching lines with context (file path, surrounding text).
5. Indicate scope for each result: [project], [branch: name], [task: name], [archive: name].
