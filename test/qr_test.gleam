import gleam/int
import gleam/list
import gleam/string
import heirloom/qr
import heirloom/qr/matrix
import heirloom/qr/reed_solomon
import heirloom/qr/segment
import heirloom/qr/svg
import heirloom/qr/tables.{High, Low, Medium, Quartile}

// The worked "HELLO WORLD" example at version 1-M, as found in the standard's
// annex and in most QR tutorials.
const hello_data = [
  32, 91, 11, 120, 209, 114, 220, 77, 67, 64, 236, 17, 236, 17, 236, 17,
]

const hello_ecc = [196, 35, 39, 119, 235, 215, 231, 226, 93, 23]

pub fn hello_world_codewords_test() {
  let s = segment.make("HELLO WORLD")
  assert s.mode == segment.Alphanumeric
  assert segment.to_codewords(s, 1, tables.data_codewords(1, Medium))
    == hello_data
}

pub fn hello_world_reed_solomon_test() {
  assert reed_solomon.remainder(hello_data, 10) == hello_ecc
}

pub fn single_block_interleave_is_concatenation_test() {
  assert qr.add_ecc_and_interleave(hello_data, 1, Medium)
    == list.append(hello_data, hello_ecc)
}

pub fn format_word_test() {
  // Level L, mask 4 → 110011000101111.
  assert matrix.format_word(Low, 4) == 0b110011000101111
  // Level M, mask 0 → 101010000010010.
  assert matrix.format_word(Medium, 0) == 0b101010000010010
}

pub fn version_word_test() {
  assert matrix.version_word(7) == 0b000111110010010100
  assert matrix.version_word(40) == 0b101000110001101001
}

pub fn alignment_positions_test() {
  assert tables.alignment_positions(1) == []
  assert tables.alignment_positions(2) == [6, 18]
  assert tables.alignment_positions(7) == [6, 22, 38]
  assert tables.alignment_positions(32) == [6, 34, 60, 86, 112, 138]
  assert tables.alignment_positions(40) == [6, 30, 58, 86, 114, 142, 170]
}

pub fn capacity_test() {
  assert tables.data_codewords(1, Low) == 19
  assert tables.data_codewords(1, High) == 9
  assert tables.data_codewords(10, Quartile) == 154
  assert tables.data_codewords(40, Low) == 2956
  assert tables.data_codewords(40, High) == 1276
}

pub fn every_version_data_path_matches_capacity_test() {
  // The number of free modules on the grid must equal the raw capacity the
  // tables promise — this cross-checks finder, alignment, timing, format and
  // version placement for all 40 versions.
  int.range(from: 1, to: 41, with: Nil, run: fn(_, version) {
    let free = list.length(matrix.data_path(matrix.function_patterns(version)))
    assert free == tables.raw_data_modules(version)
  })
}

pub fn smallest_version_is_chosen_test() {
  let assert Ok(code) = qr.encode("HELLO WORLD", Medium)
  assert code.version == 1
  assert code.size == 21
  assert list.length(code.modules) == 21
  // 11 alphanumeric chars fit 1-Q (capacity 16) but not 1-H (10): boosted.
  assert code.ecl == Quartile
}

pub fn byte_mode_for_unicode_test() {
  let assert Ok(code) = qr.encode("héllo ✓", Low)
  assert code.mode == segment.Byte
}

pub fn too_long_test() {
  assert qr.encode(string.repeat("A", 4300), Low) == Error(qr.DataTooLong)
}

pub fn svg_has_quiet_zone_test() {
  let assert Ok(code) = qr.encode("HL1:ABC", Medium)
  let doc = svg.to_svg(code, svg.default_style, 200)
  assert string.contains(doc, "viewBox=\"0 0 29 29\"")
  assert string.starts_with(svg.path_data(code, 4), "M4 4h7")
}
