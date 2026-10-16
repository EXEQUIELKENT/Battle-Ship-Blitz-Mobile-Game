import 'package:battleship_blitz/models/daily_puzzle.dart';
import 'package:battleship_blitz/models/game_models.dart';
import 'package:battleship_blitz/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

Set<String> _cells(DailyPuzzle p) => {
      for (final s in p.board.ships)
        for (final c in s.cells) '${c[0]},${c[1]}',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('same seed deals the same small fleet', () {
    final a = DailyPuzzle(seed: 20260101);
    final b = DailyPuzzle(seed: 20260101);
    expect(_cells(a), _cells(b));
    expect(a.board.ships.length, DailyPuzzle.shipCount);
    final cells =
        a.board.ships.fold<int>(0, (n, s) => n + s.spec.size);
    expect(a.shotBudget, cells + DailyPuzzle.missAllowance);
  });

  test('sinking the fleet solves within budget', () {
    final p = DailyPuzzle(seed: 20260601);
    var cells = 0;
    for (final s in p.board.ships) {
      for (final c in s.cells) {
        final res = p.fire(c[0], c[1]);
        expect(res == ShotResult.hit || res == ShotResult.sunk, isTrue);
        cells++;
      }
    }
    expect(p.solved, isTrue);
    expect(p.shotsFired, cells);
    expect(p.shotsFired, lessThanOrEqualTo(p.shotBudget));
  });

  test('a full budget of misses fails the puzzle', () {
    final p = DailyPuzzle(seed: 20260601);
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

  test('duplicate taps cost no budget', () {
    final p = DailyPuzzle(seed: 20260601);
    p.fire(0, 0);
    final after = p.shotsFired;
    expect(p.fire(0, 0), ShotResult.duplicate);
    expect(p.shotsFired, after);
  });

  group('once-per-day reward', () {
    test('solve pays 30 plus the one-time solver medal, replay pays nothing', () {
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
