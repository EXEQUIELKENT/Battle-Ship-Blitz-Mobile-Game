import 'dart:math';

import 'game_models.dart';

/// The kinds of daily puzzle there are.
///
/// One puzzle per calendar day, and the day's seed picks WHICH kind — so
/// every device still gets the same puzzle on the same date, but the slot
/// is never just "the same hunt again". The five play very differently:
/// some are about finding the fleet, one about wasting nothing, one about
/// restraint, one about order, and one about holding your nerve.
enum DailyPuzzleType {
  /// Sink the whole fleet inside the shot budget. The classic hunt.
  hunt('DAILY HUNT', 'Sink the whole fleet.'),

  /// Sink the whole fleet with almost no misses to spare — every wasted
  /// shell counts against you.
  precision('PRECISION', 'Sink the fleet. Misses are expensive.'),

  /// Sink the MARKED ships and leave the rest of the fleet alone.
  /// Sinking one of the unmarked ships ends the puzzle.
  marked('MARKED HUNT', 'Sink the marked ships only. Leave the rest.'),

  /// Sink the marked ship FIRST, then the rest of the fleet. Touching
  /// any other hull before that ends the puzzle.
  firstStrike('FIRST STRIKE', 'Sink the marked ship first, then the fleet.'),

  /// Land a run of consecutive hits. A miss breaks the run but does not
  /// end the puzzle — only running out of shells does.
  hotStreak('HOT STREAK', 'Land hits without breaking the chain.');

  const DailyPuzzleType(this.title, this.objective);

  /// The name on the puzzle's banner.
  final String title;

  /// The one-line brief under the name.
  final String objective;
}

/// Daily puzzle: one pre-seeded enemy fleet per calendar day — four hulls,
/// so it plays as a quick hunt rather than a full battle — and one kind
/// of puzzle ([type]) to play it as. The seed picks both, so every
/// device (and every replay) gets the same board and the same brief for
/// the same date.
class DailyPuzzle {
  /// Hulls per puzzle. Four hulls means more water to hunt in and more
  /// targets to keep track of than the old three.
  static const int shipCount = 4;

  /// Misses the budget forgives on top of the fleet's own cells.
  static const int missAllowance = 5;

  /// ...and how few a [DailyPuzzleType.precision] puzzle forgives —
  /// basically one careless shot and you are done.
  static const int tightMissAllowance = 1;

  /// ...and how many a [DailyPuzzleType.hotStreak] puzzle does: this one
  /// is about never missing twice in a row, so it can afford a few misses
  /// as long as they are not consecutive.
  static const int streakMissAllowance = 6;

  /// Consecutive hits a [DailyPuzzleType.hotStreak] puzzle needs — one
  /// harder than it used to be.
  static const int streakGoal = 5;

  final DailyPuzzleType type;
  final Board board;

  /// The ships the player is meant to sink (the MARKED / FIRST STRIKE
  /// targets). Empty for the types that are about the whole fleet.
  final Set<ShipKind> targetKinds;

  /// Consecutive hits this puzzle needs (hot streak puzzles only).
  final int chainGoal;

  /// Shots allowed, dealt with the fleet: its cells plus whatever
  /// allowance this puzzle's type forgives.
  final int shotBudget;

  final List<List<int>> shots =
      List.generate(kBoardSize, (_) => List.filled(kBoardSize, 0));

  int shotsFired = 0;

  /// The current run of consecutive hits (hot streak puzzles).
  int streak = 0;

  /// The longest run this attempt managed.
  int bestStreak = 0;

  /// Set when the player breaks a puzzle's own rule — sinking a ship
  /// that was to be left alone, or striking one before the marked ship.
  bool _violated = false;

  factory DailyPuzzle({required int seed}) {
    final rng = Random(seed);
    // The type is drawn FIRST, then the board, from the same generator —
    // so the type and the fleet are both fixed by the date, and neither
    // can drift from the other.
    final type = DailyPuzzleType
        .values[rng.nextInt(DailyPuzzleType.values.length)];
    final specs = (List.of(kFleet)..shuffle(rng)).take(shipCount).toList();
    final board = Board.random(rng: rng, specs: specs);
    final cells = specs.fold<int>(0, (n, s) => n + s.size);

    // Which hulls are the marked ones: one for FIRST STRIKE, one or two
    // for MARKED HUNT, none for the rest.
    final targets = <ShipKind>{};
    switch (type) {
      case DailyPuzzleType.firstStrike:
        targets.add(specs[rng.nextInt(specs.length)].kind);
      case DailyPuzzleType.marked:
        final howMany = 1 + rng.nextInt(2);
        final pool = List.of(specs);
        pool.shuffle(rng);
        targets.addAll(pool.take(howMany).map((s) => s.kind));
      case DailyPuzzleType.hunt:
      case DailyPuzzleType.precision:
      case DailyPuzzleType.hotStreak:
        break;
    }

    final budget = switch (type) {
      DailyPuzzleType.precision => cells + tightMissAllowance,
      DailyPuzzleType.hotStreak => cells + streakMissAllowance,
      DailyPuzzleType.marked =>
          specs.fold<int>(0, (n, s) => targets.contains(s.kind)
              ? n + s.size
              : n) +
          streakMissAllowance,
      DailyPuzzleType.firstStrike => cells + tightMissAllowance + 1,
      DailyPuzzleType.hunt => cells + missAllowance,
    };

    return DailyPuzzle._(
      type: type,
      board: board,
      targetKinds: targets,
      chainGoal: streakGoal,
      shotBudget: budget,
    );
  }

