//// Arithmetic in the finite field GF(2^8).
////
//// Elements are integers 0..255. Addition is XOR; multiplication is
//// carry-less polynomial multiplication reduced by an irreducible
//// polynomial. Two fields are used in this project:
////
//// - `shamir_poly` (0x11B, the AES polynomial) for secret sharing,
//// - `qr_poly` (0x11D) for the Reed–Solomon codes inside QR symbols.
////
//// Multiplication uses the "Russian peasant" loop instead of log/exp tables:
//// it is branch-light, needs no precomputed arrays (Gleam lists are linked
//// lists, so table lookups would be O(n)), and eight iterations per product
//// is plenty fast for the sizes involved.

import gleam/int
import gleam/list

/// x^8 + x^4 + x^3 + x + 1 — the field used by AES and by most Shamir
/// implementations.
pub const shamir_poly = 0x11B

/// x^8 + x^4 + x^3 + x^2 + 1 — the field mandated by ISO/IEC 18004 (QR).
pub const qr_poly = 0x11D

pub fn add(a: Int, b: Int) -> Int {
  int.bitwise_exclusive_or(a, b)
}

/// Field subtraction is identical to addition in characteristic 2.
pub fn sub(a: Int, b: Int) -> Int {
  add(a, b)
}

pub fn mul(a: Int, b: Int, poly: Int) -> Int {
  mul_loop(a, b, poly, 0)
}

fn mul_loop(a: Int, b: Int, poly: Int, acc: Int) -> Int {
  case b {
    0 -> acc
    _ -> {
      let acc = case int.bitwise_and(b, 1) {
        1 -> int.bitwise_exclusive_or(acc, a)
        _ -> acc
      }
      let a = int.bitwise_shift_left(a, 1)
      let a = case int.bitwise_and(a, 0x100) {
        0 -> a
        _ -> int.bitwise_exclusive_or(a, poly)
      }
      mul_loop(a, int.bitwise_shift_right(b, 1), poly, acc)
    }
  }
}

/// a^e by square-and-multiply.
pub fn pow(a: Int, e: Int, poly: Int) -> Int {
  pow_loop(a, e, poly, 1)
}

fn pow_loop(base: Int, e: Int, poly: Int, acc: Int) -> Int {
  case e {
    0 -> acc
    _ -> {
      let acc = case int.bitwise_and(e, 1) {
        1 -> mul(acc, base, poly)
        _ -> acc
      }
      pow_loop(mul(base, base, poly), int.bitwise_shift_right(e, 1), poly, acc)
    }
  }
}

/// Multiplicative inverse. The multiplicative group has order 255, so
/// a^254 = a^-1 for every non-zero a.
pub fn inverse(a: Int, poly: Int) -> Result(Int, Nil) {
  case a {
    0 -> Error(Nil)
    _ -> Ok(pow(a, 254, poly))
  }
}

pub fn div(a: Int, b: Int, poly: Int) -> Result(Int, Nil) {
  case inverse(b, poly) {
    Ok(inv) -> Ok(mul(a, inv, poly))
    Error(Nil) -> Error(Nil)
  }
}

/// Evaluates a polynomial at `x` with Horner's rule. Coefficients are given
/// lowest degree first: `[c0, c1, c2]` means c0 + c1·x + c2·x².
pub fn eval_poly(coefficients: List(Int), x: Int, poly: Int) -> Int {
  coefficients
  |> list.reverse
  |> list.fold(0, fn(acc, c) { add(mul(acc, x, poly), c) })
}
