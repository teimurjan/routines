// Bundles the plugin prelude into the resources of the Swift host.
import { join } from "node:path";

const ROOT = join(import.meta.dir, "..");
const OUT_DIR = join(ROOT, "app/Sources/RoutinesKit/Resources");

const built = await Bun.build({
  entrypoints: [join(ROOT, "packages/prelude/src/index.ts")],
  outdir: OUT_DIR,
  naming: "prelude.js",
  target: "browser",
  format: "iife",
  minify: true,
});
if (!built.success) {
  for (const message of built.logs) console.error(message);
  process.exit(1);
}
console.log(`prelude: ${join(OUT_DIR, "prelude.js")}`);
