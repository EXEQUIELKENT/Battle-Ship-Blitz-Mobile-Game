import 'dart:math';

import '../models/game_models.dart';

/// Pure cell-picking logic for the vs-AI opponent — deliberately free of
/// `GameController`/`Board` so the search itself can be unit-tested
/// without a running match. [AiBrain] is the stateful piece that decides
/// WHEN to fire and feeds this the right grid; this only decides WHERE.
class AiTargeting {
  AiTargeting._();

  /// Classic Battleship "hunt" parity: every ship in this game is at
  /// least 2 cells long, so any ship's footprint always includes at
  /// least one cell where `(row + col)` is even. Restricting the blind
  /// search to that checkerboard still guarantees finding every ship
  /// while trying roughly half as many cells as a plain sweep.
  static bool onHuntParity(int row, int col) => (row + col).isEven;

  /// Picks the next cell to fire at.
  ///
  /// [shots] is whatever grid the caller considers "already tried" — the
  /// real `myShots` array for every mode except GHOST FLEET, where the
  /// brain must pass its own fallible memory instead (see the doc on
  /// `AiBrain._memory` for why using the real array there would be an
  /// unfair perfect memory). A cell counts as tried when its value is
  /// non-zero.
  ///
  /// [huntQueue] is a list of specific follow-up cells worth trying next
  /// — nearest-neighbours of a hit not yet finished off — consumed
  /// nearest-first before falling back to the checkerboard search.
  /// Mutated in place (drained as candidates are consumed or found
  /// already-tried), since the caller owns one persistent queue across
  /// the whole match.
  ///
  /// Returns null only when every cell on the board has been tried.
  static (int, int)? pickTarget({
    required List<List<int>> shots,
    required List<(int, int)> huntQueue,
    required Random rng,
  }) {
    while (huntQueue.isNotEmpty) {
      final cell = huntQueue.removeAt(0);
      if (_inBounds(cell.$1, cell.$2) && shots[cell.$1][cell.$2] == 0) {
        return cell;
      }
    }

    final parityCells = <(int, int)>[];
    final anyCells = <(int, int)>[];
    for (var r = 0; r < kBoardSize; r++) {
      for (var c = 0; c < kBoardSize; c++) {
        if (shots[r][c] != 0) continue;
        anyCells.add((r, c));
        if (onHuntParity(r, c)) parityCells.add((r, c));
      }
    }
    // The endgame — once the checkerboard itself is exhausted but odd
    // cells between confirmed hits/misses remain — falls back to
    // whatever is left rather than declaring nowhere left to shoot.
    final pool = parityCells.isNotEmpty ? parityCells : anyCells;
    if (pool.isEmpty) return null;
    return pool[rng.nextInt(pool.length)];
  }

  /// The orthogonal neighbours of a hit at (row, col) worth queuing as
  /// follow-up targets, shuffled so the brain doesn't always probe in the
  /// same compass order turn after turn.
  static List<(int, int)> neighborsOf(int row, int col, Random rng) {
    final out = [
      (row - 1, col),
      (row + 1, col),
      (row, col - 1),
      (row, col + 1),
    ].where((p) => _inBounds(p.$1, p.$2)).toList();
    out.shuffle(rng);
    return out;
  }

  static bool _inBounds(int r, int c) =>
      r >= 0 && r < kBoardSize && c >= 0 && c < kBoardSize;
}
