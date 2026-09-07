import 'dart:ui' as ui;

import 'package:battleship_blitz/art/impact_fx.dart';
import 'package:battleship_blitz/services/storage_service.dart';
import 'package:battleship_blitz/widgets/wreck_reveal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs [draw] onto a throwaway canvas, so a painter that divides by zero,
/// builds a degenerate `Path` or hands `Paint` a NaN blows up here rather
/// than mid-match on someone's phone.
void _onCanvas(void Function(Canvas canvas) draw) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  draw(canvas);
  recorder.endRecording().dispose();
}

/// Progress values covering the whole life of an effect, including both
/// ends and the boundaries the splash (0.55) and arrival (0.45) phases
/// switch off at.
const _progress = [
  0.0, 0.01, 0.1, 0.25, 0.44, 0.45, 0.46, 0.54, 0.55, 0.56, 0.7, 0.99, 1.0,
];

void main() {
  group('impact fx catalogue', () {
    test('every cannon resolves to a profile, and no two guns share a look',
        () {
      final splashes = <SplashStyle, String>{};
      final bursts = <BurstStyle, String>{};
      for (final cannon in Catalog.cannonSkins) {
        final fx = impactFxForCannon(cannon.id);
        // A gun that was never given an entry silently inherits MK-I's
        // plain white spray, which is exactly the "they all look the same"
        // complaint this work exists to fix.
        expect(splashes.containsKey(fx.splash), isFalse,
            reason: '${cannon.id} splashes like ${splashes[fx.splash]}');
        expect(bursts.containsKey(fx.burst), isFalse,
            reason: '${cannon.id} bursts like ${bursts[fx.burst]}');
        splashes[fx.splash] = cannon.id;
        bursts[fx.burst] = cannon.id;
      }
      expect(splashes, hasLength(Catalog.cannonSkins.length));
    });

    test('an unknown or absent gun still gets a usable profile', () {
      for (final id in <String?>[null, '', 'not_a_cannon']) {
        final fx = impactFxForCannon(id);
        expect(fx.splash, SplashStyle.spray);
        expect(fx.scale, greaterThan(0));
      }
    });

    test('every style paints across the whole effect lifetime', () {
      for (final cannon in Catalog.cannonSkins) {
        final fx = impactFxForCannon(cannon.id);
        for (final t in _progress) {
          _onCanvas((canvas) {
            paintImpactSplash(canvas, const Offset(20, 20), 40, t, fx, 7);
            paintImpactBurst(canvas, const Offset(20, 20), 40, t, fx, 7);
            paintImpactBurst(canvas, const Offset(20, 20), 40, t, fx, 7,
                big: true);
            paintMarkArrival(canvas, const Offset(20, 20), 40, t, fx);
          });
        }
      }
    });

    test('a tiny cell (a board squeezed onto a small screen) still paints',
        () {
      for (final cannon in Catalog.cannonSkins) {
        final fx = impactFxForCannon(cannon.id);
        _onCanvas((canvas) {
          paintImpactSplash(canvas, Offset.zero, 1.0, 0.3, fx, 0);
          paintImpactBurst(canvas, Offset.zero, 1.0, 0.3, fx, 0, big: true);
          paintMarkArrival(canvas, Offset.zero, 1.0, 0.3, fx);
        });
      }
    });
  });

  group('wreck motion', () {
    test('every ship skin has its own destruction motion', () {
      final seen = <WreckMotion, String>{};
      for (final skin in Catalog.shipSkins) {
        final m = wreckMotionForShipSkin(skin.id);
        expect(seen.containsKey(m), isFalse,
            reason: '${skin.id} sinks exactly like ${seen[m]}');
        seen[m] = skin.id;
      }
      expect(seen, hasLength(Catalog.shipSkins.length));
    });

    test('an unknown hull falls back to the plain settle', () {
      expect(wreckMotionForShipSkin(null), WreckMotion.settle);
      expect(wreckMotionForShipSkin('not_a_skin'), WreckMotion.settle);
    });

    test('a revealed wreck ends exactly where it belongs', () {
      // The whole point of the reveal is that the wreck lands on its grid
      // cell, unrotated, at full size and fully opaque. A motion that ends
      // even slightly off leaves the wreck permanently misplaced — and an
      // opacity that settles below 1.0 keeps an offscreen layer alive on
      // every wreck for the rest of the match.
      for (final m in WreckMotion.values) {
        final f = wreckRevealFrame(m, 1.0, 32);
        expect(f.scaleX, closeTo(1.0, 1e-9), reason: '$m scaleX');
        expect(f.scaleY, closeTo(1.0, 1e-9), reason: '$m scaleY');
        expect(f.rotation, closeTo(0.0, 1e-9), reason: '$m rotation');
        expect(f.dx, closeTo(0.0, 1e-9), reason: '$m dx');
        expect(f.dy, closeTo(0.0, 1e-9), reason: '$m dy');
        expect(f.opacity, closeTo(1.0, 1e-9), reason: '$m opacity');
      }
    });

    test('no frame of any motion is degenerate or invisible-by-accident', () {
      for (final m in WreckMotion.values) {
        for (var i = 0; i <= 40; i++) {
          final t = i / 40;
          for (final f in [
            wreckRevealFrame(m, t, 32),
            wreckSinkFrame(m, t, 32),
          ]) {
            for (final v in [f.scaleX, f.scaleY, f.rotation, f.dx, f.dy]) {
              expect(v.isFinite, isTrue, reason: '$m @$t produced $v');
            }
            // A non-positive scale mirrors the artwork inside out.
            expect(f.scaleX, greaterThan(0.0), reason: '$m @$t scaleX');
            expect(f.scaleY, greaterThan(0.0), reason: '$m @$t scaleY');
            expect(f.opacity, inInclusiveRange(0.0, 1.0),
                reason: '$m @$t opacity');
          }
        }
      }
    });

    test('a sinking wreck has fully gone by the end', () {
      for (final m in WreckMotion.values) {
        expect(wreckSinkFrame(m, 1.0, 32).opacity, closeTo(0.0, 1e-9),
            reason: '$m is still visible after it sank');
      }
    });

    testWidgets('WreckReveal plays once and settles opaque', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: SizedBox(
              width: 100,
              height: 30,
              child: WreckReveal(
                motion: WreckMotion.capsize,
                span: 30,
                child: ColoredBox(color: Color(0xFF00FF00)),
              ),
            ),
          ),
        ),
      );
      final opacity = find.descendant(
        of: find.byType(WreckReveal),
        matching: find.byType(Opacity),
      );
      // Mid-flight it is transformed and translucent…
      await tester.pump(const Duration(milliseconds: 200));
      expect(opacity, findsOneWidget);
      // …and once settled the Opacity layer is dropped entirely.
      await tester.pumpAndSettle();
      expect(opacity, findsNothing);
    });
  });
}
