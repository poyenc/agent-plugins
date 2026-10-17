#!/usr/bin/env bash
# Activate the pi guardrails extensions for this user: symlinks every extension (*.ts) in this
# directory into pi's global auto-loaded extensions directory. A symlink (not a copy) keeps it
# current with this repo checkout -- no reinstall needed when the guardrail scripts change.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DEST_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/extensions"

mkdir -p "$DEST_DIR"

for SRC in "$HERE"/*.ts; do
  DEST="$DEST_DIR/$(basename "$SRC")"
  if [ -e "$DEST" ] && [ ! -L "$DEST" ]; then
    echo "install.sh: $DEST already exists and is not a symlink -- refusing to overwrite. Remove it first if you want to replace it." >&2
    exit 1
  fi
  ln -sf "$SRC" "$DEST"
  echo "install.sh: linked $DEST -> $SRC"
done
echo "install.sh: restart pi (or start a new session) to pick them up."
