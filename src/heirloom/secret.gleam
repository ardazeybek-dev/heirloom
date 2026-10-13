//// The plaintext that actually gets secret-shared.
////
//// Layout: kind (1 byte) · length (2 bytes, big-endian) · secret · zero
//// padding up to a multiple of `block`. Kind and length travel *inside* the
//// shared data, so a card reveals neither whether the secret is a password or
//// a binary key nor — thanks to the padding — roughly how long it is.

import gleam/list
import heirloom/bytes

pub type Secret {
  /// UTF-8 text such as a passphrase or a list of recovery codes.
  Text(String)
  /// Arbitrary bytes such as a key or a wallet seed.
  Binary(List(Int))
}

pub type DecodeError {
  Truncated
  UnknownKind(Int)
  BadLength
  InvalidUtf8
  NonZeroPadding
}

/// Largest secret accepted, in bytes. The resulting share still fits a
/// version-23 QR symbol at error-correction level M.
pub const max_length = 512

/// Default padding block: secrets of 1..13 bytes all produce equally long
/// cards, 14..29 the next size, and so on.
pub const default_block = 16

pub fn to_bytes(secret: Secret) -> List(Int) {
  case secret {
    Text(text) -> bytes.from_string(text)
    Binary(data) -> data
  }
}

pub fn encode(secret: Secret, block: Int) -> List(Int) {
  let kind = case secret {
    Text(_) -> 0
    Binary(_) -> 1
  }
  let data = to_bytes(secret)
  let body = list.flatten([[kind], bytes.from_uint(list.length(data), 2), data])
  let block = case block < 1 {
    True -> 1
    False -> block
  }
  let padding = { block - list.length(body) % block } % block
  list.append(body, list.repeat(0, padding))
}

pub fn decode(plaintext: List(Int)) -> Result(Secret, DecodeError) {
  case plaintext {
    [kind, hi, lo, ..rest] -> {
      let length = hi * 256 + lo
      case length > list.length(rest) {
        True -> Error(BadLength)
        False -> {
          let data = list.take(rest, length)
          let padding = list.drop(rest, length)
          case list.all(padding, fn(b) { b == 0 }), kind {
            False, _ -> Error(NonZeroPadding)
            True, 0 ->
              case bytes.to_string(data) {
                Ok(text) -> Ok(Text(text))
                Error(Nil) -> Error(InvalidUtf8)
              }
            True, 1 -> Ok(Binary(data))
            True, other -> Error(UnknownKind(other))
          }
        }
      }
    }
    _ -> Error(Truncated)
  }
}
