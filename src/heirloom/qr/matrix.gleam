//// Laying codewords out on the QR grid: function patterns, the zig-zag data
//// path, the eight masks and the penalty rules used to choose between them.
////
//// Coordinates are `#(x, y)` with the origin at the top-left module.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import heirloom/qr/segment
import heirloom/qr/tables.{type Ecl}

pub type Grid {
  Grid(
    size: Int,
    modules: Dict(#(Int, Int), Bool),
    function: Dict(#(Int, Int), Bool),
  )
}

fn set_function(grid: Grid, x: Int, y: Int, dark: Bool) -> Grid {
  Grid(
    ..grid,
    modules: dict.insert(grid.modules, #(x, y), dark),
    function: dict.insert(grid.function, #(x, y), True),
  )
}

pub fn is_dark(grid: Grid, x: Int, y: Int) -> Bool {
  case dict.get(grid.modules, #(x, y)) {
    Ok(dark) -> dark
    Error(Nil) -> False
  }
}

fn each_offset(
  grid: Grid,
  radius: Int,
  apply: fn(Grid, Int, Int) -> Grid,
) -> Grid {
  int.range(from: -radius, to: radius + 1, with: grid, run: fn(g, dy) {
    int.range(from: -radius, to: radius + 1, with: g, run: fn(g, dx) {
      apply(g, dx, dy)
    })
  })
}

/// Draws every function pattern. Format bits get a placeholder so the data
/// path skips them; the real values are drawn after masking.
pub fn function_patterns(version: Int) -> Grid {
  let size = tables.size(version)
  let grid = Grid(size, dict.new(), dict.new())
  // Timing patterns.
  let grid =
    int.range(from: 0, to: size, with: grid, run: fn(g, i) {
      g
      |> set_function(6, i, i % 2 == 0)
      |> set_function(i, 6, i % 2 == 0)
    })
  // Finder patterns with their separators.
  let grid =
    [#(3, 3), #(size - 4, 3), #(3, size - 4)]
    |> list.fold(grid, fn(g, centre) {
      each_offset(g, 4, fn(g, dx, dy) {
        let x = centre.0 + dx
        let y = centre.1 + dy
        let distance = int.max(int.absolute_value(dx), int.absolute_value(dy))
        case x >= 0 && x < size && y >= 0 && y < size {
          True -> set_function(g, x, y, distance != 2 && distance != 4)
          False -> g
        }
      })
    })
  // Alignment patterns, except where they would overlap a finder.
  let positions = tables.alignment_positions(version)
  let last = list.length(positions) - 1
  let grid =
    list.index_fold(positions, grid, fn(g, cx, i) {
      list.index_fold(positions, g, fn(g, cy, j) {
        let corner =
          { i == 0 && j == 0 }
          || { i == 0 && j == last }
          || { i == last && j == 0 }
        case corner {
          True -> g
          False ->
            each_offset(g, 2, fn(g, dx, dy) {
              let distance =
                int.max(int.absolute_value(dx), int.absolute_value(dy))
              set_function(g, cx + dx, cy + dy, distance != 1)
            })
        }
      })
    })
  let grid = draw_format(grid, 0)
  draw_version(grid, version)
}

fn bit(value: Int, i: Int) -> Bool {
  int.bitwise_and(int.bitwise_shift_right(value, i), 1) == 1
}

/// 15-bit format word: 2 ECL bits, 3 mask bits, a BCH(15,5) remainder and the
/// fixed XOR mask 0x5412.
pub fn format_word(ecl: Ecl, mask: Int) -> Int {
  let data =
    int.bitwise_or(int.bitwise_shift_left(tables.format_bits(ecl), 3), mask)
  let remainder =
    int.range(from: 0, to: 10, with: data, run: fn(r, _) {
      int.bitwise_exclusive_or(
        int.bitwise_shift_left(r, 1),
        int.bitwise_shift_right(r, 9) * 0x537,
      )
    })
  int.bitwise_exclusive_or(
    int.bitwise_or(
      int.bitwise_shift_left(data, 10),
      int.bitwise_and(remainder, 0x3FF),
    ),
    0x5412,
  )
}

fn draw_format(grid: Grid, word: Int) -> Grid {
  let size = grid.size
  // Copy around the top-left finder.
  let grid =
    int.range(from: 0, to: 6, with: grid, run: fn(g, i) {
      set_function(g, 8, i, bit(word, i))
    })
  let grid =
    grid
    |> set_function(8, 7, bit(word, 6))
    |> set_function(8, 8, bit(word, 7))
    |> set_function(7, 8, bit(word, 8))
  let grid =
    int.range(from: 9, to: 15, with: grid, run: fn(g, i) {
      set_function(g, 14 - i, 8, bit(word, i))
    })
  // Second copy, split between the other two finders.
  let grid =
    int.range(from: 0, to: 8, with: grid, run: fn(g, i) {
      set_function(g, size - 1 - i, 8, bit(word, i))
    })
  let grid =
    int.range(from: 8, to: 15, with: grid, run: fn(g, i) {
      set_function(g, 8, size - 15 + i, bit(word, i))
    })
  // The "dark module", always set.
  set_function(grid, 8, size - 8, True)
}

/// 18-bit version word (versions 7+): version plus a BCH(18,6) remainder.
pub fn version_word(version: Int) -> Int {
  let remainder =
    int.range(from: 0, to: 12, with: version, run: fn(r, _) {
      int.bitwise_exclusive_or(
        int.bitwise_shift_left(r, 1),
        int.bitwise_shift_right(r, 11) * 0x1F25,
      )
    })
  int.bitwise_or(
    int.bitwise_shift_left(version, 12),
    int.bitwise_and(remainder, 0xFFF),
  )
}

fn draw_version(grid: Grid, version: Int) -> Grid {
  case version < 7 {
    True -> grid
    False -> {
      let word = version_word(version)
      int.range(from: 0, to: 18, with: grid, run: fn(g, i) {
        let a = grid.size - 11 + i % 3
        let b = i / 3
        g
        |> set_function(a, b, bit(word, i))
        |> set_function(b, a, bit(word, i))
      })
    }
  }
}

/// Every non-function coordinate in data-placement order: two-module-wide
/// columns from the right edge, alternating upward and downward, skipping the
/// vertical timing column.
pub fn data_path(grid: Grid) -> List(#(Int, Int)) {
  let size = grid.size
  column_pairs(size - 1, [])
  |> list.flat_map(fn(right) {
    let upward = int.bitwise_and(right + 1, 2) == 0
    int.range(from: 0, to: size, with: [], run: fn(acc, vert) {
      let y = case upward {
        True -> size - 1 - vert
        False -> vert
      }
      [#(right - 1, y), #(right, y), ..acc]
    })
    |> list.reverse
  })
  |> list.filter(fn(p) { !dict.has_key(grid.function, p) })
}

fn column_pairs(right: Int, acc: List(Int)) -> List(Int) {
  case right < 1 {
    True -> list.reverse(acc)
    False -> {
      let right = case right == 6 {
        True -> 5
        False -> right
      }
      column_pairs(right - 2, [right, ..acc])
    }
  }
}

/// Places the codeword bits; leftover remainder modules stay light.
pub fn place(grid: Grid, codewords: List(Int)) -> Grid {
  let bits = list.flat_map(codewords, segment.int_bits(_, 8))
  let modules = place_loop(data_path(grid), bits, grid.modules)
  Grid(..grid, modules: modules)
}

fn place_loop(
  path: List(#(Int, Int)),
  bits: List(Bool),
  modules: Dict(#(Int, Int), Bool),
) -> Dict(#(Int, Int), Bool) {
  case path, bits {
    [], _ -> modules
    [p, ..rest], [] -> place_loop(rest, [], dict.insert(modules, p, False))
    [p, ..rest], [b, ..more] ->
      place_loop(rest, more, dict.insert(modules, p, b))
  }
}

pub fn mask_hits(mask: Int, x: Int, y: Int) -> Bool {
  case mask {
    0 -> { x + y } % 2 == 0
    1 -> y % 2 == 0
    2 -> x % 3 == 0
    3 -> { x + y } % 3 == 0
    4 -> { x / 3 + y / 2 } % 2 == 0
    5 -> x * y % 2 + x * y % 3 == 0
    6 -> { x * y % 2 + x * y % 3 } % 2 == 0
    _ -> { { x + y } % 2 + x * y % 3 } % 2 == 0
  }
}

/// The finished symbol for one mask, as rows of booleans (True = dark).
pub fn render(grid: Grid, ecl: Ecl, mask: Int) -> List(List(Bool)) {
  let grid = draw_format(grid, format_word(ecl, mask))
  let size = grid.size
  int.range(from: 0, to: size, with: [], run: fn(rows, y) {
    let row =
      int.range(from: 0, to: size, with: [], run: fn(row, x) {
        let dark = is_dark(grid, x, y)
        let dark = case dict.has_key(grid.function, #(x, y)) {
          True -> dark
          False -> dark != mask_hits(mask, x, y)
        }
        [dark, ..row]
      })
    [list.reverse(row), ..rows]
  })
  |> list.reverse
}

// --- Penalty rules (ISO/IEC 18004 §7.8.3) ----------------------------------

pub fn penalty(rows: List(List(Bool))) -> Int {
  let columns = list.transpose(rows)
  let lines = list.append(rows, columns)
  let runs = lines |> list.map(run_penalty) |> int.sum
  let finders = lines |> list.map(finder_penalty) |> int.sum
  runs + block_penalty(rows) + finders + balance_penalty(rows)
}

/// Rule 1: five or more same-coloured modules in a row: 3 + (length − 5).
fn run_penalty(line: List(Bool)) -> Int {
  line
  |> list.chunk(fn(x) { x })
  |> list.map(list.length)
  |> list.filter(fn(n) { n >= 5 })
  |> list.map(fn(n) { 3 + n - 5 })
  |> int.sum
}

/// Rule 2: every 2×2 block of one colour: 3.
fn block_penalty(rows: List(List(Bool))) -> Int {
  rows
  |> list.window_by_2
  |> list.map(fn(pair) {
    list.zip(pair.0, pair.1)
    |> list.window_by_2
    |> list.count(fn(cells) {
      let #(#(a, b), #(c, d)) = cells
      a == b && b == c && c == d
    })
  })
  |> int.sum
  |> int.multiply(3)
}

const finder_like_a = [
  True,
  False,
  True,
  True,
  True,
  False,
  True,
  False,
  False,
  False,
  False,
]

const finder_like_b = [
  False,
  False,
  False,
  False,
  True,
  False,
  True,
  True,
  True,
  False,
  True,
]

/// Rule 3: a 1:1:3:1:1 finder look-alike with four light modules on one side
/// (the quiet zone counts as light): 40 each.
fn finder_penalty(line: List(Bool)) -> Int {
  let quiet = list.repeat(False, 4)
  list.flatten([quiet, line, quiet])
  |> list.window(11)
  |> list.count(fn(w) { w == finder_like_a || w == finder_like_b })
  |> int.multiply(40)
}

/// Rule 4: 10 points for every 5 % the dark share deviates from 50 %.
fn balance_penalty(rows: List(List(Bool))) -> Int {
  let cells = list.flatten(rows)
  let total = list.length(cells)
  let dark = list.count(cells, fn(c) { c })
  let deviation = int.absolute_value(dark * 20 - total * 10)
  let k = { deviation + total - 1 } / total - 1
  int.max(k, 0) * 10
}
