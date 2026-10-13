// Bundles the compiled Gleam output into two single files:
//   dist/heirloom.mjs — the CLI (Node, with a shebang), published to npm
//   web/heirloom.js   — the browser API used by the playground
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

console.log("bundled dist/heirloom.mjs and web/heirloom.js");
