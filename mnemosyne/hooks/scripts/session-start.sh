#!/usr/bin/env bash
# Inject mnemosyne context and tool-use conventions into session

detect_project() {
    local url
    url="$(git remote get-url origin 2>/dev/null)" || true
    if [ -n "$url" ]; then
        url="${url%/}"
        basename "${url%.git}"
    else
        basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    fi
}

PROJECT="$(detect_project)"
BRANCH="$(git branch --show-current 2>/dev/null || echo "")"

echo "MNEMOSYNE_PROJECT=$PROJECT"
[ -n "$BRANCH" ] && echo "MNEMOSYNE_BRANCH=$BRANCH"
echo ""

cat << EOF
=== Mnemosyne Working Memory ===
Project: $PROJECT  |  Branch: ${BRANCH:-<none>}

WHEN TO RECORD (proactively, without being asked)
  - A fact is verified or observed → remember at project scope
  - A decision is made with a rationale → remember at project scope
  - Something surprising, constraining, or non-obvious is discovered → remember at project scope
  - The goal or direction of this branch becomes clear → write branch-status canonical
  - Status or blockers change → update branch-status canonical in place

STORING
  Project fact (persists across branches):
    mnemosyne_remember(content="[$PROJECT] ...", scope="global", source="fact", importance=0.7)
  Branch finding (specific to this branch):
    mnemosyne_remember(content="[$PROJECT/$BRANCH] ...", scope="session", source="fact")
  Stable canonical fact (auto-retires old value on same category+name):
    mnemosyne_remember_canonical(category=<group>, name=<key>, body=<value>)
  Cross-project preference or standing rule:
    mnemosyne_shared_remember(content=..., kind="preference")

RECALLING
  This project:   mnemosyne_recall(query="[$PROJECT] <topic>")
  This branch:    mnemosyne_recall(query="[$PROJECT/$BRANCH] <topic>")
  Global rules:   mnemosyne_shared_recall(query=<topic>)
  Canonical fact: mnemosyne_recall_canonical(category=<group>, name=<key>)

UPDATING
  Edit in place:       mnemosyne_update(memory_id=<id>, content=...)
  Supersede (changed): mnemosyne_invalidate(memory_id=<id>) then mnemosyne_remember(...)
  Canonical:           mnemosyne_remember_canonical(...) — calling again on same category+name auto-supersedes

BRANCH STATUS (goal and status persist across sessions)
  Read:  mnemosyne_recall_canonical(category="branch-status", name="$PROJECT/$BRANCH")
  Write: mnemosyne_remember_canonical(category="branch-status", name="$PROJECT/$BRANCH", body="goal: ...\nstatus: ...\nblockers: ...")

Store [VERIFIED]/[OBSERVED] facts only. Replace facts in place when they change — never append the old value.
EOF
