// BattleScreen firing — hit-keeps-firing must actually let the shooter
// fire again, on the shared screen (local pass-and-play) and against
// the plain vs-AI opponent.
//
// BUGFIX: `GameController.fireAt`/`p2FireAt`'s NON-network branch (used
// by local pass-and-play and vs-AI — hotspot/online/vsAiLan take the
// network branch instead, which this bug never reached) registers the
// shot SYNCHRONOUSLY, and its `notifyListeners()` runs
// `_BattleScreenState._onUpdate` right there in the same call stack —
// before `_fireAtCell` ever reaches `_launchBall`. At that instant the
// fresh event has no ball tracking it by any measure `_onUpdate` checks
// (`_Projectile.visible` still false, `pendingCell` still null), which
// is EXACTLY what its POWER-PLAY fallback (built for a card's batch
// shots, which really do skip `_launchBall` entirely) uses to recognise
// "this shot will never get a ball — resolve it now." Both that
// fallback and `_tryResolveImpact` raced to resolve an ORDINARY tap on
// the spot: for a HIT, that clears `_shotOutstanding` immediately, which
// the very next line in `_fireAtCell` then set back to `true` — with
// nothing left to ever clear it again, since the real ball-landing path
// can no longer find an unresolved event to finish the job. A MISS
// self-healed (its turn-pass clears the flag from inside a delayed
// callback that fires AFTER that line), which is why only a HIT ever
// wedged the shooter's own gun — reported as "I can fire once, then
// nothing" on PHANTOM local play, but the bug is in the shared firing
// path, not anything PHANTOM-specific; classic TURN BASED and vs-AI
// carry the exact same latent bug.
import 'package:battleship_blitz/models/game_models.dart';
import 'package:battleship_blitz/screens/battle_screen.dart';
import 'package:battleship_blitz/services/game_controller.dart';
import 'package:battleship_blitz/services/network_service.dart';
import 'package:battleship_blitz/services/online_service.dart';
import 'package:battleship_blitz/services/storage_service.dart';
import 'package:battleship_blitz/widgets/battle_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<GameController> _newController(
  GameMode mode, {
  bool phantom = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final profile = ProfileStore();
  await profile.load();
  final controller =
      GameController(profile: profile, network: NetworkService());
  controller.mode = mode;
  if (mode == GameMode.local) {
    controller.localPhantom = phantom;
    controller.resetLocalLoadouts();
  }
  return controller;
}

Future<void> _pumpBattleScreen(
  WidgetTester tester,
  GameController controller,
) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ProfileStore>.value(value: controller.profile),
        ChangeNotifierProvider<NetworkService>.value(value: controller.network),
        ChangeNotifierProvider<OnlineService>.value(value: OnlineService()),
        ChangeNotifierProvider<GameController>.value(value: controller),
      ],
      child: const MaterialApp(home: BattleScreen()),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// The `BattleGrid` whose grid is currently tappable, or null if neither
/// is (e.g. a shot is still resolving, or it isn't this device's turn).
BattleGrid? _firableGrid(WidgetTester tester) {
  for (final g in tester.widgetList<BattleGrid>(find.byType(BattleGrid))) {
    if (g.onTapCell != null) return g;
  }
  return null;
}

/// Lets one shot's cannonball finish its flight and impact resolve.
Future<void> _settleShot(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump();
  await tester.pump();
}

