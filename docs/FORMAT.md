# heirloom card format, version 1

This document is enough to recover a secret from heirloom cards without heirloom.

## Plaintext

Before splitting, the secret is framed as:

| Bytes | Field | Notes |
| --- | --- | --- |
| 1 | kind | `0` = UTF-8 text, `1` = raw bytes |
| 2 | length | big-endian, length of the secret in bytes (max 512) |
| *length* | secret | |
| 0–15 | padding | zero bytes up to a multiple of 16 (`--no-pad`: none) |

Kind, length and padding are secret-shared together with the secret, so a card reveals none of them.

## Sharing

Each plaintext byte *s* is shared independently with Shamir's scheme over GF(2⁸) with the reduction polynomial
x⁸ + x⁴ + x³ + x + 1 (`0x11B`, the AES field):

- choose *a₁ … aₖ₋₁* uniformly at random (CSPRNG),
- card *i* (1 ≤ *i* ≤ N ≤ 255) receives *yᵢ = s + a₁·i + … + aₖ₋₁·iᵏ⁻¹*, all arithmetic in GF(2⁸).

To recover, take any K cards with indices *xⱼ* and compute for every byte position

```
s = Σⱼ yⱼ · Πₘ≠ⱼ  xₘ / (xₘ ⊕ xⱼ)        (⊕ is XOR = field addition)
```

## Card binary layout

| Offset | Size | Field |
| --- | --- | --- |
| 0 | 1 | format version = `1` |
| 1 | 4 | set id — random, identical on every card of one split |
| 5 | 1 | threshold K |
| 6 | 1 | card index *x* (1–255) |
| 7 | 1 | total cards N (informational) |
| 8 | P | *y* values, one per plaintext byte |
| 8 + P | 4 | CRC-32 (IEEE 802.3, as in zip/PNG) of bytes 0 … 7 + P, big-endian |

## Text encodings

**Base32.** The card bytes are encoded with [Crockford Base32](https://www.crockford.com/base32.html)
(`0123456789ABCDEFGHJKMNPQRSTVWXYZ`), most significant bit first; the final symbol is zero-padded.
Decoders accept lower case, ignore spaces and hyphens, and read `O` as `0` and `I`/`L` as `1`.

**Compact form** (inside the QR code): `HL1:` followed by the Base32 string. All characters belong to
the QR alphanumeric set, so the QR code uses alphanumeric mode.

**Rows** (printed for typing): the Base32 string in rows of 24 symbols, shown as six groups of four,
prefixed with a two-digit row number and followed by one check symbol:

```
01  06T0 HX8R 0C0G ANRG 860B SGSN  3
```

The check symbol is `Σ (i + 1) · vᵢ  mod 37` over the row's symbol values *vᵢ* (*i* from 0), written with
the alphabet above extended by `* ~ $ = U` for 32–36. It detects every single substitution and every
swap of two different adjacent symbols within a row.

**Set fingerprint.** The first seven Base32 symbols of the set id, shown as `XXXX-XXX`.

## Validation order

1. Row check symbols (when rows are given) — reports the row with a typo.
2. Base32 decoding.
3. CRC-32 — catches remaining damage.
4. Header sanity: version 1, K ≥ 2, 1 ≤ *x* ≤ N, K ≤ N.
5. All cards share one set id and threshold; duplicates of the same index must be identical.
6. With more than K cards, each K-subset's polynomial is checked against the rest; the polynomial
   agreeing with the most cards is used and disagreeing cards are reported.
7. The plaintext framing must be well-formed (kind 0/1, length within bounds, zero padding).
