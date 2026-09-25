// pi extension: enforce the same Bash command *blocking* guardrails as the Claude Code
// `guardrails` plugin (block sleep, timeout-wrapped ssh, srun, whole-tree find/search), so both
// harnesses make the same block decisions. Reuses the exact scripts registered in
// ../hooks/hooks.json's Bash PreToolUse array as the single source of truth -- no separate list
// kept in sync here, so a new Claude-side guard picked up by hooks.json applies to pi
// automatically. A script's Claude-specific NON-block output (e.g. herdr-prompt-guard's
// allow-with-hint) is not propagated -- pi's tool_call result only supports block/reason/
// terminate, see README "pi support" for the documented boundary.
//
// Install: run ./install.sh to symlink this file into pi's extensions directory. Must stay a
// symlink (not a copy) -- it locates hooks.json and hooks/scripts/ relative to its own real path.
// @ts-nocheck

import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const HERE = path.dirname(fileURLToPath(import.meta.url));
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

/** Run one guard script with the same {tool_input:{command}} stdin contract the Claude Code
 *  hook runner uses, so the scripts themselves need no harness-specific branching. */
function runGuard(script, command) {
  try {
    const stdout = execFileSync("bash", [path.join(SCRIPTS_DIR, script)], {
      input: JSON.stringify({ tool_input: { command } }),
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
      const result = runGuard(script, command);
      if (result?.decision === "block") {
        return { block: true, reason: result.reason };
      }
    }
  });
}
