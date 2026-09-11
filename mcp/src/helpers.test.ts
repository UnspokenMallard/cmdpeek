import assert from "node:assert/strict";
import test from "node:test";
import {
  filterCatalogCommand,
  filterGaps,
  filterRusty,
  searchSnapshotCommands,
  filterSystemCommands,
  isBuiltinCatalog,
  sortGaps,
  rankGap,
  cap,
  summarizeSnapshot,
  installCommandFor,
} from "./helpers.js";

test("filterGaps keeps one kind", () => {
  const gaps = [
    { kind: "missing-related", command: "rg" },
    { kind: "kit", command: "fzf" },
  ];
  assert.equal(filterGaps(gaps, "kit").length, 1);
  assert.equal(filterGaps(gaps, "kit")[0].command, "fzf");
  assert.equal(filterGaps(gaps, "all").length, 2);
});

test("filterRusty keeps never vs stale", () => {
  const rows = [
    { kind: "never", command: "jq" },
    { kind: "stale", command: "fd" },
  ];
  assert.equal(filterRusty(rows, "never")[0].command, "jq");
  assert.equal(filterRusty(rows).length, 2);
});

test("searchSnapshotCommands matches capabilities", () => {
  const commands = [
    { command: "jq", capabilities: ["json"], usages: ["jq . file"] },
    { command: "fd", capabilities: ["search"], usages: ["fd pat"] },
  ];
  const hits = searchSnapshotCommands(commands, "json", 10);
  assert.equal(hits.length, 1);
  assert.equal(hits[0].command, "jq");
});

test("filterCatalogCommand matches aliases", () => {
  const catalog = [
    { command: "rg", aliases: ["ripgrep"] },
    { command: "jq", aliases: [] },
  ];
  assert.equal(filterCatalogCommand(catalog, "ripgrep")?.command, "rg");
  assert.equal(filterCatalogCommand(catalog, "nope"), undefined);
});

test("filterSystemCommands keeps builtins and system category", () => {
  const commands = [
    { command: "tasklist", origin: "builtin", packageManager: "builtin", category: "system" },
    { command: "jq", origin: "package", packageManager: "scoop", category: "dev-tools" },
  ];
  const hits = filterSystemCommands(commands);
  assert.equal(hits.length, 1);
  assert.equal(hits[0].command, "tasklist");
});

test("isBuiltinCatalog reads origin and install.builtin", () => {
  assert.equal(isBuiltinCatalog({ origin: "builtin", install: {} }), true);
  assert.equal(isBuiltinCatalog({ origin: "package", install: { builtin: true } }), true);
  assert.equal(isBuiltinCatalog({ origin: "package", install: { scoop: "jq" } }), false);
});

test("sortGaps ranks actionable kinds before advisory ones", () => {
  const gaps = [
    { kind: "thin-docs", command: "zzz" },
    { kind: "category-neighbor", command: "bat" },
    { kind: "kit", command: "delta" },
    { kind: "missing-related", command: "ffmpeg" },
  ];
  assert.deepEqual(
    sortGaps(gaps).map((g) => g.kind),
    ["kit", "missing-related", "category-neighbor", "thin-docs"],
  );
});

test("sortGaps breaks ties on command name and leaves the input alone", () => {
  const gaps = [
    { kind: "kit", command: "zoxide" },
    { kind: "kit", command: "delta" },
  ];
  assert.deepEqual(
    sortGaps(gaps).map((g) => g.command),
    ["delta", "zoxide"],
  );
  assert.equal(gaps[0].command, "zoxide");
});

test("rankGap sends unknown kinds to the back", () => {
  assert.equal(rankGap("kit"), 0);
  assert.equal(rankGap("thin-docs"), 5);
  assert.equal(rankGap("something-else"), 99);
  assert.equal(rankGap(undefined), 99);
});

test("cap reports totals and truncation", () => {
  const page = cap([1, 2, 3, 4, 5], 2);
  assert.deepEqual(page.items, [1, 2]);
  assert.equal(page.total, 5);
  assert.equal(page.returned, 2);
  assert.equal(page.truncated, true);

  const whole = cap([1, 2], 10);
  assert.equal(whole.truncated, false);
  assert.equal(whole.returned, 2);

  const uncapped = cap([1, 2, 3], 0);
  assert.equal(uncapped.returned, 3);
  assert.equal(uncapped.truncated, false);
});

test("summarizeSnapshot replaces the full scan with counts", () => {
  const summary = summarizeSnapshot({
    generatedAt: "2026-09-11T00:00:00Z",
    managers: [
      { name: "apt", present: true },
      { name: "scoop", present: false },
    ],
    commands: [{}, {}, {}],
    catalog: [{}],
    rusty: [],
    favorites: ["jq"],
    hidden: [],
    gapSummary: { total: 1230 },
  });
  assert.equal(summary.counts.commands, 3);
  assert.deepEqual(summary.managersPresent, ["apt"]);
  assert.deepEqual(summary.managersMissing, ["scoop"]);
  assert.deepEqual(summary.gapSummary, { total: 1230 });
  assert.equal("commands" in summary, false);
});

test("installCommandFor covers every manager cmdpeek can drive", () => {
  assert.equal(installCommandFor("scoop", "jq"), "scoop install jq");
  assert.equal(installCommandFor("chocolatey", "jq"), "choco install jq -y");
  assert.equal(installCommandFor("apt", "jq"), "sudo apt install -y jq");
  assert.equal(installCommandFor("pacman", "jq"), "sudo pacman -S --noconfirm jq");
  assert.equal(installCommandFor("brew", "jq"), "brew install jq");
  assert.equal(installCommandFor("unknown", "jq"), "scoop install jq");
});
