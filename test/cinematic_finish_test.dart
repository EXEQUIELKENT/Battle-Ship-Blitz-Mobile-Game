// The cinematic finish — the slow-motion close-up on the shot that ends
// the match.
//
// FEEDBACK ("the cam will zoom to the target when the projectile is
// near, and after hitting the deck cell the screen will shake, then goes
// back to normal camera view and the game is over"). That is an ORDER,
// and the order is the whole effect: every beat has to wait for the one
// before it. This pins that order, because nothing else can — the pieces
// live in three different places (the shell's own flight, the shake
// controller, the game-over bar) and each one used to run on its own
// clock.
import 'dart:math' as math;

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

/// The camera's scale — exactly 1 while it is not running.
///
/// The transform is mounted at all times and simply sits at identity when
/// idle (see the PERF note on `_CinematicCamera`: it used to appear and
/// disappear, which re-parented the whole battle screen at the worst
/// possible moment), so "is the camera running" is a question about its
/// SCALE, not about whether the widget exists.
double _zoomScale(WidgetTester tester) {
  final found = find.byKey(cameraKey).evaluate();
  if (found.isEmpty) return 1.0;
  return (found.single.widget as Transform).transform.storage[0];
}

/// Whether the camera currently has the board.
bool _cameraRunning(WidgetTester tester) => _zoomScale(tester) > 1.0001;

/// How far the board is currently displaced by the shake.
double _shakeAmount(WidgetTester tester) {
  final found = find.byKey(shakeKey).evaluate();
  if (found.isEmpty) return 0;
  final m = (found.single.widget as Transform).transform;
  return m.storage[12].abs() + m.storage[13].abs();
}

bool _gameOverShown(WidgetTester tester) =>
    find.text('CONTINUE').evaluate().isNotEmpty;

