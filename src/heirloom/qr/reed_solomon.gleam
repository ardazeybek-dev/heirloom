//// Reed–Solomon error-correction codewords for QR, over GF(2^8)/0x11D.
////
//// The generator polynomial of degree d is g(x) = Π_{i=0}^{d-1} (x − α^i)
//// with α = 2. The ECC codewords are the remainder of data(x) · x^d divided
//// by g(x), computed with a shift-register (LFSR) loop.

import gleam/int
import gleam/list
import heirloom/gf256

const poly = gf256.qr_poly

/// Coefficients of g(x) without the leading 1, highest degree first.
pub fn generator(degree: Int) -> List(Int) {
  let #(coefficients, _) =
    int.range(
      from: 0,
      to: degree,
      with: #(list.append(list.repeat(0, degree - 1), [1]), 1),
      run: fn(acc, _) {
        let #(coefficients, root) = acc
        // Multiply the current polynomial by (x − root).
        let next =
          list.index_map(coefficients, fn(c, j) {
            let product = gf256.mul(c, root, poly)
            case list.drop(coefficients, j + 1) {
              [following, ..] -> gf256.add(product, following)
              [] -> product
            }
          })
        #(next, gf256.mul(root, 2, poly))
      },
    )
  coefficients
}

/// The `degree` ECC codewords for `data`.
pub fn remainder(data: List(Int), degree: Int) -> List(Int) {
  let divisor = generator(degree)
  list.fold(data, list.repeat(0, degree), fn(register, byte) {
    let assert [head, ..tail] = register
    let factor = gf256.add(byte, head)
    let shifted = list.append(tail, [0])
    list.map2(shifted, divisor, fn(r, d) {
      gf256.add(r, gf256.mul(d, factor, poly))
    })
  })
}
