//// Capacity tables from ISO/IEC 18004:2015, Table 9, for versions 1–40.

import gleam/int
import gleam/list

pub type Ecl {
  /// ~7 % of codewords can be restored.
  Low
  /// ~15 %.
  Medium
  /// ~25 %.
  Quartile
  /// ~30 %.
  High
}

/// The two format-information bits of each level (note: not in order).
pub fn format_bits(ecl: Ecl) -> Int {
  case ecl {
    Low -> 1
    Medium -> 0
    Quartile -> 3
    High -> 2
  }
}

pub fn ecl_name(ecl: Ecl) -> String {
  case ecl {
    Low -> "L"
    Medium -> "M"
    Quartile -> "Q"
    High -> "H"
  }
}

pub fn ecl_from_name(name: String) -> Result(Ecl, Nil) {
  case name {
    "L" | "l" -> Ok(Low)
    "M" | "m" -> Ok(Medium)
    "Q" | "q" -> Ok(Quartile)
    "H" | "h" -> Ok(High)
    _ -> Error(Nil)
  }
}

// Error-correction codewords per block, indexed by version 1..40.
const ecc_per_block_low = [
  7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28,
  28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30,
]

const ecc_per_block_medium = [
  10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26,
  26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28,
]

const ecc_per_block_quartile = [
  13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30,
  28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30,
]

const ecc_per_block_high = [
  17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28,
  30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30,
]

// Number of error-correction blocks, indexed by version 1..40.
const blocks_low = [
  1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, 10, 12,
  12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25,
]

const blocks_medium = [
  1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18,
  20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49,
]

const blocks_quartile = [
  1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20, 23, 23,
  25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68,
]

const blocks_high = [
  1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25, 25, 34,
  30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81,
]

fn nth(items: List(Int), version: Int) -> Int {
  case list.drop(items, version - 1) {
    [x, ..] -> x
    [] -> 0
  }
}

pub fn ecc_per_block(version: Int, ecl: Ecl) -> Int {
  case ecl {
    Low -> nth(ecc_per_block_low, version)
    Medium -> nth(ecc_per_block_medium, version)
    Quartile -> nth(ecc_per_block_quartile, version)
    High -> nth(ecc_per_block_high, version)
  }
}

pub fn block_count(version: Int, ecl: Ecl) -> Int {
  case ecl {
    Low -> nth(blocks_low, version)
    Medium -> nth(blocks_medium, version)
    Quartile -> nth(blocks_quartile, version)
    High -> nth(blocks_high, version)
  }
}

pub fn size(version: Int) -> Int {
  version * 4 + 17
}

/// Modules left for data + ECC once every function pattern is placed
/// (finders, separators, timing, alignment, format and version info).
pub fn raw_data_modules(version: Int) -> Int {
  let base = { 16 * version + 128 } * version + 64
  case version >= 2 {
    False -> base
    True -> {
      let align = version / 7 + 2
      let base = base - { { 25 * align - 10 } * align - 55 }
      case version >= 7 {
        True -> base - 36
        False -> base
      }
    }
  }
}

pub fn total_codewords(version: Int) -> Int {
  raw_data_modules(version) / 8
}

pub fn data_codewords(version: Int, ecl: Ecl) -> Int {
  total_codewords(version)
  - ecc_per_block(version, ecl)
  * block_count(version, ecl)
}

/// Centre coordinates of the alignment patterns along one axis.
pub fn alignment_positions(version: Int) -> List(Int) {
  case version {
    1 -> []
    _ -> {
      let count = version / 7 + 2
      let step = { version * 8 + count * 3 + 5 } / { count * 4 - 4 } * 2
      let last = size(version) - 7
      let tail =
        int.range(from: 0, to: count - 1, with: [], run: fn(acc, i) {
          [last - i * step, ..acc]
        })
      [6, ..tail]
    }
  }
}
