// pi extension: enforce the same Bash command *blocking* guardrails as the Claude Code
// `guardrails` plugin (block sleep, timeout-wrapped ssh, srun, whole-tree find/search), so both
// harnesses make the same block decisions. Reuses the exact scripts registered in
// ../hooks/hooks.json's Bash PreToolUse array as the single source of truth -- no separate list
// kept in sync here, so a new Claude-side guard picked up by hooks.json applies to pi
// automatically. Any script's Claude-specific NON-block output (a hint/context field alongside
// an "allow" decision) would not be propagated -- pi's tool_call result only supports
// block/reason/terminate -- see README "pi support" for the documented boundary.
//
// Install: run ./install.sh to symlink this file into pi's extensions directory. Must stay a
// symlink (not a copy) -- realpathSync below resolves it to its real target explicitly (pi's
// loader does NOT do this itself; see the import.meta.url comment below for the repro).
// @ts-nocheck

import { execFileSync } from "node:child_process";
import { readFileSync, realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

// pi's loader does NOT resolve a symlinked extension file to its real target before setting
// import.meta.url -- it reflects the symlink's own location (confirmed live: pi's extensions
// directory), not the repo checkout the symlink points to. Resolving it explicitly here is what
// actually makes the "must stay a symlink" contract above work; without it, SCRIPTS_DIR/HOOKS_JSON
// point at nonexistent paths, loadBashGuardScripts() silently fails open, and GUARD_SCRIPTS ends up
// empty -- the extension loads with no error and never blocks anything.
//
// Exported so the test can exercise this exact resolution against a real symlink independent of
// whichever loader happens to import the module -- Node's own import() already resolves a
// symlink's import.meta.url to its real target, unlike pi's loader, so a test relying on Node's
// import() through a symlink would never catch a regression here.
export function resolveHere(moduleUrl) {
  return path.dirname(realpathSync(fileURLToPath(moduleUrl)));
}

const HERE = resolveHere(import.meta.url);
const GUARDRAILS_DIR = path.join(HERE, "..");
const SCRIPTS_DIR = path.join(GUARDRAILS_DIR, "hooks", "scripts");
const HOOKS_JSON = path.join(GUARDRAILS_DIR, "hooks", "hooks.json");

/** Extract the Bash-matched PreToolUse script filenames straight out of hooks.json. */
function loadBashGuardScripts() {
  try {
    const config = JSON.parse(readFileSync(HOOKS_JSON, "utf8"));
    const bashEntry = (config.hooks?.PreToolUse ?? []).find((e) => e.matcher === "Bash");
    const commands = (bashEntry?.hooks ?? []).map((h) => h.command);
    return commands
      .map((cmd) => cmd.match(/hooks\/scripts\/([\w.-]+\.sh)/)?.[1])
      .filter(Boolean);
  } catch {
    // Fail open: a missing/malformed hooks.json must never crash pi or block anything.
    return [];
  }
}

const GUARD_SCRIPTS = loadBashGuardScripts();

/** Run one guard script with the Claude Code PreToolUse stdin contract
 *  ({tool_input: <the real tool input>}), plus "harness":"pi" so a script whose Claude-side and
 *  pi-side policy genuinely differ (not just wording -- e.g. units, or a feature one harness
 *  doesn't have at all) can tell the two apart. A genuine Claude Code PreToolUse call never
 *  carries that marker, so this cannot be confused with one. Passing the FULL real tool_input
 *  (not just {command}) lets a script read whatever other fields pi's Bash tool actually
 *  exposes (e.g. `timeout`, in seconds); a script that only reads .tool_input.command, like
 *  every other guard here today, is unaffected by the extra fields. */
function runGuard(script, toolInput) {
  try {
    const stdout = execFileSync("bash", [path.join(SCRIPTS_DIR, script)], {
      input: JSON.stringify({ tool_input: toolInput, harness: "pi" }),
      timeout: 5000,
      encoding: "utf8",
    });
    const trimmed = stdout.trim();
    return trimmed ? JSON.parse(trimmed) : undefined;
  } catch {
    // Fail open: a guard script erroring, timing out, or missing must never block or crash pi.
    return undefined;
  }
}

export default function (pi) {
  pi.on("tool_call", (event) => {
    if (event.toolName !== "bash") return;
    const command = event.input?.command ?? "";
    if (!command) return;

    for (const script of GUARD_SCRIPTS) {
      const result = runGuard(script, event.input);
      if (result?.decision === "block") {
        return { block: true, reason: result.reason };
      }
    }
  });
}
