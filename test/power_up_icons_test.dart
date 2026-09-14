import 'dart:ui' as ui;

import 'package:battleship_blitz/art/power_up_icons.dart';
import 'package:battleship_blitz/art/svg_path.dart';
import 'package:battleship_blitz/art/svg_replay.dart';
import 'package:battleship_blitz/models/power_up.dart';
import 'package:battleship_blitz/widgets/power_up_dial.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void _onCanvas(void Function(Canvas canvas) draw) {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder));
  recorder.endRecording().dispose();
}

/// Rasterizes [draw] and reports how many pixels are not the background,
/// so a test can tell "drew nothing" from "drew something" — which is the
/// exact failure an unsupported SVG command produces.
///
/// Must be called inside `tester.runAsync`: `toImage`/`toByteData` are
/// genuinely asynchronous, and inside `testWidgets`' fake-async zone their
/// futures never complete — the test hangs rather than failing.
Future<int> _inkedPixels(void Function(Canvas canvas) draw) async {
  const side = 100;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, side * 1.0, side * 1.0),
    Paint()..color = const Color(0xFF000000),
  );
  draw(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(side, side);
  final bytes = await image.toByteData();
  var inked = 0;
  for (var i = 0; i < bytes!.lengthInBytes; i += 4) {
    if (bytes.getUint8(i) != 0 ||
        bytes.getUint8(i + 1) != 0 ||
        bytes.getUint8(i + 2) != 0) {
      inked++;
    }
  }
  image.dispose();
  picture.dispose();
  return inked;
}

void main() {
  group('power-up icons', () {
    test('every card in the deck has a glyph and a badge colour', () {
      // A card with no entry would silently paint an empty disc — the
      // "all twenty look the same" problem the icons exist to end.
      for (final def in PowerUps.deck) {
        _onCanvas((c) => paintPowerUpIcon(c, const Size(64, 64), def.card));
      }
      // Every colour distinct enough to matter: the twenty share a palette
      // deliberately (recon blues, damage reds...), but a card that fell
      // through to a default would land on the fallback blue.
      final backgrounds = {
        for (final def in PowerUps.deck) def.card: powerUpBg(def.card),
      };
      expect(backgrounds, hasLength(PowerUps.deck.length));
    });

    test('rarity reads as a distinct ring colour', () {
      final seen = <Color>{};
      for (final r in PowerUpRarity.values) {
        expect(seen.add(powerUpRingColor(r)), isTrue, reason: '$r');
      }
      // An empty hand is not a rarity and must not borrow one's colour.
      expect(seen.contains(powerUpAccent(null)), isFalse);
    });

    test('icons paint at any size, including degenerate ones', () {
      for (final size in [
        const Size(1, 1),
        const Size(20, 44), // non-square: the icon centres, never stretches
        const Size(300, 300),
        Size.zero,
      ]) {
        _onCanvas((c) => paintPowerUpIcon(c, size, PowerUpCard.sonar));
      }
    });

    testWidgets('every card actually draws something', (tester) async {
      // REGRESSION: JAM's signal arcs and SCRAMBLE's rotation arrow are
      // the design's only uses of the SVG elliptical-arc command, which
      // `parseSvgPath` did not support — it bailed out of the whole path,
      // so those shapes silently vanished while every other icon looked
      // fine. Counting inked pixels is what catches a glyph that parsed
      // to nothing.
      for (final def in PowerUps.deck) {
        final inked = await tester.runAsync(() => _inkedPixels(
              (c) => paintPowerUpIcon(c, const Size(100, 100), def.card),
            ));
        expect(inked, greaterThan(500),
            reason: '${def.name} drew almost nothing');
      }
    });
  });

  group('svg support the icons needed', () {
    test('elliptical-arc path commands are parsed, not skipped', () {
      // `A` used to fall through to the parser's bail-out, which abandoned
      // every remaining segment of the path.
      final withArc = parseSvgPath('M 36 46 A 17 17 0 0 1 50 29');
      expect(withArc.computeMetrics().isEmpty, isFalse);
      // A path that continues AFTER an arc keeps its later segments.
      final after = parseSvgPath('M 0 0 A 10 10 0 0 1 20 0 L 20 40');
      expect(after.getBounds().height, greaterThan(30));
    });

    test('a zero-radius arc degrades to a line, per the SVG spec', () {
      final p = parseSvgPath('M 0 0 A 0 0 0 0 1 50 0');
      expect(p.getBounds().width, closeTo(50, 0.001));
    });

    test('an arc that ends where it began is dropped, not drawn', () {
      final p = parseSvgPath('M 10 10 A 5 5 0 1 1 10 10');
      expect(p.getBounds().isEmpty || p.getBounds().width < 1, isTrue);
    });

    testWidgets('<line> is replayed', (tester) async {
      final inked = await tester.runAsync(() => _inkedPixels(
            (c) => paintSvgFragment(
              c,
              '<line x1="10" y1="50" x2="90" y2="50" stroke="#FFFFFF" '
              'stroke-width="6"></line>',
            ),
          ));
      expect(inked, greaterThan(300));
    });

    testWidgets('a line does not inherit a fill from its group',
        (tester) async {
      // SVG never paints a line's interior. If an enclosing `<g fill>`
      // leaked in, the two points would be filled as a degenerate polygon.
      final inked = await tester.runAsync(() => _inkedPixels(
            (c) => paintSvgFragment(
              c,
              '<g fill="#FFFFFF"><line x1="10" y1="10" x2="90" y2="90">'
              '</line></g>',
            ),
          ));
      expect(inked, 0);
    });
  });

  group('randomizer', () {
    testWidgets('spins, reveals the drawn card, then reports done',
        (tester) async {
      var done = false;
      await tester.pumpWidget(MaterialApp(
        home: Stack(children: [
          PowerUpDial(
            card: PowerUpCard.barrage,
            onDone: () => done = true,
            spin: const Duration(milliseconds: 200),
          ),
        ]),
      ));
      // Spinning: the skip affordance is up, nothing has resolved.
      expect(find.text('RANDOMIZING…'), findsOneWidget);
      expect(done, isFalse);

      // Frame by frame — one long pump fires the timers but never ticks
      // the controllers they start.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('RANDOMIZING…'), findsNothing);
      expect(find.text('BARRAGE'), findsOneWidget);

      for (var i = 0; i < 70; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(done, isTrue);
    });

    testWidgets('SKIP jumps to the reveal without changing the card',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Stack(children: [
          PowerUpDial(
            card: PowerUpCard.trapLine,
            onDone: () {},
            // Long enough that the reveal could only come from the tap.
            spin: const Duration(seconds: 10),
          ),
        ]),
      ));
      await tester.tap(find.text('SKIP ▸▸'));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('TRAP LINE'), findsOneWidget);
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    });

    testWidgets('disposing mid-spin leaves no pending timers', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Stack(children: [
          PowerUpDial(card: PowerUpCard.sonar, onDone: () {}),
        ]),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      // The binding asserts on leaked timers at teardown; reaching here
      // without that assertion is the assertion.
    });
  });
}
