//// CRC-32 (IEEE 802.3, reflected, polynomial 0xEDB88320) — the checksum
//// used by zip, PNG and Ethernet. It catches every single-byte error and
//// every burst up to 32 bits, which covers a mistyped or smudged character.
////
//// It is *not* a cryptographic MAC: a deliberate forgery can match it.
//// Forged shares are caught by `shamir.audit` instead.

import gleam/int
import gleam/list

const reflected_poly = 0xEDB88320

pub fn checksum(bytes: List(Int)) -> Int {
  bytes
  |> list.fold(0xFFFFFFFF, fn(crc, byte) {
    crc
    |> int.bitwise_exclusive_or(byte)
    |> shift_eight
  })
  |> int.bitwise_exclusive_or(0xFFFFFFFF)
}

fn shift_eight(crc: Int) -> Int {
  int.range(from: 0, to: 8, with: crc, run: fn(c, _) {
    let shifted = int.bitwise_shift_right(c, 1)
    case int.bitwise_and(c, 1) {
      1 -> int.bitwise_exclusive_or(shifted, reflected_poly)
      _ -> shifted
    }
  })
}

/// The checksum as four big-endian bytes.
pub fn to_bytes(crc: Int) -> List(Int) {
  [24, 16, 8, 0]
  |> list.map(fn(shift) {
    crc |> int.bitwise_shift_right(shift) |> int.bitwise_and(0xFF)
  })
}
