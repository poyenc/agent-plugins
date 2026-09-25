// Tests for bash-guardrails.ts: registers a fake pi extension API, then feeds it Bash
// tool_call events and asserts block/allow, exercising the exact same guard scripts under
// hooks/scripts/*.sh that the Claude Code `guardrails` plugin uses -- one representative
// trigger per script, so a script that stops loading or firing is caught here too.
//
// Run with: node --experimental-strip-types test-bash-guardrails.mjs (Node 22+)
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ext = (await import(path.join(HERE, "..", "bash-guardrails.ts"))).default;

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

console.log("== herdr-prompt-guard: --wait blocks identically to Claude Code (HERDR_ENV=1) ==");
{
  const prevEnv = process.env.HERDR_ENV;
  process.env.HERDR_ENV = "1";
  try {
    assertBlock("herdr agent prompt x --wait", "herdr agent prompt reviewer 'hi' --wait", true);

    console.log("== herdr-prompt-guard: plain send is allowed, but its allow-hint is a documented pi gap ==");
    // The script's plain-send path returns hookSpecificOutput.additionalContext, not a
    // top-level block -- pi's ToolCallEventResult has no channel for a non-blocking hint, so
    // this is dropped by design (see README "pi support"). We only assert it doesn't block.
    assertBlock("herdr agent prompt x (plain send)", "herdr agent prompt reviewer 'hi'", false);
  } finally {
    if (prevEnv === undefined) delete process.env.HERDR_ENV;
    else process.env.HERDR_ENV = prevEnv;
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

console.log(`\nPASS=${pass} FAIL=${fail}`);
process.exit(fail === 0 ? 0 : 1);
