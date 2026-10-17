// Tests for schedule-prompt-guard.ts: registers a fake pi extension API, then feeds it
// schedule_prompt tool_call events against a temporary job store and asserts block/allow,
// mirroring the cron-guard.sh rules (minimum interval, maximum concurrent recurring jobs).
//
// Run with: node --experimental-strip-types test-schedule-prompt-guard.mjs (Node 22+)
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const { default: ext, tightestIntervalSeconds } = await import(path.join(HERE, "..", "schedule-prompt-guard.ts"));

const handlers = {};
ext({ on(event, handler) { handlers[event] = handler; } });

const SESSION = "sess-A";
const cwd = fs.mkdtempSync(path.join(os.tmpdir(), "sched-guard-"));
process.on("exit", () => fs.rmSync(cwd, { recursive: true, force: true }));
const ctx = { cwd, sessionManager: { getSessionId: () => SESSION } };

function setJobs(jobs) {
  fs.mkdirSync(path.join(cwd, ".pi"), { recursive: true });
  fs.writeFileSync(path.join(cwd, ".pi", "schedule-prompts.json"), JSON.stringify({ jobs, version: 1 }));
}
const job = (over) => ({ id: "j1", name: "n", schedule: "0 */10 * * * *", type: "cron", enabled: true, session: SESSION, ...over });

let nextId = 0;
// A normal (sequential) call: checked, then its tool_result arrives before the next call.
function call(input, toolName = "schedule_prompt", context = ctx) {
  const toolCallId = `t${++nextId}`;
  const result = handlers.tool_call({ type: "tool_call", toolCallId, toolName, input }, context);
  handlers.tool_result({ type: "tool_result", toolCallId, toolName });
  return result;
}
// A call whose tool_result has not arrived yet (sibling calls running in parallel).
function callInFlight(input, id) {
  return handlers.tool_call({ type: "tool_call", toolCallId: id, toolName: "schedule_prompt", input }, ctx);
}

let pass = 0, fail = 0;
function expect(label, result, shouldBlock) {
  const blocked = !!result?.block;
  if (blocked === shouldBlock) { console.log(`  PASS: ${label}`); pass++; }
  else { console.log(`  FAIL: ${label} (expected block=${shouldBlock}, got=${blocked}${result?.reason ? `: ${result.reason}` : ""})`); fail++; }
}
function expectEq(label, actual, expected) {
  if (actual === expected) { console.log(`  PASS: ${label}`); pass++; }
  else { console.log(`  FAIL: ${label} (expected ${expected}, got ${actual})`); fail++; }
}

delete process.env.GUARDRAILS_MAX_CRONS;
delete process.env.GUARDRAILS_MIN_CRON_MINUTES;

console.log("== one-shot jobs are always allowed and never counted ==");
setJobs([job({ id: "r1" })]);
expect("once add with a recurring job already at the cap", call({ action: "add", type: "once", schedule: "+10s", prompt: "x" }), false);
setJobs([job({ id: "o1", type: "once", schedule: "2026-10-17T09:16:16.613Z" })]);
expect("enabled once job does not count toward the cap", call({ action: "add", type: "cron", schedule: "0 */10 * * * *", prompt: "x" }), false);

console.log("== minimum interval (default 5 minutes) ==");
setJobs([]);
expect("interval 5m allowed", call({ action: "add", type: "interval", schedule: "5m", prompt: "x" }), false);
expect("interval 1h allowed", call({ action: "add", type: "interval", schedule: "1h", prompt: "x" }), false);
expect("interval 4m blocked", call({ action: "add", type: "interval", schedule: "4m", prompt: "x" }), true);
expect("interval 30s blocked", call({ action: "add", type: "interval", schedule: "30s", prompt: "x" }), true);
expect("cron every 5 minutes allowed", call({ action: "add", schedule: "0 */5 * * * *", prompt: "x" }), false);
expect("cron offset step-range 2-59/5 allowed", call({ action: "add", schedule: "0 2-59/5 * * * *", prompt: "x" }), false);
expect("cron hourly allowed", call({ action: "add", schedule: "0 0 * * * *", prompt: "x" }), false);
expect("cron every minute blocked", call({ action: "add", schedule: "0 * * * * *", prompt: "x" }), true);
expect("cron every 2 minutes blocked", call({ action: "add", schedule: "0 */2 * * * *", prompt: "x" }), true);
expect("cron every 10 seconds blocked", call({ action: "add", schedule: "*/10 * * * * *", prompt: "x" }), true);
expect("cron seconds list 0,30 blocked", call({ action: "add", schedule: "0,30 * * * * *", prompt: "x" }), true);
expect("cron tight step hidden later in a minute list blocked", call({ action: "add", schedule: "0 0-10/5,20-59/1 * * * *", prompt: "x" }), true);
expect("cron plain minute range blocked (fires every minute in range)", call({ action: "add", schedule: "0 10-20 * * * *", prompt: "x" }), true);
expect("explicit type cron behaves like the default", call({ action: "add", type: "cron", schedule: "0 * * * * *", prompt: "x" }), true);
expect("unparseable interval fails open", call({ action: "add", type: "interval", schedule: "5x", prompt: "x" }), false);
expect("unparseable cron fails open", call({ action: "add", schedule: "not a cron", prompt: "x" }), false);
expect("add without a schedule fails open", call({ action: "add", prompt: "x" }), false);

