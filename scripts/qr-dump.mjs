// Emits QR matrices as JSON for scripts/verify_qr.py (cross-check with OpenCV).
import { encode } from "../build/dev/javascript/heirloom/heirloom/qr.mjs";
import { Low, Medium, Quartile, High } from "../build/dev/javascript/heirloom/heirloom/qr/tables.mjs";

const levels = { L: new Low(), M: new Medium(), Q: new Quartile(), H: new High() };
const alnum = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:";
let seed = 1;
const rand = (n) => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n; };
const cases = [];
for (const len of [1, 5, 20, 47, 80, 150, 300, 600, 1200]) {
  for (const lvl of ["L", "M", "Q", "H"]) {
    cases.push({ lvl, text: Array.from({ length: len }, () => alnum[rand(alnum.length)]).join("") });
    cases.push({ lvl, text: Array.from({ length: Math.ceil(len / 2) }, () => "héllo wörld ✓ abc"[rand(17)]).join("") });
  }
}
const out = [];
for (const c of cases) {
  const r = encode(c.text, levels[c.lvl]);
  if (!r.isOk()) { out.push({ ...c, error: true }); continue; }
  const q = r[0];
  out.push({ ...c, version: q.version, mask: q.mask, ecl: q.ecl.constructor.name,
    modules: q.modules.toArray().map((row) => row.toArray().map((b) => (b ? 1 : 0))) });
}
process.stdout.write(JSON.stringify(out));
