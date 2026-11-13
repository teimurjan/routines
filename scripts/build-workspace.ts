// Writes build/workspace, the source of the workspace where the coding agent of the threads makes routines.
// The app copies it to Application Support/Routines/workspace when its version changes.
import { cpSync, existsSync, mkdirSync, readdirSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { basename, dirname, join, relative } from "node:path";

const ROOT = join(import.meta.dir, "..");
const OUT = join(ROOT, "build/workspace");

// The plugins import only these packages from npm. A new one goes here and in workspace/AGENTS.md.
const VENDORED = [
  { name: "zod", from: "packages/sdk" },
  { name: "preact", from: "packages/ui" },
];

const DOCS = [
  "specs/001-swift-host/contracts/plugin-api.md",
  "specs/002-plugin-ui/contracts/plugin-ui.md",
  "specs/002-plugin-ui/contracts/tokens.md",
  "specs/003-custom-ui-everywhere/contracts/actions.md",
  "specs/003-custom-ui-everywhere/contracts/ui-controls.md",
  "specs/004-actionables/contracts/actionables.md",
  "specs/004-actionables/contracts/entrance.md",
  "specs/004-actionables/contracts/sources.md",
  "specs/004-actionables/contracts/memory.md",
  "DESIGN.md",
];

const withoutNodeModules = (source: string) => basename(source) !== "node_modules";

const copyFolders = (from: string, to: string) => {
  for (const name of readdirSync(join(ROOT, from))) {
    const source = join(ROOT, from, name);
    if (!existsSync(join(source, "package.json"))) continue;
    cpSync(source, join(OUT, to, name), { recursive: true, filter: withoutNodeModules });
  }
};

// Each workspace package resolves by its name, as `bun install` would link it.
const linkPackages = (folder: string) => {
  for (const name of readdirSync(join(OUT, folder))) {
    const manifest = JSON.parse(readFileSync(join(OUT, folder, name, "package.json"), "utf8")) as { name: string };
    const link = join(OUT, "node_modules", manifest.name);
    mkdirSync(dirname(link), { recursive: true });
    symlinkSync(relative(dirname(link), join(OUT, folder, name)), link);
  }
};

rmSync(OUT, { recursive: true, force: true });
cpSync(join(ROOT, "workspace"), OUT, { recursive: true });
cpSync(join(ROOT, "tsconfig.base.json"), join(OUT, "tsconfig.base.json"));
copyFolders("packages", "packages");
for (const doc of DOCS) cpSync(join(ROOT, doc), join(OUT, "docs", basename(doc)));
for (const { name, from } of VENDORED) {
  const manifest = Bun.resolveSync(`${name}/package.json`, join(ROOT, from));
  cpSync(realpathSync(dirname(manifest)), join(OUT, "node_modules", name), { recursive: true, dereference: true });
}
linkPackages("packages");
writeFileSync(join(OUT, "version.txt"), new Date().toISOString());
console.log(`built ${OUT}`);
