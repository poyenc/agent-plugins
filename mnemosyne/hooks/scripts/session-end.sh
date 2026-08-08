#!/usr/bin/env bash
# Consolidate working memories into episodic tier at session end

MNEMOSYNE_BIN="${MNEMOSYNE_BIN:-$(command -v mnemosyne 2>/dev/null)}"
[ -z "$MNEMOSYNE_BIN" ] && exit 0

"$MNEMOSYNE_BIN" sleep 2>/dev/null || true
