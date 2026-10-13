// Bundles the compiled Gleam output:
//   dist/heirloom.mjs          — the CLI (Node, with a shebang)
//   web/heirloom.js            — the browser API used by the playground
//   web/heirloom-offline.html  — the whole playground in one file that works
//                                from disk (file:// blocks ES modules)
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { build } from "esbuild";

const root = "build/dev/javascript/heirloom";

await build({
  stdin: {
    contents: `import { main } from "./heirloom.mjs";\nmain();\n`,
    resolveDir: root,
    sourcefile: "cli-entry.mjs",
  },
  bundle: true,
  platform: "node",
  format: "esm",
  target: "node20",
  banner: { js: "#!/usr/bin/env node" },
  outfile: "dist/heirloom.mjs",
  logLevel: "warning",
});

await build({
  entryPoints: [`${root}/heirloom/web.mjs`],
  bundle: true,
  platform: "browser",
  format: "esm",
  target: "es2020",
  minify: true,
  outfile: "web/heirloom.js",
  logLevel: "warning",
});

// Offline copy: inline the stylesheet and a classic (non-module) script, and
// allow exactly that script through the CSP by its SHA-256 hash.
const app = await build({
  entryPoints: ["web/app.js"],
  bundle: true,
  platform: "browser",
  format: "iife",
  target: "es2020",
  minify: true,
  write: false,
  logLevel: "warning",
});
const script = app.outputFiles[0].text.replaceAll("</script", "<\\/script");
const hash = createHash("sha256").update(script).digest("base64");
const favicon = Buffer.from(readFileSync("web/favicon.svg")).toString("base64");
const replaceOnce = (text, from, to) => {
  if (!text.includes(from)) throw new Error(`offline build: marker not found: ${from}`);
  // A function replacement keeps `$&`-style sequences in minified code literal.
  return text.replace(from, () => to);
};
let page = readFileSync("web/index.html", "utf8");
page = replaceOnce(page, "script-src 'self'", `script-src 'sha256-${hash}'`);
page = replaceOnce(page, '<link rel="stylesheet" href="styles.css">', `<style>${readFileSync("web/styles.css", "utf8")}</style>`);
page = replaceOnce(page, '<script type="module" src="app.js"></script>', "");
page = replaceOnce(page, 'href="favicon.svg"', `href="data:image/svg+xml;base64,${favicon}"`);
page = replaceOnce(page, "</body>", `<script>${script}</script>
</body>`);
writeFileSync("web/heirloom-offline.html", page);

console.log("bundled dist/heirloom.mjs, web/heirloom.js and web/heirloom-offline.html");
