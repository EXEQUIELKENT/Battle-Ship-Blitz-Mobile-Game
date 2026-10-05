import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:battleship_blitz/art/legacy_ship_art.dart';
import 'package:battleship_blitz/models/game_models.dart';
import 'package:battleship_blitz/services/storage_service.dart';
import 'package:flutter/material.dart';

/// Which launcher slot the icon is painted for.
///
/// * [full] -> opaque 1024 master.
/// * [round] -> opaque master clipped to a circle (Android
///   `ic_launcher_round`).
/// * [foreground] -> adaptive-icon foreground (transparent, ship only, NO
///   glow wash: a soft radial on a transparent layer bands once compressed
///   to mdpi and reads as a dirt ring over the flat background).
/// * [maskable] -> opaque master with the ship group pulled inside the ~80%
///   maskable safe zone; the water still bleeds full-square.
enum AppIconVariant { full, round, foreground, maskable }

/// Launcher icon: steel battleship charging up-and-right over open water,
/// shell-splash foam where shots land, spray wake off the stern.
///
/// Single source of truth for every launcher slot — the golden test and
/// the asset generator both paint this.
class AppIconPainter extends CustomPainter {
  const AppIconPainter({this.variant = AppIconVariant.full});

  /// Back-compat for the golden test's old `fullBleed:` flag.
  const AppIconPainter.fullBleed({required bool fullBleed})
      : variant =
            fullBleed ? AppIconVariant.full : AppIconVariant.foreground;

  final AppIconVariant variant;

  bool get fullBleed => variant != AppIconVariant.foreground;

  static const _deepWater = Color(0xFF06253E);
  static const _foam = Color(0xFFCDEBFF);

  /// Bow-up heading, ~26deg: reads as "charging" even at launcher size.
  static const _tilt = -0.45;

  /// Flat background for adaptive-icon XML + web theme: deep end of the
  /// water gradient, so the foreground composites onto the same sea.
  static const backgroundColor = _deepWater;

  @override
  bool shouldRepaint(covariant AppIconPainter oldDelegate) =>
      oldDelegate.variant != variant;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final foreground = variant == AppIconVariant.foreground;
    final maskable = variant == AppIconVariant.maskable;
    if (variant == AppIconVariant.round) {
      canvas.clipPath(Path()..addOval(Offset.zero & Size(s, s)));
    }
    final shipCenter = Offset(
        s * (foreground ? 0.50 : 0.54), s * (foreground ? 0.50 : 0.46));
    final shipW = s * (foreground ? 0.60 : 0.72);

    if (!foreground) {
      _water(canvas, s);
      _waveStreaks(canvas, s);
    }
    if (maskable) {
      // Water bleeds full-square; the ship group shrinks into the ~80%
      // maskable safe zone so launcher crops never clip hull or splashes.
      canvas.save();
      canvas.translate(s / 2, s / 2);
      canvas.scale(0.80);
      canvas.translate(-s / 2, -s / 2);
    }
    if (!foreground) {
      _wake(canvas, s, shipCenter, shipW, _tilt);
      _shipShadow(canvas, s, shipCenter, shipW, _tilt);
    }

    _ship(canvas, s, shipCenter, shipW, _tilt);

