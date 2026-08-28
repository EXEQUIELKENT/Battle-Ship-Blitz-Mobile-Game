import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:battleship_blitz/models/game_models.dart';
import 'package:battleship_blitz/services/game_controller.dart';
import 'package:battleship_blitz/services/network_service.dart';
import 'package:battleship_blitz/services/storage_service.dart';

/// Regression coverage for the deferred end-game transition (see the
/// bugfix note on `GameController.hasPendingFinish`): the match must be
/// logically decided the instant the winning shot is registered (so board
/// state, AI targeting, etc. stay correct), but must NOT flip to
/// `BattlePhase.finished` — and must not award RP or play the victory/
/// defeat sound — until the battle screen confirms that shot's projectile
/// has visually landed by calling `resolvePendingFinishFor`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<GameController> newController() async {
    SharedPreferences.setMockInitialValues({});
    final profile = ProfileStore();
    await profile.load();
    final controller = GameController(profile: profile, network: NetworkService());
    controller.mode = GameMode.vsAI;
    // `Board.allSunk` is vacuously true for a board with no ships at all,
    // so the player's OWN board (index 0) needs at least one live ship —
    // otherwise `_checkVictory` would immediately arm a false "loss" the
    // moment ANY hit is registered, before the enemy fleet is even
    // touched. `beginBattle` only ever populates boards[1] (the enemy
    // fleet), so this has to be seeded separately, same as the real game
    // does via the placement screen.
    controller.boards[0] = Board()..place(kFleet.first, 5, 0, true);
    return controller;
  }

  group('GameController deferred finish', () {
    test('final winning shot arms but does not finish the match', () async {
      final controller = await newController();
      final enemyBoard = Board();
      // A single 2-cell ship is enough to exercise "last ship, last shot".
      enemyBoard.place(kFleet.last, 0, 0, true);
      controller.beginBattle(enemyBoard: enemyBoard);

      // First shot: a hit, but the ship isn't sunk yet — must not arm.
      controller.fireAt(0, 0);
      expect(controller.phase, BattlePhase.battling);
      expect(controller.hasPendingFinish, isFalse);

      // Second shot sinks the last ship — the match IS decided now, but
      // must stay in battling phase until the projectile visually lands.
      controller.cooldown1 = 0; // bypass reload gate between test shots
      controller.fireAt(0, 1);

      expect(controller.phase, BattlePhase.battling,
          reason: 'must not advance to finished before the winning shot '
              'has visually landed');
      expect(controller.hasPendingFinish, isTrue);
      expect(controller.iWon, isFalse);

      final winningEvent = controller.events.last;
      expect(winningEvent.result, ShotResult.sunk);

      // An unrelated event must never be able to trigger the transition.
      final decoy = CombatEvent(
        row: 5,
        col: 5,
        result: ShotResult.miss,
        byPlayer: true,
      );
      controller.resolvePendingFinishFor(decoy);
      expect(controller.phase, BattlePhase.battling);
      expect(controller.hasPendingFinish, isTrue);

      // Resolving the ACTUAL winning event is what ends the match.
      controller.resolvePendingFinishFor(winningEvent);
      expect(controller.phase, BattlePhase.finished);
      expect(controller.hasPendingFinish, isFalse);
      expect(controller.iWon, isTrue);
    });

    test('resolving the same finish twice is a no-op (idempotent)', () async {
      final controller = await newController();
      final enemyBoard = Board();
      enemyBoard.place(kFleet.last, 0, 0, true);
      controller.beginBattle(enemyBoard: enemyBoard);

      controller.fireAt(0, 0);
      controller.cooldown1 = 0;
      controller.fireAt(0, 1);
      final winningEvent = controller.events.last;

      controller.resolvePendingFinishFor(winningEvent);
      expect(controller.phase, BattlePhase.finished);
      final rpAfterFirst = controller.rpDelta;

      // A duplicate/late-arriving call for the same event must not throw
      // or re-run the finish logic (no double RP award).
      controller.resolvePendingFinishFor(winningEvent);
      expect(controller.phase, BattlePhase.finished);
      expect(controller.rpDelta, rpAfterFirst);
    });

    test('a non-final hit never arms a pending finish', () async {
      final controller = await newController();
      final enemyBoard = Board();
      enemyBoard.place(kFleet.last, 0, 0, true); // destroyer
      enemyBoard.place(kFleet.first, 5, 0, true); // carrier — stays afloat
      controller.beginBattle(enemyBoard: enemyBoard);

      controller.fireAt(0, 0);
      controller.cooldown1 = 0;
      controller.fireAt(0, 1); // sinks the destroyer, carrier still afloat

      expect(controller.hasPendingFinish, isFalse);
      expect(controller.phase, BattlePhase.battling);
    });
  });

  /// Regression coverage for the mobile-performance fix (see the doc on
  /// `GameController.cooldownTick`). The 100ms battle ticker used to call
  /// `notifyListeners()` unconditionally, which rebuilt the entire battle
  /// screen — and, via freshly-allocated painter inputs, fully REPAINTED
  /// both grids' accumulated hit/miss marks — 10× a second. That made
  /// frame cost scale with how far into the match you were, which is
  /// exactly the "fine early, unplayable late" behavior reported on real
  /// phones. The ring now advances via `cooldownTick`, and
  /// `notifyListeners()` is reserved for genuinely structural changes.
  group('GameController tick does not spam listeners', () {
    test('a plain cooldown countdown advances the ring but does NOT '
        'notify listeners', () async {
      final controller = await newController();
      // Local mode keeps the AI out of the picture so the only thing the
      // ticker does is decrement cooldowns.
      controller.mode = GameMode.local;
      final enemyBoard = Board()..place(kFleet.first, 0, 0, true);
      controller.beginBattle(enemyBoard: enemyBoard);

      // A long cooldown so it can't reach zero (a structural change) mid-test.
      controller.cooldownMax1 = 60;
      controller.cooldown1 = 60;

      var notifications = 0;
      controller.addListener(() => notifications++);
      final ringBefore = controller.cooldownTick.value;

      // Let several 100ms ticks elapse.
      await Future<void>.delayed(const Duration(milliseconds: 450));

      expect(controller.cooldownTick.value, greaterThan(ringBefore),
          reason: 'the cooldown ring must still animate every tick');
      expect(notifications, 0,
          reason: 'a purely cosmetic cooldown advance must not rebuild '
              'the whole battle screen');

      controller.dispose();
    });

    test('a cooldown REACHING zero still notifies (so the UI never goes '
        'stale)', () async {
      final controller = await newController();
      controller.mode = GameMode.local;
      final enemyBoard = Board()..place(kFleet.first, 0, 0, true);
      controller.beginBattle(enemyBoard: enemyBoard);

      // Small enough to hit zero within a couple of ticks — readiness
      // gates grid taps, so that transition MUST still reach the UI.
      controller.cooldownMax1 = 1;
      controller.cooldown1 = 0.15;

      var notifications = 0;
      controller.addListener(() => notifications++);

      await Future<void>.delayed(const Duration(milliseconds: 450));

      expect(controller.cooldown1, 0);
      expect(notifications, greaterThan(0),
          reason: 'becoming ready to fire again is a structural change and '
              'must still rebuild the screen');

      controller.dispose();
    });
  });

  group('fireAt refuses to fire on the peer\'s turn', () {
    // Belt-and-braces alongside `BattleScreen._shotOutstanding` (see its
    // doc) — this is the controller-level half of the double-fire fix,
    // and the only half that's meaningfully testable without a widget: it
    // survives the UI's `State` being torn down and rebuilt, which the
    // screen-side latch alone would not.
    test('refused while peerHasTurn is true in a turn-based mode',
        () async {
      final controller = await newController();
      controller.mode = GameMode.hotspot;
      controller.lanBattleMode = LanBattleMode.turns;
      controller.beginBattle(enemyBoard: Board()..place(kFleet.first, 0, 0, true));
      controller.attachNetwork();
      controller.peerHasTurn = true; // not my turn

      final before = controller.network.sentForTest.length;
      final res = controller.fireAt(5, 5);

      expect(res, ShotResult.invalid);
      expect(controller.network.sentForTest.length, before,
          reason: 'no fire message should have reached the wire');
    });

    test('allowed once peerHasTurn flips back to mine', () async {
      final controller = await newController();
      controller.mode = GameMode.hotspot;
      controller.lanBattleMode = LanBattleMode.turns;
      controller.beginBattle(enemyBoard: Board()..place(kFleet.first, 0, 0, true));
      controller.attachNetwork();
      controller.peerHasTurn = false; // my turn

      final res = controller.fireAt(5, 5);

      expect(res, ShotResult.hit); // network branch's placeholder return
      expect(
          controller.network.sentForTest
              .any((m) => m['type'] == 'fire' && m['r'] == 5 && m['c'] == 5),
          isTrue);
    });

    test('CHAOS is untouched — peerHasTurn is never meaningfully set '
        'there, and nothing should gate on it', () async {
      final controller = await newController();
      controller.mode = GameMode.hotspot;
      controller.lanBattleMode = LanBattleMode.chaos;
      controller.beginBattle(enemyBoard: Board()..place(kFleet.first, 0, 0, true));
      controller.attachNetwork();
      controller.peerHasTurn = true; // meaningless in chaos; must not block

      final res = controller.fireAt(5, 5);
      expect(res, ShotResult.hit);
    });
  });
}
