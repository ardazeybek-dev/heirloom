//// High-level operations: turn a secret into cards, and cards back into the
//// secret. Everything here is pure; randomness comes in as bytes.

import gleam/int
import gleam/list
import gleam/result
import gleam/string
import heirloom/secret.{type Secret}
import heirloom/shamir
import heirloom/share.{type Share}

pub type SplitOptions {
  SplitOptions(threshold: Int, shares: Int, block: Int)
}

pub type SplitError {
  SecretEmpty
  SecretTooLong(length: Int, max: Int)
  Shamir(shamir.SplitError)
}

/// How many random bytes `split` needs for these options.
pub fn randomness_needed(value: Secret, options: SplitOptions) -> Int {
  let plaintext = secret.encode(value, options.block)
  4 + shamir.randomness_needed(list.length(plaintext), options.threshold)
}

pub fn split(
  value: Secret,
  options: SplitOptions,
  random: List(Int),
) -> Result(List(Share), SplitError) {
  let length = list.length(secret.to_bytes(value))
  case length {
    0 -> Error(SecretEmpty)
    _ if length > secret.max_length ->
      Error(SecretTooLong(length, secret.max_length))
    _ -> {
      let plaintext = secret.encode(value, options.block)
      let set_id = list.take(random, 4)
      shamir.split(
        plaintext,
        threshold: options.threshold,
        shares: options.shares,
        random: list.drop(random, 4),
      )
      |> result.map_error(Shamir)
      |> result.map(
        list.map(_, fn(point) {
          share.Share(
            set_id: set_id,
            threshold: options.threshold,
            index: point.x,
            total: options.shares,
            ys: point.ys,
          )
        }),
      )
    }
  }
}

pub type RecoverError {
  NoCards
  /// The card at this position (0-based, in input order) could not be read.
  Unreadable(position: Int, error: share.ParseError)
  MixedSets(fingerprints: List(String))
  ConflictingDuplicate(index: Int)
  NotEnough(have: Int, need: Int)
  /// The cards combine, but not into a well-formed secret: too many of them
  /// are wrong for the redundancy available.
  Inconsistent(suspicious: List(Int))
}

pub type Recovery {
  Recovery(
    secret: Secret,
    fingerprint: String,
    threshold: Int,
    total: Int,
    used: List(Int),
    suspicious: List(Int),
    tolerates: Int,
  )
}

pub fn recover(texts: List(String)) -> Result(Recovery, RecoverError) {
  use cards <- result.try(parse_all(texts))
  use first <- result.try(case cards {
    [] -> Error(NoCards)
    [c, ..] -> Ok(c)
  })
  let fingerprints = cards |> list.map(share.fingerprint) |> list.unique
  use cards <- result.try(case fingerprints {
    [_] -> dedupe(cards)
    _ -> Error(MixedSets(fingerprints))
  })
  let k = first.threshold
  let have = list.length(cards)
  use <- bool_guard(have < k, NotEnough(have, k))
  let points = list.map(cards, share.to_point)
  let assert Ok(audit) = shamir.audit(points, threshold: k)
  case audit.ambiguous, secret.decode(audit.secret) {
    False, Ok(recovered) ->
      Ok(Recovery(
        secret: recovered,
        fingerprint: share.fingerprint(first),
        threshold: k,
        total: first.total,
        used: audit.consistent,
        suspicious: audit.suspicious,
        tolerates: audit.tolerates,
      ))
    _, _ -> Error(Inconsistent(audit.suspicious))
  }
}

fn parse_all(texts: List(String)) -> Result(List(Share), RecoverError) {
  texts
  |> list.index_map(fn(text, i) { #(text, i) })
  |> list.try_map(fn(pair) {
    share.parse(pair.0) |> result.map_error(Unreadable(pair.1, _))
  })
}

fn dedupe(cards: List(Share)) -> Result(List(Share), RecoverError) {
  list.try_fold(cards, [], fn(acc, card) {
    case list.find(acc, fn(c: Share) { c.index == card.index }) {
      Error(Nil) -> Ok([card, ..acc])
      Ok(same) if same == card -> Ok(acc)
      Ok(_) -> Error(ConflictingDuplicate(card.index))
    }
  })
  |> result.map(list.reverse)
}

fn bool_guard(
  condition: Bool,
  error: e,
  next: fn() -> Result(a, e),
) -> Result(a, e) {
  case condition {
    True -> Error(error)
    False -> next()
  }
}

pub fn describe_split_error(error: SplitError) -> String {
  case error {
    SecretEmpty -> "the secret is empty"
    SecretTooLong(length, max) ->
      "the secret is "
      <> int.to_string(length)
      <> " bytes; the limit is "
      <> int.to_string(max)
    Shamir(shamir.ThresholdTooSmall) -> "the threshold must be at least 2"
    Shamir(shamir.ThresholdAboveShares) ->
      "the threshold cannot exceed the number of cards"
    Shamir(shamir.TooManyShares) -> "at most 255 cards are supported"
    Shamir(shamir.EmptySecret) -> "the secret is empty"
    Shamir(shamir.NotEnoughRandomness(needed, got)) ->
      "internal error: needed "
      <> int.to_string(needed)
      <> " random bytes, got "
      <> int.to_string(got)
  }
}

pub fn describe_recover_error(error: RecoverError) -> String {
  case error {
    NoCards -> "no cards were given"
    Unreadable(position, e) ->
      "card " <> int.to_string(position + 1) <> ": " <> share.describe_error(e)
    MixedSets(fps) -> "these cards come from different splits: " <> join(fps)
    ConflictingDuplicate(index) ->
      "two different cards both claim to be card #" <> int.to_string(index)
    NotEnough(have, need) ->
      "need " <> int.to_string(need) <> " cards, got " <> int.to_string(have)
    Inconsistent([]) ->
      "the cards do not combine into a valid secret — at least one is wrong, and there are not enough extra cards to tell which"
    Inconsistent(suspicious) ->
      "the cards do not agree; suspicious cards: "
      <> join(list.map(suspicious, fn(x) { "#" <> int.to_string(x) }))
  }
}

fn join(items: List(String)) -> String {
  case items {
    [] -> ""
    [one] -> one
    [first, ..rest] -> first <> ", " <> join(rest)
  }
}

/// Splits pasted or file text into individual cards: blank lines separate
/// cards, and every `HL1:` line is a card of its own.
pub fn split_card_text(text: String) -> List(String) {
  // Normalise whitespace-only lines to empty ones so they separate cards too.
  text
  |> string.replace("\r", "")
  |> string.split("\n")
  |> list.map(string.trim)
  |> string.join("\n")
  |> string.split("\n\n")
  |> list.flat_map(fn(block) {
    let lines = block |> string.split("\n") |> list.map(string.trim)
    let compact =
      list.filter(lines, fn(l) {
        string.contains(string.uppercase(l), share.prefix)
      })
    case compact {
      [] -> [string.join(list.filter(lines, is_card_line), "\n")]
      _ -> compact
    }
  })
  |> list.filter(fn(card) { string.trim(card) != "" })
}

/// Drops headings such as "Card 2 of 5 · …" that `--text` output contains.
fn is_card_line(line: String) -> Bool {
  line != "" && !string.starts_with(string.lowercase(line), "card ")
}
