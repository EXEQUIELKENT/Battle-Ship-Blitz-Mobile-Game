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
}
