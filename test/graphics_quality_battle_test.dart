// The graphics-quality setting, end to end in a running battle.
//
// The three levers (`fxDensity`, `screenShakeEnabled`, `shellTrailCount`)
// are unit-tested in `settings_test.dart` at the ProfileStore level; this
// file pins what the user actually asked for — that picking a quality in
// settings CHANGES the running game. The most visible promise on the LOW
// row is "no screen shake": here a real hit lands on a real battle screen
// with each quality picked, and the shake transform is read off the live
// widget tree.
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

/// How far the board is currently displaced by the shake (see
/// `cinematic_finish_test.dart`'s helper — same key, same read).
double _shakeAmount(WidgetTester tester) {
  final found = find.byKey(shakeKey).evaluate();
  if (found.isEmpty) return 0;
  final m = (found.single.widget as Transform).transform;
  return m.storage[12].abs() + m.storage[13].abs();
}

BattleGrid? _firableGrid(WidgetTester tester) {
  for (final g in tester.widgetList<BattleGrid>(find.byType(BattleGrid))) {
    if (g.onTapCell != null) return g;
  }
  return null;
}

Future<GameController> _setUpMatch(GraphicsQuality quality) async {
  SharedPreferences.setMockInitialValues({});
  final profile = ProfileStore();
  await profile.load();
  await profile.setGraphics(quality);
  final controller =
      GameController(profile: profile, network: NetworkService());
  controller.mode = GameMode.local;
  controller.resetLocalLoadouts();
  // One two-cell hull each: the first shot is a hit that keeps the gun.
  controller.boards[0] = Board()..place(kFleet.last, 9, 0, true);
  controller.startPlacement();
  controller.boards[0] = Board()..place(kFleet.last, 9, 0, true);
  controller.beginBattle(
    enemyBoard: Board()..place(kFleet.last, 0, 0, true),
  );
  controller.resumedMidMatch = true;
  return controller;
}

Future<void> _pump(WidgetTester tester, GameController c) async {
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

/// Fires the human's gun at the enemy hull and rides the shell to its
/// impact, running [probe] after every step — the moment the screen shake
/// would play.
Future<void> _fireAndLandWhile(
    WidgetTester tester, void Function() probe) async {
  _firableGrid(tester)!.onTapCell!(0, 0);
  await tester.pump();
  for (var i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    probe();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('LOW graphics: an impact does not shake the screen',
      (tester) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final c = await _setUpMatch(GraphicsQuality.low);
    await _pump(tester, c);

    var sawShake = false;
    await _fireAndLandWhile(tester, () {
      if (_shakeAmount(tester) > 0.5) sawShake = true;
    });
    expect(sawShake, isFalse,
        reason: 'LOW promises "no screen shake" and the battle screen must '
            'honour that — a transform on the whole board is exactly the '
            'per-frame cost the tier exists to remove');
    c.dispose();
  });

  testWidgets('BALANCED graphics: the same impact shakes the screen',
      (tester) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final c = await _setUpMatch(GraphicsQuality.balanced);
    await _pump(tester, c);

    var sawShake = false;
    await _fireAndLandWhile(tester, () {
      if (_shakeAmount(tester) > 0.5) sawShake = true;
    });
    expect(sawShake, isTrue,
        reason: 'the default tier keeps the full impact feedback — the '
            'control must do more than nothing');
    c.dispose();
  });
}

