//// The `heirloom` command-line interface.

import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import heirloom/bytes
import heirloom/card
import heirloom/cli/args.{Switch, Valued}
import heirloom/kit
import heirloom/qr
import heirloom/qr/segment
import heirloom/qr/svg
import heirloom/qr/tables
import heirloom/secret
import heirloom/share

pub const version = "1.0.0"

pub const default_recovery_url = "ardazeybek-dev.github.io/heirloom"

// --- host bindings ----------------------------------------------------------

@external(javascript, "../heirloom_node_ffi.mjs", "argv")
pub fn argv() -> List(String)

@external(javascript, "../heirloom_node_ffi.mjs", "get_env")
fn get_env(name: String) -> Result(String, Nil)

@external(javascript, "../heirloom_node_ffi.mjs", "load_dotenv")
fn load_dotenv() -> Nil

@external(javascript, "../heirloom_node_ffi.mjs", "read_stdin")
fn read_stdin() -> Result(String, String)

@external(javascript, "../heirloom_node_ffi.mjs", "read_file")
fn read_file(path: String) -> Result(String, String)

@external(javascript, "../heirloom_node_ffi.mjs", "write_file")
fn write_file(path: String, content: String) -> Result(Nil, String)

@external(javascript, "../heirloom_node_ffi.mjs", "stdin_is_tty")
fn stdin_is_tty() -> Bool

@external(javascript, "../heirloom_node_ffi.mjs", "stdout_is_tty")
fn stdout_is_tty() -> Bool

@external(javascript, "../heirloom_node_ffi.mjs", "print_error")
fn print_error(text: String) -> Nil

@external(javascript, "../heirloom_node_ffi.mjs", "exit")
fn exit(code: Int) -> Nil

@external(javascript, "../heirloom_ffi.mjs", "random_bytes")
fn random_bytes(count: Int) -> List(Int)

@external(javascript, "../heirloom_ffi.mjs", "today")
fn today() -> String

// --- presentation ------------------------------------------------------------

fn color_enabled() -> Bool {
  stdout_is_tty() && result.is_error(get_env("NO_COLOR"))
}

fn paint(code: String, text: String) -> String {
  case color_enabled() {
    True -> "\u{001b}[" <> code <> "m" <> text <> "\u{001b}[0m"
    False -> text
  }
}

fn bold(text: String) -> String {
  paint("1", text)
}

fn dim(text: String) -> String {
  paint("2", text)
}

fn green(text: String) -> String {
  paint("32", text)
}

fn yellow(text: String) -> String {
  paint("33", text)
}

fn red(text: String) -> String {
  paint("31", text)
}

/// Diagnostics go to stderr so stdout stays pipeable.
fn note(text: String) -> Nil {
  print_error(text)
}

fn fail(message: String) -> Nil {
  print_error(red("error: ") <> message)
  exit(1)
}

const help = "heirloom — split a secret into printable cards; any K of N bring it back.

USAGE
  heirloom split   [options] [< secret.txt]   make cards from a secret
  heirloom combine [card files…|-]            recover the secret from cards
  heirloom verify  [card files…|-]            check cards without revealing anything
  heirloom qr      <text> [--svg] [-o file]   draw any text as a QR code

SPLIT OPTIONS
  -k, --threshold N    cards needed to recover          (env HEIRLOOM_THRESHOLD, default 3)
  -n, --shares N       cards to make                    (env HEIRLOOM_SHARES, default 5)
  -l, --label TEXT     what the secret is for, printed on every card
      --holders LIST   comma-separated names, one per card
      --secret-file F  read the secret from a file instead of stdin
      --hex            the secret is hex-encoded bytes (keys, seeds)
      --no-pad         do not pad — cards then reveal the secret's length
      --ecl L|M|Q|H    QR error-correction level        (env HEIRLOOM_QR_LEVEL, default M)
      --paper a4|letter                                 (env HEIRLOOM_PAPER, default a4)
  -o, --out FILE       printable HTML sheet             (default cards.html)
      --text           print the cards as text instead of writing HTML

COMBINE OPTIONS
      --hex            print the secret as hex

Cards are read from files or stdin: one card per file, or several separated by
blank lines. Each card may be the QR text (HL1:…) or its numbered rows.

Settings can also live in a .env file in the working directory (see .env.example).
"

// --- entry point -----------------------------------------------------------

