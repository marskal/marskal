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

// The toolbar icon picks its own colour from the colour scheme it is
// drawn in. Thunderbird coloured neither context-stroke nor theme_icons
// reliably, which left the icon dark on a dark theme.
const icon = await readFile(
  new URL("./node_modules/lucide-static/icons/inbox.svg", import.meta.url),
  "utf8",
);
const style =
  "<style>svg { color: #18181b } @media (prefers-color-scheme: dark) { svg { color: #fbfbfe } }</style>";
await writeFile(new URL("icon.svg", dist), icon.replace(/<svg[^>]*>/, (tag) => `${tag}\n  ${style}`));

// The add-on list and notifications show the app's logo, which carries
// its own background and reads on any theme.
await cp(new URL("../../web/priv/static/images/icon.svg", import.meta.url), new URL("logo.svg", dist));
