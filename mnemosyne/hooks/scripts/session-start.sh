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

WHEN TO RECALL (do this before acting, not after)
  Before any multi-step procedure (run, build, deploy, test, submit, publish, ...):
    → mnemosyne_recall(query="[$PROJECT] how to <procedure>")
  Before choosing an approach or making a decision:
    → mnemosyne_recall(query="[$PROJECT] <topic> decision")
    → mnemosyne_recall(query="[$PROJECT] <topic> dead end")
  When first touching a topic or area this session:
    → mnemosyne_recall(query="[$PROJECT] <topic>")
  When diagnosing an unexpected result or problem:
    → mnemosyne_recall(query="[$PROJECT] <symptom or problem type>")
  On a non-default branch: also recall branch layer and retrieve branch-status
  When recalled content conflicts with current evidence: invalidate and replace

WHEN TO RECORD (proactively, without being asked)
  Project scope — knowledge that outlives this branch:
    - A procedure or workflow is established or corrected ("how to <X>")
    - A fact, behavior, or outcome is verified or observed
    - A decision is made and the rationale matters
    - Something surprising, constraining, or non-obvious is discovered
    - A measured result is obtained (number, outcome, comparison)
    - A dead end is confirmed ("do not re-pursue X because Y")
  Branch scope — findings specific to current line of work:
    - An intermediate finding that may not generalize beyond this branch
    - A working hypothesis confirmed within this branch's context
  Canonical / branch status:
    - The goal or direction of this branch becomes clear → write branch-status
    - Status or blockers change → update branch-status in place
  Shared (cross-project):
    - A preference, standing rule, or workflow correction applies globally

RECALLING
  Project layer (always):  mnemosyne_recall(query="[$PROJECT] <topic>")
EOF

if [ -n "$BRANCH" ]; then
cat << EOF
  Branch layer:            mnemosyne_recall(query="[$PROJECT/$BRANCH] <topic>")
  Branch status:           mnemosyne_recall_canonical(category="branch-status", name="$PROJECT/$BRANCH")
EOF
fi

cat << EOF
  Global rules:            mnemosyne_shared_recall(query=<topic>)
  Canonical fact:          mnemosyne_recall_canonical(category=<group>, name=<key>)

STORING
  Procedure / how-to (any multi-step process established or corrected):
    mnemosyne_remember(content="[$PROJECT] how to <procedure>: <steps>", scope="global", source="fact", importance=0.8)
  Project fact (survives across branches):
    mnemosyne_remember(content="[$PROJECT] ...", scope="global", source="fact", importance=0.7)
EOF

if [ -n "$BRANCH" ]; then
cat << EOF
  Branch finding (specific to this branch):
    mnemosyne_remember(content="[$PROJECT/$BRANCH] ...", scope="global", source="fact")
  Branch status (goal/status/blockers — replaces in place):
    mnemosyne_remember_canonical(category="branch-status", name="$PROJECT/$BRANCH", body="goal: ...\nstatus: ...\nblockers: ...")
EOF
fi

cat << EOF
  Stable canonical fact (auto-retires old value on same category+name):
    mnemosyne_remember_canonical(category=<group>, name=<key>, body=<value>)
  Cross-project preference or standing rule:
    mnemosyne_shared_remember(content=..., kind="preference")

UPDATING
  Edit in place:       mnemosyne_update(memory_id=<id>, content=...)
  Supersede (changed): mnemosyne_invalidate(memory_id=<id>) then mnemosyne_remember(...)
  Canonical:           mnemosyne_remember_canonical(...) — calling again on same category+name auto-supersedes

Record only [VERIFIED] or [OBSERVED] facts. Goals, decisions, and status go in branch-status canonical.
Near-duplicates accumulate and are NOT auto-merged — mnemosyne_sleep does not deduplicate.
Before storing: recall first. If a matching memory exists, update or invalidate it — never add alongside it.
EOF
