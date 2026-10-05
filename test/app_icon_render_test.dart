import 'package:battleship_blitz/art/app_icon_art.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders the launcher icon from the game's OWN art painter (single source
/// of truth: lib/art/app_icon_art.dart), so the icon ships the same ship
/// the player sails — no duplicated painter, no foreground glow halo.
///
/// The master (full-bleed square) is what the Android/iOS/macOS/web/Windows
/// launcher icons are cut from; the foreground variant is the adaptive-icon
/// layer (transparent background, ship inside the round safe zone).
///
/// Regenerate with:
///   flutter test --update-goldens test/app_icon_render_test.dart
void main() {
  testWidgets('app icon master + adaptive foreground', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1024, 1024);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(CustomPaint(
      size: const Size(1024, 1024),
      painter: const AppIconPainter.fullBleed(fullBleed: true),
    ));
    await expectLater(
      find.byType(CustomPaint),
      matchesGoldenFile('goldens/app_icon_master.png'),
    );

    await tester.pumpWidget(CustomPaint(
      size: const Size(1024, 1024),
      painter: const AppIconPainter.fullBleed(fullBleed: false),
    ));
    await expectLater(
      find.byType(CustomPaint),
      matchesGoldenFile('goldens/app_icon_foreground.png'),
    );
  });
}