  DailyPuzzle._({
    required this.type,
    required this.board,
    required this.targetKinds,
    required this.chainGoal,
    required this.shotBudget,
  });

  int get shotsLeft => shotBudget - shotsFired;

  List<PlacedShip> get sunkShips =>
      [for (final s in board.ships) if (s.isSunk) s];

  /// The ships this puzzle wants drawn on the board — the marked ones
  /// only, and only while they still matter. Null means "reveal nothing",
  /// which is every type that is about hunting blind.
  List<PlacedShip>? get revealedShips {
    if (targetKinds.isEmpty) return null;
    if (type == DailyPuzzleType.firstStrike) {
      // The target is on show until it goes down; after that the rest of
      // the fleet is a normal blind hunt.
      final target = board.shipOfKind(targetKinds.first);
      if (target == null || target.isSunk) return null;
      return [target];
    }
    return [
      for (final s in board.ships)
        if (targetKinds.contains(s.spec.kind) && !s.isSunk) s,
    ];
  }

  /// Whether the marked target of a FIRST STRIKE puzzle is already down.
  bool get firstStrikeDone => targetKinds.isNotEmpty &&
      (board.shipOfKind(targetKinds.first)?.isSunk ?? false);

  /// The puzzle's own progress, as a short line for the HUD.
  String get progressLabel => switch (type) {
        DailyPuzzleType.hotStreak =>
          'STREAK  $streak/$chainGoal   BEST $bestStreak',
        DailyPuzzleType.marked => 'TARGETS  $_targetsSunk/${targetKinds.length}'
            '   SHIPS SUNK ${sunkShips.length}/$shipCount',
        DailyPuzzleType.firstStrike => firstStrikeDone
            ? 'TARGET DOWN — SINK THE REST  ${sunkShips.length}/$shipCount'
            : 'SINK THE MARKED SHIP FIRST',
        DailyPuzzleType.hunt ||
        DailyPuzzleType.precision =>
          'SUNK  ${sunkShips.length}/$shipCount',
      };

  int get _targetsSunk => [
        for (final k in targetKinds)
          if (board.shipOfKind(k)?.isSunk ?? false) 1,
      ].length;

  /// The one-line brief for this puzzle's banner.
  String get brief => switch (type) {
        DailyPuzzleType.hunt => 'Sink the fleet in $shotBudget shots.',
        DailyPuzzleType.precision =>
          'Sink the fleet in $shotBudget shots. No room to waste.',
        DailyPuzzleType.marked =>
          'Sink the ${targetKinds.length} marked ship'
              '${targetKinds.length == 1 ? '' : 's'}. '
              'Sink an unmarked ship and it is over.',
        DailyPuzzleType.firstStrike =>
          'Sink the marked ship FIRST. Touch another hull first and it is over.',
        DailyPuzzleType.hotStreak =>
          'Land $chainGoal hits in a row. A miss breaks the chain.',
      };

  bool get solved => switch (type) {
        DailyPuzzleType.hunt => board.allSunk,
        DailyPuzzleType.precision => board.allSunk,
        DailyPuzzleType.marked =>
          targetKinds.isNotEmpty && _targetsSunk == targetKinds.length,
        DailyPuzzleType.firstStrike => board.allSunk,
        DailyPuzzleType.hotStreak => bestStreak >= chainGoal,
      };

  bool get failed => _violated || (shotsFired >= shotBudget && !solved);
  bool get done => solved || failed;

  /// Why the puzzle ended badly, when it did — shown on the result panel.
  String? get failReason => _violated
      ? switch (type) {
          DailyPuzzleType.marked => 'You sank a ship that was to be left alone.',
          DailyPuzzleType.firstStrike =>
            'You struck another hull before the marked one.',
          _ => 'The rules of this puzzle were broken.',
        }
      : null;

  /// Fires at (r, c). Duplicate taps are refused (no budget spent);
  /// firing after the puzzle ended is invalid.
  ShotResult fire(int r, int c) {
    if (done) return ShotResult.invalid;
    if (r < 0 || r >= kBoardSize || c < 0 || c >= kBoardSize) {
      return ShotResult.invalid;
    }
    if (shots[r][c] != 0) return ShotResult.duplicate;
    final (result, sunk) = board.receiveShot(r, c);
    final hit = result == ShotResult.hit || result == ShotResult.sunk;
    shots[r][c] = hit ? 2 : 1;
    shotsFired++;

    // The chain (hot streak puzzles): a hit extends it, a miss breaks it.
    if (hit) {
      streak++;
      if (streak > bestStreak) bestStreak = streak;
    } else if (result == ShotResult.miss) {
      streak = 0;
    }

    // The type's own rule, checked on the shell that just landed.
    switch (type) {
      case DailyPuzzleType.marked:
        // Sinking a ship that was to be left alone ends it.
        if (sunk != null && !targetKinds.contains(sunk.spec.kind)) {
          _violated = true;
        }
      case DailyPuzzleType.firstStrike:
        // Striking ANY other hull before the marked one goes down ends it.
        if (hit && !firstStrikeDone) {
          final ship = board.shipAt(r, c);
          if (ship != null && !targetKinds.contains(ship.spec.kind)) {
            _violated = true;
          }
        }
      case DailyPuzzleType.hunt:
      case DailyPuzzleType.precision:
      case DailyPuzzleType.hotStreak:
        break;
    }
    return result;
  }
}
