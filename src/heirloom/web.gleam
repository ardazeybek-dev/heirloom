//// The API the browser playground calls. Arguments and results are plain
//// strings, ints, bools and records so JavaScript can use them directly;
//// lists cross the boundary as newline-separated text on the way in and as
//// Gleam lists (`.toArray()`) on the way out.

import gleam/int
import gleam/list
import gleam/result
import gleam/string
import heirloom/bytes
import heirloom/card
import heirloom/kit
import heirloom/qr
import heirloom/qr/svg
import heirloom/qr/tables
import heirloom/secret
import heirloom/share

@external(javascript, "../heirloom_ffi.mjs", "random_bytes")
fn random_bytes(count: Int) -> List(Int)

@external(javascript, "../heirloom_ffi.mjs", "today")
fn today() -> String

pub type CardView {
  CardView(
    index: Int,
    total: Int,
    threshold: Int,
    fingerprint: String,
    compact: String,
    rows: String,
    html: String,
  )
}

pub type SplitView {
  SplitView(
    cards: List(CardView),
    sheet_html: String,
    fingerprint: String,
    qr_version: String,
    share_bytes: Int,
  )
}

pub fn split(
  secret_text: String,
  is_hex: Bool,
  threshold: Int,
  shares: Int,
  pad: Bool,
  label: String,
  holders: String,
  ecl_name: String,
  paper_name: String,
  recovery_url: String,
) -> Result(SplitView, String) {
  use value <- result.try(case is_hex {
    True ->
      bytes.from_hex(secret_text)
      |> result.map(secret.Binary)
      |> result.replace_error("That is not valid hex.")
    False -> Ok(secret.Text(secret_text))
  })
  let block = case pad {
    True -> secret.default_block
    False -> 1
  }
  let options = kit.SplitOptions(threshold: threshold, shares: shares, block: block)
  use cards <- result.try(
    kit.split(value, options, random_bytes(kit.randomness_needed(value, options)))
    |> result.map_error(kit.describe_split_error),
  )
  let ecl = result.unwrap(tables.ecl_from_name(ecl_name), tables.Medium)
  let sheet =
    card.Sheet(
      label: label,
      holders: string.split(holders, "\n"),
      created: today(),
      recovery_url: recovery_url,
      paper: result.unwrap(card.paper_from_name(paper_name), card.A4),
      ecl: ecl,
    )
  let assert [first, ..] = cards
  let qr_version = case qr.encode(share.to_compact(first), ecl) {
    Ok(code) -> int.to_string(code.version) <> "-" <> tables.ecl_name(code.ecl)
    Error(_) -> "—"
  }
  Ok(SplitView(
    cards: list.map(cards, fn(c) {
      CardView(
        index: c.index,
        total: c.total,
        threshold: c.threshold,
        fingerprint: share.fingerprint(c),
        compact: share.to_compact(c),
        rows: string.join(share.to_rows(c), "\n"),
        html: card.card_html(c, sheet),
      )
    }),
    sheet_html: card.sheet_html(cards, sheet),
    fingerprint: share.fingerprint(first),
    qr_version: qr_version,
    share_bytes: list.length(share.to_bytes(first)),
  ))
}

pub type CardStatus {
  CardStatus(
    ok: Bool,
    message: String,
    index: Int,
    total: Int,
    threshold: Int,
    fingerprint: String,
  )
}

/// Splits pasted text into cards and checks each one on its own.
pub fn inspect(text: String) -> List(CardStatus) {
  text
  |> kit.split_card_text
  |> list.map(fn(card_text) {
    case share.parse(card_text) {
      Ok(c) ->
        CardStatus(True, "readable", c.index, c.total, c.threshold, share.fingerprint(c))
      Error(e) -> CardStatus(False, share.describe_error(e), 0, 0, 0, "")
    }
  })
}

pub type RecoverView {
  RecoverView(
    is_text: Bool,
    text: String,
    hex: String,
    fingerprint: String,
    threshold: Int,
    total: Int,
    used: List(Int),
    suspicious: List(Int),
    tolerates: Int,
  )
}

pub fn recover(text: String) -> Result(RecoverView, String) {
  text
  |> kit.split_card_text
  |> kit.recover
  |> result.map_error(kit.describe_recover_error)
  |> result.map(fn(r) {
    let data = secret.to_bytes(r.secret)
    let #(is_text, text) = case r.secret {
      secret.Text(t) -> #(True, t)
      secret.Binary(_) -> #(False, "")
    }
    RecoverView(
      is_text: is_text,
      text: text,
      hex: bytes.to_hex(data),
      fingerprint: r.fingerprint,
      threshold: r.threshold,
      total: r.total,
      used: r.used,
      suspicious: r.suspicious,
      tolerates: r.tolerates,
    )
  })
}

pub fn card_stylesheet() -> String {
  card.stylesheet
}

/// Any text as an SVG QR code (used for the page's decorative demo).
pub fn qr_svg(text: String, ecl_name: String, foreground: String) -> Result(String, String) {
  let ecl = result.unwrap(tables.ecl_from_name(ecl_name), tables.Medium)
  qr.encode(text, ecl)
  |> result.replace_error("Too long for a QR code.")
  |> result.map(fn(code) {
    svg.to_svg(code, svg.Style(foreground, "transparent", 0), code.size * 8)
  })
}
