// pi extension: enforce, for the pi-schedule-prompt package's `schedule_prompt` tool, the same
// limits the Claude Code `guardrails` plugin's cron-guard.sh enforces on CronCreate -- a minimum
// interval between runs and a maximum number of concurrent recurring jobs -- so both harnesses
// behave the same.
//
// Mapping: a recurring job (type cron/interval) is CronCreate -- interval-limited and counted.
// A one-shot job (type once) is ScheduleWakeup -- always allowed, never counted. cron-guard.sh
// bans one-shot CronCreate only because that alternative exists; here it is the one-shot type.
//
// Limits (same env vars as cron-guard.sh, read at call time):
//   GUARDRAILS_MAX_CRONS=1            concurrent enabled recurring jobs in this session
//   GUARDRAILS_MIN_CRON_MINUTES=5     minimum interval between runs of a recurring job
//
// Checked on: add (interval + count), update with a new schedule (interval), enable of a
// recurring job (interval of its stored schedule + count -- re-enabling must not get around
// either limit).
//
// pi runs sibling tool calls in parallel, so two adds can both be checked before either is
// stored. A call that passes is therefore remembered by toolCallId until its tool_result (or the
// end of the turn) and counted against the cap in the meantime.
//
// The job store is <cwd>/.pi/schedule-prompts.json, re-read on every call. Any error, an
// unreadable store, or a schedule that can't be parsed fails open: a guard problem must never
// block a call or crash pi (the package itself rejects invalid schedules).
//
// Install: ./install.sh symlinks this file into pi's extensions directory.
// @ts-nocheck

import { readFileSync } from "node:fs";
import path from "node:path";

const TOOL = "schedule_prompt";
const UNIT_SECONDS = { s: 1, m: 60, h: 3600, d: 86400 };

function envNumber(name, fallback) {
  const raw = process.env[name];
  if (raw === undefined || raw === "") return fallback;
  const n = Number(raw);
  return Number.isFinite(n) && n >= 0 ? n : fallback;
}

/** Sorted values a 0-59 cron field (seconds or minutes) fires on, or null when unparseable. */
function fieldValues(field) {
  const values = new Set();
  for (const sub of field.split(",")) {
    const [range, stepText] = sub.split("/");
    const step = stepText === undefined ? 1 : Number(stepText);
    if (!Number.isInteger(step) || step < 1) return null;
    let lo, hi;
    if (range === "*") {
      lo = 0;
      hi = 59;
    } else if (/^\d+$/.test(range)) {
      lo = Number(range);
      hi = stepText === undefined ? lo : 59;
    } else if (/^\d+-\d+$/.test(range)) {
      [lo, hi] = range.split("-").map(Number);
    } else {
      return null;
    }
    if (lo > hi || hi > 59) return null;
    for (let v = lo; v <= hi; v += step) values.add(v);
  }
  return [...values].sort((a, b) => a - b);
}

/** Smallest gap between consecutive values on a 60-step cycle (60 when there is one value). */
function minGap(values) {
  if (values.length < 2) return 60;
  let gap = values[0] + 60 - values[values.length - 1];
  for (let i = 1; i < values.length; i++) gap = Math.min(gap, values[i] - values[i - 1]);
  return gap;
}

/**
 * Tightest time between two runs, in seconds, or null when the schedule can't be parsed.
 * `interval`: "5m", "30s", ... `cron`: pi-schedule-prompt's 6-field form (second minute hour dom
 * month dow); only the seconds and minutes fields are read, so a restriction in the hour/day
 * fields can only make the real interval longer than reported (the guard errs toward blocking).
 */
export function tightestIntervalSeconds(type, schedule) {
  if (typeof schedule !== "string") return null;
  if (type === "interval") {
    const m = /^(\d+)(s|m|h|d)$/.exec(schedule.trim());
    return m ? Number(m[1]) * UNIT_SECONDS[m[2]] : null;
  }
  if (type === "cron") {
    const fields = schedule.trim().split(/\s+/);
    if (fields.length !== 6) return null;
    const seconds = fieldValues(fields[0]);
    const minutes = fieldValues(fields[1]);
    if (!seconds || !minutes) return null;
    if (seconds.length > 1) return minGap(seconds);
    if (minutes.length > 1) return minGap(minutes) * 60;
    return 3600;
  }
  return null;
}

function loadJobs(cwd) {
  try {
    const store = JSON.parse(readFileSync(path.join(cwd, ".pi", "schedule-prompts.json"), "utf8"));
    return Array.isArray(store?.jobs) ? store.jobs : [];
  } catch {
    return [];
  }
}

function describeSeconds(seconds) {
  return seconds < 60 ? `${seconds} second(s)` : `${+(seconds / 60).toFixed(2)} minute(s)`;
}

// toolCallIds of add/enable calls that passed the check but may not be in the store yet.
const pending = new Set();

function check(event, ctx) {
  if (event.toolName !== TOOL) return undefined;
  const input = event.input ?? {};
  const action = input.action;
  if (action !== "add" && action !== "update" && action !== "enable") return undefined;
  if (!ctx?.cwd) return undefined;

  const jobs = loadJobs(ctx.cwd);
  let type;
  let schedule;
  let enabling = false;
  if (action === "add") {
    type = input.type ?? "cron";
    schedule = input.schedule;
  } else {
    const stored = jobs.find((j) => j.id === input.jobId);
    if (!stored) return undefined;
    type = stored.type ?? "cron";
    if (action === "update") schedule = input.schedule;
    else {
      enabling = !stored.enabled;
      schedule = stored.schedule;
    }
  }
  if (type === "once") return undefined;
  if (action === "enable" && !enabling) return undefined;

  const minMinutes = envNumber("GUARDRAILS_MIN_CRON_MINUTES", 5);
  if (schedule !== undefined) {
    const interval = tightestIntervalSeconds(type, schedule);
    if (interval !== null && interval < minMinutes * 60) {
      return {
        block: true,
        reason: `Recurring job interval is ${describeSeconds(interval)}, below the minimum of ${minMinutes} minutes. Use a longer interval to avoid flooding the context window.`,
      };
    }
  }

  if (action === "add" || action === "enable") {
    const maxCrons = envNumber("GUARDRAILS_MAX_CRONS", 1);
    const sessionId = ctx.sessionManager?.getSessionId?.();
    const inStore = jobs.filter(
      (j) => j.enabled && (j.type ?? "cron") !== "once" && (!j.session || j.session === sessionId),
    ).length;
    const inFlight = [...pending].filter((id) => id !== event.toolCallId).length;
    const active = inStore + inFlight;
    if (active >= maxCrons) {
      return {
        block: true,
        reason: `You already have ${active} active recurring job(s) (max: ${maxCrons}). Remove one with schedule_prompt action=remove (using its jobId) before adding or enabling another. One-shot jobs (type once) are not counted.`,
      };
    }
    pending.add(event.toolCallId);
  }
  return undefined;
}

export default function (pi) {
  pi.on("tool_call", (event, ctx) => {
    try {
      return check(event, ctx);
    } catch {
      return undefined;
    }
  });
  pi.on("tool_result", (event) => {
    pending.delete(event.toolCallId);
  });
  pi.on("turn_end", () => {
    pending.clear();
  });
}
