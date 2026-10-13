//// Printable cards: one self-contained HTML document with a distribution
//// sheet (no secret material) followed by one card per share.

import gleam/int
import gleam/list
import gleam/string
import heirloom/qr
import heirloom/qr/svg
import heirloom/qr/tables.{type Ecl}
import heirloom/share.{type Share}

pub type Paper {
  A4
  Letter
}

pub type Sheet {
  Sheet(
    label: String,
    holders: List(String),
    created: String,
    recovery_url: String,
    paper: Paper,
    ecl: Ecl,
  )
}

pub fn paper_from_name(name: String) -> Result(Paper, Nil) {
  case string.lowercase(name) {
    "a4" -> Ok(A4)
    "letter" -> Ok(Letter)
    _ -> Error(Nil)
  }
}

pub fn escape(text: String) -> String {
  text
  |> string.replace("&", "&amp;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
  |> string.replace("\"", "&quot;")
  |> string.replace("'", "&#39;")
}

fn holder(sheet: Sheet, index: Int) -> String {
  case list.drop(sheet.holders, index - 1) {
    [name, ..] -> string.trim(name)
    [] -> ""
  }
}

/// The QR symbol for a card, as inline SVG.
pub fn qr_svg(card: Share, ecl: Ecl) -> String {
  case qr.encode(share.to_compact(card), ecl) {
    Ok(code) ->
      svg.to_svg(code, svg.Style("#14161c", "#ffffff", 4), 220)
      |> string.replace(
        "width=\"220\" height=\"220\"",
        "class=\"qr-svg\" role=\"img\" aria-label=\"QR code of this card\"",
      )
    Error(qr.DataTooLong) ->
      "<p class=\"qr-missing\">Secret too long for a QR code — use the rows below.</p>"
  }
}

pub fn card_html(card: Share, sheet: Sheet) -> String {
  let k = int.to_string(card.threshold)
  let n = int.to_string(card.total)
  let i = int.to_string(card.index)
  let kept_by = case holder(sheet, card.index) {
    "" -> "<span class=\"blank\"></span>"
    name -> escape(name)
  }
  let label_row = case string.trim(sheet.label) {
    "" -> ""
    label -> "<dt>For</dt><dd>" <> escape(label) <> "</dd>"
  }
  let rows =
    share.to_rows(card)
    |> list.map(fn(row) {
      let number = string.slice(row, 0, 2)
      let check = string.slice(row, string.length(row) - 1, 1)
      let body = string.slice(row, 4, string.length(row) - 7)
      "<span class=\"n\">"
      <> number
      <> "</span>"
      <> body
      <> "<span class=\"c\">"
      <> check
      <> "</span>"
    })
    |> string.join("\n")
  string.concat([
    "<section class=\"card\" aria-label=\"Card ",
    i,
    " of ",
    n,
    "\">",
    "<header><span class=\"brand\"><svg viewBox=\"0 0 24 24\" aria-hidden=\"true\"><path d=\"M12 2 3 7v10l9 5 9-5V7z\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.6\"/><path d=\"M12 7v10M7.5 9.5 12 12l4.5-2.5\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.6\"/></svg>heirloom</span>",
    "<span class=\"seq\">Card <b>",
    i,
    "</b> of ",
    n,
    "</span></header>",
    "<div class=\"body\"><div class=\"qr\">",
    qr_svg(card, sheet.ecl),
    "</div>",
    "<div class=\"meta\"><p class=\"rule\">Any <b>",
    k,
    "</b> of the <b>",
    n,
    "</b> cards recover the secret.<br><span>This card alone reveals nothing.</span></p>",
    "<dl>",
    label_row,
    "<dt>Kept by</dt><dd>",
    kept_by,
    "</dd>",
    "<dt>Set</dt><dd class=\"mono\">",
    share.fingerprint(card),
    "</dd>",
    "<dt>Created</dt><dd>",
    escape(sheet.created),
    "</dd></dl></div></div>",
    "<pre class=\"rows\" aria-label=\"Card text\">",
    rows,
    "</pre>",
    "<footer>Recover: scan or type this card at <b>",
    escape(sheet.recovery_url),
    "</b> (runs offline) or <code>heirloom combine</code>. ",
    "The last symbol of each row is a check — it pinpoints typos.</footer>",
    "</section>",
  ])
}

fn distribution_html(cards: List(Share), sheet: Sheet) -> String {
  let assert [first, ..] = cards
  let k = int.to_string(first.threshold)
  let n = int.to_string(first.total)
  let rows =
    cards
    |> list.map(fn(card) {
      let name = case holder(sheet, card.index) {
        "" -> "<span class=\"blank\"></span>"
        name -> escape(name)
      }
      "<tr><td>#"
      <> int.to_string(card.index)
      <> "</td><td>"
      <> name
      <> "</td><td class=\"blank-cell\"></td></tr>"
    })
    |> string.concat
  let label = case string.trim(sheet.label) {
    "" -> ""
    label -> "<p class=\"for\">For: <b>" <> escape(label) <> "</b></p>"
  }
  string.concat([
    "<section class=\"cover\"><p class=\"eyebrow\">Distribution sheet · contains no secret material</p>",
    "<h1>Set <span class=\"mono\">",
    share.fingerprint(first),
    "</span></h1>",
    label,
    "<p class=\"lead\">",
    n,
    " cards were made. Any <b>",
    k,
    "</b> of them recover the secret; ",
    int.to_string(first.threshold - 1),
    " or fewer reveal nothing at all — not even its length.</p>",
    "<table><thead><tr><th>Card</th><th>Holder</th><th>Handed over (date · signature)</th></tr></thead><tbody>",
    rows,
    "</tbody></table>",
    "<ol class=\"steps\"><li>Cut out each card and give it to a different person or place.</li>",
    "<li>Tell holders what the card is for and who else holds one — never put two cards in the same drawer.</li>",
    "<li>Destroy this printout's digital file (and your printer queue) once the cards are handed out.</li>",
    "<li>To recover, collect ",
    k,
    " cards and open <b>",
    escape(sheet.recovery_url),
    "</b> — it works offline — or run <code>heirloom combine</code>.</li></ol>",
    "</section>",
  ])
}

pub fn sheet_html(cards: List(Share), sheet: Sheet) -> String {
  let page = case sheet.paper {
    A4 -> "A4"
    Letter -> "letter"
  }
  let cards_html = cards |> list.map(card_html(_, sheet)) |> string.concat
  string.concat([
    "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">",
    "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
    "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'; img-src data:\">",
    "<title>heirloom cards</title><style>@page{size:",
    page,
    ";margin:12mm}",
    stylesheet,
    "</style></head><body>",
    "<div class=\"screen-note\">Print this page (Ctrl/⌘ + P). Each card is cut along the dashed line.</div>",
    distribution_html(cards, sheet),
    cards_html,
    "</body></html>",
  ])
}

/// Card styles, shared with the browser playground's preview.
pub const stylesheet =
  "
:root{--ink:#14161c;--muted:#5d6472;--line:#d9d3c7;--paper:#fffdf8;--brass:#9a7b4f}
*{box-sizing:border-box}
body{margin:0;background:#ece8df;color:var(--ink);font:14px/1.45 'Iowan Old Style','Palatino Linotype',Palatino,Georgia,serif}
.mono,code,pre{font-family:ui-monospace,'Cascadia Mono','SF Mono',Menlo,Consolas,monospace}
.screen-note{max-width:180mm;margin:16px auto 0;padding:10px 14px;border-radius:8px;background:#14161c;color:#f5efe3;font:13px/1.4 system-ui,sans-serif}
.cover,.card{width:180mm;max-width:calc(100% - 24px);margin:16px auto;background:var(--paper);border-radius:4px;box-shadow:0 1px 2px rgba(0,0,0,.06),0 8px 24px rgba(20,22,28,.08)}
.cover{padding:14mm 14mm 10mm}
.eyebrow{margin:0 0 4px;font:600 11px/1 system-ui,sans-serif;letter-spacing:.12em;text-transform:uppercase;color:var(--brass)}
.cover h1{margin:0 0 6px;font-weight:600;font-size:30px;letter-spacing:-.01em}
.for{margin:0 0 10px;color:var(--muted)}
.lead{font-size:16px;margin:0 0 14px}
table{width:100%;border-collapse:collapse;margin:8px 0 14px;font-size:13px}
th{text-align:left;font:600 11px/1 system-ui,sans-serif;letter-spacing:.06em;text-transform:uppercase;color:var(--muted);padding:6px 4px;border-bottom:1.5px solid var(--ink)}
td{padding:9px 4px;border-bottom:1px solid var(--line)}
td.blank-cell{width:45%}
.blank{display:inline-block;min-width:44mm;border-bottom:1px solid var(--ink);height:1em}
.steps{padding-left:18px;margin:0;color:#2b2f38}
.steps li{margin:3px 0}
.card{padding:7mm 8mm 6mm;border:1px dashed #b9b2a4;page-break-inside:avoid;break-inside:avoid}
.card header{display:flex;justify-content:space-between;align-items:center;border-bottom:1.5px solid var(--ink);padding-bottom:5px;margin-bottom:6mm}
.brand{display:inline-flex;align-items:center;gap:6px;font-weight:600;font-size:17px;letter-spacing:.01em}
.brand svg{width:18px;height:18px;color:var(--brass)}
.seq{font:600 12px/1 system-ui,sans-serif;letter-spacing:.08em;text-transform:uppercase}
.seq b{font-size:15px}
.body{display:flex;gap:7mm;align-items:flex-start}
.qr{flex:0 0 52mm}
.qr-svg{width:52mm;height:52mm;display:block}
.qr-missing{font-size:12px;color:var(--muted)}
.meta{flex:1;min-width:0}
.rule{margin:0 0 4mm;font-size:17px;line-height:1.35}
.rule span{font-size:13px;color:var(--muted)}
dl{display:grid;grid-template-columns:max-content 1fr;gap:5px 12px;margin:0;font-size:13px}
dt{font:600 10.5px/1.7 system-ui,sans-serif;letter-spacing:.08em;text-transform:uppercase;color:var(--muted)}
dd{margin:0;overflow-wrap:anywhere}
.rows{margin:6mm 0 4mm;padding:4mm 5mm;background:#f6f2e9;border-radius:3px;font-size:12.5px;line-height:1.75;letter-spacing:.06em;white-space:pre;overflow-x:auto}
.rows .n{color:var(--muted);margin-right:2.2em}
.rows .c{color:var(--brass);font-weight:700;margin-left:2.2em}
.card footer{font:11px/1.45 system-ui,sans-serif;color:var(--muted)}
.card footer code{font-size:10.5px}
@media (max-width:640px){.body{flex-direction:column}.qr{flex-basis:auto;width:60%}.qr-svg{width:100%;height:auto}}
@media print{body{background:#fff}.screen-note{display:none}.cover,.card{box-shadow:none;margin:0 auto 8mm;max-width:none}.cover{page-break-after:always;break-after:page}.rows{background:#fff;border:1px solid var(--line)}}
"
