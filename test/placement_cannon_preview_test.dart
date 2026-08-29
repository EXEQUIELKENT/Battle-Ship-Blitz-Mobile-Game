// DEPLOY SCREEN — the cosmetic cannon preview.
//
// Tapping an empty deck cell with nothing selected from the dock isn't a
// placement action, so the screen test-fires the equipped cannon at that
// cell instead: recoil, muzzle smoke, a shell arcing over, and the same
// reload the gun will have all through battle. Nothing here touches
// `Board` or `GameController` — there is no opponent to hit yet — so what
// needs pinning down is purely how it LOOKS and how often it can happen.
//
// Both cases below are regressions with the same reported symptom ("the
// projectile covers the whole screen and I can fire forever with no
// reload or smoke"), and both reproduce loudly when their fix is removed.
import 'package:battleship_blitz/screens/placement_screen.dart';
import 'package:battleship_blitz/services/game_controller.dart';
import 'package:battleship_blitz/services/network_service.dart';
import 'package:battleship_blitz/services/online_service.dart';
import 'package:battleship_blitz/services/storage_service.dart';
import 'package:battleship_blitz/widgets/battle_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The preview shell in flight, or null if none is.
///
/// The shell art itself changed from a painted gradient ball to the
/// equipped cannon's REAL shell (`_previewCannonball` — a family or legacy
/// `CustomPaint`, different silhouette per skin), so the finder can't key
/// off the old `BoxDecoration` any more. The in-flight ball is now tagged
/// with the `previewShell` key at its one mount point in
/// `_previewShotLayer`; the Opacity there lays out to exactly the ball's
/// box for every shell branch, so its size IS the shell's size.
Size? _shellSize(WidgetTester tester) {
  final finder = find.byKey(const ValueKey('previewShell'));
  if (finder.evaluate().isEmpty) return null;
  return tester.getSize(finder);
}

Future<BattleGrid> _pumpDeployScreen(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final profile = ProfileStore();
  await profile.load();
  final controller =
      GameController(profile: profile, network: NetworkService());
  controller.mode = GameMode.vsAI;
  controller.startPlacement();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ProfileStore>.value(value: profile),
        ChangeNotifierProvider<NetworkService>.value(value: controller.network),
        ChangeNotifierProvider<OnlineService>.value(value: OnlineService()),
        ChangeNotifierProvider<GameController>.value(value: controller),
      ],
      child: const MaterialApp(home: PlacementScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(); // the deliberate post-first-frame geometry rebuild
  return tester.widget<BattleGrid>(find.byType(BattleGrid));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the shell is a small ball, not a screen-filling blob',
      (tester) async {
    // BUGFIX: the flight layer's `AnimatedBuilder` returned a bare
    // `Positioned` under an `IgnorePointer`, with no Stack of its own. A
    // `Positioned` only means anything to its IMMEDIATE Stack parent, so
    // its left/top were discarded — and the `Positioned.fill` above it
    // handed down TIGHT full-layer constraints, which `Container` obeys
    // over its own width/height. The little iron ball was inflated to the
    // whole play area, hiding the grid, the gun and its smoke behind one
    // enormous sphere. Without the fix this reports ~800x337 on an
    // 800x600 surface, alongside the framework's "Incorrect use of
    // ParentDataWidget" error.
    final grid = await _pumpDeployScreen(tester);
    final screen = tester.getSize(find.byType(PlacementScreen));
    expect(_shellSize(tester), isNull, reason: 'nothing in flight yet');

    grid.onTapCell!(3, 3);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final shell = _shellSize(tester);
    expect(shell, isNotNull, reason: 'the tap should launch a shell');
    expect(shell!.width, lessThan(screen.width * 0.25),
        reason: 'a cannonball is roughly a grid cell across, not a screen');
    expect(shell.width, shell.height, reason: 'and it is round');

    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('the gun reloads between shots instead of firing forever',
      (tester) async {
    // BUGFIX: the preview passed a hardcoded `cooldownFraction: 1` and
    // gated nothing, so every tap restarted the shell mid-flight — you
    // could fire as fast as you could tap, and each new shot cut the
    // previous one's recoil and smoke short, which is why the gun looked
    // like it never animated at all.
    final grid = await _pumpDeployScreen(tester);

    grid.onTapCell!(3, 3);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600)); // flight is 480ms
    expect(_shellSize(tester), isNull, reason: 'the first shell has landed');

    // The reload runs `kCooldownSeconds` (2s), so every tap in here is
    // refused — the gun is empty.
    for (var i = 0; i < 5; i++) {
      grid.onTapCell!(7, 7);
      await tester.pump();
      expect(_shellSize(tester), isNull,
          reason: 'tap #$i landed inside the reload and must be refused');
      await tester.pump(const Duration(milliseconds: 100));
    }

    // And once it finishes, the gun fires again.
    await tester.pump(const Duration(milliseconds: 1200));
    grid.onTapCell!(7, 7);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_shellSize(tester), isNotNull,
        reason: 'a reloaded gun must be able to fire again');

    await tester.pump(const Duration(seconds: 3));
  });
}
