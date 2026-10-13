//// Shamir's Secret Sharing over GF(2^8), applied byte-wise.
////
//// For every byte s of the secret a random polynomial of degree k − 1 is
//// drawn with constant term s. Share number x receives f(x) for each byte.
//// Any k shares determine the polynomials (Lagrange interpolation) and so
//// the secret; any k − 1 shares are consistent with *every* possible secret,
//// which is why the scheme is information-theoretically secure.
////
//// Shares are also a Reed–Solomon codeword: with m > k shares the extra
//// points can be used to detect — and, while fewer than (m − k + 1) / 2 are
//// wrong, to pinpoint — damaged or forged shares. See `audit`.

import gleam/int
import gleam/list
import gleam/result
import heirloom/gf256

const poly = gf256.shamir_poly

/// One share: the x coordinate (1..255) and the y value for every byte.
pub type Point {
  Point(x: Int, ys: List(Int))
}

pub type SplitError {
  ThresholdTooSmall
  ThresholdAboveShares
  TooManyShares
  EmptySecret
  NotEnoughRandomness(needed: Int, got: Int)
}

pub type CombineError {
  NoShares
  DuplicateIndex(x: Int)
  InvalidIndex(x: Int)
  LengthMismatch
}

/// How many random bytes `split` consumes.
pub fn randomness_needed(secret_length: Int, threshold: Int) -> Int {
  secret_length * { threshold - 1 }
}

/// Splits `secret` into `shares` points, any `threshold` of which recover it.
///
/// `random` must hold at least `randomness_needed(..)` bytes from a
/// cryptographically secure source; it is a parameter (not drawn here) so the
/// core stays pure and deterministic tests are possible.
pub fn split(
  secret: List(Int),
  threshold k: Int,
  shares n: Int,
  random random: List(Int),
) -> Result(List(Point), SplitError) {
  let needed = randomness_needed(list.length(secret), k)
  let got = list.length(random)
  case secret {
    _ if k < 2 -> Error(ThresholdTooSmall)
    _ if k > n -> Error(ThresholdAboveShares)
    _ if n > 255 -> Error(TooManyShares)
    [] -> Error(EmptySecret)
    _ if got < needed -> Error(NotEnoughRandomness(needed, got))
    _ -> {
      let polynomials = build_polynomials(secret, random, k - 1, [])
      int.range(from: 1, to: n + 1, with: [], run: fn(acc, x) {
        let ys = list.map(polynomials, gf256.eval_poly(_, x, poly))
        [Point(x, ys), ..acc]
      })
      |> list.reverse
      |> Ok
    }
  }
}

fn build_polynomials(
  secret: List(Int),
  random: List(Int),
  degree: Int,
  acc: List(List(Int)),
) -> List(List(Int)) {
  case secret {
    [] -> list.reverse(acc)
    [s, ..rest] -> {
      let coefficients = [s, ..list.take(random, degree)]
      build_polynomials(rest, list.drop(random, degree), degree, [
        coefficients,
        ..acc
      ])
    }
  }
}

/// Recovers the secret from the given points (the constant terms).
/// Every point is used; pass exactly `threshold` points, or more if they are
/// known to be consistent (see `audit` otherwise).
pub fn combine(points: List(Point)) -> Result(List(Int), CombineError) {
  interpolate_at(points, 0)
}

/// Evaluates the unique polynomial through `points` at `x`, byte-wise.
pub fn interpolate_at(
  points: List(Point),
  x: Int,
) -> Result(List(Int), CombineError) {
  use _ <- result.try(validate(points))
  let xs = list.map(points, fn(p) { p.x })
  let weights =
    list.map(xs, fn(xi) {
      // Lagrange basis l_i(x) = Π_{j≠i} (x − x_j) / (x_i − x_j).
      list.fold(xs, 1, fn(acc, xj) {
        case xj == xi {
          True -> acc
          False -> {
            let assert Ok(term) =
              gf256.div(gf256.sub(x, xj), gf256.sub(xi, xj), poly)
            gf256.mul(acc, term, poly)
          }
        }
      })
    })
  let assert [first, ..] = points
  let zero = list.map(first.ys, fn(_) { 0 })
  list.zip(points, weights)
  |> list.fold(zero, fn(acc, pair) {
    let #(point, weight) = pair
    list.map2(acc, point.ys, fn(a, y) {
      gf256.add(a, gf256.mul(y, weight, poly))
    })
  })
  |> Ok
}