    if (!foreground) {
      _splash(canvas, Offset(s * 0.80, s * 0.586), s * 0.102, seed: 3);
      _splash(canvas, Offset(s * 0.228, s * 0.346), s * 0.066, seed: 9);
    } else {
      // Inside the ~66% round safe zone: ship + two accents, nothing else.
      _splash(canvas, Offset(s * 0.660, s * 0.601), s * 0.039, seed: 3);
      _splash(canvas, Offset(s * 0.317, s * 0.322), s * 0.027, seed: 9);
    }
    if (maskable) canvas.restore();
    if (!foreground) _vignette(canvas, s);
  }

  void _water(Canvas canvas, double s) {
    final rect = Offset.zero & Size(s, s);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(s * 0.66, s * 0.30),
          s * 0.98,
          const [Color(0xFF2B7DB8), _deepWater],
          const [0.0, 1.0],
        ),
    );
    canvas.drawCircle(
      Offset(s * 0.54, s * 0.44),
      s * 0.40,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(s * 0.54, s * 0.44),
          s * 0.40,
          const [Color(0x66FFDFA8), Color(0x00FFDFA8)],
          const [0.0, 1.0],
        ),
    );
  }

  /// Current streaks and sparkles aligned with the ship's heading —
  /// texture that survives launcher size without turning to noise.
  void _waveStreaks(Canvas canvas, double s) {
    final r = math.Random(11);
    final heading = Offset(math.cos(_tilt), math.sin(_tilt));
    for (var i = 0; i < 22; i++) {
      final len = s * (0.05 + r.nextDouble() * 0.11);
      final c = Offset(r.nextDouble() * s, r.nextDouble() * s);
      canvas.drawLine(
        c - heading * (len / 2),
        c + heading * (len / 2),
        Paint()
          ..color = _foam.withValues(alpha: 0.045 + r.nextDouble() * 0.075)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = s * 0.010,
      );
    }
    for (var i = 0; i < 34; i++) {
      canvas.drawCircle(
        Offset(r.nextDouble() * s, r.nextDouble() * s),
        s * (0.0018 + r.nextDouble() * 0.003),
        Paint()..color = _foam.withValues(alpha: 0.10 + r.nextDouble() * 0.20),
      );
    }
  }

  /// A shell splash in the water beside the hull — hand-drawn foam rings
  /// and droplets. The game's own damage art renders as flat plate
  /// craters, which read as black blobs at icon scale.
  void _splash(Canvas canvas, Offset c, double r, {required int seed}) {
    // Soft white core.
    canvas.drawCircle(
      c,
      r * 0.62,
      Paint()
        ..shader = ui.Gradient.radial(
          c,
          r * 0.62,
          const [Color(0xA6FFFFFF), Color(0x00FFFFFF)],
          const [0.0, 1.0],
        ),
    );
    // Broken foam ring around it.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.14
      ..strokeCap = StrokeCap.round
      ..color = _foam.withValues(alpha: 0.80);
    final rand = math.Random(seed);
    for (var i = 0; i < 6; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        rand.nextDouble() * math.pi * 2,
        0.45 + rand.nextDouble() * 0.40,
        false,
        ring,
      );
    }
    // Droplets cast outward on the golden angle.
    for (var i = 0; i < 9; i++) {
      final a = seed + i * 2.399963;
      final d = r * (1.15 + (i % 3) * 0.14);
      canvas.drawCircle(
        c + Offset(math.cos(a), math.sin(a)) * d,
        r * (0.10 + (i % 2) * 0.05),
        Paint()..color = _foam.withValues(alpha: 0.85),
      );
    }
  }

