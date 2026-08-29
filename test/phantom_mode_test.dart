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
import 'package:battleship_blitz/screens/battle_screen.dart';
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

      // A fresh fire at the same cell is evaluated rather than bounced as
      // a duplicate (nothing was recorded) — but PHANTOM's dead-cell rule
      // means that plating is already holed, so the shell scores nothing.
      await _incomingFire(c, 2, 2, 1);
      expect(c.p2Shots[2][2], 1,
          reason: 'a miss now — the hole it struck was already there');
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

    test('a repeat on a hole already there scores nothing, for good',
        () async {
      // PHANTOM's own rule, and the one thing separating it from GHOST
      // FLEET (which instead redirects such a shell onto fresh plating so
      // the hull can still be finished off). Here the shot is simply
      // wasted: no damage, and — since a PHANTOM fleet never moves — that
      // cell goes on reading as a miss for the rest of the match. Every
      // hull still sinks, but only by shelling all of it.
      final c = await _newPhantomController(host: true);
      c.boards[0] = Board()..place(kFleet.last, 2, 2, true); // destroyer
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();

      await _incomingFire(c, 2, 2, 0);
      final ship = c.boards[0].shipOfKind(ShipKind.destroyer)!;
      expect(ship.hitIndices, {0});

      await _incomingFire(c, 2, 2, 1); // same reported cell, distinct seq
      expect(ship.isSunk, isFalse, reason: 'the repeat did nothing at all');
      expect(ship.hitIndices, {0}, reason: 'and dealt no damage');
      expect(c.p2Shots[2][2], 1, reason: 'scored as a miss');

      // Still a miss however many times it is tried.
      await _incomingFire(c, 2, 2, 2);
      expect(ship.hitIndices, {0});

      // The hull goes down when its OTHER cell is actually shelled.
      await _incomingFire(c, 2, 3, 3);
      expect(ship.isSunk, isTrue);
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

  group('what each side is SHOWN when a repeat lands', () {
    // The asymmetry the rule is built around: the shooter is told nothing
    // (a miss, no shake), while the captain being shot at sees the shell
    // really strike their hull. See `phantomImpactVisual`.
    Board defenderBoard() => Board()..place(kFleet.last, 2, 2, true);

    CombatEvent shotAt(int r, int c, ShotResult result, {bool byPlayer = false}) =>
        CombatEvent(byPlayer: byPlayer, row: r, col: c, result: result);

    test('the DEFENDER sees a hit where the shell actually struck', () {
      final board = defenderBoard()..receiveShot(2, 2);
      expect(
        phantomImpactVisual(
          event: shotAt(2, 2, ShotResult.miss),
          viewerIsDefender: true,
          phantom: true,
          defenderBoard: board,
        ),
        ShotResult.hit,
        reason: 'it landed on their hull — they feel it, it just did not '
            'count',
      );
    });

    test('the SHOOTER is told nothing — a plain miss', () {
      final board = defenderBoard()..receiveShot(2, 2);
      expect(
        phantomImpactVisual(
          event: shotAt(2, 2, ShotResult.miss, byPlayer: true),
          viewerIsDefender: false,
          phantom: true,
          defenderBoard: board,
        ),
        ShotResult.miss,
      );
    });

    test('a shared screen shows the miss to everyone', () {
      // Local pass-and-play has no defender-only view to put a private hit
      // on: dressing it up would leak to the shooter, sitting right there,
      // exactly what the rule hides.
      final board = defenderBoard()..receiveShot(2, 2);
      expect(
        phantomImpactVisual(
          event: shotAt(2, 2, ShotResult.miss),
          viewerIsDefender: false, // never set off the wire modes
          phantom: true,
          defenderBoard: board,
        ),
        ShotResult.miss,
      );
    });

    test('an ordinary miss on open water stays a miss', () {
      expect(
        phantomImpactVisual(
          event: shotAt(9, 9, ShotResult.miss),
          viewerIsDefender: true,
          phantom: true,
          defenderBoard: defenderBoard(),
        ),
        ShotResult.miss,
      );
    });

    test('shells falling on a wreck stay misses too', () {
      final board = defenderBoard()
        ..receiveShot(2, 2)
        ..receiveShot(2, 3); // sunk
      expect(
        phantomImpactVisual(
          event: shotAt(2, 2, ShotResult.miss),
          viewerIsDefender: true,
          phantom: true,
          defenderBoard: board,
        ),
        ShotResult.miss,
        reason: 'a wreck is not a near-thing',
      );
    });

    test('every other mode passes straight through', () {
      final board = defenderBoard()..receiveShot(2, 2);
      expect(
        phantomImpactVisual(
          event: shotAt(2, 2, ShotResult.miss),
          viewerIsDefender: true,
          phantom: false,
          defenderBoard: board,
        ),
        ShotResult.miss,
      );
      expect(
        phantomImpactVisual(
          event: shotAt(2, 2, ShotResult.hit),
          viewerIsDefender: true,
          phantom: true,
          defenderBoard: board,
        ),
        ShotResult.hit,
        reason: 'a real hit is untouched',
      );
    });
  });
}