pub fn run(arguments: List(String)) -> Nil {
  load_dotenv()
  case arguments {
    ["split", ..rest] -> split(rest)
    ["combine", ..rest] -> combine(rest)
    ["verify", ..rest] -> verify(rest)
    ["qr", ..rest] -> draw_qr(rest)
    ["--version"] | ["-V"] | ["version"] -> io.println("heirloom " <> version)
    [] | ["help"] | ["--help"] | ["-h"] -> io.print(help)
    [other, ..] -> fail("unknown command '" <> other <> "' — try heirloom --help")
  }
}

fn int_setting(parsed: args.Parsed, name: String, env: String, default: Int) -> Result(Int, String) {
  case args.get(parsed, name), get_env(env) {
    Ok(text), _ | Error(Nil), Ok(text) ->
      int.parse(string.trim(text))
      |> result.replace_error("--" <> name <> " expects a whole number, got '" <> text <> "'")
    Error(Nil), Error(Nil) -> Ok(default)
  }
}

fn text_setting(parsed: args.Parsed, name: String, env: String, default: String) -> String {
  case args.get(parsed, name), get_env(env) {
    Ok(text), _ | Error(Nil), Ok(text) -> text
    Error(Nil), Error(Nil) -> default
  }
}

// --- split -------------------------------------------------------------------

fn split(arguments: List(String)) -> Nil {
  let specs = [
    Valued("threshold", "k"), Valued("shares", "n"), Valued("label", "l"),
    Valued("holders", ""), Valued("secret-file", ""), Switch("hex", ""),
    Switch("no-pad", ""), Valued("ecl", ""), Valued("paper", ""),
    Valued("out", "o"), Switch("text", ""),
  ]
  let outcome = {
    use parsed <- result.try(args.parse(arguments, specs) |> result.map_error(args.describe))
    use k <- result.try(int_setting(parsed, "threshold", "HEIRLOOM_THRESHOLD", 3))
    use n <- result.try(int_setting(parsed, "shares", "HEIRLOOM_SHARES", 5))
    use ecl <- result.try(
      text_setting(parsed, "ecl", "HEIRLOOM_QR_LEVEL", "M")
      |> tables.ecl_from_name
      |> result.replace_error("--ecl must be one of L, M, Q, H"),
    )
    use paper <- result.try(
      text_setting(parsed, "paper", "HEIRLOOM_PAPER", "a4")
      |> card.paper_from_name
      |> result.replace_error("--paper must be a4 or letter"),
    )
    use raw <- result.try(read_secret(parsed))
    use value <- result.try(case args.has(parsed, "hex") {
      True ->
        bytes.from_hex(raw)
        |> result.map(secret.Binary)
        |> result.replace_error("--hex was given but the secret is not valid hex")
      False -> Ok(secret.Text(strip_final_newline(raw)))
    })
    let block = case args.has(parsed, "no-pad") {
      True -> 1
      False -> secret.default_block
    }
    let options = kit.SplitOptions(threshold: k, shares: n, block: block)
    use cards <- result.try(
      kit.split(value, options, random_bytes(kit.randomness_needed(value, options)))
      |> result.map_error(kit.describe_split_error),
    )
    use _ <- result.try(self_test(cards, value))
    let holders = case args.get(parsed, "holders") {
      Ok(list_text) -> string.split(list_text, ",")
      Error(Nil) -> []
    }
    let sheet =
      card.Sheet(
        label: result.unwrap(args.get(parsed, "label"), ""),
        holders: holders,
        created: today(),
        recovery_url: text_setting(parsed, "recovery-url", "HEIRLOOM_RECOVERY_URL", default_recovery_url),
        paper: paper,
        ecl: ecl,
      )
    case args.has(parsed, "text") {
      True -> {
        print_text_cards(cards, sheet)
        Ok(Nil)
      }
      False -> {
        let out = result.unwrap(args.get(parsed, "out"), "cards.html")
        use _ <- result.try(write_file(out, card.sheet_html(cards, sheet)))
        let assert [first, ..] = cards
        let qr_info = case qr.encode(share.to_compact(first), ecl) {
          Ok(code) ->
            "QR version " <> int.to_string(code.version) <> "-" <> tables.ecl_name(code.ecl)
          Error(_) -> "no QR (too long)"
        }
        note(
          green("✓ ")
          <> bold(int.to_string(n) <> " cards")
          <> " written to "
          <> bold(out)
          <> dim(" · any " <> int.to_string(k) <> " recover · set " <> share.fingerprint(first) <> " · " <> qr_info),
        )
        note(dim("  self-test passed: the cards recombine to your secret."))
        note(yellow("  Print it, then delete " <> out <> " — it holds every share."))
        Ok(Nil)
      }
    }
  }
  case outcome {
    Ok(Nil) -> Nil
    Error(message) -> fail(message)
  }
}