/// Draws the real in-game steel battleship by rasterising its painter at
  /// design scale (so the hand-authored ink weights stay true) and blowing
  /// that picture up as vectors.
  void _ship(
      Canvas canvas, double s, Offset center, double shipW, double tilt) {
    final skin = Catalog.shipById('steel');
    final spec = kFleet[1]; // Battleship
    final bounds = hullBounds(skin, spec.kind);

    final rec = ui.PictureRecorder();
    paintLegacyShip(
        Canvas(rec), Size(bounds.width, bounds.height), skin, spec.kind);
    final picture = rec.endRecording();

    final k = shipW / bounds.width;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(tilt);
    canvas.scale(k);
    canvas.translate(-bounds.width / 2, -bounds.height / 2);
    canvas.drawPicture(picture);
    canvas.restore();
  }

  void _shipShadow(
      Canvas canvas, double s, Offset center, double shipW, double tilt) {
    // Tie the oval to the hull's real aspect, not a guessed 0.20.
    final bounds = hullBounds(Catalog.shipById('steel'), kFleet[1].kind);
    final shipH = shipW * bounds.height / bounds.width;
    canvas.save();
    canvas.translate(center.dx + shipW * 0.02, center.dy + shipH * 0.55);
    canvas.rotate(tilt);
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset.zero, width: shipW * 1.02, height: shipH * 1.04),
      Paint()
        ..shader = ui.Gradient.radial(
          Offset.zero,
          shipW * 0.51,
          const [Color(0x5A04121F), Color(0x0004121F)],
          const [0.0, 1.0],
        ),
    );
    canvas.restore();
  }

  /// Foam wake streaming off the stern, seen from above: a tapered wash
  /// down the spine, churn blobs on top, spray lines fanning outward.
  void _wake(
      Canvas canvas, double s, Offset center, double shipW, double tilt) {
    final dir = Offset(math.cos(tilt), math.sin(tilt));
    final beam = Offset(-math.sin(tilt), math.cos(tilt));
    final stern = center - dir * shipW * 0.46;
    final trail = -dir;

    // Tapered wash under everything, wide at the stern, thin astern.
    final wash = Path()
      ..moveTo(stern.dx - beam.dx * shipW * 0.05,
          stern.dy - beam.dy * shipW * 0.05)
      ..lineTo(stern.dx + beam.dx * shipW * 0.05,
          stern.dy + beam.dy * shipW * 0.05)
      ..lineTo(
        stern.dx + trail.dx * shipW * 0.55 + beam.dx * shipW * 0.012,
        stern.dy + trail.dy * shipW * 0.55 + beam.dy * shipW * 0.012,
      )
      ..lineTo(
        stern.dx + trail.dx * shipW * 0.55 - beam.dx * shipW * 0.012,
        stern.dy + trail.dy * shipW * 0.55 - beam.dy * shipW * 0.012,
      )
      ..close();
    canvas.drawPath(
        wash, Paint()..color = _foam.withValues(alpha: 0.16));

    // Churn blobs down the spine, shrinking and fading astern.
    const blobs = 8;
    for (var i = 0; i < blobs; i++) {
      final t = (i + 1) / blobs;
      canvas.drawCircle(
        stern +
            trail * shipW * 0.56 * t +
            beam * math.sin(t * 5.2) * shipW * 0.02,
        shipW * (0.045 - 0.033 * t),
        Paint()..color = _foam.withValues(alpha: 0.32 - 0.25 * t),
      );
    }

    // Spray lines fanning out from the stern, fading as they spread.
    Paint spray(Offset end) => Paint()
      ..shader =
          ui.Gradient.linear(stern, end, const [Color(0x8CCDEBFF), Color(0x00CDEBFF)])
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = s * 0.005;
    for (final side in const [1.0, -1.0]) {
      final outerEnd = stern + trail * shipW * 0.50 + beam * side * shipW * 0.16;
      final outerCtrl = stern + trail * shipW * 0.24 + beam * side * shipW * 0.04;
      canvas.drawPath(
        Path()
          ..moveTo(stern.dx, stern.dy)
          ..quadraticBezierTo(outerCtrl.dx, outerCtrl.dy, outerEnd.dx, outerEnd.dy),
        spray(outerEnd),
      );
      final innerEnd = stern + trail * shipW * 0.30 + beam * side * shipW * 0.09;
      final innerCtrl = stern + trail * shipW * 0.14 + beam * side * shipW * 0.02;
      canvas.drawPath(
        Path()
          ..moveTo(stern.dx, stern.dy)
          ..quadraticBezierTo(innerCtrl.dx, innerCtrl.dy, innerEnd.dx, innerEnd.dy),
        spray(innerEnd),
      );
    }
  }

  // -------------------------------------------------------------- finishing

  void _vignette(Canvas canvas, double s) {
    canvas.drawRect(
      Offset.zero & Size(s, s),
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(s * 0.5, s * 0.46),
          s * 0.72,
          const [Color(0x00000000), Color(0x9E03101C)],
          const [0.55, 1.0],
        ),
    );
  }
}
