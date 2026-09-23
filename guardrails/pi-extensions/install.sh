#!/usr/bin/env bash
# Activate the pi Bash guardrails extension for this user: symlinks bash-guardrails.ts into
# pi's global auto-loaded extensions directory. A symlink (not a copy) keeps it current with
# this repo checkout -- no reinstall needed when the guardrail scripts change.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/bash-guardrails.ts"
DEST_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/extensions"
DEST="$DEST_DIR/bash-guardrails.ts"

mkdir -p "$DEST_DIR"

if [ -e "$DEST" ] && [ ! -L "$DEST" ]; then
  echo "install.sh: $DEST already exists and is not a symlink -- refusing to overwrite. Remove it first if you want to replace it." >&2
  exit 1
fi

ln -sf "$SRC" "$DEST"
echo "install.sh: linked $DEST -> $SRC"
echo "install.sh: restart pi (or start a new session) to pick it up."
