//// Crockford Base32: digits and upper-case letters without I, L, O and U.
////
//// Chosen for shares that may be typed back in by hand:
//// - no visually ambiguous symbols; on input O is read as 0 and I/L as 1,
//// - case-insensitive, hyphens and spaces ignored,
//// - every symbol is in the QR *alphanumeric* charset, so a share packs into
////   QR at 5.5 bits per character instead of 8.
////
//// `row_check` adds a per-row check symbol (weighted sum mod 37) so a typo
//// is reported as "row 3", not just "somewhere in this card".

import gleam/int
import gleam/list
import gleam/string

pub const alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

/// Crockford's five extra check symbols extend the alphabet to 37 (a prime).
const check_alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ*~$=U"

pub type DecodeError {
  InvalidCharacter(character: String, position: Int)
}

pub fn encode(bytes: List(Int)) -> String {
  let symbols = string.to_graphemes(alphabet)
  encode_loop(bytes, 0, 0, symbols, [])
}

fn encode_loop(
  bytes: List(Int),
  buffer: Int,
  bits: Int,
  symbols: List(String),
  acc: List(String),
) -> String {
  case bits >= 5, bytes {
    True, _ -> {
      let shift = bits - 5
      let value = int.bitwise_and(int.bitwise_shift_right(buffer, shift), 31)
      let rest = int.bitwise_and(buffer, int.bitwise_shift_left(1, shift) - 1)
      encode_loop(bytes, rest, shift, symbols, [at(symbols, value), ..acc])
    }
    False, [byte, ..more] ->
      encode_loop(
        more,
        int.bitwise_or(int.bitwise_shift_left(buffer, 8), byte),
        bits + 8,
        symbols,
        acc,
      )
    False, [] ->
      case bits {
        0 -> acc |> list.reverse |> string.concat
        _ -> {
          let value = int.bitwise_shift_left(buffer, 5 - bits)
          [at(symbols, value), ..acc] |> list.reverse |> string.concat
        }
      }
  }
}

fn at(symbols: List(String), index: Int) -> String {
  case list.drop(symbols, index) {
    [s, ..] -> s
    [] -> "?"
  }
}

/// Maps one input character to its 5-bit value, applying Crockford's
/// forgiving aliases. `Ok(-1)` means "ignore" (separators).
pub fn symbol_value(char: String) -> Result(Int, Nil) {
  case string.uppercase(char) {
    "-" | " " | "\t" -> Ok(-1)
    "O" -> Ok(0)
    "I" | "L" -> Ok(1)
    c -> index_of(string.to_graphemes(alphabet), c, 0)
  }
}

fn index_of(items: List(String), target: String, i: Int) -> Result(Int, Nil) {
  case items {
    [] -> Error(Nil)
    [x, ..] if x == target -> Ok(i)
    [_, ..rest] -> index_of(rest, target, i + 1)
  }
}

pub fn decode(text: String) -> Result(List(Int), DecodeError) {
  decode_loop(string.to_graphemes(text), 0, 0, 0, [])
}

fn decode_loop(
  chars: List(String),
  position: Int,
  buffer: Int,
  bits: Int,
  acc: List(Int),
) -> Result(List(Int), DecodeError) {
  case chars {
    [] -> Ok(list.reverse(acc))
    [c, ..rest] ->
      case symbol_value(c) {
        Error(Nil) -> Error(InvalidCharacter(c, position))
        Ok(-1) -> decode_loop(rest, position + 1, buffer, bits, acc)
        Ok(v) -> {
          let buffer = int.bitwise_or(int.bitwise_shift_left(buffer, 5), v)
          let bits = bits + 5
          case bits >= 8 {
            True -> {
              let shift = bits - 8
              let byte =
                int.bitwise_and(int.bitwise_shift_right(buffer, shift), 0xFF)
              let buffer =
                int.bitwise_and(buffer, int.bitwise_shift_left(1, shift) - 1)
              decode_loop(rest, position + 1, buffer, shift, [byte, ..acc])
            }
            False -> decode_loop(rest, position + 1, buffer, bits, acc)
          }
        }
      }
  }
}

/// Check symbol for one row of symbols: Σ (i + 1) · value_i  mod 37.
///
/// Position weights 1..36 are distinct and non-zero modulo the prime 37, so
/// any single substitution and any swap of two different neighbours changes
/// the result.
pub fn row_check(row: String) -> String {
  let sum =
    row
    |> string.to_graphemes
    |> list.filter_map(fn(c) {
      case symbol_value(c) {
        Ok(v) if v >= 0 -> Ok(v)
        _ -> Error(Nil)
      }
    })
    |> list.index_fold(0, fn(acc, v, i) { acc + { i + 1 } * v })
  at(string.to_graphemes(check_alphabet), sum % 37)
}

/// True when `symbol` is the right check for `row` (case-insensitive).
pub fn row_check_matches(row: String, symbol: String) -> Bool {
  row_check(row) == string.uppercase(symbol)
}
