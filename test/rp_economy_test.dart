import 'package:battleship_blitz/models/game_models.dart';
import 'package:battleship_blitz/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Purchases read the unlock-all flag — off here so cost is real.
  setUpAll(() => ProfileStore.debugUnlockAllOverride = false);
  tearDownAll(() => ProfileStore.debugUnlockAllOverride = null);

  group('RP vs Doubloons split', () {
    test('buying never lowers rank', () {
      final p = ProfileStore()
        ..rp = 1500
        ..doubloons = 99999
        ..owned = {'ship:steel', 'cannon:mk1', 'theme:mk1'};
      final beforeRp = p.rp;
      expect(p.equipShipSkin(Catalog.shipById('f_volcanic')), isTrue);
      expect(p.rp, beforeRp);
      expect(p.doubloons, 99999 - Catalog.shipById('f_volcanic').cost);
    });

    test('Elo: beating stronger opponent pays more than beating weaker', () {
      final underdog = ProfileStore()..rp = 1000;
      final gainVsStrong =
          underdog.recordResult(won: true, opponentRp: 1400);
      final favorite = ProfileStore()..rp = 1400;
      final gainVsWeak = favorite.recordResult(won: true, opponentRp: 1000);
      expect(gainVsStrong, greaterThan(gainVsWeak));
      expect(gainVsStrong, lessThanOrEqualTo(36));
      expect(gainVsWeak, greaterThanOrEqualTo(8));
    });

    test('Elo break-even is 50%: equal win/loss cancel out', () {
      final p = ProfileStore()..rp = 1000;
      final win = p.recordResult(won: true, opponentRp: 1000);
      final loss = p.recordResult(won: false, opponentRp: 1000);
      // +16..17 win vs -16 loss -> net ~0, not the old +10 drift.
      expect((win + loss).abs(), lessThanOrEqualTo(4));
    });

    test('Rookie wins diminish and pay less than Admiral', () {
      final rookie = ProfileStore()..rp = 1000;
      final first = rookie.recordResult(
          won: true, aiDifficulty: AIDifficulty.easy);
      final second = rookie.recordResult(
          won: true, aiDifficulty: AIDifficulty.easy);
      final third = rookie.recordResult(
          won: true, aiDifficulty: AIDifficulty.easy);
      expect(second, lessThan(first));
      expect(third, lessThanOrEqualTo(second));
      final admiral = ProfileStore()..rp = 1000;
      final hard =
          admiral.recordResult(won: true, aiDifficulty: AIDifficulty.hard);
      expect(hard, greaterThan(first));
    });

    test('losses still earn Doubloons but lose RP', () {
      final p = ProfileStore()
        ..rp = 1000
        ..doubloons = 100;
      final dRp = p.recordResult(won: false, opponentRp: 1000);
      expect(dRp, lessThan(0));
      expect(p.lastDoubloonsDelta, greaterThan(0));
      expect(p.doubloons, greaterThan(100));
    });
  });
}
