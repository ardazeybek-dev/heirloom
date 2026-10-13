//// Small helpers for moving between strings, bit arrays and byte lists.

import gleam/bit_array
import gleam/int
import gleam/list
import gleam/string

pub fn from_string(text: String) -> List(Int) {
  from_bit_array(bit_array.from_string(text))
}

pub fn from_bit_array(bits: BitArray) -> List(Int) {
  from_bits_loop(bits, [])
}

fn from_bits_loop(bits: BitArray, acc: List(Int)) -> List(Int) {
  case bits {
    <<byte, rest:bytes>> -> from_bits_loop(rest, [byte, ..acc])
    _ -> list.reverse(acc)
  }
}

pub fn to_bit_array(bytes: List(Int)) -> BitArray {
  bytes
  |> list.map(fn(b) { <<b>> })
  |> bit_array.concat
}

/// Decodes UTF-8; fails on invalid sequences.
pub fn to_string(bytes: List(Int)) -> Result(String, Nil) {
  bit_array.to_string(to_bit_array(bytes))
}

pub fn to_hex(bytes: List(Int)) -> String {
  bytes
  |> list.map(fn(b) { b |> int.to_base16 |> string.pad_start(2, "0") })
  |> string.concat
  |> string.lowercase
}

/// Parses hex, ignoring whitespace, colons and an optional 0x prefix.
pub fn from_hex(text: String) -> Result(List(Int), Nil) {
  let cleaned =
    text
    |> string.trim
    |> string.remove_prefix("0x")
    |> string.replace(" ", "")
    |> string.replace(":", "")
    |> string.replace("\n", "")
    |> string.replace("\r", "")
    |> string.replace("\t", "")
  case bit_array.base16_decode(string.uppercase(cleaned)) {
    Ok(bits) -> Ok(from_bit_array(bits))
    Error(Nil) -> Error(Nil)
  }
}

/// Big-endian unsigned integer from bytes.
pub fn to_uint(bytes: List(Int)) -> Int {
  list.fold(bytes, 0, fn(acc, b) { acc * 256 + b })
}

pub fn from_uint(value: Int, width: Int) -> List(Int) {
  int.range(from: width - 1, to: -1, with: [], run: fn(acc, i) {
    let byte = value |> int.bitwise_shift_right(8 * i) |> int.bitwise_and(0xFF)
    [byte, ..acc]
  })
  |> list.reverse
}
