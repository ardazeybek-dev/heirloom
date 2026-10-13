import gleam/int
import gleam/list
import gleam/string
import gleeunit
import heirloom/base32
import heirloom/bytes
import heirloom/crc32
import heirloom/gf256
import heirloom/kit
import heirloom/secret
import heirloom/shamir
import heirloom/share

pub fn main() -> Nil {
  gleeunit.main()
}

/// Deterministic byte stream (LCG) so failures are reproducible.
pub fn pseudo_random(seed: Int, count: Int) -> List(Int) {
  int.range(from: 0, to: count, with: #([], seed), run: fn(acc, _) {
    let state = { acc.1 * 1_103_515_245 + 12_345 } % 2_147_483_648
    #([state / 65_536 % 256, ..acc.0], state)
  }).0
}

// --- GF(256) ---------------------------------------------------------------

pub fn gf_known_product_test() {
  // FIPS-197 §4.2: {57} • {83} = {c1}
  assert gf256.mul(0x57, 0x83, gf256.shamir_poly) == 0xC1
}

pub fn gf_every_element_has_inverse_test() {
  list.each([gf256.shamir_poly, gf256.qr_poly], fn(poly) {
    int.range(from: 1, to: 256, with: Nil, run: fn(_, a) {
      let assert Ok(inv) = gf256.inverse(a, poly)
      assert gf256.mul(a, inv, poly) == 1
    })
  })
}

pub fn gf_zero_has_no_inverse_test() {
  assert gf256.inverse(0, gf256.shamir_poly) == Error(Nil)
}

// --- CRC-32 ----------------------------------------------------------------

pub fn crc32_check_value_test() {
  // The standard check value for CRC-32/ISO-HDLC.
  assert crc32.checksum(bytes.from_string("123456789")) == 0xCBF43926
}

pub fn crc32_empty_test() {
  assert crc32.checksum([]) == 0
}

// --- Base32 ----------------------------------------------------------------

pub fn base32_roundtrip_test() {
  list.each([0, 1, 2, 3, 4, 5, 7, 31, 100], fn(n) {
    let data = pseudo_random(n + 1, n)
    assert base32.decode(base32.encode(data)) == Ok(data)
  })
}

pub fn base32_known_value_test() {
  assert base32.encode(bytes.from_string("hi")) == "D1MG"
}

pub fn base32_forgiving_input_test() {
  let encoded = base32.encode([0, 1, 2, 3, 4])
  let messy =
    encoded |> string.lowercase |> string.replace("0", "o") |> string.replace("1", "l")
  assert base32.decode("  " <> messy <> " - ") == Ok([0, 1, 2, 3, 4])
}

pub fn base32_rejects_u_test() {
  assert base32.decode("ABU") == Error(base32.InvalidCharacter("U", 2))
}

pub fn row_check_catches_substitution_and_swap_test() {
  let row = "7KQ2M9X4ABCDEFGHJKMNPQRS"
  let check = base32.row_check(row)
  assert base32.row_check_matches(row, check)
  assert !base32.row_check_matches("7KQ2M9X4ABCDEFGHJKMNPQRT", check)
  assert !base32.row_check_matches("K7Q2M9X4ABCDEFGHJKMNPQRS", check)
}

// --- Shamir ----------------------------------------------------------------

pub fn every_threshold_subset_recovers_test() {
  let data = bytes.from_string("correct horse battery staple")
  let random = pseudo_random(7, shamir.randomness_needed(list.length(data), 3))
  let assert Ok(points) = shamir.split(data, threshold: 3, shares: 5, random:)
  list.combinations(points, 3)
  |> list.each(fn(subset) {
    assert shamir.combine(subset) == Ok(data)
    assert shamir.combine(list.reverse(subset)) == Ok(data)
  })
}

pub fn below_threshold_does_not_recover_test() {
  let data = bytes.from_string("hunter2")
  let random = pseudo_random(9, shamir.randomness_needed(list.length(data), 3))
  let assert Ok(points) = shamir.split(data, threshold: 3, shares: 5, random:)
  list.combinations(points, 2)
  |> list.each(fn(subset) { assert shamir.combine(subset) != Ok(data) })
}

pub fn two_shares_fit_every_secret_test() {
  // Perfect secrecy, concretely: for a 2-of-n split, one share is consistent
  // with each of the 256 possible values of a one-byte secret.
  let share = shamir.Point(1, [0x42])
  let candidates =
    int.range(from: 0, to: 256, with: [], run: fn(acc, guess) {
      // Line through (0, guess) and (1, 0x42): evaluate at x = 0 gives guess.
      let assert Ok([value]) =
        shamir.combine([share, shamir.Point(2, [guess_at_two(guess)])])
      [value, ..acc]
    })
  assert list.length(list.unique(candidates)) == 256
}

fn guess_at_two(guess: Int) -> Int {
  // f(x) = guess + slope·x with f(1) = 0x42  ⇒  slope = 0x42 ⊕ guess.
  let slope = gf256.add(0x42, guess)
  gf256.add(guess, gf256.mul(slope, 2, gf256.shamir_poly))
}

pub fn split_validates_parameters_test() {
  assert shamir.split([1], threshold: 1, shares: 3, random: [])
    == Error(shamir.ThresholdTooSmall)
  assert shamir.split([1], threshold: 4, shares: 3, random: [1, 2, 3])
    == Error(shamir.ThresholdAboveShares)
  assert shamir.split([1, 2], threshold: 2, shares: 3, random: [1])
    == Error(shamir.NotEnoughRandomness(2, 1))
}

