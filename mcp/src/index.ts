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
  filterSystemCommands,
  isBuiltinCatalog,
  sortGaps,
  cap,
  summarizeSnapshot,
  installCommandFor,
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
    origin?: string;
    os?: string[];
    shell?: string[];
    capabilities?: string[];
    aliases?: string[];
    substitutes?: string[];
    gotchas?: string[];
    whenToUse?: string;
    whenNotToUse?: string;
    collisions?: Array<{ command?: string; shell?: string; warning?: string } | string>;
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
    origin?: string;
    os?: string[];
    shell?: string[];
    capabilities?: string[];
    aliases?: string[];
    related?: string[];
    substitutes?: string[];
    gotchas?: string[];
    whenToUse?: string;
    whenNotToUse?: string;
    collisions?: Array<{ command?: string; shell?: string; warning?: string } | string>;
    usages?: string[];
    install?: Record<string, unknown>;
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
  gapSummary?: {
    total?: number;
    returned?: number;
    truncated?: boolean;
    counts?: Record<string, number>;
    note?: string;
  };
  rusty?: Array<{ command: string; kind: string; lastLine?: string; lastUsedAt?: string; packageManager?: string }>;
};

// Every list tool caps its answer so one call cannot swamp an agent's context.
const DEFAULT_LIST_LIMIT = 25;

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

// Read rather than hardcode: a third copy of the version is a third thing to forget
// to bump, and cmdpeek doctor compares the module against package.json.
function packageVersion(): string {
  for (const dir of [here, path.join(here, ".."), path.join(here, "..", "..")]) {
    const candidate = path.join(dir, "package.json");
    try {
      const pkg = JSON.parse(fs.readFileSync(candidate, "utf8")) as { name?: string; version?: string };
      if (pkg.name === "@cmdpeek/mcp" && pkg.version) return pkg.version;
    } catch {
      // keep looking
    }
  }
  return "0.0.0";
}

const server = new McpServer({
  name: "cmdpeek",
  version: packageVersion(),
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
    const all = searchSnapshotCommands(snap.commands ?? [], query, Number.MAX_SAFE_INTEGER);
    const page = cap(all, limit ?? DEFAULT_LIST_LIMIT);
    return asText({
      query,
      commands: page.items,
      returned: page.returned,
      matched: page.total,
      truncated: page.truncated,
    });
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
      collisions: catalog?.collisions ?? installed[0]?.collisions ?? [],
      gotchas: catalog?.gotchas ?? installed[0]?.gotchas ?? [],
      whenToUse: catalog?.whenToUse ?? installed[0]?.whenToUse ?? null,
      whenNotToUse: catalog?.whenNotToUse ?? installed[0]?.whenNotToUse ?? null,
      origin: catalog?.origin ?? installed[0]?.origin ?? null,
      note: unsafeNote,
    });
  },
);

