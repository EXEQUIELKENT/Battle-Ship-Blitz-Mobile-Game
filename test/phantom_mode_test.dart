// PHANTOM — Ghost Fleet's silence with a fleet that can never move.
//
// Ghost Fleet refuses to REMEMBER a shot (no persistent marks, no wreck
// left for the attacker) but still shows the just-landed hit moment — the
// explosion fading out, the screen shaking. PHANTOM keeps exactly that
// same dramatic instant, and adds a single difference on top: the fleet is
// FIXED, so a damaged hull can never run. The impact is felt; the record is
// not kept. The only steady progress report either captain gets is the
// fleet-status row (and a sinking's coordinate-less log line).
import 'package:battleship_blitz/models/game_models.dart';
import 'package:battleship_blitz/services/game_controller.dart';
import 'package:battleship_blitz/services/network_service.dart';
import 'package:battleship_blitz/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<GameController> _newPhantomController({bool host = true}) async {
  SharedPreferences.setMockInitialValues({});
  final profile = ProfileStore();
  await profile.load();
  final net = NetworkService();
  net.setMatchHost(host);
  final c = GameController(profile: profile, network: net);
  c.mode = GameMode.hotspot;
  c.lanBattleMode = LanBattleMode.phantom;
  return c;
}

/// Feeds a raw incoming 'fire' message to [c] and lets it be processed.
///
/// PHANTOM is not a manoeuvring mode, so an arriving 'fire' is scored
/// IMMEDIATELY (no `IncomingShell` dodge window — see
/// `GameController._armIncomingShell`). That immediacy is itself under test
/// below: these helpers deliberately do NOT call
/// `landIncomingShellsForTest`, so a test only passes here if the shot
/// resolved straight away.
Future<void> _incomingFire(GameController c, int r, int col, int seq) async {
  c.network
      .handleIncomingForTest({'type': 'fire', 'r': r, 'c': col, 'seq': seq});
  await pumpEventQueue();
}

/// A single enemy ship far from anything these tests fire at — see the
/// matching helper in `ghost_mode_test.dart` for why an EMPTY board is a
/// trap (`Board.allSunk` is vacuously true over no ships).
Board _harmlessEnemyBoard() => Board()..place(kFleet.first, 9, 5, true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LanBattleMode.phantom — the rules it turns on', () {
    test('turn-based, record-free, and never rearranging', () {
      expect(LanBattleMode.phantom.hasTurns, isTrue);
      expect(LanBattleMode.phantom.canRearrange, isFalse);
      expect(LanBattleMode.phantom.recordsShots, isFalse);
      expect(LanBattleMode.phantom.movesWhenDamaged, isFalse);
    });

    test('controller flags: record-free (like ghost) but its own mode',
        () async {
      final c = await _newPhantomController();
      expect(c.usesMatchProtocol, isTrue);
      expect(c.isGhostBattle, isTrue,
          reason: 'the record-free machinery (seq guard, refire, silent '
              'log) keys off isGhostBattle and must cover PHANTOM');
      expect(c.isPhantomBattle, isTrue);
      expect(c.isManoeuvreBattle, isFalse,
          reason: 'fixed fleets — no dodge window, no ship dragging');
      expect(c.isChaosBattle, isFalse);
      expect(c.isPowerUpBattle, isFalse);
    });
  });

  group('shooting in PHANTOM', () {
    test('the same cell may be fired at again — nothing was recorded',
        () async {
      final c = await _newPhantomController(host: true);
      c.boards[0] = Board();
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.peerHasTurn = false; // our gun
      c.cooldown1 = 0;

      final first = c.fireAt(5, 5);
      expect(first, isNot(ShotResult.duplicate));
      final second = c.fireAt(5, 5);
      expect(second, isNot(ShotResult.duplicate),
          reason: 'with no marks kept, the player has no way to know a '
              'cell was tried — refusing the tap would read as a dead '
              'control');
    });

    test('an incoming fire is scored the instant it arrives (no dodge '
        'window)', () async {
      final c = await _newPhantomController(host: true);
      c.boards[0] = Board()..place(kFleet.last, 2, 2, true); // destroyer
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();

      await _incomingFire(c, 2, 2, 0);
      expect(c.p2Shots[2][2], 2,
          reason: 'resolved immediately — the fleet cannot move, so there '
              'is nothing the dodge window would protect');
      expect(c.incomingShells, isEmpty);

      // A fresh fire at the same cell evaluates whatever is there now
      // (nothing was recorded) — the record-free rule, not a replay.
      await _incomingFire(c, 2, 2, 1);
      expect(c.p2Shots[2][2], 2,
          reason: 'still a hit — the destroyer is still there');
    });

    test('a redelivered fire (same seq) is answered but not re-applied',
        () async {
      final c = await _newPhantomController(host: true);
      c.boards[0] = Board()..place(kFleet.last, 2, 2, true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();

      await _incomingFire(c, 2, 2, 0);
      final eventsAfterFirst = c.events.length;

      await _incomingFire(c, 2, 2, 0); // same seq — a genuine retry
      expect(c.events.length, eventsAfterFirst,
          reason: 'the seq guard replaces the cell-based duplicate rule '
              'this mode gave up');
    });

    test('repeated fire on the same cell can still sink the hull', () async {
      // BUGFIX (permanently unsinkable hull): with no marks kept, a
      // shooter re-targeting the exact cell they already hit is expected
      // here, not a mistake — but a naive re-hit that just re-confirms
      // the same internal cell index would leave a hull stuck at partial
      // damage forever, no matter how many shots landed on it. See
      // `Board.receiveShot`'s redirect-to-the-nearest-open-cell fix.
      final c = await _newPhantomController(host: true);
      c.boards[0] = Board()..place(kFleet.last, 2, 2, true); // destroyer
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();

      await _incomingFire(c, 2, 2, 0);
      final ship = c.boards[0].shipOfKind(ShipKind.destroyer)!;
      expect(ship.isSunk, isFalse);

      await _incomingFire(c, 2, 2, 1); // same reported cell, distinct seq
      expect(ship.isSunk, isTrue,
          reason: 'the second hit redirects onto the hull\'s other cell');
    });
  });

  group("the combat log stays as silent as Ghost Fleet's", () {
    test('misses and hits go unlogged; a sinking is named but not placed',
        () async {
      final c = await _newPhantomController(host: true);
      c.boards[0] = Board()..place(kFleet.last, 0, 0, true); // destroyer
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.combatLog.clear();

      await _incomingFire(c, 5, 5, 0); // miss
      expect(c.combatLog, isEmpty, reason: 'a miss must not be logged');

      await _incomingFire(c, 0, 0, 1); // hit, not yet sunk
      expect(c.combatLog, isEmpty, reason: 'nor a hit');

      await _incomingFire(c, 0, 1, 2); // the killing blow
      expect(c.combatLog, hasLength(1));
      expect(c.combatLog.single, contains('SANK'));
      expect(c.combatLog.single, isNot(contains('B1')),
          reason: 'the sinking is narrated, never placed — (0,1) would '
              'print as B1');
    });
  });
}
