#!/usr/bin/env node
// Development entry point: runs the CLI straight from `gleam build` output.
// The published package uses the single-file bundle in dist/ instead.
import { main } from "../build/dev/javascript/heirloom/heirloom.mjs";

main();