BattleGrid? _firableGrid(WidgetTester tester) {
  for (final g in tester.widgetList<BattleGrid>(find.byType(BattleGrid))) {
    if (g.onTapCell != null) return g;
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<GameController> setUpMatch({
    required bool cinematic,
    GameMode mode = GameMode.local,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final profile = ProfileStore();
    await profile.load();
    await profile.setCinematicFinish(cinematic);
    final controller =
        GameController(profile: profile, network: NetworkService());
    controller.mode = mode;
    if (mode == GameMode.local) controller.resetLocalLoadouts();
    // One two-cell hull each, so the SECOND shot is the deciding one.
    controller.boards[0] = Board()..place(kFleet.last, 9, 0, true);
    controller.startPlacement();
    controller.boards[0] = Board()..place(kFleet.last, 9, 0, true);
    controller.beginBattle(
      enemyBoard: Board()..place(kFleet.last, 0, 0, true),
    );
    controller.resumedMidMatch = true;
    return controller;
  }

  Future<void> pump(WidgetTester tester, GameController c) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ProfileStore>.value(value: c.profile),
          ChangeNotifierProvider<NetworkService>.value(value: c.network),
          ChangeNotifierProvider<OnlineService>.value(value: OnlineService()),
          ChangeNotifierProvider<GameController>.value(value: c),
        ],
        child: const MaterialApp(home: BattleScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('the camera waits for the shell, then shakes, then leaves',
      (tester) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final c = await setUpMatch(cinematic: true);
    await pump(tester, c);

    final grid = _firableGrid(tester)!;
    grid.onTapCell!(0, 0);
    await tester.pump();
    for (var i = 0; i < 32; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final again = _firableGrid(tester);
    expect(again, isNotNull, reason: 'a hit keeps the gun');
    again!.onTapCell!(0, 1); // the shot that ends it
    expect(c.hasPendingFinish, isTrue,
        reason: 'that shot must be the one that decides the match');

    // Beat one: the camera must NOT have moved yet — the shell has only
    // just left the muzzle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(_cameraRunning(tester), isFalse,
        reason: "the camera must not push in while the shell is still far "
            "away — it zooms when the projectile is NEAR");

    // Beat two: as the shell closes, the camera pushes in; the impact
    // then shakes the screen, and the result stays unannounced
    // throughout.
    var peak = 1.0;
    var sawShake = false;
    var shakeAfterZoom = false;
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      final z = _zoomScale(tester);
      if (z > peak) peak = z;
      if (_shakeAmount(tester) > 0.5) {
        sawShake = true;
        if (peak > 1.0001) shakeAfterZoom = true;
      }
      if (_cameraRunning(tester)) {
        expect(_gameOverShown(tester), isFalse,
            reason: 'the result must not be announced over the close-up');
      }
    }

    expect(peak, greaterThan(1.5),
        reason: 'the push-in must actually reach the close-up');
    expect(sawShake, isTrue, reason: 'the impact must shake the screen');
    expect(shakeAfterZoom, isTrue,
        reason: 'the shake belongs to the impact, so it comes after the '
            'camera has arrived');

    // Beat three: the camera has left, and only now is it over.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(_cameraRunning(tester), isFalse,
        reason: "the camera must return to the ordinary view");
    expect(c.phase, BattlePhase.finished);
    expect(_gameOverShown(tester), isTrue,
        reason: 'the game is over once the camera has gone');

    c.dispose();
  });

  testWidgets('with the setting off there is no camera move at all',
      (tester) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final c = await setUpMatch(cinematic: false);
    await pump(tester, c);

    _firableGrid(tester)!.onTapCell!(0, 0);
    await tester.pump();
    for (var i = 0; i < 32; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    _firableGrid(tester)!.onTapCell!(0, 1);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(_cameraRunning(tester), isFalse,
          reason: "the cinematic is opt-in and this profile did not opt in");
    }
    expect(c.phase, BattlePhase.finished);
    expect(_gameOverShown(tester), isTrue,
        reason: 'without the camera the bar appears as soon as it ends');
    c.dispose();
  });

  /// Drives the shared close-up sequence for a shot that has JUST been
  /// fired with the finish armed: no zoom while the shell is far, the
  /// push-in to the close-up, the shake under it, and the camera gone with
  /// the match only over once it has left.
  Future<void> expectFullCinematic(WidgetTester tester, GameController c) async {
    // Beat one: the camera must NOT have moved yet.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(_cameraRunning(tester), isFalse,
        reason: "the camera must not push in while the shell is still far "
            "away — it zooms when the projectile is NEAR");

    // Beat two: the push-in, then the shake under it.
    //
    // The ramp is sampled as a SET of distinct intermediate zooms reached
    // BEFORE the shake — i.e. while the shell was still in the air. That
    // is the part a merely "camera engaged" assertion cannot see: if the
    // close-up is only picked up at IMPACT (the deciding shell registered
    // long before it is launched, so the camera is asked before there is
    // anything to follow — see `_maybeStartCinematic`'s empty-`flying`
    // bail), the transform jumps 1.0 → 1.75 in the one frame the shake
    // starts, and "peak > 1.5" is satisfied by a hard cut with no push-in
    // at all.
    var peak = 1.0;
    var sawShake = false;
    final rampBeforeImpact = <double>{};
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      final z = _zoomScale(tester);
      if (z > peak) peak = z;
      if (!sawShake && z > 1.02 && z < 1.7) {
        rampBeforeImpact.add(double.parse(z.toStringAsFixed(3)));
      }
      if (_shakeAmount(tester) > 0.5) sawShake = true;
      if (_cameraRunning(tester)) {
        expect(_gameOverShown(tester), isFalse,
            reason: 'the result must not be announced over the close-up');
      }
    }
    expect(peak, greaterThan(1.5),
        reason: 'the push-in must actually reach the close-up');
    expect(rampBeforeImpact.length, greaterThanOrEqualTo(3),
        reason: 'the camera must PUSH IN through the flight and arrive '
            'with the shell (#{rampBeforeImpact}), not snap to the '
            'close-up on the frame the shot lands');
    expect(sawShake, isTrue, reason: 'the impact must shake the screen');
    expect(rampBeforeImpact.reduce(math.max), lessThan(peak),
        reason: 'the push-in has to finish under the impact, not before '
            'it — the zoom may only reach the close-up once the shell '
            'has actually landed');

    // Beat three: the camera has left, and only now is it over.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(_cameraRunning(tester), isFalse,
        reason: "the camera must return to the ordinary view");
    expect(c.phase, BattlePhase.finished);
    expect(_gameOverShown(tester), isTrue,
        reason: 'the game is over once the camera has gone');
  }

  testWidgets(
      'local pass-and-play: Player 2’s deciding shot gets the camera too',
      (tester) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final c = await setUpMatch(cinematic: true);
    await pump(tester, c);

    // P1 hits the enemy hull, keeping the gun (a hit's reload is 2s).
    _firableGrid(tester)!.onTapCell!(0, 0);
    for (var i = 0; i < 22; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // P1 deliberately misses — the handoff delay later, Player 2 is active.
    _firableGrid(tester)!.onTapCell!(5, 5);
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Player 2's turn: the firable grid is now P1's own board (bottom).
    // Their first shot is a hit that does NOT end the match.
    _firableGrid(tester)!.onTapCell!(9, 0);
    for (var i = 0; i < 22; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(c.phase, BattlePhase.battling,
        reason: 'the first P2 hit must not end it');

    // FEEDBACK ("there are no cinematic zoom camera effect on the local
    // multiplayer"): the shot that ends it fired from the TOP seat. It goes
    // through the same `_fireAtCell` launch as P1's, and the close-up must
    // ride it exactly the same way.
    _firableGrid(tester)!.onTapCell!(9, 1);
    expect(c.hasPendingFinish, isTrue,
        reason: 'P2’s shot must be the one that decides the match');

    await expectFullCinematic(tester, c);
    c.dispose();
  });

  testWidgets('vs AI: the AI’s deciding shot gets the camera too',
      (tester) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final c = await setUpMatch(cinematic: true, mode: GameMode.vsAI);
    await pump(tester, c);

    // P1 hits, then deliberately misses so the turn hands over to the AI.
    _firableGrid(tester)!.onTapCell!(0, 0);
    for (var i = 0; i < 22; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    _firableGrid(tester)!.onTapCell!(5, 5);
    // The handover is a flag the shot raises as it is SCORED — `fireAt`
    // sets it inside the tap, before its shell is even in the air — so it
    // is read right here rather than after a wait. Waiting is how this
    // expectation used to flake: the brain's think delay is 1.6s at NORMAL
    // difficulty, so sixteen ticks of 100ms put it exactly one tick short
    // of a random shot of its own — a miss there clears the very flag
    // being pinned, and a lucky hit would take the hull this test needs.
    expect(c.aiTurnToFire, isTrue,
        reason: 'a miss hands the turn to the AI');

    // Let that miss's shell land (750ms) and its own handoff settle, and
    // stop well short of the think delay so the AI cannot fire on its own
    // — the test is about to take its gun and fire the deciding shot by
    // hand (see `fireAiShotForTest`).
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(c.aiTurnToFire, isTrue,
        reason: 'the AI still holds the turn while the test takes its gun');

    // Drive the AI's gun at exact cells — `_aiPickTarget` is deliberately
    // random and a test that waits on luck flakes. First shell: a hit that
    // does NOT end the match. Its 900ms visual-fire delay, then flight.
    c.fireAiShotForTest(9, 0);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(c.phase, BattlePhase.battling,
        reason: 'the AI’s first hit must not end it');

    // FEEDBACK ("there are no cinematic zoom camera effect on the … ai
    // mode"): the AI's shot is REGISTERED long before its shell visibly
    // flies — the brain scores, then waits out the visual-fire delay, and
    // the camera used to give up in that gap and never ask again. The
    // deciding shell must be picked up the moment it leaves the muzzle.
    c.fireAiShotForTest(9, 1);
    expect(c.hasPendingFinish, isTrue,
        reason: 'the AI’s shot must be the one that decides the match');

    // A single COARSE pump on purpose. The AI's shot has two timers racing
    // from the same instant: the controller's own 900ms visual-fire notify
    // (scheduled first, when the shot was scored) and this screen's 900ms
    // launch delay. On a real device the first one wins, so the camera is
    // asked for the deciding shell BEFORE it exists — and the launch site
    // has to ask again (`_launchOpponentBall`). Pumping in 100ms steps hid
    // that: it landed the two in the other order and the camera came up by
    // luck rather than by the re-arm.
    await tester.pump(const Duration(milliseconds: 950));

    await expectFullCinematic(tester, c);
    c.dispose();
  });
}