console.log("== maximum concurrent recurring jobs (default 1) ==");
setJobs([job({ id: "r1" })]);
expect("second recurring job blocked", call({ action: "add", schedule: "0 */10 * * * *", prompt: "x" }), true);
setJobs([job({ id: "r1", enabled: false })]);
expect("disabled job does not count", call({ action: "add", schedule: "0 */10 * * * *", prompt: "x" }), false);
setJobs([job({ id: "r1", session: "sess-B" })]);
expect("another session's job does not count", call({ action: "add", schedule: "0 */10 * * * *", prompt: "x" }), false);
setJobs([job({ id: "r1", session: undefined })]);
expect("unbound job counts", call({ action: "add", schedule: "0 */10 * * * *", prompt: "x" }), true);
setJobs([job({ id: "r1", type: "interval", schedule: "10m" })]);
expect("interval job counts", call({ action: "add", schedule: "0 */10 * * * *", prompt: "x" }), true);
process.env.GUARDRAILS_MAX_CRONS = "2";
expect("GUARDRAILS_MAX_CRONS=2 allows a second", call({ action: "add", schedule: "0 */10 * * * *", prompt: "x" }), false);
setJobs([job({ id: "r1" }), job({ id: "r2" })]);
expect("GUARDRAILS_MAX_CRONS=2 blocks a third", call({ action: "add", schedule: "0 */10 * * * *", prompt: "x" }), true);
delete process.env.GUARDRAILS_MAX_CRONS;
process.env.GUARDRAILS_MIN_CRON_MINUTES = "1";
setJobs([]);
expect("GUARDRAILS_MIN_CRON_MINUTES=1 allows every minute", call({ action: "add", schedule: "0 * * * * *", prompt: "x" }), false);
delete process.env.GUARDRAILS_MIN_CRON_MINUTES;

console.log("== update and enable cannot get around the limits ==");
setJobs([job({ id: "r1" })]);
expect("update to a too-short schedule blocked", call({ action: "update", jobId: "r1", schedule: "0 * * * * *" }), true);
expect("update to a long enough schedule allowed", call({ action: "update", jobId: "r1", schedule: "0 */15 * * * *" }), false);
expect("update without a schedule allowed", call({ action: "update", jobId: "r1", prompt: "new text" }), false);
setJobs([job({ id: "o1", type: "once", schedule: "2026-10-17T09:16:16.613Z" })]);
expect("update of a once job allowed", call({ action: "update", jobId: "o1", schedule: "+10s" }), false);
setJobs([job({ id: "r1" }), job({ id: "r2", enabled: false })]);
expect("enabling a recurring job at the cap blocked", call({ action: "enable", jobId: "r2" }), true);
expect("enabling an already-enabled job allowed", call({ action: "enable", jobId: "r1" }), false);
setJobs([job({ id: "f1", enabled: false, schedule: "0 * * * * *" })]);
expect("enabling a too-fast cron job blocked even under the cap", call({ action: "enable", jobId: "f1" }), true);
setJobs([job({ id: "f2", enabled: false, type: "interval", schedule: "1m" })]);
expect("enabling a too-fast interval job blocked", call({ action: "enable", jobId: "f2" }), true);
setJobs([job({ id: "f3", enabled: false, type: "interval", schedule: "15m" })]);
expect("enabling a long enough job under the cap allowed", call({ action: "enable", jobId: "f3" }), false);
setJobs([job({ id: "r1" }), job({ id: "r2", enabled: false })]);
setJobs([job({ id: "r1" }), job({ id: "o2", type: "once", enabled: false })]);
expect("enabling a once job allowed", call({ action: "enable", jobId: "o2" }), false);
expect("unknown jobId fails open", call({ action: "enable", jobId: "nope" }), false);