server.tool(
  "resolve_task",
  "Map a task or capability to tools. Always prefer installed matches, then OS builtins on this machine, before suggesting a new package.",
  {
    task: z.string().describe('Task, capability, or tool name, e.g. "pretty-print json" or "search"'),
    limit: z.number().int().min(1).max(50).optional().describe("Maximum matches per group (default 10)"),
  },
  async ({ task, limit }) => {
    try {
      const extra = ["-Task", task, "-Json"];
      if (limit) extra.push("-TaskLimit", String(limit));
      const raw = await runCmdPeek(extra);
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
  "Identify tooling gaps: missing related CLIs, not-on-path, shadowing (includes PATH winner), incomplete kits with install commands, and category neighbors. Ranked and capped; thin-docs is excluded unless you ask for it by kind. Call with summary=true first to see how many of each kind exist. Prefer resolve_task before telling the user to install something.",
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
      .describe("Gap kind to return (default: every kind except thin-docs)"),
    limit: z
      .number()
      .int()
      .min(1)
      .max(200)
      .optional()
      .describe(`Maximum gaps to return (default ${DEFAULT_LIST_LIMIT})`),
    summary: z
      .boolean()
      .optional()
      .describe("Return only per-kind counts, no gap rows"),
  },
  async ({ kind, limit, summary }) => {
    const snap = await loadSnapshot();
    if (summary) {
      return asText({ summary: snap.gapSummary ?? null });
    }
    // thin-docs is dropped from the cached snapshot, so ask cmdpeek for it directly.
    let rows = snap.gaps ?? [];
    if (kind === "thin-docs" || kind === "all") {
      const max = limit ?? DEFAULT_LIST_LIMIT;
      const raw = await runCmdPeek(["-Gaps", "-Json", "-GapKind", kind, "-GapLimit", String(max)]);
      const parsed = JSON.parse(raw) as { gaps?: Snapshot["gaps"]; summary?: Snapshot["gapSummary"] };
      return asText({ gaps: parsed.gaps ?? [], summary: parsed.summary ?? null });
    }
    rows = sortGaps(filterGaps(rows, kind));
    const page = cap(rows, limit ?? DEFAULT_LIST_LIMIT);
    return asText({
      gaps: page.items,
      returned: page.returned,
      matched: page.total,
      truncated: page.truncated,
      summary: snap.gapSummary ?? null,
    });
  },
);

server.tool(
  "list_rusty",
  "Installed CLIs that do not appear in recent PSReadLine history (never used, or not in the last 500 history lines). Use this to remind the user how to use idle tools. Not a packaging gap.",
  {
    kind: z.enum(["never", "stale", "all"]).optional().describe("Rusty kind to return (default all)"),
    limit: z.number().int().min(1).max(200).optional().describe(`Maximum rows to return (default ${DEFAULT_LIST_LIMIT})`),
  },
  async ({ kind, limit }) => {
    const snap = await loadSnapshot();
    const page = cap(filterRusty(snap.rusty ?? [], kind), limit ?? DEFAULT_LIST_LIMIT);
    return asText({
      rusty: page.items,
      returned: page.returned,
      matched: page.total,
      truncated: page.truncated,
    });
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
    manager: z
      .enum(["scoop", "chocolatey", "winget", "pipx", "npm", "cargo", "brew", "apt", "pacman"])
      .optional()
      .describe("Package manager to use. Defaults to the first manager present on this machine."),
    execute: z.boolean().optional().describe("If true, run cmdpeek -Reinstall. Default false (dry-run)."),
  },
  async ({ name, manager, execute }) => {
    const snap = await loadSnapshot();
    const catalog = filterCatalogCommand(snap.catalog ?? [], name);
    if (isBuiltinCatalog(catalog)) {
      return asText({
        error: `Command '${name}' is an OS builtin (origin=builtin) and cannot be installed from a package manager.`,
        origin: catalog?.origin ?? "builtin",
      });
    }
    const install = (catalog?.install ?? {}) as Record<string, string>;
    const present = (snap.managers ?? []).filter((m) => m.present).map((m) => m.name);
    const pref = manager ?? present[0] ?? "scoop";
    const id = install[pref] ?? install.scoop ?? install.winget ?? install.chocolatey ?? name;
    const command = installCommandFor(pref, id);
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
  "export_agent_playbook",
  "Return a markdown playbook of tools installed on this machine (names, aliases, substitutes, usages). Use this to prefer installed CLIs instead of suggesting new packages.",
  async () => {
    try {
      const raw = await runCmdPeek(["agent-export"]);
      return { content: [{ type: "text", text: raw }] };
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      return asText({ error: message });
    }
  },
);

server.tool(
  "compare_commands",
  "Compare two commands (origin, OS, gotchas, usages) and say which to prefer on this machine.",
  {
    left: z.string().describe("First command, e.g. robocopy"),
    right: z.string().describe("Second command, e.g. Copy-Item"),
  },
  async ({ left, right }) => {
    try {
      const raw = await runCmdPeek(["-Compare", `${left} ${right}`, "-Json"]);
      return asText(JSON.parse(raw));
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      return asText({ error: message });
    }
  },
);

server.tool(
  "suggest_for_argv",
  "Map a hallucinated or off-OS command line to an installed equivalent on this machine.",
  {
    argv: z.string().describe('Command line, e.g. "ps aux" or "grep -R foo ."'),
  },
  async ({ argv }) => {
    try {
      const raw = await runCmdPeek(["-Suggest", argv, "-Json"]);
      return asText(JSON.parse(raw));
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      return asText({ error: message });
    }
  },
);

server.tool(
  "diagnose",
  "Health check for this machine's cmdpeek setup: versions, data directory, detected package managers, catalog counts and validation errors, cache ages, and shell history. Call this when a cmdpeek answer looks wrong, empty, or stale.",
  {
    timing: z
      .boolean()
      .optional()
      .describe("Also measure per-stage scan timings. Costs a full rescan, so leave this off unless diagnosing slowness."),
  },
  async ({ timing }) => {
    try {
      const extra = ["-Doctor", "-Json"];
      if (timing) extra.push("-Timing");
      const raw = await runCmdPeek(extra);
      return asText(JSON.parse(raw));
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      return asText({ error: message });
    }
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
      gapCount: snap.gapSummary?.total ?? snap.gaps?.length ?? 0,
    });
  },
);

