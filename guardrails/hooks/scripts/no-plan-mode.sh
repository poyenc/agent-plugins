#!/usr/bin/env bash
# PreToolUse(EnterPlanMode): block entering plan mode.
set -euo pipefail

printf '{"decision":"block","reason":"Plan mode is banned. Describe your intended approach to the user and wait for their approval before taking any action."}'
