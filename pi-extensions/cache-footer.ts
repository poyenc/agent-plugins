/**
 * Footer that adds the cache hit rate: CH<latest request>%/<whole session>%.
 * Replaces the built-in footer via ctx.ui.setFooter(); re-applied on every
 * session_start (startup, /reload, new, resume, fork).
 */
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { relative, resolve, sep } from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

const fmt = (n: number): string =>
	n < 1000 ? `${n}` : n < 10000 ? `${(n / 1000).toFixed(1)}k` : n < 1e6 ? `${Math.round(n / 1000)}k` : n < 1e7 ? `${(n / 1e6).toFixed(1)}M` : `${Math.round(n / 1e6)}M`;

function shortCwd(cwd: string): string {
	const rel = relative(resolve(homedir()), resolve(cwd));
	if (rel === "") return "~";
	return rel.startsWith("..") ? cwd : `~${sep}${rel}`;
}

function autoCompactEnabled(): boolean {
	try {
		const s = JSON.parse(readFileSync(`${homedir()}/.pi/agent/settings.json`, "utf8"));
		return s?.compaction?.enabled !== false;
	} catch {
		return true;
	}
}

interface Totals {
	input: number;
	output: number;
	cacheRead: number;
	cacheWrite: number;
	cost: number;
	latestHit: number | undefined;
}

function collect(ctx: ExtensionContext): Totals {
	const t: Totals = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: 0, latestHit: undefined };
	const add = (u: any) => {
		if (!u) return;
		t.input += u.input;
		t.output += u.output;
		t.cacheRead += u.cacheRead;
		t.cacheWrite += u.cacheWrite;
		t.cost += u.cost?.total ?? 0;
	};
	for (const e of ctx.sessionManager.getEntries() as any[]) {
		if (e.type === "message" && e.message.role === "assistant") {
			const u = e.message.usage;
			add(u);
			const prompt = u.input + u.cacheRead + u.cacheWrite;
			t.latestHit = prompt > 0 ? (u.cacheRead / prompt) * 100 : undefined;
		} else if (e.type === "message" && e.message.role === "toolResult") {
			add(e.message.usage);
		} else {
			add(e.usage);
		}
	}
	return t;
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", async (_event, ctx) => {
		if (ctx.mode !== "tui") return;
		const auto = autoCompactEnabled();

		ctx.ui.setFooter((tui, theme, footerData) => {
			const unsub = footerData.onBranchChange(() => tui.requestRender());
			let memoKey = "";
			let memo: Totals | undefined;

			const totals = (): Totals => {
				const key = `${ctx.sessionManager.getSessionId()}|${ctx.sessionManager.getLeafId()}|${ctx.sessionManager.getEntries().length}`;
				if (key !== memoKey || !memo) {
					memo = collect(ctx);
					memoKey = key;
				}
				return memo;
			};

			return {
				dispose: unsub,
				invalidate() {
					memoKey = "";
				},
				render(width: number): string[] {
					const t = totals();
					const usage = ctx.getContextUsage();
					const window = usage?.contextWindow ?? ctx.model?.contextWindow ?? 0;
					const pctValue = usage?.percent ?? 0;
					const pct = usage?.percent !== null && usage?.percent !== undefined ? pctValue.toFixed(1) : "?";

					let pwd = shortCwd(ctx.sessionManager.getCwd());
					const branch = footerData.getGitBranch();
					if (branch) pwd = `${pwd} (${branch})`;

					const parts: string[] = [];
					if (t.input) parts.push(`↑${fmt(t.input)}`);
					if (t.output) parts.push(`↓${fmt(t.output)}`);
					if (t.cacheRead) parts.push(`R${fmt(t.cacheRead)}`);
					if (t.cacheWrite) parts.push(`W${fmt(t.cacheWrite)}`);
					if ((t.cacheRead > 0 || t.cacheWrite > 0) && t.latestHit !== undefined) {
						const sessionPrompt = t.input + t.cacheRead + t.cacheWrite;
						const sessionHit = sessionPrompt > 0 ? (t.cacheRead / sessionPrompt) * 100 : 0;
						parts.push(`CH${t.latestHit.toFixed(1)}%/${Math.round(sessionHit)}%`);
					}
					if (t.cost) parts.push(`$${t.cost.toFixed(3)}`);

					const ctxText = `${pct === "?" ? "?" : `${pct}%`}/${fmt(window)}${auto ? " (auto)" : ""}`;
					parts.push(pctValue > 90 ? theme.fg("error", ctxText) : pctValue > 70 ? theme.fg("warning", ctxText) : ctxText);

					let left = parts.join(" ");
					let leftWidth = visibleWidth(left);
					if (leftWidth > width) {
						left = truncateToWidth(left, width, "...");
						leftWidth = visibleWidth(left);
					}

					const modelId = ctx.model?.id || "no-model";
					let right = modelId;
					if (ctx.model?.reasoning) {
						const level = ctx.thinkingLevel || "off";
						right = level === "off" ? `${modelId} • thinking off` : `${modelId} • ${level}`;
					}
					if (footerData.getAvailableProviderCount() > 1 && ctx.model) {
						const withProvider = `(${ctx.model.provider}) ${right}`;
						if (leftWidth + 2 + visibleWidth(withProvider) <= width) right = withProvider;
					}

					let line: string;
					const rightWidth = visibleWidth(right);
					if (leftWidth + 2 + rightWidth <= width) {
						line = left + " ".repeat(width - leftWidth - rightWidth) + right;
					} else {
						const room = width - leftWidth - 2;
						if (room > 0) {
							const cut = truncateToWidth(right, room, "");
							line = left + " ".repeat(Math.max(0, width - leftWidth - visibleWidth(cut))) + cut;
						} else {
							line = left;
						}
					}

					const lines = [
						truncateToWidth(theme.fg("dim", pwd), width, theme.fg("dim", "...")),
						theme.fg("dim", left) + theme.fg("dim", line.slice(left.length)),
					];

					const statuses = footerData.getExtensionStatuses();
					if (statuses.size > 0) {
						const text = [...statuses.entries()]
							.sort(([a], [b]) => a.localeCompare(b))
							.map(([, s]) => s.replace(/[\r\n\t]/g, " ").replace(/ +/g, " ").trim())
							.join(" ");
						lines.push(truncateToWidth(text, width, theme.fg("dim", "...")));
					}
					return lines;
				},
			};
		});
	});
}
