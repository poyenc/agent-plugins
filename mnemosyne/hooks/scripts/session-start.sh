#!/usr/bin/env bash
# Inject mnemosyne bank/branch context and tool-use conventions into session

MNEMOSYNE_BIN="${MNEMOSYNE_BIN:-mnemosyne}"

# Detect project name from git remote, fall back to directory basename
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

BANK="$(detect_project)"
BRANCH="$(git branch --show-current 2>/dev/null || echo "")"

echo "MNEMOSYNE_BANK=$BANK"
[ -n "$BRANCH" ] && echo "MNEMOSYNE_BRANCH=$BRANCH"
echo ""

cat << EOF
=== Mnemosyne Working Memory ===
Bank: $BANK  |  Branch: ${BRANCH:-<none>}

Tool-use conventions (apply to every mnemosyne tool call this session):

STORING memories
  Project fact (survives branch):  mnemosyne_remember(bank="$BANK", scope="global", ...)
  Branch finding (this branch):    mnemosyne_remember(bank="$BANK", scope="session", metadata={"branch": "${BRANCH:-<branch>}"}, ...)
  Stable canonical fact:           mnemosyne_remember_canonical(category=..., name=..., body=...)
  Cross-project preference/rule:   mnemosyne_shared_remember(content=..., kind="preference"|"meta")

RECALLING memories
  This project:    mnemosyne_recall(query=..., bank="$BANK")
  Cross-project:   mnemosyne_shared_recall(query=...)

UPDATING memories
  Edit in place:              mnemosyne_update(memory_id=..., content=...)
  Replace (fact changed):     mnemosyne_invalidate(memory_id=...) then mnemosyne_remember(...)
  Canonical fact (auto-retires old): mnemosyne_remember_canonical(...) — just overwrite the slot

Store [VERIFIED]/[OBSERVED] facts only. Hypotheses stay in conversation context, not in memory.
When a fact changes, replace it — never append "used to be X, now Y".
EOF
