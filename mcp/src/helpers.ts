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

export function isBuiltinCatalog<
  T extends { origin?: string; install?: Record<string, unknown> },
>(entry: T | undefined): boolean {
  if (!entry) return false;
  if (normalize(entry.origin) === "builtin") return true;
  const flag = entry.install?.builtin;
  return flag === true || flag === "true";
}
