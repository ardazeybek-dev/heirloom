//// One printed card's worth of data, and its two text forms.
////
//// Binary layout (version 1):
////
////     0      version        = 1
////     1..4   set id         random; ties the cards of one split together
////     5      threshold k
////     6      index x        1..255, the share's x coordinate
////     7      total n        informational ("card 2 of 5")
////     8..    y values       one per plaintext byte
////     last 4 CRC-32 of everything before it
////
//// Text forms:
////
//// - **compact** — `HL1:` + Crockford Base32. Used inside the QR code; every
////   character is in the QR alphanumeric set.
//// - **rows** — the Base32 split into numbered rows of 6 × 4 symbols, each
////   ending in a check symbol, for typing in by hand:
////
////       01  7KQ2 M9X4 ABCD EFGH JKMN PQRS  W
////       02  ...

import gleam/int
import gleam/list
import gleam/result
import gleam/string
import heirloom/base32
import heirloom/bytes
import heirloom/crc32
import heirloom/shamir

pub const version = 1

pub const prefix = "HL1:"

const group_size = 4

const groups_per_row = 6

pub type Share {
  Share(
    set_id: List(Int),
    threshold: Int,
    index: Int,
    total: Int,
    ys: List(Int),
  )
}

pub type ParseError {
  Empty
  BadCharacter(character: String, row: Int)
  RowTypo(row: Int)
  RowOutOfOrder(expected: Int, found: Int)
  ChecksumMismatch
  UnsupportedVersion(Int)
  TooShort
  InvalidHeader(reason: String)
}

pub fn to_point(share: Share) -> shamir.Point {
  shamir.Point(share.index, share.ys)
}

pub fn set_id_text(share: Share) -> String {
  base32.encode(share.set_id)
}

pub fn to_bytes(share: Share) -> List(Int) {
  let body =
    list.flatten([
      [version],
      share.set_id,
      [share.threshold, share.index, share.total],
      share.ys,
    ])
  list.append(body, crc32.to_bytes(crc32.checksum(body)))
}

pub fn from_bytes(data: List(Int)) -> Result(Share, ParseError) {
  let length = list.length(data)
  use <- guard(length < 13, TooShort)
  let body = list.take(data, length - 4)
  let crc = list.drop(data, length - 4)
  use <- guard(crc32.to_bytes(crc32.checksum(body)) != crc, ChecksumMismatch)
  case body {
    [v, ..] if v != version -> Error(UnsupportedVersion(v))
    [_, a, b, c, d, k, x, n, ..ys] -> {
      use <- guard(k < 2, InvalidHeader("threshold below 2"))
      use <- guard(x < 1, InvalidHeader("card index 0"))
      use <- guard(n < k, InvalidHeader("fewer cards than the threshold"))
      use <- guard(x > n, InvalidHeader("card index above the card count"))
      Ok(Share([a, b, c, d], k, x, n, ys))
    }
    _ -> Error(TooShort)
  }
}

fn guard(
  condition: Bool,
  error: e,
  next: fn() -> Result(a, e),
) -> Result(a, e) {
  case condition {
    True -> Error(error)
    False -> next()
  }
}

pub fn to_compact(share: Share) -> String {
  prefix <> base32.encode(to_bytes(share))
}

/// Numbered rows with check symbols, for printing.
pub fn to_rows(share: Share) -> List(String) {
  share
  |> to_bytes
  |> base32.encode
  |> string.to_graphemes
  |> list.sized_chunk(group_size * groups_per_row)
  |> list.index_map(fn(symbols, i) {
    let row = string.concat(symbols)
    let groups =
      symbols
      |> list.sized_chunk(group_size)
      |> list.map(string.concat)
      |> string.join(" ")
    let number = int.to_string(i + 1) |> string.pad_start(2, "0")
    number <> "  " <> groups <> "  " <> base32.row_check(row)
  })
}

/// Parses any text form: compact (`HL1:...`), numbered rows, or bare Base32.
/// Row check symbols, when present, are verified before the CRC so a typo is
/// reported with its row number.
pub fn parse(text: String) -> Result(Share, ParseError) {
  let trimmed = string.trim(text)
  case string.split_once(trimmed, prefix), string.split_once(trimmed, "hl1:") {
    _, _ if trimmed == "" -> Error(Empty)
    Ok(#(_, compact)), _ | _, Ok(#(_, compact)) -> parse_symbols(compact, 0)
    _, _ -> {
      let lines =
        trimmed
        |> string.replace("\r", "")
        |> string.split("\n")
        |> list.map(string.trim)
        |> list.filter(fn(l) { l != "" })
      case list.all(lines, is_row) {
        True -> parse_rows(lines)
        False -> parse_symbols(string.join(lines, ""), 0)
      }
    }
  }
}

fn tokens(line: String) -> List(String) {
  line
  |> string.replace("\t", " ")
  |> string.split(" ")
  |> list.filter(fn(t) { t != "" })
}

fn is_row(line: String) -> Bool {
  case tokens(line) {
    [number, _, _, ..] ->
      string.length(number) == 2 && result.is_ok(int.parse(number))
    _ -> False
  }
}

fn parse_rows(lines: List(String)) -> Result(Share, ParseError) {
  lines
  |> list.index_map(fn(line, i) { #(line, i + 1) })
  |> list.try_map(fn(pair) {
    let #(line, expected) = pair
    let assert [number, ..rest] = tokens(line)
    let assert Ok(found) = int.parse(number)
    let assert Ok(check) = list.last(rest)
    let row = rest |> list.take(list.length(rest) - 1) |> string.concat
    case found == expected, base32.row_check_matches(row, check) {
      False, _ -> Error(RowOutOfOrder(expected, found))
      True, False ->
        case base32.decode(row) {
          Error(base32.InvalidCharacter(c, _)) -> Error(BadCharacter(c, found))
          Ok(_) -> Error(RowTypo(found))
        }
      True, True -> Ok(row)
    }
  })
  |> result.try(fn(rows) { parse_symbols(string.concat(rows), 0) })
}

fn parse_symbols(symbols: String, row: Int) -> Result(Share, ParseError) {
  case base32.decode(symbols) {
    Error(base32.InvalidCharacter(c, _)) -> Error(BadCharacter(c, row))
    Ok(data) -> from_bytes(data)
  }
}

pub fn describe_error(error: ParseError) -> String {
  case error {
    Empty -> "the card text is empty"
    BadCharacter(c, 0) -> "unexpected character '" <> c <> "'"
    BadCharacter(c, row) ->
      "unexpected character '" <> c <> "' in row " <> int.to_string(row)
    RowTypo(row) ->
      "row "
      <> int.to_string(row)
      <> " does not match its check symbol — look for a mistyped character"
    RowOutOfOrder(expected, found) ->
      "expected row "
      <> int.to_string(expected)
      <> " but found row "
      <> int.to_string(found)
    ChecksumMismatch ->
      "checksum mismatch — the card is damaged or was copied incorrectly"
    UnsupportedVersion(v) ->
      "card format version "
      <> int.to_string(v)
      <> " is newer than this tool understands"
    TooShort -> "the card text is too short — is part of it missing?"
    InvalidHeader(reason) -> "invalid card header: " <> reason
  }
}

/// Fingerprint shown on every card so holders can tell sets apart.
pub fn fingerprint(share: Share) -> String {
  let id = set_id_text(share)
  string.slice(id, 0, 4) <> "-" <> string.slice(id, 4, 3)
}

/// Exposed for tests and the playground.
pub fn bytes_hex(share: Share) -> String {
  bytes.to_hex(to_bytes(share))
}