server.resource("inventory", "cmdpeek://inventory", async () => ({
  contents: [
    {
      uri: "cmdpeek://inventory",
      mimeType: "application/json",
      text: JSON.stringify(summarizeSnapshot(await loadSnapshot()), null, 2),
    },
  ],
}));

server.resource("gaps", "cmdpeek://gaps", async () => {
  const snap = await loadSnapshot();
  const page = cap(sortGaps(snap.gaps ?? []), DEFAULT_LIST_LIMIT);
  return {
    contents: [
      {
        uri: "cmdpeek://gaps",
        mimeType: "application/json",
        text: JSON.stringify(
          {
            gaps: page.items,
            returned: page.returned,
            matched: page.total,
            truncated: page.truncated,
            summary: snap.gapSummary ?? null,
          },
          null,
          2,
        ),
      },
    ],
  };
});

server.resource("doctor", "cmdpeek://doctor", async () => {
  const raw = await runCmdPeek(["-Doctor", "-Json"]);
  return {
    contents: [
      {
        uri: "cmdpeek://doctor",
        mimeType: "application/json",
        text: raw.trim(),
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

server.resource("agent-export", "cmdpeek://agent-export", async () => {
  const raw = await runCmdPeek(["agent-export"]);
  return {
    contents: [
      {
        uri: "cmdpeek://agent-export",
        mimeType: "text/markdown",
        text: raw,
      },
    ],
  };
});

server.resource("system", "cmdpeek://system", async () => {
  const snap = await loadSnapshot();
  const commands = filterSystemCommands(snap.commands ?? []);
  const catalog = (snap.catalog ?? []).filter(
    (c) => (c.origin ?? "").toLowerCase() === "builtin" || (c.category ?? "").toLowerCase() === "system",
  );
  const commandPage = cap(commands, 60);
  const catalogPage = cap(catalog, 60);
  return {
    contents: [
      {
        uri: "cmdpeek://system",
        mimeType: "application/json",
        text: JSON.stringify(
          {
            commands: commandPage.items,
            commandsTotal: commandPage.total,
            commandsTruncated: commandPage.truncated,
            catalog: catalogPage.items,
            catalogTotal: catalogPage.total,
            catalogTruncated: catalogPage.truncated,
            note: "Use get_command for detail on a specific name.",
          },
          null,
          2,
        ),
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
  "prefer_system_then_installed",
  {
    title: "Prefer system then installed tools",
    description: "Try OS builtins, then inventoried CLIs, and only then suggest an install",
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
          text: `The user wants to: ${task}\n\n1. Call resolve_task.\n2. Prefer OS builtins on this machine (cmdpeek://system) when they apply.\n3. Then prefer other installed inventory matches.\n4. Honor collisions/gotchas (PowerShell curl/sc/find/where).\n5. Only suggest a missing catalog package if nothing installed or builtin covers the task.\n${unsafeNote}`,
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
          text: `The user wants to: ${task}\n\nCall cmdpeek resolve_task with that text. Prefer OS builtins and installed matches. Only suggest a missing catalog tool if nothing installed covers the task. ${unsafeNote}`,
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
