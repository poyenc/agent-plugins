// Tests for bash-guardrails.ts: registers a fake pi extension API, then feeds it Bash
// tool_call events and asserts block/allow, exercising the exact same guard scripts under
// hooks/scripts/*.sh that the Claude Code `guardrails` plugin uses -- one representative
// trigger per script, so a script that stops loading or firing is caught here too.
//
// Run with: node --experimental-strip-types test-bash-guardrails.mjs (Node 22+)
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const EXT_PATH = path.join(HERE, "..", "bash-guardrails.ts");
const { default: ext, resolveHere } = await import(EXT_PATH);

const handlers = {};
const fakePi = { on(event, handler) { handlers[event] = handler; } };
ext(fakePi);

function call(command) {
  return handlers.tool_call({ type: "tool_call", toolCallId: "t1", toolName: "bash", input: { command } });
}

let pass = 0, fail = 0;
function assertBlock(label, command, shouldBlock) {
  const result = call(command);
  const blocked = !!result?.block;
  if (blocked === shouldBlock) {
    console.log(`  PASS: ${label}`);
    pass++;
  } else {
    console.log(`  FAIL: ${label} (expected block=${shouldBlock}, got=${blocked})`);
    fail++;
  }
}

console.log("== BLOCK: one trigger per registered guard script ==");
assertBlock("no-sleep: sleep 10", "sleep 10", true);
assertBlock("no-timeout-ssh: timeout 5 ssh host echo hi", "timeout 5 ssh host echo hi", true);
assertBlock("no-srun: srun --pty bash -i", "srun --pty bash -i", true);
assertBlock("no-blind-find: find / -iname *.pyi", "find / -iname '*.pyi'", true);
assertBlock("no-blind-search: grep -r foo /", "grep -r foo /", true);

console.log("== no-sleep: the block reason names an action actually available on pi ==");
{
  const result = call("sleep 10");
  const reason = (result?.reason ?? "").toLowerCase();
  const ok = reason.includes("pi") && reason.includes("run the long command directly");
  if (ok) { console.log("  PASS: reason gives a pi-actionable path"); pass++; }
  else { console.log(`  FAIL: reason gives a pi-actionable path (got: ${result?.reason})`); fail++; }
}

console.log("== herdr-prompt-guard / no-herdr-wait: HERDR_ENV=1-gated guards ==");
{
  const prevEnv = process.env.HERDR_ENV;
  process.env.HERDR_ENV = "1";
  try {
    assertBlock("herdr agent prompt x --wait", "herdr agent prompt reviewer 'hi' --wait", true);

    console.log("== herdr-prompt-guard: plain send blocks identically to --wait (HERDR_ENV=1) ==");
    // herdr-prompt-guard.sh blocks every direct `herdr agent prompt` invocation unconditionally,
    // not just --wait -- so plain send blocks here too, the same as --wait above.
    assertBlock("herdr agent prompt x (plain send)", "herdr agent prompt reviewer 'hi'", true);

    console.log("== no-herdr-wait: herdr agent wait / pane wait-output (HERDR_ENV=1) ==");
    assertBlock("no-herdr-wait: herdr agent wait foo", "herdr agent wait foo --until idle", true);

    console.log("== no-herdr-wait: the block reason names an action actually available on pi ==");
    const result = call("herdr agent wait foo --until idle");
    const reason = (result?.reason ?? "").toLowerCase();
    const ok = reason.includes("message skill") && reason.includes("--callback");
    if (ok) { console.log("  PASS: reason gives a pi-actionable path"); pass++; }
    else { console.log(`  FAIL: reason gives a pi-actionable path (got: ${result?.reason})`); fail++; }
  } finally {
    if (prevEnv === undefined) delete process.env.HERDR_ENV;
    else process.env.HERDR_ENV = prevEnv;
  }
}

console.log("== no-docker-on-login-node: docker on an Alola login node (hostname mocked via PATH) ==");
{
  const mockDir = fs.mkdtempSync(path.join(os.tmpdir(), "docker-guard-mock-"));
  fs.writeFileSync(path.join(mockDir, "hostname"), "#!/usr/bin/env bash\nprintf '%s' 'ctr2-alola-login-04'\n", { mode: 0o755 });
  const prevPath = process.env.PATH;
  process.env.PATH = `${mockDir}:${prevPath}`;
  try {
    assertBlock("no-docker-on-login-node: docker run (mocked Alola login node)", "docker run --rm myimage", true);
  } finally {
    process.env.PATH = prevPath;
    fs.rmSync(mockDir, { recursive: true, force: true });
  }
}

console.log("== ALLOW: unrelated and documented-alternative commands ==");
assertBlock("git status", "git status", false);
assertBlock("salloc --gres=... --time=...", "salloc --gres=gpu:1 --time=1-0", false);
assertBlock("plain ssh to a node", "ssh host uptime", false);
assertBlock("find . -name foo (scoped)", "find . -name foo", false);

console.log("== non-bash tool_call events are ignored ==");
{
  const result = handlers.tool_call({ type: "tool_call", toolCallId: "t2", toolName: "read", input: { path: "/etc/passwd" } });
  if (result === undefined) { console.log("  PASS: non-bash toolName ignored"); pass++; }
  else { console.log("  FAIL: non-bash toolName ignored (got a result)"); fail++; }
}

console.log("== empty command is ignored ==");
{
  const result = call("");
  if (result === undefined) { console.log("  PASS: empty command ignored"); pass++; }
  else { console.log("  FAIL: empty command ignored (got a result)"); fail++; }
}

console.log("== installed-path regression: resolveHere follows a symlink to its real target ==");
{
  // Node's own import() already resolves a symlink's import.meta.url to its real target -- pi's
  // loader does NOT, which is the exact bug this guarded against (see bash-guardrails.ts). So
  // importing THIS test file's own extension through a symlink would never exercise that bug;
  // instead call resolveHere directly with a synthetic symlinked file:// URL, independent of
  // whichever loader is importing this test. Must fail if realpathSync is ever removed from it.
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "bash-guardrails-symlink-test-"));
  const symlinkPath = path.join(tmpDir, "bash-guardrails.ts");
  fs.symlinkSync(EXT_PATH, symlinkPath);
  try {
    const resolved = resolveHere(`file://${symlinkPath}`);
    const expected = path.dirname(EXT_PATH);
    if (resolved === expected) {
      console.log("  PASS: resolveHere returns the real directory, not the symlink's own directory");
      pass++;
    } else {
      console.log(`  FAIL: resolveHere returns the real directory (expected ${expected}, got ${resolved})`);
      fail++;
    }
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
}

console.log(`\nPASS=${pass} FAIL=${fail}`);
process.exit(fail === 0 ? 0 : 1);