fn read_secret(parsed: args.Parsed) -> Result(String, String) {
  case args.get(parsed, "secret-file") {
    Ok(path) -> read_file(path)
    Error(Nil) -> {
      case stdin_is_tty() {
        True ->
          note(dim(
            "Type or paste the secret, then press Ctrl+D (Windows: Ctrl+Z, Enter).",
          ))
        False -> Nil
      }
      read_stdin()
    }
  }
}

/// Typed or piped secrets end with the newline of the last line; that newline
/// is not part of the secret.
fn strip_final_newline(text: String) -> String {
  case string.ends_with(text, "\r\n"), string.ends_with(text, "\n") {
    True, _ -> string.drop_end(text, 2)
    _, True -> string.drop_end(text, 1)
    _, _ -> text
  }
}

/// Recombines the first and the last k cards before anything is written.
fn self_test(cards: List(share.Share), value: secret.Secret) -> Result(Nil, String) {
  let assert [first, ..] = cards
  let k = first.threshold
  let subsets = [list.take(cards, k), list.drop(cards, list.length(cards) - k)]
  case
    list.all(subsets, fn(subset) {
      case kit.recover(list.map(subset, share.to_compact)) {
        Ok(recovery) -> recovery.secret == value
        Error(_) -> False
      }
    })
  {
    True -> Ok(Nil)
    False -> Error("internal self-test failed: cards did not recombine; nothing was written")
  }
}

fn print_text_cards(cards: List(share.Share), sheet: card.Sheet) -> Nil {
  list.each(cards, fn(c) {
    let holder = case list.drop(sheet.holders, c.index - 1) {
      [name, ..] -> " · kept by " <> string.trim(name)
      [] -> ""
    }
    io.println(
      bold("Card " <> int.to_string(c.index) <> " of " <> int.to_string(c.total))
      <> dim(" · any " <> int.to_string(c.threshold) <> " recover · set " <> share.fingerprint(c) <> holder),
    )
    io.println(share.to_compact(c))
    list.each(share.to_rows(c), fn(row) { io.println("  " <> row) })
    io.println("")
  })
}

// --- combine / verify ------------------------------------------------------

/// Reads card texts from the given files (or stdin) and splits them into
/// individual cards: blank lines separate cards, and every `HL1:` line is a
/// card of its own.
fn read_cards(paths: List(String)) -> Result(List(String), String) {
  let sources = case paths {
    [] -> [read_stdin()]
    _ ->
      list.map(paths, fn(path) {
        case path {
          "-" -> read_stdin()
          _ -> read_file(path)
        }
      })
  }
  use texts <- result.try(result.all(sources))
  Ok(list.flat_map(texts, kit.split_card_text))
}

fn combine(arguments: List(String)) -> Nil {
  let outcome = {
    use parsed <- result.try(args.parse(arguments, [Switch("hex", "")]) |> result.map_error(args.describe))
    use texts <- result.try(read_cards(parsed.positional))
    use recovery <- result.try(kit.recover(texts) |> result.map_error(kit.describe_recover_error))
    let output = case recovery.secret, args.has(parsed, "hex") {
      secret.Text(text), False -> text
      value, _ -> bytes.to_hex(secret.to_bytes(value))
    }
    io.println(output)
    let used = recovery.used |> list.map(fn(x) { "#" <> int.to_string(x) }) |> string.join(" ")
    note(
      green("✓ recovered")
      <> dim(" · set " <> recovery.fingerprint <> " · cards " <> used),
    )
    case recovery.suspicious {
      [] -> Nil
      bad ->
        note(yellow(
          "! ignored inconsistent card(s): "
          <> string.join(list.map(bad, fn(x) { "#" <> int.to_string(x) }), " ")
          <> " — they may be damaged or forged",
        ))
    }
    Ok(Nil)
  }
  case outcome {
    Ok(Nil) -> Nil
    Error(message) -> fail(message)
  }
}

