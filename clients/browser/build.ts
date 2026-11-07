// Builds the extension into dist/firefox and dist/chromium (ADR 0035): the
// scripts bundled by esbuild, the shared stylesheet and this extension's
// pages beside them, the logo drawn as PNG icons (Chromium draws no SVG
// icons), and a manifest for each browser.

import { cp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { Resvg } from "@resvg/resvg-js";
import { build } from "esbuild";

const root = new URL("./", import.meta.url);
const dist = new URL("./dist/", root);
const common = new URL("../webext-common/static/", root);
const SIZES = [16, 32, 48, 96, 128];

const base = JSON.parse(await readFile(new URL("./static/manifest.json", root), "utf8"));

const targets = {
  firefox: {
    ...base,
    browser_specific_settings: {
      gecko: {
        id: "browser@marskal.app",
        // The oldest supported ESR (ADR 0035).
        strict_min_version: "140.0",
        data_collection_permissions: { required: ["browsingActivity", "websiteContent"] },
      },
    },
    background: { scripts: ["background.js"], type: "module" },
  },
  chromium: {
    ...base,
    minimum_chrome_version: "120",
    background: { service_worker: "background.js", type: "module" },
  },
};

await rm(dist, { recursive: true, force: true });

const logo = await readFile(new URL("logo.svg", common));
const icons = SIZES.map((size) => ({
  size,
  png: new Resvg(logo, { fitTo: { mode: "width", value: size } }).render().asPng(),
}));

for (const [name, manifest] of Object.entries(targets)) {
  const out = new URL(`./${name}/`, dist);
  await mkdir(out, { recursive: true });

  await build({
    entryPoints: ["src/background.ts", "src/popup.ts", "src/options.ts"],
    bundle: true,
    format: "esm",
    target: ["firefox140", "chrome120"],
    outdir: `dist/${name}`,
    logLevel: "warning",
  });

  await cp(new URL("style.css", common), new URL("style.css", out));
  await cp(new URL("./static/", root), out, { recursive: true });
  await writeFile(new URL("manifest.json", out), JSON.stringify(manifest, null, 2) + "\n");
  for (const { size, png } of icons) await writeFile(new URL(`icon-${size}.png`, out), png);
}
