import assert from "node:assert/strict";
import test from "node:test";
import {
  filterCatalogCommand,
  filterGaps,
  filterRusty,
  searchSnapshotCommands,
  filterSystemCommands,
  isBuiltinCatalog,
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
