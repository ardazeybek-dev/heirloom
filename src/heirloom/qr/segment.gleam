//// Turning text into the QR data bit stream.
////
//// Two modes are supported:
//// - **alphanumeric** — `0-9 A-Z space $ % * + - . / :`, two characters per
////   11 bits. Every heirloom share is pure alphanumeric.
//// - **byte** — UTF-8, eight bits per byte, for anything else.

import gleam/int
import gleam/list
import gleam/string
import heirloom/bytes

pub const alphanumeric_charset = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:"

pub type Mode {
  Alphanumeric
  Byte
}

/// A bit stream, most significant bit first.
pub type Bits =
  List(Bool)

pub type Segment {
  Segment(mode: Mode, count: Int, data: Bits)
}

pub fn mode_name(mode: Mode) -> String {
  case mode {
    Alphanumeric -> "alphanumeric"
    Byte -> "byte"
  }
}

/// `value` as `width` bits, most significant first.
pub fn int_bits(value: Int, width: Int) -> Bits {
  int.range(from: width - 1, to: -1, with: [], run: fn(acc, i) {
    [int.bitwise_and(int.bitwise_shift_right(value, i), 1) == 1, ..acc]
  })
  |> list.reverse
}

pub fn make(text: String) -> Segment {
  let chars = string.to_graphemes(text)
  let alnum = string.to_graphemes(alphanumeric_charset)
  case list.all(chars, list.contains(alnum, _)) {
    True -> alphanumeric(chars, alnum)
    False -> byte(bytes.from_string(text))
  }
}

fn alphanumeric(chars: List(String), alnum: List(String)) -> Segment {
  let values = list.map(chars, fn(c) { index_of(alnum, c, 0) })
  let data =
    values
    |> list.sized_chunk(2)
    |> list.flat_map(fn(pair) {
      case pair {
        [a, b] -> int_bits(a * 45 + b, 11)
        [a] -> int_bits(a, 6)
        _ -> []
      }
    })
  Segment(Alphanumeric, list.length(chars), data)
}

fn byte(data: List(Int)) -> Segment {
  Segment(Byte, list.length(data), list.flat_map(data, int_bits(_, 8)))
}

fn index_of(items: List(String), target: String, i: Int) -> Int {
  case items {
    [] -> 0
    [x, ..] if x == target -> i
    [_, ..rest] -> index_of(rest, target, i + 1)
  }
}

fn mode_indicator(mode: Mode) -> Int {
  case mode {
    Alphanumeric -> 0b0010
    Byte -> 0b0100
  }
}

/// Width of the character-count field, which grows with the version.
pub fn count_bits(mode: Mode, version: Int) -> Int {
  case mode, version {
    Alphanumeric, v if v <= 9 -> 9
    Alphanumeric, v if v <= 26 -> 11
    Alphanumeric, _ -> 13
    Byte, v if v <= 9 -> 8
    Byte, _ -> 16
  }
}

/// Total bits the segment occupies at `version` (header included), or an
/// error when its character count overflows the count field.
pub fn bit_length(segment: Segment, version: Int) -> Result(Int, Nil) {
  let width = count_bits(segment.mode, version)
  case segment.count >= int.bitwise_shift_left(1, width) {
    True -> Error(Nil)
    False -> Ok(4 + width + list.length(segment.data))
  }
}

/// Header, payload, terminator, byte alignment and 0xEC/0x11 padding, as
/// exactly `capacity` data codewords.
pub fn to_codewords(segment: Segment, version: Int, capacity: Int) -> List(Int) {
  let header =
    list.append(
      int_bits(mode_indicator(segment.mode), 4),
      int_bits(segment.count, count_bits(segment.mode, version)),
    )
  let bits = list.append(header, segment.data)
  let capacity_bits = capacity * 8
  let terminator = int.min(4, capacity_bits - list.length(bits))
  let bits = list.append(bits, list.repeat(False, terminator))
  let align = { 8 - list.length(bits) % 8 } % 8
  let bits = list.append(bits, list.repeat(False, align))
  let codewords =
    bits
    |> list.sized_chunk(8)
    |> list.map(fn(octet) {
      list.fold(octet, 0, fn(acc, bit) {
        acc * 2
        + case bit {
          True -> 1
          False -> 0
        }
      })
    })
  let missing = capacity - list.length(codewords)
  let padding =
    int.range(from: 0, to: missing, with: [], run: fn(acc, i) {
      [
        case i % 2 {
          0 -> 0xEC
          _ -> 0x11
        },
        ..acc
      ]
    })
    |> list.reverse
  list.append(codewords, padding)
}
