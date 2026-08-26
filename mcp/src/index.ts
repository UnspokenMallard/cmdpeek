#!/usr/bin/env node
import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import {
  filterCatalogCommand,
  filterGaps,
  filterRusty,
  searchSnapshotCommands,
  AGENT_PLAYBOOK,
} from "./helpers.js";

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
    capabilities?: string[];
    aliases?: string[];
    substitutes?: string[];
    usages?: string[];
    usageDetails?: Array<{ argv: string; comment?: string; unsafe?: boolean }>;
    related?: string[];
    favorite?: boolean;
    hidden?: boolean;
    onPath?: boolean;
  }>;
  catalog?: Array<{
    command: string;
    category?: string;
    capabilities?: string[];
    aliases?: string[];
    related?: string[];
    substitutes?: string[];
    usages?: string[];
    install?: Record<string, string>;
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
    packageManagers?: string[];
    onPathManager?: string;
    installCommands?: string[];
  }>;
  rusty?: Array<{ command: string; kind: string; lastLine?: string; lastUsedAt?: string; packageManager?: string }>;
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
  const extra = force ? ["-Json", "-Refresh"] : ["-Json"];
  const raw = await runCmdPeek(extra);
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

const unsafeNote =
  "Do not run usage lines that contain <placeholders> or usageDetails.unsafe=true; copy them for the user instead.";

const server = new McpServer({
  name: "cmdpeek",
  version: "0.2.0",
});

server.tool(
  "list_recent_commands",
  `List recently installed CLI commands with package manager, date, usages, related tools, and install lines. Call this after any package install. ${unsafeNote}`,
  {
    limit: z.number().int().min(1).max(200).optional().describe("Maximum commands to return (default 20)"),
    since: z.string().optional().describe('Recency lower bound: omit = LastMcpAt cursor; "all" = newest N; ISO datetime or 24h/7d.'),
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
  "Search installed commands by name, package manager, category, capability, or usage text.",
  {
    query: z.string().describe("Substring to match against command name, manager, category, capabilities, or usages"),
    limit: z.number().int().min(1).max(200).optional(),
  },
  async ({ query, limit }) => {
    const snap = await loadSnapshot();
    const hits = searchSnapshotCommands(snap.commands ?? [], query, limit ?? 20);
    return asText({ query, commands: hits });
  },
);

server.tool(
  "get_command",
  `Get full detail for a command. Works for installed inventory rows and catalog-only names (not installed). ${unsafeNote}`,
  {
    name: z.string().describe("Command name, e.g. fd or yt-dlp"),
  },
  async ({ name }) => {
    const snap = await loadSnapshot();
    const installed = (snap.commands ?? []).filter(
      (c) => (c.command ?? "").toLowerCase() === name.toLowerCase(),
    );
    const catalog = filterCatalogCommand(snap.catalog ?? [], name);
    if (installed.length === 0 && !catalog) {
      return asText({ error: `Command '${name}' is not in the current cmdpeek inventory or catalog.` });
    }
    const relatedGaps = (snap.gaps ?? []).filter((g) => {
      const kind = (g.kind ?? "").toLowerCase();
      const related = g.relatedTo ?? [];
      return (
        (kind === "missing-related" || kind === "kit") &&
        related.some((r) => r.toLowerCase() === name.toLowerCase())
      );
    });
    return asText({
      installed: installed[0] ?? null,
      catalog: catalog ?? null,
      relatedGaps,
      note: unsafeNote,
    });
  },
);

server.tool(
  "resolve_task",
  "Map a task or capability to tools. Always prefer installed matches before suggesting a new package.",
  {
    task: z.string().describe('Task, capability, or tool name, e.g. "pretty-print json" or "search"'),
    limit: z.number().int().min(1).max(50).optional(),
  },
  async ({ task }) => {
    try {
      const raw = await runCmdPeek(["-Task", task, "-Json"]);
      return asText(JSON.parse(raw));
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      return asText({ error: message });
    }
  },
);

server.tool(
  "explain_command",
  `Explain how to use a command: usages, PATH winner, substitutes, and install lines. ${unsafeNote}`,
  {
    name: z.string().describe("Command name"),
  },
  async ({ name }) => {
    try {
      const raw = await runCmdPeek(["-Explain", name, "-Json"]);
      return asText(JSON.parse(raw));
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      return asText({ error: message });
    }
  },
);

server.tool(
  "search_available",
  "Find catalog tools (installed first, then missing with install commands) matching a query. Use before recommending a new package.",
  {
    query: z.string().describe("Name, capability, or task"),
  },
  async ({ query }) => {
    try {
      const raw = await runCmdPeek(["-SearchAvailable", query, "-Json"]);
      return asText(JSON.parse(raw));
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      return asText({ error: message });
    }
  },
);

server.tool(
  "list_installed_for",
  "List installed catalog tools the user can already use, optionally filtered by capability.",
  {
    capability: z.string().optional().describe("Capability such as search, json, http, git, media"),
    category: z.string().optional(),
  },
  async ({ capability, category }) => {
    const extra = ["-Have", "-Json"];
    if (capability) extra.push("-Capability", capability);
    if (category) extra.push("-Category", category);
    try {
      const raw = await runCmdPeek(extra);
      return asText(JSON.parse(raw));
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      return asText({ error: message });
    }
  },
);

server.tool(
  "list_gaps",
  "Identify tooling gaps: missing related CLIs, thin docs, not-on-path, shadowing (includes PATH winner), incomplete kits with install commands, and category neighbors. Prefer resolve_task before telling the user to install something.",
  {
    kind: z
      .enum([
        "missing-related",
        "thin-docs",
        "not-on-path",
        "shadowing",
        "category-neighbor",
        "kit",
        "all",
      ])
      .optional()
      .describe("Gap kind to return (default all)"),
  },
  async ({ kind }) => {
    const snap = await loadSnapshot();
    const gaps = filterGaps(snap.gaps ?? [], kind);
    return asText({ gaps });
  },
);

server.tool(
  "list_rusty",
  "Installed CLIs that do not appear in recent PSReadLine history (never used, or not in the last 500 history lines). Use this to remind the user how to use idle tools. Not a packaging gap.",
  {
    kind: z.enum(["never", "stale", "all"]).optional().describe("Rusty kind to return (default all)"),
  },
  async ({ kind }) => {
    const snap = await loadSnapshot();
    const rusty = filterRusty(snap.rusty ?? [], kind);
    return asText({ rusty });
  },
);

server.tool(
  "list_package_managers",
  "Show which package managers cmdpeek detected (Chocolatey, Scoop, WinGet, pipx, npm, cargo, brew) and how to install any that are missing.",
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
    const commands = (snap.commands ?? []).filter((c) => names.has((c.command ?? "").toLowerCase()));
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
      (c) => Boolean(c.hidden) || names.has((c.command ?? "").toLowerCase()),
    );
    return asText({ hidden: snap.hidden ?? [], commands });
  },
);

