//// Renders a QR symbol as a compact SVG: one `<path>` built from horizontal
//// runs of dark modules, with the mandatory 4-module quiet zone.

import gleam/int
import gleam/list
import gleam/string
import heirloom/qr.{type QrCode}

pub type Style {
  Style(foreground: String, background: String, quiet_zone: Int)
}

pub const default_style = Style("#111111", "#ffffff", 4)

/// Just the path data, in module units with the quiet zone offset applied.
pub fn path_data(code: QrCode, quiet_zone: Int) -> String {
  code.modules
  |> list.index_map(fn(row, y) {
    row
    |> list.index_map(fn(dark, x) { #(x, dark) })
    |> list.chunk(fn(cell) { cell.1 })
    |> list.filter_map(fn(run) {
      case run {
        [#(x, True), ..] ->
          Ok(
            "M"
            <> int.to_string(x + quiet_zone)
            <> " "
            <> int.to_string(y + quiet_zone)
            <> "h"
            <> int.to_string(list.length(run))
            <> "v1h-"
            <> int.to_string(list.length(run))
            <> "z",
          )
        _ -> Error(Nil)
      }
    })
    |> string.concat
  })
  |> string.concat
}

/// A standalone SVG document; `pixels` sets the rendered width and height.
pub fn to_svg(code: QrCode, style: Style, pixels: Int) -> String {
  let span = int.to_string(code.size + 2 * style.quiet_zone)
  let px = int.to_string(pixels)
  string.concat([
    "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 ",
    span,
    " ",
    span,
    "\" width=\"",
    px,
    "\" height=\"",
    px,
    "\" shape-rendering=\"crispEdges\">",
    "<rect width=\"100%\" height=\"100%\" fill=\"",
    style.background,
    "\"/>",
    "<path fill=\"",
    style.foreground,
    "\" d=\"",
    path_data(code, style.quiet_zone),
    "\"/></svg>",
  ])
}
