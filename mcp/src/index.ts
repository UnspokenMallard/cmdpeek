#!/usr/bin/env node
import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

type Snapshot = {
  generatedAt?: string;
  managers?: Array<{ name: string; command: string; present: boolean; installHint?: string }>;
  commands?: Array<{
    command: string;
    packageName?: string;
    packageManager?: string;
    installDate?: string;
    version?: string;
    category?: string;
    usages?: string[];
    related?: string[];
    favorite?: boolean;
    hidden?: boolean;
    onPath?: boolean;
  }>;
  favorites?: string[];
  hidden?: string[];
  gaps?: Array<{
    kind: string;
    command: string;
    reason?: string;
    relatedTo?: string[];
    category?: string;
    packageName?: string;
    packageManager?: string;
  }>;
};

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = process.env.CMDPEEK_ROOT
  ? path.resolve(process.env.CMDPEEK_ROOT)
  : path.resolve(here, "..", "..");

const scriptPath = path.join(repoRoot, "src", "cmdpeek.ps1");

let cache: { at: number; data: Snapshot } | null = null;
const cacheMs = 15_000;

function findShell(): string {
  if (process.env.CMDPEEK_PWSH) return process.env.CMDPEEK_PWSH;
  return process.platform === "win32" ? "pwsh.exe" : "pwsh";
}

function spawnOnce(shell: string, extraArgs: string[]): Promise<string> {
  return new Promise((resolve, reject) => {
    const args = [
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      scriptPath,
      "-NonInteractive",
      ...extraArgs,
    ];
    const child = spawn(shell, args, { windowsHide: true });
    let stdout = "";
    let stderr = "";
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk: string) => {
      stdout += chunk;
    });
    child.stderr.on("data", (chunk: string) => {
      stderr += chunk;
    });
    child.on("error", (err) => reject(err));
    child.on("close", (code) => {
      if (code !== 0) {
        reject(new Error(stderr.trim() || `cmdpeek exited ${code}`));
        return;
      }
      resolve(stdout);
    });
  });
}

async function runCmdPeek(extraArgs: string[]): Promise<string> {
  if (!fs.existsSync(scriptPath)) {
    throw new Error(`cmdpeek.ps1 not found at ${scriptPath}. Set CMDPEEK_ROOT to the repo.`);
  }
  const shells =
    process.platform === "win32" ? [findShell(), "powershell.exe"] : [findShell()];
  let lastErr: unknown;
  for (const shell of shells) {
    try {
      return await spawnOnce(shell, extraArgs);
    } catch (err) {
      lastErr = err;
    }
  }
  throw lastErr instanceof Error ? lastErr : new Error("Failed to run cmdpeek");
}

async function loadSnapshot(force = false): Promise<Snapshot> {
  if (!force && cache && Date.now() - cache.at < cacheMs) {
    return cache.data;
  }
  const raw = await runCmdPeek(["-Json"]);
  const data = JSON.parse(raw) as Snapshot;
  cache = { at: Date.now(), data };
  return data;
}

async function loadRecent(args: { limit?: number; since?: string; category?: string }): Promise<unknown> {
  const extra = ["-Json", "-Recent"];
  if (args.limit) extra.push("-Count", String(args.limit));
  if (args.since) extra.push("-Since", args.since);
  if (args.category) extra.push("-Category", args.category);
  const raw = await runCmdPeek(extra);
  return JSON.parse(raw);
}

function asText(value: unknown): { content: Array<{ type: "text"; text: string }> } {
  return { content: [{ type: "text", text: JSON.stringify(value, null, 2) }] };
}

function normalize(value: string | undefined): string {
  return (value ?? "").toLowerCase();
}

const server = new McpServer({
  name: "cmdpeek",
  version: "0.1.0",
});

server.tool(
  "list_recent_commands",
  "List recently installed CLI commands with package manager, date, category, and common usages. Use this to discover what tools the user just got.",
  {
    limit: z.number().int().min(1).max(200).optional().describe("Maximum commands to return (default 20)"),
    since: z.string().optional().describe('Recency lower bound: omit = LastMcpAt cursor; "all" = newest N; ISO datetime or 24h/7d. Exclusive (InstallDate > instant), not on-or-after.'),
    category: z.string().optional().describe("Optional category filter such as media, dev-tools, network, system"),
  },
  async ({ limit, since, category }) => {
    try {
      const payload = await loadRecent({ limit, since, category });
      return asText(payload);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      return asText({ error: message });
    }
  },
);

server.tool(
  "search_commands",
  "Search installed commands by name, package manager, category, or usage text.",
  {
    query: z.string().describe("Substring to match against command name, manager, category, or usages"),
    limit: z.number().int().min(1).max(200).optional(),
  },
  async ({ query, limit }) => {
    const snap = await loadSnapshot();
    const needle = query.toLowerCase();
    const hits = (snap.commands ?? []).filter((c) => {
      const blob = [c.command, c.packageName, c.packageManager, c.category, ...(c.usages ?? [])]
        .join("\n")
        .toLowerCase();
      return blob.includes(needle);
    });
    return asText({ query, commands: hits.slice(0, limit ?? 20) });
  },
);

