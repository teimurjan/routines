// Type-checks the SDK, the UI controls and the prelude. SDK and UI code runs in JavaScriptCore or WebKit, so it cannot use Bun or Node APIs outside its tests.
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";

const ROOT = join(import.meta.dir, "..");
const RUNTIME_ONLY = /\bfrom "node:|\bBun\.|\bprocess\.|\bimport\.meta\.(dir|main)\b|\brequire\(/;

// `bun scripts/typecheck.ts packages/sdk` checks one project.
const workspaces = ["scripts", ...readdirSync(join(ROOT, "packages")).map((name) => `packages/${name}`)];
// The scan skips these: the scripts run in Bun, and the prelude builds the web APIs itself.
const BUN_PROJECTS = new Set(["scripts", "packages/prelude"]);
const projects = (process.argv.length > 2 ? process.argv.slice(2) : workspaces).filter((dir) => existsSync(join(ROOT, dir, "tsconfig.json")));

const sourceFiles = (dir: string): string[] =>
  readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) return entry.name === "node_modules" || entry.name === "dist" ? [] : sourceFiles(path);
    return /\.tsx?$/.test(entry.name) && !/\.test\.tsx?$/.test(entry.name) && entry.name !== "testing.ts" ? [path] : [];
  });


let failed = false;
for (const project of projects) {
  const checked = Bun.spawnSync(["bunx", "tsc", "--noEmit", "-p", join(ROOT, project)], { cwd: ROOT, stdout: "inherit", stderr: "inherit" });
  if (checked.exitCode !== 0) failed = true;
  if (BUN_PROJECTS.has(project)) continue;
  for (const file of sourceFiles(join(ROOT, project, "src"))) {
    readFileSync(file, "utf8")
      .split("\n")
      .forEach((line, index) => {
        if (!RUNTIME_ONLY.test(line) || line.trim().startsWith("//")) return;
        failed = true;
        console.error(`${relative(ROOT, file)}:${index + 1}: SDK and UI code cannot use: ${line.trim()}`);
      });
  }
}
if (failed) process.exit(1);
console.log(`type-checked ${projects.length} projects`);
