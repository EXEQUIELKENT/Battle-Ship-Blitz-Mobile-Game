import 'dart:math';

import 'game_models.dart';

/// Daily puzzle: one pre-seeded enemy fleet per calendar day — just three
/// hulls, so it plays as a quick hunt rather than a full battle — sink it
/// within [shotBudget] shots. Local-only, no server — the seed IS the
/// puzzle, so every device (and every replay) gets the same board for
/// the same date.
class DailyPuzzle {
  /// Hulls per puzzle. Three keeps it solvable over coffee: enough water
  /// to hunt in, few enough hulls that every hit matters.
  static const int shipCount = 3;

  /// Misses the budget forgives on top of the fleet's own cells — the
  /// same allowance the old five-hull puzzle gave, so a smaller fleet
  /// means a smaller budget, not a stricter one.
  static const int missAllowance = 7;

  /// Shots allowed, dealt with the fleet: its cells plus [missAllowance].
  final int shotBudget;

  final Board board;
  final List<List<int>> shots =
      List.generate(kBoardSize, (_) => List.filled(kBoardSize, 0));

  int shotsFired = 0;

  factory DailyPuzzle({required int seed}) {
    final rng = Random(seed);
    final specs = (List.of(kFleet)..shuffle(rng)).take(shipCount).toList();
    final board = Board.random(rng: rng, specs: specs);
    final cells = specs.fold<int>(0, (n, s) => n + s.size);
    return DailyPuzzle._(board, cells + missAllowance);
  }

  DailyPuzzle._(this.board, this.shotBudget);

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
