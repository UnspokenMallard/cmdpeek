export const AGENT_PLAYBOOK = `You have cmdpeek MCP tools for discovering CLIs on this machine, including OS builtins.

After any package install (scoop, choco, winget, pipx, npm, cargo, brew):
1. Call refresh_inventory
2. Call list_recent_commands
3. Show the user the new command name and 1-3 usages
4. Do not execute usage lines that contain <placeholders> or usageDetails.unsafe=true

When the user asks how to do something (search files, list processes, copy a tree, pretty-print JSON):
1. Call resolve_task first
2. Prefer installed matches, then OS builtins on this machine (cmdpeek://system), then catalog installs
3. On Windows prefer tasklist/findstr/robocopy/Get-Process over POSIX ps/grep/cp when those Windows tools are present
4. Honor gotchas and collisions (curl/sc/find/where aliases in PowerShell)
5. Only then mention catalog-missing tools with their install command
6. Never recommend scoop/choco/winget for origin=builtin commands

When explaining a specific CLI, call get_command or explain_command. Catalog-only names are allowed.
To map a hallucinated argv to something installed, call suggest_for_argv.
To pick between two tools, call compare_commands.

For a durable per-machine cheat sheet, read cmdpeek://agent-export or call export_agent_playbook.
`;

export function normalize(value: string | undefined): string {
  return (value ?? "").toLowerCase();
}

export function filterGaps<T extends { kind?: string }>(gaps: T[], kind?: string): T[] {
  if (!kind || kind === "all") return gaps;
  const want = kind.toLowerCase();
  return gaps.filter((g) => normalize(g.kind) === want);
}

// Mirrors $script:CmdPeekGapKindRank in src/Inventory.ps1.
export const GAP_KIND_RANK: Record<string, number> = {
  kit: 0,
  "missing-related": 1,
  shadowing: 2,
  "not-on-path": 3,
  "category-neighbor": 4,
  "thin-docs": 5,
};

export function rankGap(kind: string | undefined): number {
  return GAP_KIND_RANK[normalize(kind)] ?? 99;
}

export function sortGaps<T extends { kind?: string; command?: string }>(gaps: T[]): T[] {
  return [...gaps].sort((a, b) => {
    const byKind = rankGap(a.kind) - rankGap(b.kind);
    if (byKind !== 0) return byKind;
    return normalize(a.command).localeCompare(normalize(b.command));
  });
}

export type Capped<T> = {
  items: T[];
  total: number;
  returned: number;
  truncated: boolean;
};

export function cap<T>(items: T[], limit: number): Capped<T> {
  const all = items ?? [];
  const kept = limit > 0 ? all.slice(0, limit) : all;
  return {
    items: kept,
    total: all.length,
    returned: kept.length,
    truncated: kept.length < all.length,
  };
}

export function filterRusty<T extends { kind?: string }>(rows: T[], kind?: string): T[] {
  if (!kind || kind === "all") return rows;
  const want = kind.toLowerCase();
  return rows.filter((r) => normalize(r.kind) === want);
}

export function searchSnapshotCommands<
  T extends {
    command?: string;
    packageName?: string;
    packageManager?: string;
    category?: string;
    capabilities?: string[];
    usages?: string[];
  },
>(commands: T[], query: string, limit = 20): T[] {
  const needle = query.toLowerCase();
  const hits = commands.filter((c) => {
    const blob = [
      c.command,
      c.packageName,
      c.packageManager,
      c.category,
      ...(c.capabilities ?? []),
      ...(c.usages ?? []),
    ]
      .join("\n")
      .toLowerCase();
    return blob.includes(needle);
  });
  return hits.slice(0, limit);
}

export function filterCatalogCommand<
  T extends { command?: string; aliases?: string[] },
>(catalog: T[], name: string): T | undefined {
  const needle = name.toLowerCase();
  return catalog.find((c) => {
    if (normalize(c.command) === needle) return true;
    return (c.aliases ?? []).some((a) => a.toLowerCase() === needle);
  });
}

export function filterSystemCommands<
  T extends {
    origin?: string;
    packageManager?: string;
    category?: string;
  },
>(commands: T[]): T[] {
  return commands.filter((c) => {
    const origin = normalize(c.origin);
    const pm = normalize(c.packageManager);
    const cat = normalize(c.category);
    return origin === "builtin" || pm === "builtin" || pm === "windows" || cat === "system";
  });
}

type SnapshotShape = {
  generatedAt?: string;
  managers?: Array<{ name: string; present: boolean }>;
  commands?: unknown[];
  catalog?: unknown[];
  gaps?: unknown[];
  rusty?: unknown[];
  favorites?: string[];
  hidden?: string[];
  gapSummary?: unknown;
};

export type SnapshotSummary = {
  generatedAt: string | null;
  counts: {
    commands: number;
    catalog: number;
    rusty: number;
    favorites: number;
    hidden: number;
  };
  managersPresent: string[];
  managersMissing: string[];
  gapSummary: unknown;
  note: string;
};

// cmdpeek://inventory used to serialize the whole scan. On a machine with a
// populated package database that is hundreds of kilobytes of context, so the
// resource now describes the inventory and points at the tools that slice it.
export function summarizeSnapshot(snap: SnapshotShape): SnapshotSummary {
  const managers = snap.managers ?? [];
  return {
    generatedAt: snap.generatedAt ?? null,
    counts: {
      commands: (snap.commands ?? []).length,
      catalog: (snap.catalog ?? []).length,
      rusty: (snap.rusty ?? []).length,
      favorites: (snap.favorites ?? []).length,
      hidden: (snap.hidden ?? []).length,
    },
    managersPresent: managers.filter((m) => m?.present).map((m) => m.name),
    managersMissing: managers.filter((m) => !m?.present).map((m) => m.name),
    gapSummary: snap.gapSummary ?? null,
    note:
      "This resource is a summary. Use search_commands, get_command, list_recent_commands, " +
      "list_installed_for, or list_gaps to read the parts you need.",
  };
}

export function isBuiltinCatalog<
  T extends { origin?: string; install?: Record<string, unknown> },
>(entry: T | undefined): boolean {
  if (!entry) return false;
  if (normalize(entry.origin) === "builtin") return true;
  const flag = entry.install?.builtin;
  return flag === true || flag === "true";
}
