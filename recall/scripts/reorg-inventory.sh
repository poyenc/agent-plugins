#!/usr/bin/env bash
# scripts/reorg-inventory.sh — mechanical inventory for /recall-reorg (step 3a).
# Read-only. Parses every topic in a knowledge/ or workflows/ dir and reports the
# facts that need no judgment: identity (filename vs frontmatter name vs H1 title),
# metadata.type, line count, frontmatter validity, index membership (both ways),
# oversize, and a staleness-marker grep. Feed the output to the analysis step so a
# subagent only has to read the handful of files that are actually flagged.
#
# Usage: reorg-inventory.sh <knowledge-dir> [topic-max-lines]
#   <knowledge-dir>  dir containing topic *.md files and an index.md
#   [topic-max-lines] size limit (default 200)

set -euo pipefail

DIR="${1:?usage: reorg-inventory.sh <knowledge-dir> [topic-max-lines]}"
LIMIT="${2:-200}"
DIR="${DIR%/}"

[ -d "$DIR" ] || { echo "error: not a directory: $DIR" >&2; exit 1; }

INDEX="$DIR/index.md"

DIR="$DIR" LIMIT="$LIMIT" INDEX="$INDEX" python3 - <<'PY'
import os, re, glob

d = os.environ["DIR"]
limit = int(os.environ["LIMIT"])
index = os.environ["INDEX"]

files = sorted(f for f in glob.glob(os.path.join(d, "*.md"))
               if os.path.basename(f) != "index.md")

listed = set()
if os.path.exists(index):
    listed = set(re.findall(r'\]\(([^)]+\.md)\)', open(index).read()))

print(f"{'FILE':46} {'FM':3} {'NAME':6} {'TYPE':10} LINES")
print("-" * 78)
problems = []
for f in files:
    base = os.path.basename(f)
    txt = open(f).read()
    lines = txt.count("\n") + 1
    m = re.match(r'^---\n(.*?)\n---', txt, re.S)
    fm = bool(m)
    name = typ = ""
    if fm:
        body = m.group(1)
        nm = re.search(r'^name:\s*(.+)$', body, re.M)
        name = nm.group(1).strip() if nm else ""
        ty = re.search(r'^\s*type:\s*(.+)$', body, re.M)
        typ = ty.group(1).strip() if ty else ""
    stem = base[:-3]
    flags = []
    if not fm: flags.append("NO-FRONTMATTER")
    if fm and not name: flags.append("NO-NAME")
    if name and name != stem: flags.append(f"NAME!={name}")
    if fm and not typ: flags.append("NO-TYPE")
    if lines > limit: flags.append(f"OVER-LIMIT({lines})")
    if base not in listed: flags.append("NOT-IN-INDEX")
    if not re.search(r'^#\s+', txt, re.M): flags.append("NO-H1")
    name_col = "ok" if name == stem else "DIFF"
    print(f"{base:46} {'y' if fm else 'N':3} {name_col:6} {typ:10} {lines}")
    if flags:
        problems.append((base, ", ".join(flags)))

print("\n=== FLAGGED FILES ===")
if problems:
    for b, fl in problems:
        print(f"  {b}: {fl}")
else:
    print("  (none — all topics mechanically clean)")

print("\n=== INDEX DRIFT ===")
dead = [l for l in sorted(listed) if not os.path.exists(os.path.join(d, os.path.basename(l)))]
missing = [os.path.basename(f) for f in files if os.path.basename(f) not in listed]
if dead:
    print("  dead links (in index, no file):")
    for l in dead: print(f"    {l}")
if missing:
    print("  missing from index (file, no entry):")
    for mss in missing: print(f"    {mss}")
if not dead and not missing:
    print("  (index in sync)")

print(f"\n=== TOTALS === {len(files)} topics | index lists {len(listed)} | "
      f"limit {limit} | over-limit {sum(1 for _,fl in problems if 'OVER-LIMIT' in fl)}")
PY

echo
echo "=== STALENESS / DEAD-END MARKERS (read these files closely) ==="
grep -rniE 'FALSIFIED|superseded|turned out|was wrong|no longer|ruled out|red herring|dead end|NOOP|confounded|abandon' \
    "$DIR"/*.md 2>/dev/null | grep -v '/index.md:' | sed 's|'"$DIR"'/||' || echo "  (none)"

echo
echo "=== DELIBERATELY-KEPT SIGNALS (do NOT delete these — see size policy §1) ==="
grep -rniE 'kept as|do not re-?(pursue|hunt|investigate)|not (be )?re-?hunted|retained for|historical only|falsified-lead' \
    "$DIR"/*.md 2>/dev/null | grep -v '/index.md:' | sed 's|'"$DIR"'/||' || echo "  (none)"
