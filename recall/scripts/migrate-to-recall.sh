#!/usr/bin/env bash
# migrate-to-recall.sh — Migrate from knowledge-management to recall
# Updates: storage directory, settings.json, CLAUDE.md
# Does NOT commit changes (files are outside the repo)
set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "[DRY RUN] No changes will be made."
    echo
fi

CHANGES=0

# --- 1. Move storage directory ---
OLD_STORE="$HOME/.local/share/claude/knowledge"
NEW_STORE="$HOME/.local/share/claude/recall"

if [ -d "$OLD_STORE" ] && [ ! -d "$NEW_STORE" ]; then
    echo "Moving storage: $OLD_STORE -> $NEW_STORE"
    if [ "$DRY_RUN" = false ]; then
        mv "$OLD_STORE" "$NEW_STORE"
    fi
    CHANGES=$((CHANGES + 1))
elif [ -d "$OLD_STORE" ] && [ -d "$NEW_STORE" ]; then
    echo "WARNING: Both $OLD_STORE and $NEW_STORE exist. Skipping move — resolve manually."
elif [ ! -d "$OLD_STORE" ]; then
    echo "No old storage directory found at $OLD_STORE — skipping."
fi

# --- 2. Update ~/.claude/settings.json ---
SETTINGS="$HOME/.claude/settings.json"

if [ -f "$SETTINGS" ]; then
    if grep -q '"knowledge-management@agent-plugins"' "$SETTINGS" || grep -q '"knowledge"' "$SETTINGS"; then
        echo "Updating settings: $SETTINGS"
        if [ "$DRY_RUN" = false ]; then
            cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
            python3 -c "
import json, sys

with open(sys.argv[1], 'r') as f:
    data = json.load(f)

# Rename enabledPlugins key
ep = data.get('enabledPlugins', {})
if 'knowledge-management@agent-plugins' in ep:
    ep['recall@agent-plugins'] = ep.pop('knowledge-management@agent-plugins')

# Rename settings key
if 'knowledge' in data:
    data['recall'] = data.pop('knowledge')

with open(sys.argv[1], 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" "$SETTINGS"
        fi
        CHANGES=$((CHANGES + 1))
    else
        echo "No knowledge-management references in $SETTINGS — skipping."
    fi
else
    echo "No settings file found at $SETTINGS — skipping."
fi

# --- 3. Update ~/.claude/CLAUDE.md ---
CLAUDEMD="$HOME/.claude/CLAUDE.md"

if [ -f "$CLAUDEMD" ]; then
    if grep -q 'Knowledge Management\|/knowledge-status\|claude/knowledge/' "$CLAUDEMD"; then
        echo "Updating CLAUDE.md: $CLAUDEMD"
        if [ "$DRY_RUN" = false ]; then
            cp "$CLAUDEMD" "$CLAUDEMD.bak.$(date +%Y%m%d%H%M%S)"
            sed -i \
                -e 's/## Knowledge Management/## Recall/' \
                -e 's|/knowledge-status|/recall-status|g' \
                -e 's|claude/knowledge/|claude/recall/|g' \
                "$CLAUDEMD"
        fi
        CHANGES=$((CHANGES + 1))
    else
        echo "No knowledge-management references in $CLAUDEMD — skipping."
    fi
else
    echo "No CLAUDE.md found at $CLAUDEMD — skipping."
fi

# --- Summary ---
echo
if [ "$DRY_RUN" = true ]; then
    echo "[DRY RUN] Would have made $CHANGES change(s)."
else
    echo "Done. Made $CHANGES change(s)."
    echo "Backup files created with .bak.* suffix where applicable."
fi
