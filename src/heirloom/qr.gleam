//// A from-scratch QR Code (ISO/IEC 18004) encoder, model 2, versions 1–40.
////
//// Pipeline: text → segment bits → data codewords → split into blocks →
//// Reed–Solomon ECC per block → interleave → place on the grid → try all
//// eight masks → keep the one with the lowest penalty.

import gleam/int
import gleam/list
import heirloom/qr/matrix
import heirloom/qr/reed_solomon
import heirloom/qr/segment
import heirloom/qr/tables.{type Ecl, High, Low, Medium, Quartile}

pub type QrCode {
  QrCode(
    version: Int,
    size: Int,
    ecl: Ecl,
    mask: Int,
    mode: segment.Mode,
    /// Rows of modules, True = dark. No quiet zone included.
    modules: List(List(Bool)),
  )
}

pub type QrError {
  /// The text does not fit in a version-40 symbol at this level.
  DataTooLong
}

/// Encodes `text` with at least error-correction level `min_ecl`, using the
/// smallest version that fits. When the chosen version has room to spare the
/// level is raised for free (as long as the version stays the same).
pub fn encode(text: String, min_ecl: Ecl) -> Result(QrCode, QrError) {
  let segment = segment.make(text)
  case smallest_version(segment, min_ecl, 1) {
    Error(Nil) -> Error(DataTooLong)
    Ok(version) -> {
      let ecl = boost(segment, version, min_ecl)
      Ok(build(segment, version, ecl))
    }
  }
}

fn fits(segment: segment.Segment, version: Int, ecl: Ecl) -> Bool {
  case segment.bit_length(segment, version) {
    Ok(bits) -> bits <= tables.data_codewords(version, ecl) * 8
    Error(Nil) -> False
  }
}

fn smallest_version(
  segment: segment.Segment,
  ecl: Ecl,
  version: Int,
) -> Result(Int, Nil) {
  case version > 40, fits(segment, version, ecl) {
    True, _ -> Error(Nil)
    _, True -> Ok(version)
    _, False -> smallest_version(segment, ecl, version + 1)
  }
}

fn boost(segment: segment.Segment, version: Int, ecl: Ecl) -> Ecl {
  let order = [Low, Medium, Quartile, High]
  order
  |> list.drop_while(fn(e) { e != ecl })
  |> list.filter(fits(segment, version, _))
  |> list.last
  |> fn(r) {
    case r {
      Ok(e) -> e
      Error(Nil) -> ecl
    }
  }
}

fn build(segment: segment.Segment, version: Int, ecl: Ecl) -> QrCode {
  let data =
    segment.to_codewords(segment, version, tables.data_codewords(version, ecl))
  let codewords = add_ecc_and_interleave(data, version, ecl)
  let grid = matrix.place(matrix.function_patterns(version), codewords)
  let #(mask, modules, _) =
    int.range(from: 0, to: 8, with: #(-1, [], -1), run: fn(best, mask) {
      let rows = matrix.render(grid, ecl, mask)
      let score = matrix.penalty(rows)
      case best.2 < 0 || score < best.2 {
        True -> #(mask, rows, score)
        False -> best
      }
    })
  QrCode(
    version: version,
    size: tables.size(version),
    ecl: ecl,
    mask: mask,
    mode: segment.mode,
    modules: modules,
  )
}

/// Splits data into blocks (short blocks first), appends each block's ECC
/// and interleaves: first byte of every block, second byte of every block…,
/// then the ECC bytes the same way.
pub fn add_ecc_and_interleave(
  data: List(Int),
  version: Int,
  ecl: Ecl,
) -> List(Int) {
  let blocks = tables.block_count(version, ecl)
  let ecc_length = tables.ecc_per_block(version, ecl)
  let total = tables.total_codewords(version)
  let short_blocks = blocks - total % blocks
  let short_data = total / blocks - ecc_length
  let #(data_blocks, _) =
    int.range(from: 0, to: blocks, with: #([], data), run: fn(acc, i) {
      let #(done, rest) = acc
      let length = case i < short_blocks {
        True -> short_data
        False -> short_data + 1
      }
      #([list.take(rest, length), ..done], list.drop(rest, length))
    })
  let data_blocks = list.reverse(data_blocks)
  let ecc_blocks = list.map(data_blocks, reed_solomon.remainder(_, ecc_length))
  list.append(interleave(data_blocks), interleave(ecc_blocks))
}

fn interleave(blocks: List(List(Int))) -> List(Int) {
  case list.all(blocks, list.is_empty) {
    True -> []
    False -> {
      let heads = list.filter_map(blocks, list.first)
      let tails =
        list.map(blocks, fn(b) {
          case b {
            [_, ..rest] -> rest
            [] -> []
          }
        })
      list.append(heads, interleave(tails))
    }
  }
}
