import 'dart:math';

import 'game_models.dart';

/// Daily puzzle: one pre-seeded enemy fleet per calendar day, sink it
/// within [shotBudget] shots. Local-only, no server — the seed IS the
/// puzzle, so every device (and every replay) gets the same board for
/// the same date.
class DailyPuzzle {
  /// Shots allowed. The fleet covers 17 cells; 24 leaves room for
  /// misses while still demanding real hunting.
  static const int shotBudget = 24;

  final Board board;
  final List<List<int>> shots =
      List.generate(kBoardSize, (_) => List.filled(kBoardSize, 0));

  int shotsFired = 0;

  DailyPuzzle({required int seed}) : board = Board.random(rng: Random(seed));

  int get shotsLeft => shotBudget - shotsFired;

  List<PlacedShip> get sunkShips =>
      [for (final s in board.ships) if (s.isSunk) s];

  bool get solved => board.allSunk;
  bool get failed => shotsFired >= shotBudget && !solved;
  bool get done => solved || failed;

  /// Fires at (r, c). Duplicate taps are refused (no budget spent);
  /// firing after the puzzle ended is invalid.
  ShotResult fire(int r, int c) {
    if (done) return ShotResult.invalid;
    if (r < 0 || r >= kBoardSize || c < 0 || c >= kBoardSize) {
      return ShotResult.invalid;
    }
    if (shots[r][c] != 0) return ShotResult.duplicate;
    final (result, _) = board.receiveShot(r, c);
    shots[r][c] =
        (result == ShotResult.hit || result == ShotResult.sunk) ? 2 : 1;
    shotsFired++;
    return result;
  }
}
