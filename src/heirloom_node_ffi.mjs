// Node.js I/O for the command-line interface.
import * as fs from "node:fs";
import { Ok, Error, toList } from "./gleam.mjs";

export function argv() {
  return toList(process.argv.slice(2));
}

export function get_env(name) {
  const value = process.env[name];
  return value === undefined || value === "" ? new Error(undefined) : new Ok(value);
}

/** Loads ./.env when present (Node 20.12+). Variables already set win. */
export function load_dotenv() {
  if (typeof process.loadEnvFile === "function" && fs.existsSync(".env")) {
    try {
      process.loadEnvFile(".env");
    } catch {
      // A malformed .env should not stop the CLI.
    }
  }
  return undefined;
}

export function read_stdin() {
  try {
    return new Ok(fs.readFileSync(0, "utf8"));
  } catch (e) {
    return new Error(String(e?.message ?? e));
  }
}

export function read_file(path) {
  try {
    return new Ok(fs.readFileSync(path, "utf8"));
  } catch (e) {
    return new Error(e?.code === "ENOENT" ? `no such file: ${path}` : String(e?.message ?? e));
  }
}

export function write_file(path, content) {
  try {
    // Cards hold secret shares: keep the file private to the current user.
    fs.writeFileSync(path, content, { encoding: "utf8", mode: 0o600 });
    return new Ok(undefined);
  } catch (e) {
    return new Error(String(e?.message ?? e));
  }
}

export function stdin_is_tty() {
  return !!process.stdin.isTTY;
}

export function stdout_is_tty() {
  return !!process.stdout.isTTY;
}

export function print_error(text) {
  process.stderr.write(text + "\n");
  return undefined;
}

export function exit(code) {
  process.exit(code);
}
