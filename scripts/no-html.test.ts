import { expect, test } from "bun:test";
import { readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";

const ROOT = join(import.meta.dir, "..");
const HTML_SINKS = /dangerouslySetInnerHTML|innerHTML/;

const files = (dir: string): string[] =>
  readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) return entry.name === "node_modules" || entry.name === "dist" ? [] : files(path);
    return /\.(tsx?|js)$/.test(entry.name) ? [path] : [];
  });

// Rule 1 of specs/002-plugin-ui/contracts/plugin-ui.md: text from items shows as text, so no UI code inserts HTML.
test("no shared control inserts HTML", () => {
  const offenders = files(join(ROOT, "packages/ui/src"))
    .filter((file) => HTML_SINKS.test(readFileSync(file, "utf8")))
    .map((file) => relative(ROOT, file));
  expect(offenders).toEqual([]);
});