pub fn combine_rejects_duplicates_test() {
  let p = shamir.Point(1, [5])
  assert shamir.combine([p, p]) == Error(shamir.DuplicateIndex(1))
}

pub fn audit_pinpoints_a_forged_share_test() {
  let data = bytes.from_string("vault key")
  let random = pseudo_random(3, shamir.randomness_needed(list.length(data), 2))
  let assert Ok(points) = shamir.split(data, threshold: 2, shares: 5, random:)
  let forged =
    list.map(points, fn(p) {
      case p.x == 4 {
        True -> shamir.Point(4, list.map(p.ys, gf256.add(_, 0x5A)))
        False -> p
      }
    })
  let assert Ok(audit) = shamir.audit(forged, threshold: 2)
  assert audit.secret == data
  assert audit.suspicious == [4]
  assert !audit.ambiguous
}

pub fn audit_flags_ambiguity_test() {
  // 2-of-3 with one bad share: three different lines, each through two
  // points — the shares cannot say which one is wrong.
  let data = [7]
  let assert Ok(points) =
    shamir.split(data, threshold: 2, shares: 3, random: [9])
  let bad =
    list.map(points, fn(p) {
      case p.x == 2 {
        True -> shamir.Point(2, [gf256.add(1, p.ys |> list.first |> unwrap)])
        False -> p
      }
    })
  let assert Ok(audit) = shamir.audit(bad, threshold: 2)
  assert audit.ambiguous
}

fn unwrap(r: Result(Int, Nil)) -> Int {
  let assert Ok(v) = r
  v
}

// --- Secret encoding ------------------------------------------------------

pub fn secret_padding_hides_length_test() {
  let short = secret.encode(secret.Text("abc"), 16)
  let longer = secret.encode(secret.Text("abcdefghij"), 16)
  assert list.length(short) == 16
  assert list.length(longer) == 16
  assert secret.decode(short) == Ok(secret.Text("abc"))
}

pub fn secret_binary_roundtrip_test() {
  let value = secret.Binary([0, 255, 16, 0])
  assert secret.decode(secret.encode(value, 1)) == Ok(value)
}

pub fn secret_rejects_garbage_padding_test() {
  assert secret.decode([0, 0, 1, 65, 9]) == Error(secret.NonZeroPadding)
}

// --- Cards end to end -----------------------------------------------------

fn make_cards(text: String, k: Int, n: Int) -> List(share.Share) {
  let value = secret.Text(text)
  let options = kit.SplitOptions(threshold: k, shares: n, block: 16)
  let random = pseudo_random(42, kit.randomness_needed(value, options))
  let assert Ok(cards) = kit.split(value, options, random)
  cards
}

pub fn compact_and_rows_roundtrip_test() {
  let cards = make_cards("Bitwarden: tulip-anchor-91-ember", 3, 5)
  list.each(cards, fn(card) {
    assert share.parse(share.to_compact(card)) == Ok(card)
    assert share.parse(string.join(share.to_rows(card), "\n")) == Ok(card)
    assert string.starts_with(share.to_compact(card), "HL1:")
  })
}

pub fn recover_from_any_three_cards_test() {
  let cards = make_cards("ünïcødé ✓ passphrase", 3, 5)
  list.combinations(cards, 3)
  |> list.each(fn(subset) {
    let assert Ok(recovery) = kit.recover(list.map(subset, share.to_compact))
    assert recovery.secret == secret.Text("ünïcødé ✓ passphrase")
    assert recovery.suspicious == []
  })
}

pub fn typo_is_reported_with_row_number_test() {
  let assert [card, ..] = make_cards("a secret long enough for three rows!!", 2, 3)
  let rows = share.to_rows(card)
  let assert [r1, r2, ..rest] = rows
  // Flip one data symbol in row 2 (after the "02  " prefix).
  let broken = string.slice(r2, 0, 5) <> flip(string.slice(r2, 5, 1)) <> string.drop_start(r2, 6)
  let text = string.join([r1, broken, ..rest], "\n")
  assert share.parse(text) == Error(share.RowTypo(2))
}

fn flip(symbol: String) -> String {
  case symbol {
    "A" -> "B"
    _ -> "A"
  }
}

pub fn damaged_compact_text_fails_checksum_test() {
  let assert [card, ..] = make_cards("abc", 2, 2)
  let compact = share.to_compact(card)
  let damaged = string.drop_end(compact, 3) <> flip(string.slice(compact, -3, 1)) <> string.slice(compact, -2, 2)
  let assert Error(error) = share.parse(damaged)
  assert error == share.ChecksumMismatch || error == share.TooShort
}

pub fn recover_reports_missing_cards_test() {
  let cards = make_cards("abc", 3, 5)
  let texts = cards |> list.take(2) |> list.map(share.to_compact)
  assert kit.recover(texts) == Error(kit.NotEnough(2, 3))
}

pub fn recover_rejects_mixed_sets_test() {
  let a = make_cards("abc", 2, 3)
  let value = secret.Text("abc")
  let options = kit.SplitOptions(threshold: 2, shares: 3, block: 16)
  let assert Ok(b) =
    kit.split(value, options, pseudo_random(99, kit.randomness_needed(value, options)))
  let assert [a1, ..] = a
  let assert [_, b2, ..] = b
  let assert Error(kit.MixedSets(_)) =
    kit.recover([share.to_compact(a1), share.to_compact(b2)])
}

pub fn duplicate_identical_card_is_ignored_test() {
  let assert [c1, c2, ..] = make_cards("abc", 2, 3)
  let texts = list.map([c1, c1, c2], share.to_compact)
  let assert Ok(recovery) = kit.recover(texts)
  assert recovery.secret == secret.Text("abc")
}