console.log("== parallel calls cannot both slip under the cap ==");
setJobs([]);
expect("first of two parallel adds allowed", callInFlight({ action: "add", schedule: "0 */10 * * * *", prompt: "x" }, "p1"), false);
expect("second parallel add blocked while the first is in flight", callInFlight({ action: "add", schedule: "0 */10 * * * *", prompt: "x" }, "p2"), true);
handlers.tool_result({ type: "tool_result", toolCallId: "p1", toolName: "schedule_prompt" });
expect("after the first call's result, the (still empty) store allows an add again", callInFlight({ action: "add", schedule: "0 */10 * * * *", prompt: "x" }, "p3"), false);
handlers.tool_result({ type: "tool_result", toolCallId: "p3", toolName: "schedule_prompt" });
setJobs([job({ id: "r1", enabled: false }), job({ id: "r2", enabled: false })]);
expect("parallel enable: first allowed", callInFlight({ action: "enable", jobId: "r1" }, "p4"), false);
expect("parallel enable: second blocked", callInFlight({ action: "enable", jobId: "r2" }, "p5"), true);
handlers.tool_result({ type: "tool_result", toolCallId: "p4", toolName: "schedule_prompt" });
setJobs([]);
expect("a blocked call is not remembered as in flight", (callInFlight({ action: "add", schedule: "0 * * * * *", prompt: "x" }, "p6"), callInFlight({ action: "add", schedule: "0 */10 * * * *", prompt: "x" }, "p7")), false);
handlers.tool_result({ type: "tool_result", toolCallId: "p7", toolName: "schedule_prompt" });
expect("one-shot calls in flight do not count", (callInFlight({ action: "add", type: "once", schedule: "+10s", prompt: "x" }, "p8"), callInFlight({ action: "add", schedule: "0 */10 * * * *", prompt: "x" }, "p9")), false);
handlers.tool_result({ type: "tool_result", toolCallId: "p8", toolName: "schedule_prompt" });
handlers.tool_result({ type: "tool_result", toolCallId: "p9", toolName: "schedule_prompt" });
callInFlight({ action: "add", schedule: "0 */10 * * * *", prompt: "x" }, "p10");
handlers.turn_end({ type: "turn_end", turnIndex: 0 }, ctx);
expect("turn end clears a call whose result never arrived", callInFlight({ action: "add", schedule: "0 */10 * * * *", prompt: "x" }, "p11"), false);
handlers.turn_end({ type: "turn_end", turnIndex: 0 }, ctx);

console.log("== everything else is ignored ==");
setJobs([job({ id: "r1" })]);
expect("list allowed", call({ action: "list" }), false);
expect("remove allowed", call({ action: "remove", jobId: "r1" }), false);
expect("disable allowed", call({ action: "disable", jobId: "r1" }), false);
expect("cleanup allowed", call({ action: "cleanup" }), false);
expect("other tool ignored", call({ command: "ls" }, "bash"), false);

console.log("== fails open ==");
fs.rmSync(path.join(cwd, ".pi"), { recursive: true, force: true });
expect("missing store", call({ action: "add", schedule: "0 */10 * * * *", prompt: "x" }), false);
fs.mkdirSync(path.join(cwd, ".pi"), { recursive: true });
fs.writeFileSync(path.join(cwd, ".pi", "schedule-prompts.json"), "{ not json");
expect("malformed store", call({ action: "add", schedule: "0 */10 * * * *", prompt: "x" }), false);
expect("no ctx", call({ action: "add", schedule: "0 * * * * *", prompt: "x" }, "schedule_prompt", null), false);
expect("missing input", handlers.tool_call({ type: "tool_call", toolName: "schedule_prompt" }, ctx), false);

console.log("== tightestIntervalSeconds ==");
expectEq("seconds step", tightestIntervalSeconds("cron", "*/15 * * * * *"), 15);
expectEq("wrap-around gap 0,59 is 1s", tightestIntervalSeconds("cron", "0,59 * * * * *"), 1);
expectEq("single second and minute defaults to hourly", tightestIntervalSeconds("cron", "0 5 * * * *"), 3600);
expectEq("interval days", tightestIntervalSeconds("interval", "2d"), 172800);
expectEq("5 fields is unparseable", tightestIntervalSeconds("cron", "* * * * *"), null);

console.log(`\nPASS=${pass} FAIL=${fail}`);
process.exit(fail === 0 ? 0 : 1);
