// Host bindings shared by the CLI and the browser playground.
// Only Web-platform APIs here — Node-specific I/O lives in heirloom_node_ffi.mjs.
import { toList } from "./gleam.mjs";

/** Cryptographically secure random bytes (Web Crypto: Node 19+ and every browser). */
export function random_bytes(count) {
  const out = new Uint8Array(count);
  // getRandomValues is limited to 65 536 bytes per call.
  for (let offset = 0; offset < count; offset += 65536) {
    globalThis.crypto.getRandomValues(out.subarray(offset, Math.min(count, offset + 65536)));
  }
  return toList(Array.from(out));
}

/** Local date as YYYY-MM-DD. */
export function today() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}
