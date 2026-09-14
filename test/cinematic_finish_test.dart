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

  Future<GameController> setUpMatch({required bool cinematic}) async {
    SharedPreferences.setMockInitialValues({});
    final profile = ProfileStore();
    await profile.load();
    await profile.setCinematicFinish(cinematic);
    final controller =
        GameController(profile: profile, network: NetworkService());
    controller.mode = GameMode.local;
    controller.resetLocalLoadouts();
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
}
