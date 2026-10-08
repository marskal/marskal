// Builds the extension into dist/: the scripts bundled by esbuild, the
// static pages beside them, and the toolbar icon from lucide-static.

import { cp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { build } from "esbuild";

const dist = new URL("./dist/", import.meta.url);

await rm(dist, { recursive: true, force: true });
await mkdir(dist, { recursive: true });

await build({
  entryPoints: ["src/background.ts", "src/popup.ts", "src/options.ts"],
  bundle: true,
  format: "esm",
  target: "firefox140",
  outdir: "dist",
  logLevel: "warning",
});

await cp(new URL("./static/", import.meta.url), dist, { recursive: true });

// Thunderbird colours toolbar icons through context-stroke.
const icon = await readFile(
  new URL("./node_modules/lucide-static/icons/inbox.svg", import.meta.url),
  "utf8",
);
await writeFile(new URL("icon.svg", dist), icon.replaceAll("currentColor", "context-stroke"));
