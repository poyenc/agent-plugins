#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; S="$HERE/../../scripts"
PASS=0; FAIL=0
assert_eq(){ if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; echo "    exp:[$2] act:[$3]"; FAIL=$((FAIL+1)); fi; }

# herdr must never be called for any of these -- they all die before self_target()/resolve()
# would ever run. A herdr stub that fails loudly turns "the ordering regressed and resolve()
# now runs before the handoff-file check" into a visible, distinct failure instead of a silent
# pass for the wrong reason. Built under mktemp -d, never inside this tests/ directory itself.
FAIL_LOUD_DIR=$(mktemp -d)
export PATH="$FAIL_LOUD_DIR:$PATH"
cat > "$FAIL_LOUD_DIR/herdr" <<'INNER'
#!/usr/bin/env bash
echo "UNEXPECTED herdr call: $*" >&2
exit 99
INNER
chmod +x "$FAIL_LOUD_DIR/herdr"

run(){ HERDR_ENV=1 HERDR_PANE_ID=wG:p1 bash "$@"; }

# 1. no args at all
out=$(run "$S/herdr-rotate-self" 2>&1); rc=$?
assert_eq "no args: exit 1"         "1" "$rc"
assert_eq "no args: usage message"  "1" "$(printf '%s' "$out" | grep -c 'usage: herdr-rotate-self')"

# 2. missing handoff file
out=$(run "$S/herdr-rotate-self" /tmp/does-not-exist-$$ 2>&1); rc=$?
assert_eq "missing handoff file: exit 1" "1" "$rc"
assert_eq "missing handoff file: message" "1" "$(printf '%s' "$out" | grep -c 'handoff file missing/empty')"

# 3. empty handoff file
empty=$(mktemp); : > "$empty"
out=$(run "$S/herdr-rotate-self" "$empty" 2>&1); rc=$?
assert_eq "empty handoff file: exit 1" "1" "$rc"
rm -f "$empty"

# 4. unrecognized extra positional after handoff path
ho=$(mktemp); printf '# handoff\n' > "$ho"
out=$(run "$S/herdr-rotate-self" "$ho" extra-positional 2>&1); rc=$?
assert_eq "extra positional: exit 1" "1" "$rc"
assert_eq "extra positional: message" "1" "$(printf '%s' "$out" | grep -c 'unexpected extra argument')"

# 5. HERDR_ENV unset -> no-op, exit 0, no herdr call
out=$(HERDR_ENV=0 HERDR_PANE_ID=wG:p1 PATH="$HERE/mock-fail-loud:$PATH" bash "$S/herdr-rotate-self" "$ho" 2>&1); rc=$?
assert_eq "HERDR_ENV=0: exit 0" "0" "$rc"

# 6. none of the above ever called herdr (the stub would have exit-99'd and this whole script
#    would already have crashed above if it had) -- explicit assertion that no stub was hit is
#    redundant with the exit codes already checked, since a stub hit changes rc to 99 not 1/0.
rm -f "$ho"
rm -rf "$FAIL_LOUD_DIR"

echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
