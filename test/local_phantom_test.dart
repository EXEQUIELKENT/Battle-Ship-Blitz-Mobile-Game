// LOCAL PHANTOM — PHANTOM's rules on the shared-screen (pass-and-play)
// match instead of a hotspot/online one.
//
// Local play never goes through `NetworkService` (`fireAt`/`p2FireAt`
// resolve synchronously against the two local boards) and never sets
// `usesMatchProtocol`, so `GameController.localPhantom` is a standalone
// flag rather than a `lanBattleMode` vote — but every rule it turns on
// (no persistent marks, a fired cell may be re-targeted, a
// coordinate-less log) reuses the EXACT SAME `isGhostBattle`-gated code
// PHANTOM already runs over the wire. This file is about that wiring:
// that `localPhantom` actually reaches `isGhostBattle`, that classic
// local play is completely unaffected when it's off, and that the
// duplicate-fire relaxation applies symmetrically to BOTH local seats.
import 'package:battleship_blitz/models/game_models.dart';
import 'package:battleship_blitz/services/game_controller.dart';
import 'package:battleship_blitz/services/network_service.dart';
import 'package:battleship_blitz/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<GameController> _newLocalController({bool phantom = false}) async {
  SharedPreferences.setMockInitialValues({});
  final profile = ProfileStore();
  await profile.load();
  final controller =
      GameController(profile: profile, network: NetworkService());
  controller.mode = GameMode.local;
  controller.localPhantom = phantom;
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GameController.isGhostBattle for local play', () {
    test('false for classic local — the untouched default', () async {
      final c = await _newLocalController();
      expect(c.isGhostBattle, isFalse);
    });

    test('true only once mode is local AND localPhantom is set', () async {
      final c = await _newLocalController(phantom: true);
      expect(c.isGhostBattle, isTrue);

      // Neither alone is enough.
      c.localPhantom = false;
      expect(c.isGhostBattle, isFalse);
      c.localPhantom = true;
      c.mode = GameMode.vsAI;
      expect(c.isGhostBattle, isFalse,
          reason: 'localPhantom is meaningless outside GameMode.local');
    });

    test('never implies the wire-protocol modes', () async {
      final c = await _newLocalController(phantom: true);
      expect(c.usesMatchProtocol, isFalse);
      expect(c.isManoeuvreBattle, isFalse,
          reason: 'local play never rearranges, phantom or not');
      expect(c.isChaosBattle, isFalse);
      expect(c.isPowerUpBattle, isFalse);
    });
  });

  group('firing in local PHANTOM', () {
    test('P1 may re-target a cell already fired at', () async {
      final c = await _newLocalController(phantom: true);
      c.boards[0] = Board()..place(kFleet.first, 9, 0, true);
      c.beginBattle(enemyBoard: Board());
      c.cooldown1 = 0;

      final first = c.fireAt(0, 0);
      expect(first, isNot(ShotResult.duplicate));
      c.cooldown1 = 0;
      final second = c.fireAt(0, 0);
      expect(second, isNot(ShotResult.duplicate),
          reason: 'no marks were kept, so the player has no way to know '
              'this cell was already tried');
    });

    test('P2 may re-target a cell already fired at', () async {
      final c = await _newLocalController(phantom: true);
      c.boards[0] = Board()..place(kFleet.first, 9, 0, true);
      c.beginBattle(enemyBoard: Board());
      c.cooldown2 = 0;

      final first = c.p2FireAt(0, 0);
      expect(first, isNot(ShotResult.duplicate));
      c.cooldown2 = 0;
      final second = c.p2FireAt(0, 0);
      expect(second, isNot(ShotResult.duplicate));
    });

    test('classic local (phantom off) still refuses a repeat cell',
        () async {
      final c = await _newLocalController();
      c.boards[0] = Board()..place(kFleet.first, 9, 0, true);
      c.beginBattle(enemyBoard: Board());
      c.cooldown1 = 0;

      expect(c.fireAt(0, 0), isNot(ShotResult.duplicate));
      c.cooldown1 = 0;
      expect(c.fireAt(0, 0), ShotResult.duplicate,
          reason: 'the ordinary rule, untouched when phantom is off');
    });

    test('a repeat on a hole already there scores nothing', () async {
      // PHANTOM's dead-cell rule reaches the shared screen through the
      // same `isPhantomBattle` the wire modes use — see
      // `Board.receiveShot`'s `repeatHitMisses`.
      final c = await _newLocalController(phantom: true);
      c.boards[0] = Board()..place(kFleet.last, 0, 0, true); // destroyer
      c.beginBattle(enemyBoard: _harmlessBoard());
      c.cooldown2 = 0;

      expect(c.p2FireAt(0, 0), ShotResult.hit);
      final ship = c.boards[0].shipOfKind(ShipKind.destroyer)!;
      expect(ship.hitIndices, {0});

      c.cooldown2 = 0;
      expect(c.p2FireAt(0, 0), ShotResult.miss,
          reason: 'same reported cell — the hole was already there');
      expect(ship.hitIndices, {0}, reason: 'no damage dealt');

      // The hull still goes down, by shelling the cell that is intact.
      c.cooldown2 = 0;
      expect(c.p2FireAt(0, 1), ShotResult.sunk);
    });

    test('classic local still lets a repeat be refused as a duplicate',
        () async {
      // The new rule is PHANTOM's alone — turn-based local play never
      // reaches it, because the duplicate check fires first.
      final c = await _newLocalController();
      c.boards[0] = Board()..place(kFleet.last, 0, 0, true);
      c.beginBattle(enemyBoard: _harmlessBoard());
      c.cooldown2 = 0;

      expect(c.p2FireAt(0, 0), ShotResult.hit);
      c.cooldown2 = 0;
      expect(c.p2FireAt(0, 0), ShotResult.duplicate);
    });
  });

  group('no persistent record in local PHANTOM', () {
    test('myShots/p2Shots still update (the model always tracks this)',
        () async {
      // `isGhostBattle` hides the PERSISTENT marker at the display layer
      // (`BattleScreen._refreshDerivedCache`'s `if (!ghost) cache[...]`)
      // — the underlying arrays this test reads are what the win
      // condition, log and resume all still depend on, in every mode.
      final c = await _newLocalController(phantom: true);
      c.boards[0] = Board()..place(kFleet.first, 9, 0, true);
      c.beginBattle(enemyBoard: Board()..place(kFleet.first, 0, 0, true));
      c.cooldown1 = 0;

      c.fireAt(0, 0);
      expect(c.myShots[0][0], isNot(0));
    });

    test('the combat log never names a coordinate', () async {
      final c = await _newLocalController(phantom: true);
      c.boards[0] = Board()..place(kFleet.last, 0, 0, true); // destroyer
      c.beginBattle(enemyBoard: _harmlessBoard());
      c.combatLog.clear();
      c.cooldown2 = 0;

      c.p2FireAt(5, 5); // a miss
      expect(c.combatLog, isEmpty);

      c.cooldown2 = 0;
      c.p2FireAt(0, 0); // hit, not yet sunk
      expect(c.combatLog, isEmpty);

      c.cooldown2 = 0;
      c.p2FireAt(0, 1); // the hull's other cell — sinks it
      expect(c.combatLog, hasLength(1));
      expect(c.combatLog.single, contains('SANK'));
      expect(c.combatLog.single, isNot(contains('A2')),
          reason: 'the sinking is narrated, never placed — (0,1) would '
              'print as A2');
    });

    test('classic local still logs a coordinate on every shot', () async {
      final c = await _newLocalController();
      c.boards[0] = Board()..place(kFleet.first, 9, 0, true);
      c.beginBattle(enemyBoard: Board()..place(kFleet.first, 0, 0, true));
      c.combatLog.clear();
      c.cooldown1 = 0;

      c.fireAt(0, 0);
      expect(c.combatLog.any((l) => l.contains('A1')), isTrue);
    });
  });
}

/// A single enemy ship far from anything these tests fire at — an EMPTY
/// board is a trap for `Board.allSunk` (vacuously true with no ships).
Board _harmlessBoard() => Board()..place(kFleet.first, 9, 5, true);
