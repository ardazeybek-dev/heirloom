# Contributing

Thanks for helping. heirloom guards people's most important secrets, so correctness beats features.

## Setup

- [Gleam](https://gleam.run/getting-started/installing/) ≥ 1.19 (JavaScript target — Erlang is not needed)
- Node.js ≥ 20.12
- Optional, for the QR cross-check: Python 3 with `opencv-python-headless`

```sh
npm install
npm run build
gleam test
npm run verify:qr
```

## Ground rules

- **The core stays pure.** Randomness, files and the clock enter through `src/heirloom_ffi.mjs` and
  `src/heirloom_node_ffi.mjs` only; everything in `src/heirloom/` must be testable with fixed bytes.
- **No runtime dependencies.** The playground's CSP blocks all network access; keep it that way.
- **The card format is a promise.** Cards printed today must recover in twenty years. Any change to
  `docs/FORMAT.md` needs a new format version, and old versions must keep decoding.
- **Tests with every change.** Prefer known-answer vectors (standards, published examples) and
  properties ("every K-subset recovers") over snapshots.
- Format with `gleam format`.

## Pull requests

Describe what changed and why, and how you tested it. For anything touching `shamir`, `share`,
`secret` or `qr`, include a test that would have failed before the change.