server.tool(
  "get_command",
  "Get full detail for one installed command: usages, related missing tools, package source, and whether it is a favorite.",
  {
    name: z.string().describe("Command name, e.g. fd or yt-dlp"),
  },
  async ({ name }) => {
    const snap = await loadSnapshot();
    const command = (snap.commands ?? []).find((c) => normalize(c.command) === name.toLowerCase());
    if (!command) {
      return asText({ error: `Command '${name}' is not in the current cmdpeek inventory.` });
    }
    const relatedGaps = (snap.gaps ?? []).filter(
      (g) =>
        normalize(g.kind) === "missing-related" &&
        (g.relatedTo ?? []).some((r) => normalize(r) === name.toLowerCase()),
    );
    return asText({ command, relatedGaps });
  },
);

server.tool(
  "list_gaps",
  "Identify tooling gaps: related CLIs that are not installed, and installed commands that only have generic --help (no curated examples). Use this to suggest what to install or document next.",
  {
    kind: z
      .enum(["missing-related", "thin-docs", "not-on-path", "all"])
      .optional()
      .describe("Gap kind to return (default all)"),
  },
  async ({ kind }) => {
    const snap = await loadSnapshot();
    let gaps = snap.gaps ?? [];
    if (kind && kind !== "all") {
      gaps = gaps.filter((g) => normalize(g.kind) === kind);
    }
    return asText({ gaps });
  },
);

server.tool(
  "list_package_managers",
  "Show which Windows package managers cmdpeek detected (Chocolatey, Scoop, WinGet) and how to install any that are missing.",
  async () => {
    const snap = await loadSnapshot();
    return asText({ managers: snap.managers ?? [] });
  },
);

server.tool(
  "list_favorites",
  "List commands the user marked as favorites in cmdpeek.",
  async () => {
    const snap = await loadSnapshot();
    const names = new Set((snap.favorites ?? []).map((n) => n.toLowerCase()));
    const commands = (snap.commands ?? []).filter((c) => names.has(normalize(c.command)));
    return asText({ favorites: snap.favorites ?? [], commands });
  },
);

server.tool(
  "list_hidden",
  "List commands hidden from cmdpeek -n quick view. Hidden commands still appear in interactive mode.",
  async () => {
    const snap = await loadSnapshot();
    const names = new Set((snap.hidden ?? []).map((n) => n.toLowerCase()));
    const commands = (snap.commands ?? []).filter(
      (c) => Boolean(c.hidden) || names.has(normalize(c.command)),
    );
    return asText({ hidden: snap.hidden ?? [], commands });
  },
);

server.tool(
  "set_hidden",
  "Hide or unhide a command from cmdpeek -n quick view without opening the TUI. Use this to hide GUI tools such as LogExpert from the recent list.",
  {
    name: z.string().describe("Command name, e.g. LogExpert"),
    hidden: z.boolean().describe("true to hide from -n, false to show it again"),
  },
  async ({ name, hidden }) => {
    await runCmdPeek(hidden ? ["-Hide", name] : ["-Unhide", name]);
    cache = null;
    const snap = await loadSnapshot(true);
    return asText({ name, hidden, hiddenList: snap.hidden ?? [] });
  },
);

server.tool(
  "set_favorite",
  "Star or unstar a command in cmdpeek state (same as the TUI f key).",
  {
    name: z.string().describe("Command name, e.g. fd"),
    favorite: z.boolean().describe("true to star, false to unstar"),
  },
  async ({ name, favorite }) => {
    await runCmdPeek(favorite ? ["-Star", name] : ["-Unstar", name]);
    cache = null;
    const snap = await loadSnapshot(true);
    return asText({ name, favorite, favorites: snap.favorites ?? [] });
  },
);

server.tool(
  "refresh_inventory",
  "Rescan Chocolatey/Scoop/WinGet install roots and refresh the cmdpeek cache. Call this after installing or uninstalling a package.",
  async () => {
    const snap = await loadSnapshot(true);
    return asText({
      generatedAt: snap.generatedAt,
      commandCount: snap.commands?.length ?? 0,
      gapCount: snap.gaps?.length ?? 0,
    });
  },
);

server.resource("inventory", "cmdpeek://inventory", async () => ({
  contents: [
    {
      uri: "cmdpeek://inventory",
      mimeType: "application/json",
      text: JSON.stringify(await loadSnapshot(), null, 2),
    },
  ],
}));

server.resource("gaps", "cmdpeek://gaps", async () => {
  const snap = await loadSnapshot();
  return {
    contents: [
      {
        uri: "cmdpeek://gaps",
        mimeType: "application/json",
        text: JSON.stringify(snap.gaps ?? [], null, 2),
      },
    ],
  };
});

async function main(): Promise<void> {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((err: unknown) => {
  const message = err instanceof Error ? err.message : String(err);
  process.stderr.write(`cmdpeek MCP failed: ${message}\n`);
  process.exit(1);
});
