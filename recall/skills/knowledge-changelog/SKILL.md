---
name: knowledge-changelog
description: >
  Show recent changes across all knowledge files. Use when the user asks what's changed,
  "what did we learn recently", or wants a summary of recent findings.
---

# /knowledge-changelog [days]

Show recent knowledge changes.

## Arguments
- `[days]`: number of days to look back (default: 7)

## Steps

1. Resolve project directory.
2. Find all knowledge and workflow files modified in the last N days:
   ```bash
   find <project>/ -name "*.md" -mtime -<days> -not -path "*/archive/*" | sort -t/ -k3
   ```
3. For each modified file:
   - Show file path (relative to project root), last modified time
   - Show a brief summary of content (first heading + first paragraph or list)
4. Group by: project-level changes, then per-branch changes.
5. Format as a compact changelog.