fn validate(points: List(Point)) -> Result(Nil, CombineError) {
  case points {
    [] -> Error(NoShares)
    [first, ..] -> {
      let length = list.length(first.ys)
      list.try_fold(points, [], fn(seen, p) {
        case p.x < 1 || p.x > 255, list.contains(seen, p.x) {
          True, _ -> Error(InvalidIndex(p.x))
          _, True -> Error(DuplicateIndex(p.x))
          _, _ ->
            case list.length(p.ys) == length {
              True -> Ok([p.x, ..seen])
              False -> Error(LengthMismatch)
            }
        }
      })
      |> result.replace(Nil)
    }
  }
}

/// Result of cross-checking more shares than the threshold.
pub type Audit {
  Audit(
    secret: List(Int),
    /// x of every share that lies on the winning polynomial.
    consistent: List(Int),
    /// x of every share that does not — damaged, mistyped or forged.
    suspicious: List(Int),
    /// How many wrong shares the given set can always pinpoint.
    tolerates: Int,
    /// True when two different polynomials explain the shares equally well,
    /// i.e. there are too many bad shares to know which ones are bad.
    ambiguous: Bool,
  )
}

/// Upper bound on the number of k-subsets `audit` will try.
pub const audit_subset_limit = 5000

/// Recovers the secret from `points` using the known `threshold`, and checks
/// every extra share against the result.
///
/// Each k-subset defines a candidate polynomial; the candidate passing
/// through the most shares wins. With b bad shares among m, a subset of good
/// shares agrees with m − b points, while any polynomial through a bad share
/// agrees with at most k − 1 + b, so the winner is correct whenever
/// b ≤ (m − k) / 2. The search stops at the first candidate that explains
/// every share — the normal case costs one interpolation.
pub fn audit(
  points: List(Point),
  threshold k: Int,
) -> Result(Audit, CombineError) {
  use _ <- result.try(validate(points))
  let m = list.length(points)
  case m < k {
    True -> Error(NoShares)
    False -> {
      let subsets = case m == k {
        True -> [points]
        False -> list.take(list.combinations(points, k), audit_subset_limit)
      }
      let #(best, _, tie) = search(subsets, points, m, #([], -1, False))
      let consistent = list.map(best, fn(p) { p.x })
      let suspicious =
        points
        |> list.filter(fn(p) { !list.contains(consistent, p.x) })
        |> list.map(fn(p) { p.x })
      let assert Ok(secret) = combine(list.take(best, k))
      Ok(Audit(
        secret: secret,
        consistent: consistent,
        suspicious: suspicious,
        tolerates: { m - k } / 2,
        ambiguous: tie,
      ))
    }
  }
}

/// Returns the agreeing points of the best candidate, their count and whether
/// another candidate with a *different* agreeing set tied with it.
fn search(
  subsets: List(List(Point)),
  points: List(Point),
  m: Int,
  best: #(List(Point), Int, Bool),
) -> #(List(Point), Int, Bool) {
  case subsets {
    [] -> best
    [subset, ..rest] -> {
      let agreeing =
        list.filter(points, fn(p) {
          list.contains(subset, p) || interpolate_at(subset, p.x) == Ok(p.ys)
        })
      let count = list.length(agreeing)
      let #(best_points, best_count, tie) = best
      let next = case count > best_count, count == best_count {
        True, _ -> #(agreeing, count, False)
        _, True -> #(
          best_points,
          best_count,
          tie || !same_xs(agreeing, best_points),
        )
        _, _ -> best
      }
      case count == m {
        True -> next
        False -> search(rest, points, m, next)
      }
    }
  }
}

fn same_xs(a: List(Point), b: List(Point)) -> Bool {
  list.map(a, fn(p) { p.x }) == list.map(b, fn(p) { p.x })
}