/// This device's own fleet AS DRAWN — the enemy half is handed `ships:
/// null`, so the one grid carrying ships is our own. These are the
/// landed-only copies built by `_refreshDerivedCache`, not the raw model,
/// which is exactly the difference the damage-sync test is about.
PlacedShip _drawnOwnShip(WidgetTester tester, ShipKind kind) {
  for (final g in tester.widgetList<BattleGrid>(find.byType(BattleGrid))) {
    final ships = g.ships;
    if (ships == null) continue;
    for (final s in ships) {
      if (s.spec.kind == kind) return s;
    }
  }
  throw StateError('no own fleet is being drawn');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a HIT lets the same shooter fire again', () {
    Future<void> run(WidgetTester tester, GameController controller) async {
      controller.boards[0] = Board()..place(kFleet.first, 9, 0, true);
      controller.startPlacement();
      controller.boards[0] = Board()..place(kFleet.first, 9, 0, true);
      controller.beginBattle(
        enemyBoard: Board()..place(kFleet.last, 0, 0, true), // destroyer
      );
      controller.resumedMidMatch = true; // skip the 3-2-1 countdown

      await _pumpBattleScreen(tester, controller);

      final grid = _firableGrid(tester);
      expect(grid, isNotNull, reason: 'someone must be able to open fire');
      grid!.onTapCell!(0, 0); // the destroyer sits here
      await tester.pump();
      await _settleShot(tester);

      expect(controller.events, hasLength(1));
      expect(controller.events.single.result, ShotResult.hit);
      expect(_firableGrid(tester), isNotNull,
          reason: 'a hit must not be the last shot the shooter ever gets '
              'to take');

      // `GameController`'s own 100ms cooldown ticker is a real `Timer`
      // the widget test framework insists nothing leaves pending —
      // `dispose()` is normally the STATE's job (via `BattleScreen`'s own
      // teardown), but there is no screen transition here to trigger it.
      controller.dispose();
    }

    testWidgets('classic local (TURN BASED)', (tester) async {
      final controller = await _newController(GameMode.local);
      await run(tester, controller);
    });

    testWidgets('local PHANTOM', (tester) async {
      final controller = await _newController(GameMode.local, phantom: true);
      await run(tester, controller);
    });

    testWidgets('vs-AI', (tester) async {
      final controller = await _newController(GameMode.vsAI);
      await run(tester, controller);
    });
  });

  group('local pass-and-play: the fix applies to BOTH seats', () {
    testWidgets('P2 keeps firing after a hit too', (tester) async {
      final controller = await _newController(GameMode.local, phantom: true);
      // P1's own fleet — what P2 will be shooting at.
      controller.boards[0] = Board()..place(kFleet.last, 5, 5, true);
      controller.startPlacement();
      controller.boards[0] = Board()..place(kFleet.last, 5, 5, true);
      // NOT a bare `Board()`: `Board.allSunk` is vacuously true for an
      // empty fleet, so a hit on the OTHER board would instantly (and
      // wrongly) end the match the moment `_checkVictory` runs — see the
      // matching `_harmlessEnemyBoard` helpers elsewhere in this suite.
      controller.beginBattle(
        enemyBoard: Board()..place(kFleet.first, 9, 5, true),
      );
      controller.resumedMidMatch = true;

      await _pumpBattleScreen(tester, controller);

      // P1 opens with a deliberate MISS so the turn passes to P2 — (0,0)
      // is clear of the carrier placed at (9,5)-(9,9) above.
      var grid = _firableGrid(tester)!;
      grid.onTapCell!(0, 0);
      await tester.pump();
      await _settleShot(tester);
      // The miss's turn-pass is on its own 500ms beat, on top of the
      // shot settling above.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();

      expect(controller.peerHasTurn, isTrue, reason: 'the miss passed the turn to P2');

      grid = _firableGrid(tester)!;
      grid.onTapCell!(5, 5); // P1's destroyer
      await tester.pump();
      await _settleShot(tester);

      expect(controller.events.last.result, ShotResult.hit);
      expect(_firableGrid(tester), isNotNull,
          reason: 'P2 must keep firing after their own hit too');

      controller.dispose();
    });
  });

  group('a re-hit hull shows its owner the FRESH damage', () {
    // BUGFIX: in the record-free modes the attacker has no marks, so
    // shelling the same reported cell twice is ordinary play — and
    // `Board.receiveShot` scores the repeat as real, additional damage by
    // redirecting it onto the nearest cell of that hull not yet holed. The
    // crater drawn on the DEFENDER's own ship was still being looked up by
    // the cell that was AIMED at, which already carried one, so the second
    // shell visibly landed on a ship that did not change: the owner
    // watched an apparently untouched hull right up until the moment it
    // sank. Only reproducible where a player's own fleet is drawn — every
    // network mode and vs-AI (see `BattleScreen`'s `showOwnFleet`).
    Future<void> run(WidgetTester tester, LanBattleMode mode) async {
      SharedPreferences.setMockInitialValues({});
      final profile = ProfileStore();
      await profile.load();
      final net = NetworkService()..setMatchHost(true);
      final controller = GameController(profile: profile, network: net);
      controller.mode = GameMode.hotspot;
      controller.lanBattleMode = mode;
      // A carrier along row 0 — big enough that a re-hit on its middle has
      // open cells on both sides to be redirected onto.
      controller.boards[0] = Board()..place(kFleet.first, 0, 0, true);
      controller.beginBattle(
        enemyBoard: Board()..place(kFleet.first, 9, 5, true),
      );
      controller.attachNetwork();
      controller.resumedMidMatch = true; // skip the 3-2-1 countdown
      controller.peerHasTurn = true; // the opponent is the one shooting

      await _pumpBattleScreen(tester, controller);

      Future<void> incoming(int r, int c, int seq) async {
        net.handleIncomingForTest({'type': 'fire', 'r': r, 'c': c, 'seq': seq});
        await tester.pump();
        // The shot is scored against wherever the hulls sit when the shell
        // LANDS, not when the message arrives — see
        // `GameController._armIncomingShell`.
        controller.landIncomingShellsForTest();
        await tester.pump();
        await _settleShot(tester);
      }

      final kind = kFleet.first.kind;
      await incoming(0, 2, 0);
      expect(controller.boards[0].shipOfKind(kind)!.hitIndices, {2});
      expect(_drawnOwnShip(tester, kind).hitIndices, {2},
          reason: 'the crater appears where the shell landed');

      await incoming(0, 2, 1); // the same reported cell again
      final model = controller.boards[0].shipOfKind(kind)!.hitIndices;

      if (mode == LanBattleMode.ghost) {
        // GHOST FLEET redirects the repeat onto fresh plating, so there
        // is genuinely new damage — and the owner must be able to see it.
        expect(model, hasLength(2),
            reason: 'the repeat shell did real, additional damage');
        expect(_drawnOwnShip(tester, kind).hitIndices, model,
            reason: 'the drawn hull must track the cell the model holed');
      } else {
        // PHANTOM instead lets the shell fall into the hole already there:
        // nothing is dealt, so nothing new may appear on the hull either.
        expect(model, {2}, reason: 'the repeat dealt no damage');
        expect(_drawnOwnShip(tester, kind).hitIndices, {2},
            reason: 'and so the hull must look exactly as it did');
        // The captain being shot at still SEES the strike, though — that
        // asymmetry is the mode. See `phantomImpactVisual`.
        expect(
          phantomImpactVisual(
            event: controller.events.last,
            viewerIsDefender: true,
            phantom: controller.isPhantomBattle,
            defenderBoard: controller.boards[0],
          ),
          ShotResult.hit,
          reason: 'scored a miss, but it really did strike their hull',
        );
        expect(controller.events.last.result, ShotResult.miss,
            reason: 'while the scoreboard — and the shooter — say miss');
        // Scoring a miss means the shooter's streak ends: let the 500ms
        // turn-pass beat `_maybePassTurn` schedules actually run, both
        // because it is the rule under test and because the widget test
        // framework refuses to leave a timer pending.
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump();
        expect(controller.peerHasTurn, isFalse,
            reason: 'the wasted shell handed the turn back to us');
      }

      controller.dispose();
    }

    testWidgets('GHOST FLEET redirects onto fresh plating',
        (tester) => run(tester, LanBattleMode.ghost));
    testWidgets('PHANTOM deals nothing, but the defender still feels it',
        (tester) => run(tester, LanBattleMode.phantom));
  });
}