server.tool(
  "set_hidden",
  "Hide or unhide a command from cmdpeek -n quick view without opening the TUI.",
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
  "install_package",
  "Return (or optionally execute) a package-manager install command for a catalog tool. Default is dry-run. Set execute=true only with user consent.",
  {
    name: z.string().describe("Command or package name"),
    manager: z.enum(["scoop", "chocolatey", "winget"]).optional(),
    execute: z.boolean().optional().describe("If true, run cmdpeek -Reinstall. Default false (dry-run)."),
  },
  async ({ name, manager, execute }) => {
    const snap = await loadSnapshot();
    const catalog = filterCatalogCommand(snap.catalog ?? [], name);
    const install = catalog?.install ?? {};
    const pref = manager ?? "scoop";
    const id = install[pref] ?? install.scoop ?? install.winget ?? install.chocolatey ?? name;
    const command =
      pref === "chocolatey"
        ? `choco install ${id} -y`
        : pref === "winget"
          ? `winget install --id ${id} -e --accept-package-agreements --accept-source-agreements`
          : `scoop install ${id}`;
    if (!execute) {
      return asText({ dryRun: true, command, manager: pref, packageId: id });
    }
    const extra = ["-Reinstall", name];
    if (manager) extra.push("-Manager", manager);
    await runCmdPeek(extra);
    cache = null;
    return asText({ executed: true, command, manager: pref, packageId: id });
  },
);

server.tool(
  "refresh_inventory",
  "Rescan package managers and PATH, bypass caches. Call this after installing or uninstalling a package, then call list_recent_commands.",
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

server.resource("recent", "cmdpeek://recent", async () => {
  const payload = await loadRecent({ limit: 20 });
  return {
    contents: [
      {
        uri: "cmdpeek://recent",
        mimeType: "application/json",
        text: JSON.stringify(payload, null, 2),
      },
    ],
  };
});

server.resource("last-install", "cmdpeek://last-install", async () => {
  const raw = await runCmdPeek(["-LastInstall"]);
  return {
    contents: [
      {
        uri: "cmdpeek://last-install",
        mimeType: "application/json",
        text: raw,
      },
    ],
  };
});

server.registerPrompt(
  "after_install",
  {
    title: "After a package install",
    description: "How an agent should discover newly installed commands with cmdpeek",
  },
  async () => ({
    messages: [
      {
        role: "user",
        content: {
          type: "text",
          text: AGENT_PLAYBOOK,
        },
      },
    ],
  }),
);

server.registerPrompt(
  "prefer_installed",
  {
    title: "Prefer installed tools",
    description: "Resolve a user task against tools already on the machine before suggesting installs",
    argsSchema: {
      task: z.string().describe("What the user wants to do"),
    },
  },
  async ({ task }) => ({
    messages: [
      {
        role: "user",
        content: {
          type: "text",
          text: `The user wants to: ${task}\n\nCall cmdpeek resolve_task with that text. If installed matches exist, use those and show usages. Only suggest a missing catalog tool if nothing installed covers the task. ${unsafeNote}`,
        },
      },
    ],
  }),
);

async function main(): Promise<void> {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((err: unknown) => {
  const message = err instanceof Error ? err.message : String(err);
  process.stderr.write(`cmdpeek MCP failed: ${message}\n`);
  process.exit(1);
});
