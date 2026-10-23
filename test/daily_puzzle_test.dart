import 'package:battleship_blitz/models/daily_puzzle.dart';
import 'package:battleship_blitz/models/game_models.dart';
import 'package:battleship_blitz/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

Set<String> _cells(DailyPuzzle p) => {
      for (final s in p.board.ships)
        for (final c in s.cells) '${c[0]},${c[1]}',
    };

/// The first seed that deals a puzzle of [type] — the type is drawn
/// from the seed, so a test that wants a specific kind of puzzle has to
/// go looking for one.
int _seedFor(DailyPuzzleType type) {
  for (var seed = 1; seed < 20000; seed++) {
    if (DailyPuzzle(seed: seed).type == type) return seed;
  }
  throw StateError('no seed deals a ${type.name} puzzle');
}

/// Fires every cell of every ship on the board, in order.
void _sinkEverything(DailyPuzzle p) {
  for (final s in p.board.ships) {
    for (final c in s.cells) {
      p.fire(c[0], c[1]);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('same seed deals the same fleet AND the same kind of puzzle', () {
    final a = DailyPuzzle(seed: 20260101);
    final b = DailyPuzzle(seed: 20260101);
    expect(_cells(a), _cells(b));
    expect(a.type, b.type);
    expect(a.board.ships.length, DailyPuzzle.shipCount);
    final cells = a.board.ships.fold<int>(0, (n, s) => n + s.spec.size);
    expect(a.shotBudget, greaterThanOrEqualTo(cells));
  });

  test('four ships per puzzle, not three', () {
    final p = DailyPuzzle(seed: 20260101);
    expect(p.board.ships.length, DailyPuzzle.shipCount);
    expect(DailyPuzzle.shipCount, 4);
  });

  test('the daily slot rotates through every kind of puzzle', () {
    // The type is drawn from the date seed, so every device plays the
    // same one on the same day — and over a stretch of days each kind
    // comes up.
    final seen = <DailyPuzzleType>{};
    for (var day = 1; day <= 60; day++) {
      final seed = ProfileStore.dailyPuzzleSeed(DateTime(2026, 1, day));
      final p = DailyPuzzle(seed: seed);
      expect(DailyPuzzle(seed: seed).type, p.type,
          reason: 'the same date must deal the same kind of puzzle');
      seen.add(p.type);
    }
    expect(seen, hasLength(DailyPuzzleType.values.length),
        reason: 'every kind of puzzle must come up in a two-month run');
  });

  group('a plain hunt', () {
    test('sinking the fleet solves it', () {
      final p = DailyPuzzle(seed: _seedFor(DailyPuzzleType.hunt));
      _sinkEverything(p);
      expect(p.solved, isTrue);
      expect(p.failed, isFalse);
      expect(p.shotsFired, lessThanOrEqualTo(p.shotBudget));
    });

    test('running out of shots fails it', () {
      final p = DailyPuzzle(seed: _seedFor(DailyPuzzleType.hunt));
      final ship = _cells(p);
      var fired = 0;
      for (var r = 0; r < kBoardSize && fired < p.shotBudget; r++) {
        for (var c = 0; c < kBoardSize && fired < p.shotBudget; c++) {
          if (ship.contains('$r,$c')) continue;
          expect(p.fire(r, c), ShotResult.miss);
          fired++;
        }
      }
      expect(fired, p.shotBudget);
      expect(p.failed, isTrue);
      expect(p.solved, isFalse);
    });

    test('five misses is all the budget forgives', () {
      final p = DailyPuzzle(seed: _seedFor(DailyPuzzleType.hunt));
      final cells =
          p.board.ships.fold<int>(0, (n, s) => n + s.spec.size);
      expect(p.shotBudget - cells, DailyPuzzle.missAllowance);
    });
  });

  group('a precision puzzle', () {
    test('allows far fewer misses than a plain hunt', () {
      final hunt = DailyPuzzle(seed: _seedFor(DailyPuzzleType.hunt));
      final precision =
          DailyPuzzle(seed: _seedFor(DailyPuzzleType.precision));
      final huntCells =
          hunt.board.ships.fold<int>(0, (n, s) => n + s.spec.size);
      final precisionCells =
          precision.board.ships.fold<int>(0, (n, s) => n + s.spec.size);
      // The ALLOWANCE is what differs, not the fleet.
      expect(hunt.shotBudget - huntCells,
          DailyPuzzle.missAllowance);
      expect(precision.shotBudget - precisionCells,
          DailyPuzzle.tightMissAllowance);
    });

    test('sinking the fleet still solves it', () {
      final p = DailyPuzzle(seed: _seedFor(DailyPuzzleType.precision));
      _sinkEverything(p);
      expect(p.solved, isTrue);
    });
  });

  group('a marked hunt', () {
    test('the targets are marked and revealed', () {
      final p = DailyPuzzle(seed: _seedFor(DailyPuzzleType.marked));
      expect(p.targetKinds, isNotEmpty);
      expect(p.revealedShips, isNotNull);
      for (final s in p.revealedShips!) {
        expect(p.targetKinds, contains(s.spec.kind));
      }
    });

    test('sinking the marked ships solves it', () {
      final p = DailyPuzzle(seed: _seedFor(DailyPuzzleType.marked));
      for (final s in p.board.ships) {
        if (!p.targetKinds.contains(s.spec.kind)) continue;
        for (final c in s.cells) {
          p.fire(c[0], c[1]);
        }
      }
      expect(p.solved, isTrue);
      expect(p.failed, isFalse);
    });

    test('sinking an unmarked ship ends the puzzle', () {
      final p = DailyPuzzle(seed: _seedFor(DailyPuzzleType.marked));
      final bystander = p.board.ships
          .firstWhere((s) => !p.targetKinds.contains(s.spec.kind));
      for (final c in bystander.cells) {
        p.fire(c[0], c[1]);
      }
      expect(p.failed, isTrue,
          reason: 'the unmarked ship was to be left alone');
      expect(p.failReason, isNotNull);
    });
  });

  group('a first-strike puzzle', () {
    test('the target is revealed and the rest is not', () {
      final p = DailyPuzzle(seed: _seedFor(DailyPuzzleType.firstStrike));
      expect(p.targetKinds, hasLength(1));
      expect(p.revealedShips, hasLength(1));
      expect(p.revealedShips!.single.spec.kind, p.targetKinds.first);
    });

    test('the target first, then the rest, solves it', () {
      final p = DailyPuzzle(seed: _seedFor(DailyPuzzleType.firstStrike));
      final target = p.board.shipOfKind(p.targetKinds.first)!;
      for (final c in target.cells) {
        p.fire(c[0], c[1]);
      }
      expect(p.firstStrikeDone, isTrue);
      expect(p.failed, isFalse, reason: 'the marked ship went down first');
      // The rest of the fleet is now a normal blind hunt.
      expect(p.revealedShips, isNull);
      for (final s in p.board.ships) {
        if (p.targetKinds.contains(s.spec.kind)) continue;
        for (final c in s.cells) {
          p.fire(c[0], c[1]);
        }
      }
      expect(p.solved, isTrue);
    });

    test('striking another hull first ends the puzzle', () {
      final p = DailyPuzzle(seed: _seedFor(DailyPuzzleType.firstStrike));
      final other = p.board.ships
          .firstWhere((s) => !p.targetKinds.contains(s.spec.kind));
      p.fire(other.cells.first[0], other.cells.first[1]);
      expect(p.failed, isTrue,
          reason: 'the marked ship had to go down first');
    });
  });

  group('a hot-streak puzzle', () {
    test('a run of hits solves it, and a miss breaks the run', () {
      final p = DailyPuzzle(seed: _seedFor(DailyPuzzleType.hotStreak));
      expect(p.chainGoal, DailyPuzzle.streakGoal);
      // One miss, then a run of hits.
      final empty = <String>{
        for (var r = 0; r < kBoardSize; r++)
          for (var c = 0; c < kBoardSize; c++) '$r,$c',
      }..removeAll(_cells(p));
      final miss = empty.first.split(',');
      p.fire(int.parse(miss[0]), int.parse(miss[1]));
      expect(p.streak, 0, reason: 'a miss breaks the chain');

      // Now hit the fleet, cell by cell, without missing again.
      for (final s in p.board.ships) {
        for (final c in s.cells) {
          if (p.solved) break;
          p.fire(c[0], c[1]);
        }
      }
      expect(p.bestStreak, greaterThanOrEqualTo(p.chainGoal));
      expect(p.solved, isTrue);
    });

    test('it forgives fewer misses than a plain hunt', () {
      final p = DailyPuzzle(seed: _seedFor(DailyPuzzleType.hotStreak));
      final cells =
          p.board.ships.fold<int>(0, (n, s) => n + s.spec.size);
      expect(p.shotBudget - cells, DailyPuzzle.streakMissAllowance);
    });
  });

  test('duplicate taps cost no budget', () {
    final p = DailyPuzzle(seed: 20260601);
    p.fire(0, 0);
    final after = p.shotsFired;
    expect(p.fire(0, 0), ShotResult.duplicate);
    expect(p.shotsFired, after);
  });

  group('once-per-day reward', () {
    test('solve pays 30 plus the one-time solver medal, replay pays nothing',
        () {
      final profile = ProfileStore();
      final day = DateTime(2026, 6, 1);
      final before = profile.doubloons;
      expect(profile.claimDailyPuzzleReward(solved: true, now: day), 30);
      // 30 solve reward + 20 first-solve medal (see awards_test).
      expect(profile.doubloons, before + 50);
      expect(profile.dailyPuzzleStreak, 1);
      // Same day again — free replay, no pay.
      expect(profile.claimDailyPuzzleReward(solved: true, now: day), 0);
      expect(profile.doubloons, before + 50);
    });

    test('consecutive solves grow the streak payout', () {
      final profile = ProfileStore();
      expect(
          profile.claimDailyPuzzleReward(
              solved: true, now: DateTime(2026, 6, 1)),
          30);
      expect(
          profile.claimDailyPuzzleReward(
              solved: true, now: DateTime(2026, 6, 2)),
          35);
      expect(profile.dailyPuzzleStreak, 2);
    });

    test('a fail pays 5 and breaks the streak', () {
      final profile = ProfileStore();
      profile.claimDailyPuzzleReward(
          solved: true, now: DateTime(2026, 6, 1));
      expect(profile.dailyPuzzleStreak, 1);
      expect(
          profile.claimDailyPuzzleReward(
              solved: false, now: DateTime(2026, 6, 2)),
          5);
      expect(profile.dailyPuzzleStreak, 0);
    });

    test('a skipped day resets the streak', () {
      final profile = ProfileStore();
      profile.claimDailyPuzzleReward(
          solved: true, now: DateTime(2026, 6, 1));
      expect(
          profile.claimDailyPuzzleReward(
              solved: true, now: DateTime(2026, 6, 5)),
          30);
      expect(profile.dailyPuzzleStreak, 1);
    });
  });
}
