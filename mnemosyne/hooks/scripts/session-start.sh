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

STORING
  Project fact (persists across branches):
    mnemosyne_remember(content="[$PROJECT] ...", scope="global", source="fact", importance=0.7)
  Branch finding (current work):
    mnemosyne_remember(content="[$PROJECT/$BRANCH] ...", scope="session", source="fact")
  Stable canonical fact (auto-retires old value):
    mnemosyne_remember_canonical(category=<group>, name=<key>, body=<value>)
  Cross-project preference or rule:
    mnemosyne_shared_remember(content=..., kind="preference")

RECALLING
  This project:   mnemosyne_recall(query="[$PROJECT] <topic>")
  This branch:    mnemosyne_recall(query="[$PROJECT/$BRANCH] <topic>")
  Global rules:   mnemosyne_shared_recall(query=<topic>)
  Canonical fact: mnemosyne_recall_canonical(category=<group>, name=<key>)

UPDATING
  Edit in place:        mnemosyne_update(memory_id=<id>, content=...)
  Supersede (fact changed): mnemosyne_invalidate(memory_id=<id>) then mnemosyne_remember(...)
  Canonical (auto-supersedes): mnemosyne_remember_canonical(...) — just call again on same category+name

BRANCH STATUS (persist goal/status across sessions)
  Read:  mnemosyne_recall_canonical(category="branch-status", name="$PROJECT/$BRANCH")
  Write: mnemosyne_remember_canonical(category="branch-status", name="$PROJECT/$BRANCH", body="goal: ...\nstatus: ...\nblockers: ...")
  When:  write when you first learn the branch goal, update when status or blockers change

Store [VERIFIED]/[OBSERVED] facts only. Never append "used to be X, now Y" — replace in place.
EOF
