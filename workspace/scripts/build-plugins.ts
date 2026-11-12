// Bundles each plugin into dist/plugin.js, the one file that the Swift host loads in JavaScriptCore.
// A plugin with ui/main.tsx also gets dist/ui, the page that the host shows in a web view.
// Plugin ids as arguments build only those plugins. The workspace of the threads runs this script too.
import { existsSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { basename, join } from "node:path";

const PLUGINS_DIR = join(import.meta.dir, "../plugins");

// The host serves this shell, so a plugin cannot add inline script or a remote link. See specs/002-plugin-ui/research.md, section 10.
const UI_SHELL = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="stylesheet" href="ui.css">
<script defer src="ui.js"></script>
</head>
<body><div id="root"></div></body>
</html>
`;

const only = process.argv.slice(2);
const pluginDirs = readdirSync(PLUGINS_DIR)
  .map((name) => join(PLUGINS_DIR, name))
  .filter((dir) => existsSync(join(dir, "plugin.json")))
  .filter((dir) => only.length === 0 || only.includes(basename(dir)));

const unknown = only.filter((id) => !pluginDirs.some((dir) => basename(dir) === id));
if (unknown.length > 0) {
  console.error(`no plugin.json in ${unknown.map((id) => join(PLUGINS_DIR, id)).join(", ")}`);
  process.exit(1);
}

const report = (dir: string, built: Bun.BuildOutput) => {
  if (built.success) return true;
  console.error(`${dir}:`);
  for (const message of built.logs) console.error(message);
  return false;
};

const buildPlugin = async (dir: string) => {
  const built = await Bun.build({
    entrypoints: [join(dir, "src/index.ts")],
    outdir: join(dir, "dist"),
    naming: "plugin.js",
    target: "browser",
    format: "iife",
    loader: { ".md": "text", ".txt": "text" },
  });
  if (report(dir, built)) console.log(`built ${join(dir, "dist/plugin.js")}`);
  return built.success;
};

const buildUI = async (dir: string) => {
  const outdir = join(dir, "dist/ui");
  rmSync(outdir, { recursive: true, force: true });
  const built = await Bun.build({
    entrypoints: [join(dir, "ui/main.tsx")],
    outdir,
    naming: { entry: "ui.[ext]", asset: "[name]-[hash].[ext]" },
    target: "browser",
    format: "iife",
    jsx: { runtime: "automatic", importSource: "preact" },
  });
  if (!report(dir, built)) return false;
  // The shell always links ui.css, so a UI without CSS gets an empty file.
  if (!existsSync(join(outdir, "ui.css"))) writeFileSync(join(outdir, "ui.css"), "");
  writeFileSync(join(outdir, "index.html"), UI_SHELL);
  console.log(`built ${join(outdir, "index.html")}`);
  return true;
};

let failed = false;
for (const dir of pluginDirs) {
  if (!(await buildPlugin(dir))) failed = true;
  if (existsSync(join(dir, "ui/main.tsx")) && !(await buildUI(dir))) failed = true;
}
if (failed) process.exit(1);
