#!/usr/bin/env bash
# Consolidate working memories into episodic tier at session end

MNEMOSYNE_BIN="${MNEMOSYNE_BIN:-$(command -v mnemosyne 2>/dev/null)}"
[ -z "$MNEMOSYNE_BIN" ] && exit 0

if ! "$MNEMOSYNE_BIN" sleep 2>&1; then
    echo "mnemosyne sleep failed — working memories not consolidated this session" >&2
fi