fn verify(arguments: List(String)) -> Nil {
  let outcome = {
    use parsed <- result.try(args.parse(arguments, []) |> result.map_error(args.describe))
    use texts <- result.try(read_cards(parsed.positional))
    let results = list.map(texts, share.parse)
    list.index_map(results, fn(r, i) {
      let position = "card " <> int.to_string(i + 1) <> ": "
      case r {
        Ok(c) ->
          io.println(
            green("✓ ") <> position <> "#" <> int.to_string(c.index) <> " of "
            <> int.to_string(c.total) <> dim(" · set " <> share.fingerprint(c)
            <> " · needs " <> int.to_string(c.threshold)),
          )
        Error(e) -> io.println(red("✗ ") <> position <> share.describe_error(e))
      }
    })
    let good = result.values(results)
    case list.length(good) == list.length(results), good {
      True, [first, ..] -> {
        let have = list.length(good)
        case have >= first.threshold, kit.recover(texts) {
          True, Ok(recovery) if recovery.suspicious == [] ->
            io.println(dim(
              "  " <> int.to_string(have) <> " cards — enough to recover, and mutually consistent.",
            ))
          True, Ok(recovery) ->
            io.println(yellow(
              "  inconsistent card(s): "
              <> string.join(list.map(recovery.suspicious, fn(x) { "#" <> int.to_string(x) }), " "),
            ))
          True, Error(e) -> io.println(yellow("  " <> kit.describe_recover_error(e)))
          False, _ ->
            io.println(dim(
              "  " <> int.to_string(have) <> " of " <> int.to_string(first.threshold)
              <> " cards needed — readable, not yet enough to recover.",
            ))
        }
        Ok(Nil)
      }
      _, _ -> Error("some cards could not be read")
    }
  }
  case outcome {
    Ok(Nil) -> Nil
    Error(message) -> fail(message)
  }
}

// --- qr ---------------------------------------------------------------------

fn draw_qr(arguments: List(String)) -> Nil {
  let specs = [Switch("svg", ""), Valued("out", "o"), Valued("ecl", "")]
  let outcome = {
    use parsed <- result.try(args.parse(arguments, specs) |> result.map_error(args.describe))
    use text <- result.try(case parsed.positional {
      [] -> Error("qr needs the text to encode")
      words -> Ok(string.join(words, " "))
    })
    use ecl <- result.try(
      text_setting(parsed, "ecl", "HEIRLOOM_QR_LEVEL", "M")
      |> tables.ecl_from_name
      |> result.replace_error("--ecl must be one of L, M, Q, H"),
    )
    use code <- result.try(qr.encode(text, ecl) |> result.replace_error("text too long for a QR code"))
    let document = svg.to_svg(code, svg.default_style, 320)
    case args.get(parsed, "out"), args.has(parsed, "svg") {
      Ok(path), _ -> write_file(path, document)
      Error(Nil), True -> Ok(io.println(document))
      Error(Nil), False -> {
        io.println(terminal(code))
        note(dim(
          "version " <> int.to_string(code.version) <> "-" <> tables.ecl_name(code.ecl)
          <> " · " <> int.to_string(code.size) <> "×" <> int.to_string(code.size)
          <> " · mask " <> int.to_string(code.mask) <> " · " <> segment_name(code),
        ))
        Ok(Nil)
      }
    }
  }
  case outcome {
    Ok(Nil) -> Nil
    Error(message) -> fail(message)
  }
}

fn segment_name(code: qr.QrCode) -> String {
  segment.mode_name(code.mode) <> " mode"
}

/// Renders with half-block characters, two module rows per text line. Light
/// modules are drawn, so it scans on the usual dark terminal background.
pub fn terminal(code: qr.QrCode) -> String {
  let quiet = 2
  let width = code.size + 2 * quiet
  let blank = list.repeat(False, width)
  let padded =
    list.flatten([
      list.repeat(blank, quiet),
      list.map(code.modules, fn(row) {
        list.flatten([list.repeat(False, quiet), row, list.repeat(False, quiet)])
      }),
      list.repeat(blank, quiet + 1),
    ])
  padded
  |> list.sized_chunk(2)
  |> list.map(fn(pair) {
    case pair {
      [top, bottom] ->
        list.map2(top, bottom, fn(t, b) {
          case t, b {
            False, False -> "█"
            False, True -> "▀"
            True, False -> "▄"
            True, True -> " "
          }
        })
        |> string.concat
      _ -> ""
    }
  })
  |> list.filter(fn(line) { line != "" })
  |> string.join("\n")
}
