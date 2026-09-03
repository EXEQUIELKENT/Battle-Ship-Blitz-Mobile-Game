import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'fleet_family.dart';
import 'legacy_identity.dart';

/// This reticle's own theme colour, for the parts drawn here rather than
/// inside a skin's own `case` below — currently the corner brackets.
/// Reads the SAME accent the gun, its board and its hit marks already
/// use, so a bracket can never drift out of step with the reticle it
/// frames.
Color crosshairAccent(String id) {
  final family =
      FleetFamilies.byKey(id.startsWith('f_') ? id.substring(2) : null);
  return family?.accent ?? legacyIdentityFor(id).accent;
}

/// FEEDBACK ("add angle lines on the four corners so the reticle is more
/// noticeable"): an L-shaped bracket in each corner of the targeted
/// CELL, which is what actually makes a reticle read as "this square" at
/// a glance — the reticle art itself is centre-weighted, so on a busy
/// board it had nothing marking the cell's own extent.
///
/// Drawn from [size] directly rather than through the reticle's own
/// design-box mapping, so the brackets stay pinned to the true cell
/// corners no matter how the art inside is scaled. Each is laid down
/// twice — a dark backing stroke, then the theme colour — so it holds up
/// over a pale deck (Arctic Storm, Rime Wardens) as well as a dark one.
void _paintCornerBrackets(Canvas canvas, Size size, Color accent) {
  final w = size.width;
  final h = size.height;
  final inset = w * 0.05;
  final arm = w * 0.27;
  final stroke = math.max(w * 0.055, 2.0);
  for (var pass = 0; pass < 2; pass++) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = pass == 0 ? stroke + math.max(w * 0.024, 1.4) : stroke
      ..color = pass == 0
          ? const Color(0xFF0E151C).withValues(alpha: 0.5)
          : accent;
    for (final corner in const [
      Offset(0, 0),
      Offset(1, 0),
      Offset(0, 1),
      Offset(1, 1),
    ]) {
      final ox = corner.dx == 0 ? inset : w - inset;
      final oy = corner.dy == 0 ? inset : h - inset;
      final sx = corner.dx == 0 ? arm : -arm;
      final sy = corner.dy == 0 ? arm : -arm;
      canvas.drawPath(
        Path()
          ..moveTo(ox, oy + sy)
          ..lineTo(ox, oy)
          ..lineTo(ox + sx, oy),
        paint,
      );
    }
  }
}

/// The fifteen redesigned crosshairs — the nine legacy cannons plus the
/// six thematic families — ported verbatim from `uploads/New Design/Cross
/// Hairs/ch-*.svg` / `ch-f-*.svg`, all authored in one shared 100×100 box
/// centred at (50,50). Called from each of `battle_grid.dart`'s existing,
/// already-wired `_XxxCrosshairPainter` classes — this only replaces
/// their geometry, not their names, constructors, or the dispatch table
/// that picks between them.
void paintLegacyCrosshair(Canvas canvas, Size size, String id) {
  _paintCornerBrackets(canvas, size, crosshairAccent(id));
  _paintReticle(canvas, size, id);
}

/// The reticle art itself. Split from [paintLegacyCrosshair] so the
/// unknown-id fallback at the bottom can re-enter it without drawing a
/// second set of corner brackets over the first.
void _paintReticle(Canvas canvas, Size size, String id) {
  // FEEDBACK ("the crosshair is still kinda small"): the authored box
  // mapped 1:1 onto the cell, which left the reticle's own art — all of
  // it centre-weighted, none of it near the box edge — reading as a
  // small mark floating in a large square. Magnifying about the CENTRE
  // (rather than remapping the box) grows the art without moving where
  // it is aimed; the corner brackets above are drawn from `size`, so
  // they stay on the true cell corners regardless of this.
  const magnify = 1.18;
  final scale = size.width / 100 * magnify;
  final origin = Offset(size.width / 2, size.height / 2);
  Offset p(double x, double y) => origin + (Offset(x, y) - const Offset(50, 50)) * scale;
  double s(double len) => len * scale;
  Paint fill(Color c, {double opacity = 1}) => Paint()..color = c.withValues(alpha: opacity);
  // FEEDBACK: the crosshairs' shapes read fine but were too thin to
  // actually spot in the middle of a match — every line width below is
  // boosted well past its authored SVG weight, with a floor so even the
  // faintest 0.5–0.7-unit accent strokes stay visible at on-grid cell
  // size rather than aliasing away to nothing.
  Paint strokeP(Color c, double w, {double opacity = 1, StrokeCap cap = StrokeCap.butt, List<double>? dash}) =>
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(s(w) * 1.8, 1.4)
        ..strokeCap = cap
        ..color = c.withValues(alpha: opacity);
  void ring(double r, Color c, double w, {double opacity = 1, List<double>? dash, StrokeCap cap = StrokeCap.butt}) {
    if (dash == null) {
      canvas.drawCircle(p(50, 50), s(r), strokeP(c, w, opacity: opacity, cap: cap));
      return;
    }
    final path = Path()..addOval(Rect.fromCircle(center: p(50, 50), radius: s(r)));
    final out = Path();
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      var i = 0;
      var draw = true;
      while (d < metric.length) {
        final len = s(dash[i % dash.length]);
        if (draw) out.addPath(metric.extractPath(d, (d + len).clamp(0, metric.length)), Offset.zero);
        d += len;
        i++;
        draw = !draw;
      }
    }
    canvas.drawPath(out, strokeP(c, w, opacity: opacity));
  }
  void poly(List<Offset> pts, Paint paint) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final pt in pts.skip(1)) {
      path.lineTo(pt.dx, pt.dy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  switch (id) {
    // ============================================================ mk1 ===
    case 'mk1':
      ring(22, const Color(0xFF9CA3AF), 0.7, opacity: 0.28, dash: const [2, 3]);
      canvas.drawCircle(p(50, 50), s(1.7), fill(const Color(0xFFE5E9EE)));
      ring(5.8, const Color(0xFF9CA3AF), 1.2, opacity: 0.95);
      canvas.drawLine(p(50, 17), p(50, 31), strokeP(const Color(0xFFE5E9EE), 2, cap: StrokeCap.square));
      canvas.drawLine(p(50, 69), p(50, 83), strokeP(const Color(0xFFE5E9EE), 2, cap: StrokeCap.square));
      canvas.drawLine(p(17, 50), p(31, 50), strokeP(const Color(0xFFE5E9EE), 2, cap: StrokeCap.square));
      canvas.drawLine(p(69, 50), p(83, 50), strokeP(const Color(0xFFE5E9EE), 2, cap: StrokeCap.square));
      for (final c in const [[22, 22, 30, 30], [78, 22, 70, 30], [22, 78, 30, 70], [78, 78, 70, 70]]) {
        canvas.drawPath(
            (Path()..moveTo(p(c[0].toDouble(), c[1].toDouble()).dx, p(c[0].toDouble(), c[1].toDouble()).dy)
              ..lineTo(p(c[0].toDouble(), c[3].toDouble()).dx, p(c[0].toDouble(), c[3].toDouble()).dy)
              ..lineTo(p(c[2].toDouble(), c[3].toDouble()).dx, p(c[2].toDouble(), c[3].toDouble()).dy)),
            strokeP(const Color(0xFF9CA3AF), 1.5));
      }
      for (final xy in const [[50, 28], [50, 72], [28, 50], [72, 50]]) {
        canvas.drawCircle(p(xy[0].toDouble(), xy[1].toDouble()), s(1), fill(const Color(0xFF9CA3AF), opacity: 0.9));
      }
      break;

    // ========================================================= inferno ===
    case 'inferno':
      ring(23, const Color(0xFF7C2D12), 1.1, opacity: 0.9, dash: const [5, 5]);
      poly([p(50, 18), p(52, 26), p(48, 26)], fill(const Color(0xFFEF4444)));
      poly([p(50, 82), p(52, 74), p(48, 74)], fill(const Color(0xFFEF4444)));
      poly([p(18, 50), p(26, 52), p(26, 48)], fill(const Color(0xFFEF4444)));
      poly([p(82, 50), p(74, 52), p(74, 48)], fill(const Color(0xFFEF4444)));
      canvas.drawLine(p(50, 20), p(50, 34), strokeP(const Color(0xFFEF4444), 1.9));
      canvas.drawLine(p(50, 66), p(50, 80), strokeP(const Color(0xFFEF4444), 1.9));
      canvas.drawLine(p(20, 50), p(34, 50), strokeP(const Color(0xFFEF4444), 1.9));
      canvas.drawLine(p(66, 50), p(80, 50), strokeP(const Color(0xFFEF4444), 1.9));
      poly([p(50, 38), p(56, 50), p(50, 62), p(44, 50)], strokeP(const Color(0xFFFFD54A), 1.2, opacity: 0.95));
      poly([p(38, 50), p(50, 44), p(62, 50), p(50, 56)], strokeP(const Color(0xFFFFD54A), 1.2, opacity: 0.95));
      canvas.drawCircle(p(50, 50), s(3.2), fill(const Color(0xFFFFD54A)));
      ring(6.5, const Color(0xFFEF4444), 0.9, opacity: 0.5);
      break;

    // ========================================================== kraken ===
    case 'kraken':
      ring(8, const Color(0xFF34D399), 1.1);
      canvas.drawCircle(p(50, 50), s(2.4), fill(const Color(0xFFB6FFF1)));
      canvas.drawLine(p(50, 18), p(50, 32), strokeP(const Color(0xFF0F766E), 1.6));
      canvas.drawLine(p(50, 68), p(50, 82), strokeP(const Color(0xFF0F766E), 1.6));
      canvas.drawLine(p(18, 50), p(32, 50), strokeP(const Color(0xFF0F766E), 1.6));
      canvas.drawLine(p(68, 50), p(82, 50), strokeP(const Color(0xFF0F766E), 1.6));
      for (final c in const [
        [34.0, 32.0, 28.0, 24.0, 18.0, 26.0, 18.0, 18.0],
        [66.0, 32.0, 72.0, 24.0, 82.0, 26.0, 82.0, 18.0],
        [34.0, 68.0, 28.0, 76.0, 18.0, 74.0, 18.0, 82.0],
        [66.0, 68.0, 72.0, 76.0, 82.0, 74.0, 82.0, 82.0],
      ]) {
        canvas.drawPath(
            (Path()..moveTo(p(c[0], c[1]).dx, p(c[0], c[1]).dy)..cubicTo(
                p(c[2], c[3]).dx, p(c[2], c[3]).dy, p(c[4], c[5]).dx, p(c[4], c[5]).dy, p(c[6], c[7]).dx, p(c[6], c[7]).dy)),
            strokeP(const Color(0xFF34D399), 1.4, cap: StrokeCap.round));
      }
      canvas.drawCircle(p(38, 42), s(2), fill(const Color(0xFF34D399)));
      canvas.drawCircle(p(62, 42), s(1.5), fill(const Color(0xFF34D399)));
      canvas.drawCircle(p(38, 58), s(1.5), fill(const Color(0xFF34D399)));
      canvas.drawCircle(p(62, 58), s(2), fill(const Color(0xFF34D399)));
      for (final xy in const [[18, 18], [82, 18], [18, 82], [82, 82]]) {
        canvas.drawCircle(p(xy[0].toDouble(), xy[1].toDouble()), s(1.6), fill(const Color(0xFFB6FFF1)));
      }
      break;

    // ========================================================= phantom ===
    case 'phantom':
      poly([p(50, 18), p(53, 28), p(47, 28)], fill(const Color(0xFF7C6BC4)));
      canvas.drawLine(p(50, 22), p(50, 38), strokeP(const Color(0xFF7C6BC4), 1.6, dash: const [4, 3]));
      canvas.drawLine(p(50, 62), p(50, 78), strokeP(const Color(0xFF7C6BC4), 1.6, dash: const [4, 3]));
      canvas.drawLine(p(22, 50), p(38, 50), strokeP(const Color(0xFF7C6BC4), 1.2, opacity: 0.6));
      canvas.drawLine(p(62, 50), p(78, 50), strokeP(const Color(0xFF7C6BC4), 1.2, opacity: 0.6));
      canvas.drawOval(Rect.fromCenter(center: p(50, 50), width: s(32), height: s(11)),
          strokeP(const Color(0xFF7C6BC4), 1, opacity: 0.85));
      canvas.drawOval(Rect.fromCenter(center: p(50, 50), width: s(40), height: s(13)),
          strokeP(const Color(0xFF7C6BC4), 0.7, opacity: 0.5));
      poly([p(50, 74), p(44, 84), p(50, 80)], fill(const Color(0xFF312E81)));
      poly([p(50, 74), p(56, 84), p(50, 80)], fill(const Color(0xFF312E81)));
      canvas.drawCircle(p(50, 50), s(2.2), fill(const Color(0xFFF1E3FF)));
      ring(6, const Color(0xFF7C6BC4), 0.8, opacity: 0.6);
      break;

    // =========================================================== royal ===
    case 'royal':
      canvas.drawOval(Rect.fromCenter(center: p(50, 50), width: s(44), height: s(16)),
          strokeP(const Color(0xFFFBBF24), 1.2, opacity: 0.9));
      canvas.drawOval(Rect.fromCenter(center: p(50, 50), width: s(44), height: s(16)),
          strokeP(const Color(0xFFFFF3C4), 0.6, opacity: 0.7));
      for (final xy in const [[32, 50], [42, 54], [50, 55], [58, 54], [68, 50]]) {
        canvas.drawCircle(p(xy[0].toDouble(), xy[1].toDouble()), s(1.5), fill(const Color(0xFFFBBF24)));
      }
      poly([p(50, 18), p(46, 28), p(54, 28)], fill(const Color(0xFFFBBF24)));
      canvas.drawCircle(p(50, 16), s(1.6), fill(const Color(0xFFFFF3C4)));
      canvas.drawLine(p(50, 22), p(50, 36), strokeP(const Color(0xFF92400E), 1.4, opacity: 0.9));
      canvas.drawLine(p(50, 64), p(50, 82), strokeP(const Color(0xFF92400E), 1.4, opacity: 0.9));
      canvas.drawLine(p(22, 50), p(34, 50), strokeP(const Color(0xFF92400E), 1.4, opacity: 0.9));
      canvas.drawLine(p(66, 50), p(78, 50), strokeP(const Color(0xFF92400E), 1.4, opacity: 0.9));
      canvas.drawCircle(p(50, 50), s(2.6), fill(const Color(0xFFFBBF24)));
      ring(6.5, const Color(0xFFFBBF24), 0.8, opacity: 0.5);
      break;

    // ========================================================= sunfire ===
    case 'sunfire':
      ring(24.5, const Color(0xFFB45309), 0.55, opacity: 0.22, dash: const [2, 3.5]);
      for (final a in const [0, 90, 180, 270]) {
        final rad = a * math.pi / 180;
        Offset rot(double x, double y) {
          final dx = x - 50, dy = y - 50;
          return p(50 + dx * math.cos(rad) - dy * math.sin(rad), 50 + dx * math.sin(rad) + dy * math.cos(rad));
        }
        poly([rot(50, 17), rot(47.2, 28.5), rot(52.8, 28.5)], fill(const Color(0xFFE0715A)));
      }
      for (final a in const [45, 135, 225, 315]) {
        final rad = a * math.pi / 180;
        Offset rot(double x, double y) {
          final dx = x - 50, dy = y - 50;
          return p(50 + dx * math.cos(rad) - dy * math.sin(rad), 50 + dx * math.sin(rad) + dy * math.cos(rad));
        }
        poly([rot(50, 22), rot(47.8, 31), rot(52.2, 31)], fill(const Color(0xFFE0715A)));
      }
      ring(9.5, const Color(0xFFB45309), 1.15);
      ring(9.5, const Color(0xFFFFF8D6), 0.45, opacity: 0.5, dash: const [1, 5.5]);
      canvas.drawCircle(p(50, 50), s(5.6), fill(const Color(0xFFE0715A)));
      canvas.drawCircle(p(50, 50), s(2.1), fill(const Color(0xFFFFF8D6)));
      canvas.drawCircle(p(50, 50), s(0.9), fill(Colors.white, opacity: 0.96));
      break;

    // =========================================================== tesla ===
    case 'tesla':
      ring(24, const Color(0xFF0E7490), 1, opacity: 0.9, dash: const [8, 6]);
      canvas.drawLine(p(50, 18), p(50, 32), strokeP(const Color(0xFF7FB8D6), 1.7));
      canvas.drawLine(p(50, 68), p(50, 82), strokeP(const Color(0xFF7FB8D6), 1.7));
      canvas.drawLine(p(18, 50), p(32, 50), strokeP(const Color(0xFF7FB8D6), 1.7));
      canvas.drawLine(p(68, 50), p(82, 50), strokeP(const Color(0xFF7FB8D6), 1.7));
      poly([p(50, 38), p(46, 42), p(50, 46), p(54, 42)], strokeP(const Color(0xFF7FB8D6), 1.1));
      poly([p(38, 50), p(42, 46), p(46, 50), p(42, 54)], strokeP(const Color(0xFF7FB8D6), 1.1));
      poly([p(62, 50), p(58, 46), p(54, 50), p(58, 54)], strokeP(const Color(0xFF7FB8D6), 1.1));
      poly([p(50, 62), p(46, 58), p(50, 54), p(54, 58)], strokeP(const Color(0xFF7FB8D6), 1.1));
      canvas.drawPath(
          (Path()..moveTo(p(30, 38).dx, p(30, 38).dy)..lineTo(p(40, 46).dx, p(40, 46).dy)..lineTo(p(34, 52).dx, p(34, 52).dy)),
          strokeP(const Color(0xFFE0FBFF), 1.1, opacity: 0.95, cap: StrokeCap.round));
      canvas.drawPath(
          (Path()..moveTo(p(70, 62).dx, p(70, 62).dy)..lineTo(p(60, 54).dx, p(60, 54).dy)..lineTo(p(66, 48).dx, p(66, 48).dy)),
          strokeP(const Color(0xFFE0FBFF), 1.1, opacity: 0.95, cap: StrokeCap.round));
      canvas.drawCircle(p(50, 50), s(2.4), fill(const Color(0xFFE0FBFF)));
      ring(6.2, const Color(0xFF7FB8D6), 0.9, opacity: 0.6);
      for (final c in const [[24, 24, 32, 24], [76, 24, 68, 24], [24, 76, 32, 76], [76, 76, 68, 76]]) {
        canvas.drawLine(p(c[0].toDouble(), c[1].toDouble()), p(c[0].toDouble(), (c[1] + (c[1] < 50 ? 8 : -8)).toDouble()),
            strokeP(const Color(0xFF0E7490), 1.2));
        canvas.drawLine(p(c[0].toDouble(), c[1].toDouble()), p(c[2].toDouble(), c[1].toDouble()),
            strokeP(const Color(0xFF0E7490), 1.2));
      }
      break;

    // =========================================================== venom ===
    case 'venom':
      ring(24, const Color(0xFF365314), 1.3, opacity: 0.9, dash: const [3, 4]);
      canvas.drawLine(p(50, 18), p(50, 30), strokeP(const Color(0xFFA3E635), 1.9));
      canvas.drawLine(p(50, 70), p(50, 82), strokeP(const Color(0xFFA3E635), 1.9));
      canvas.drawLine(p(18, 50), p(30, 50), strokeP(const Color(0xFFA3E635), 1.9));
      canvas.drawLine(p(70, 50), p(82, 50), strokeP(const Color(0xFFA3E635), 1.9));
      poly([p(50, 22), p(46, 30), p(54, 30)], fill(const Color(0xFF365314)));
      poly([p(50, 78), p(46, 70), p(54, 70)], fill(const Color(0xFF365314)));
      poly([p(22, 50), p(30, 46), p(30, 54)], fill(const Color(0xFF365314)));
      poly([p(78, 50), p(70, 46), p(70, 54)], fill(const Color(0xFF365314)));
      ring(8, const Color(0xFFA3E635), 1.1, dash: const [3, 2]);
      canvas.drawCircle(p(50, 50), s(3), fill(const Color(0xFFD4F98A)));
      poly([p(36, 72), p(36, 76), p(38, 74)], fill(const Color(0xFFA3E635), opacity: 0.9));
      poly([p(64, 72), p(64, 76), p(62, 74)], fill(const Color(0xFFA3E635), opacity: 0.9));
      break;

    // ============================================================ void ===
    case 'void':
      canvas.drawOval(Rect.fromCenter(center: p(50, 50), width: s(48), height: s(20)),
          strokeP(const Color(0xFF4B72A8), 1.2, opacity: 0.85));
      canvas.drawOval(Rect.fromCenter(center: p(50, 50), width: s(48), height: s(20)),
          strokeP(const Color(0xFFFBCFE8), 0.6, opacity: 0.6));
      canvas.drawCircle(p(50, 50), s(9), fill(const Color(0xFF111827)));
      canvas.drawCircle(p(50, 50), s(9), fill(Colors.black, opacity: 0.35));
      canvas.drawCircle(p(50, 50), s(2), fill(const Color(0xFFFBCFE8)));
      canvas.drawLine(p(50, 18), p(50, 30), strokeP(const Color(0xFF4B72A8), 1.2, opacity: 0.7));
      canvas.drawLine(p(50, 70), p(50, 82), strokeP(const Color(0xFF4B72A8), 1.2, opacity: 0.7));
      canvas.drawLine(p(18, 50), p(30, 50), strokeP(const Color(0xFF4B72A8), 1.2, opacity: 0.7));
      canvas.drawLine(p(70, 50), p(82, 50), strokeP(const Color(0xFF4B72A8), 1.2, opacity: 0.7));
      canvas.drawPath(
          (Path()..moveTo(p(18, 42).dx, p(18, 42).dy)..cubicTo(p(26, 44).dx, p(26, 44).dy, p(26, 56).dx, p(26, 56).dy, p(18, 58).dx, p(18, 58).dy)),
          strokeP(const Color(0xFF4B72A8), 0.9, opacity: 0.55, cap: StrokeCap.round));
      canvas.drawPath(
          (Path()..moveTo(p(82, 42).dx, p(82, 42).dy)..cubicTo(p(74, 44).dx, p(74, 44).dy, p(74, 56).dx, p(74, 56).dy, p(82, 58).dx, p(82, 58).dy)),
          strokeP(const Color(0xFF4B72A8), 0.9, opacity: 0.55, cap: StrokeCap.round));
      canvas.drawCircle(p(16, 34), s(1), fill(const Color(0xFFFBCFE8), opacity: 0.7));
      canvas.drawCircle(p(84, 66), s(1), fill(const Color(0xFFFBCFE8), opacity: 0.7));
      break;

    // ==================================================== family: arctic ===
    case 'f_arctic':
      canvas.drawLine(p(50, 18), p(50, 30), strokeP(const Color(0xFF7FB6CE), 1.4));
      canvas.drawRect(Rect.fromLTWH(p(44, 30).dx, p(44, 30).dy, s(12), s(12)), strokeP(const Color(0xFF7FB6CE), 1.4));
      canvas.drawLine(p(50, 42), p(50, 54), strokeP(const Color(0xFF7FB6CE), 1.4));
      canvas.drawRect(Rect.fromLTWH(p(40, 54).dx, p(40, 54).dy, s(20), s(12)), strokeP(const Color(0xFF7FB6CE), 1.4));
      canvas.drawLine(p(18, 50), p(32, 50), strokeP(const Color(0xFF7FB6CE), 1.4));
      canvas.drawLine(p(68, 50), p(82, 50), strokeP(const Color(0xFF7FB6CE), 1.4));
      poly([p(42, 42), p(38, 30), p(44, 34)], fill(const Color(0xFFBDF1FF)));
      poly([p(58, 42), p(62, 30), p(56, 34)], fill(const Color(0xFFBDF1FF)));
      poly([p(42, 66), p(38, 78), p(44, 74)], fill(const Color(0xFFBDF1FF)));
      poly([p(58, 66), p(62, 78), p(56, 74)], fill(const Color(0xFFBDF1FF)));
      ring(24, const Color(0xFFC8DCE6), 0.8, opacity: 0.45, dash: const [2, 3]);
      ring(7, const Color(0xFFBDF1FF), 1);
      canvas.drawCircle(p(50, 50), s(2), fill(const Color(0xFFEAF7FC)));
      canvas.drawCircle(p(30, 30), s(0.8), fill(Colors.white, opacity: 0.7));
      canvas.drawCircle(p(70, 70), s(0.8), fill(Colors.white, opacity: 0.7));
      break;

    // ===================================================== family: naval ===
    case 'f_naval':
      canvas.drawLine(p(50, 16), p(50, 40), strokeP(const Color(0xFF5A6B78), 2.2, cap: StrokeCap.square));
      canvas.drawLine(p(50, 60), p(50, 84), strokeP(const Color(0xFF5A6B78), 2.2, cap: StrokeCap.square));
      canvas.drawLine(p(20, 50), p(38, 50), strokeP(const Color(0xFF8CA0AD), 1.5, opacity: 0.8));
      canvas.drawLine(p(62, 50), p(80, 50), strokeP(const Color(0xFF8CA0AD), 1.5, opacity: 0.8));
      canvas.drawLine(p(46, 16), p(54, 16), strokeP(const Color(0xFF1B252D), 0.9, opacity: 0.9));
      canvas.drawLine(p(46, 20), p(54, 20), strokeP(const Color(0xFF1B252D), 0.9, opacity: 0.9));
      canvas.drawRect(Rect.fromLTWH(p(42, 44).dx, p(44, 44).dy, s(16), s(12)), strokeP(const Color(0xFFCFE0EA), 0.9, opacity: 0.9));
      canvas.drawCircle(p(50, 50), s(2), fill(const Color(0xFFCFE0EA)));
      ring(5.8, const Color(0xFFCFE0EA), 0.8, opacity: 0.5);
      for (final xy in const [[36, 36], [64, 36], [36, 64], [64, 64]]) {
        canvas.drawCircle(p(xy[0].toDouble(), xy[1].toDouble()), s(1), fill(const Color(0xFF1B252D), opacity: 0.5));
      }
      break;

    // ==================================================== family: pirate ===
    case 'f_pirate':
      ring(26, const Color(0xFF8A5A2B), 1.3, opacity: 0.9);
      canvas.drawLine(p(50, 18), p(50, 32), strokeP(const Color(0xFFF2B24C), 1.9));
      canvas.drawLine(p(50, 68), p(50, 82), strokeP(const Color(0xFFF2B24C), 1.9));
      canvas.drawLine(p(18, 50), p(32, 50), strokeP(const Color(0xFFF2B24C), 1.9));
      canvas.drawLine(p(68, 50), p(82, 50), strokeP(const Color(0xFFF2B24C), 1.9));
      poly([p(46, 18), p(54, 18), p(56, 14), p(44, 14)], fill(const Color(0xFFC98A3E)));
      ring(7, const Color(0xFF8A5A2B), 0.9);
      canvas.save();
      canvas.translate(p(28, 50).dx - p(50, 50).dx, 0);
      canvas.drawCircle(p(50, 50), s(7), strokeP(const Color(0xFF8A5A2B), 0.9));
      canvas.restore();
      canvas.drawCircle(p(72, 50), s(7), strokeP(const Color(0xFF8A5A2B), 0.9));
      canvas.drawLine(p(28, 43), p(28, 57), strokeP(const Color(0xFF2A1B0F), 0.7, opacity: 0.6));
      canvas.drawLine(p(21, 50), p(35, 50), strokeP(const Color(0xFF2A1B0F), 0.7, opacity: 0.6));
      canvas.drawLine(p(72, 43), p(72, 57), strokeP(const Color(0xFF2A1B0F), 0.7, opacity: 0.6));
      canvas.drawLine(p(65, 50), p(79, 50), strokeP(const Color(0xFF2A1B0F), 0.7, opacity: 0.6));
      canvas.drawCircle(p(50, 50), s(4.5), fill(const Color(0xFFF2B24C)));
      canvas.drawCircle(p(50, 50), s(1.6), fill(const Color(0xFF2A1B0F)));
      break;

    // ===================================================== family: scifi ===
    case 'f_scifi':
      canvas.drawRect(Rect.fromLTWH(p(46, 18).dx, p(18, 18).dy, s(8), s(12)), strokeP(const Color(0xFF6E8FD8), 0.9));
      canvas.drawRect(Rect.fromLTWH(p(46, 34).dx, p(34, 34).dy, s(8), s(12)), strokeP(const Color(0xFF6E8FD8), 0.9));
      canvas.drawRect(Rect.fromLTWH(p(46, 50).dx, p(50, 50).dy, s(8), s(10)), strokeP(const Color(0xFF6E8FD8), 0.9));
      canvas.drawLine(p(50, 30), p(50, 34), strokeP(const Color(0xFF6FE7FF), 1.4, cap: StrokeCap.round));
      canvas.drawLine(p(50, 46), p(50, 50), strokeP(const Color(0xFF6FE7FF), 1.4, cap: StrokeCap.round));
      canvas.drawLine(p(46, 18), p(42, 12), strokeP(const Color(0xFF6E8FD8), 1.1, cap: StrokeCap.round));
      canvas.drawLine(p(54, 18), p(58, 12), strokeP(const Color(0xFF6E8FD8), 1.1, cap: StrokeCap.round));
      canvas.drawCircle(p(50, 10), s(2.5), fill(const Color(0xFF6FE7FF), opacity: 0.95));
      canvas.drawCircle(p(50, 10), s(5), fill(const Color(0xFF6FE7FF), opacity: 0.18));
      poly([p(50, 38), p(58, 42), p(58, 58), p(50, 62), p(42, 58), p(42, 42)],
          strokeP(const Color(0xFF6FE7FF), 0.9, opacity: 0.9));
      canvas.drawLine(p(18, 50), p(34, 50), strokeP(const Color(0xFF6FE7FF), 1.2, opacity: 0.7));
      canvas.drawLine(p(66, 50), p(82, 50), strokeP(const Color(0xFF6FE7FF), 1.2, opacity: 0.7));
      canvas.drawLine(p(50, 66), p(50, 82), strokeP(const Color(0xFF6FE7FF), 1.2, opacity: 0.7));
      canvas.drawCircle(p(50, 50), s(1.8), fill(Colors.white));
      ring(5.5, const Color(0xFF6FE7FF), 0.7, opacity: 0.5);
      for (final c in const [[24, 24, 30], [76, 24, 70]]) {
        canvas.drawLine(p(c[0].toDouble(), c[1].toDouble()), p(c[0].toDouble(), 30), strokeP(const Color(0xFF6E8FD8), 0.9, opacity: 0.8));
        canvas.drawLine(p(c[0].toDouble(), c[1].toDouble()), p(c[2].toDouble(), c[1].toDouble()), strokeP(const Color(0xFF6E8FD8), 0.9, opacity: 0.8));
      }
      break;

    // ===================================================== family: steam ===
    case 'f_steam':
      ring(25, const Color(0xFF7A5A34), 1.1, opacity: 0.9);
      canvas.drawRect(Rect.fromLTWH(p(44, 20).dx, p(20, 20).dy, s(12), s(10)), strokeP(const Color(0xFFC99A3F), 0.9));
      canvas.drawRect(Rect.fromLTWH(p(44, 34).dx, p(34, 34).dy, s(12), s(10)), strokeP(const Color(0xFFC99A3F), 0.9));
      canvas.drawRect(Rect.fromLTWH(p(44, 48).dx, p(48, 48).dy, s(12), s(10)), strokeP(const Color(0xFFC99A3F), 0.9));
      canvas.drawPath(
          (Path()..moveTo(p(32, 42).dx, p(32, 42).dy)..cubicTo(p(24, 36).dx, p(24, 36).dy, p(24, 64).dx, p(24, 64).dy, p(32, 58).dx, p(32, 58).dy)),
          strokeP(const Color(0xFFC99A3F), 1.4, opacity: 0.85));
      canvas.drawCircle(p(72, 34), s(6), fill(const Color(0xFFE8A33D)));
      canvas.drawCircle(p(72, 34), s(6), strokeP(const Color(0xFF241A10), 0.8));
      canvas.drawLine(p(72, 34), p(72, 30), strokeP(const Color(0xFF241A10), 1, cap: StrokeCap.round));
      canvas.drawLine(p(72, 34), p(75, 36), strokeP(const Color(0xFF241A10), 1, cap: StrokeCap.round));
      canvas.drawLine(p(50, 62), p(50, 78), strokeP(const Color(0xFFE8A33D), 1.6));
      canvas.drawLine(p(50, 78), p(50, 82), strokeP(const Color(0xFFE8A33D), 1.6));
      canvas.drawLine(p(18, 50), p(36, 50), strokeP(const Color(0xFFE8A33D), 1.6));
      canvas.drawLine(p(64, 50), p(82, 50), strokeP(const Color(0xFFE8A33D), 1.6));
      canvas.drawCircle(p(50, 50), s(1.8), fill(const Color(0xFF241A10)));
      break;

    // ================================================== family: volcanic ===
    case 'f_volcanic':
      poly([p(36, 36), p(64, 36), p(66, 46), p(60, 50), p(40, 50), p(34, 46)],
          strokeP(const Color(0xFFFF6A2B), 1.1, opacity: 0.9));
      canvas.drawLine(p(50, 18), p(50, 36), strokeP(const Color(0xFFFF6A2B), 1.7));
      canvas.drawLine(p(50, 50), p(50, 68), strokeP(const Color(0xFFFF6A2B), 1.7));
      canvas.drawLine(p(50, 68), p(50, 82), strokeP(const Color(0xFFFF6A2B), 1.7));
      canvas.drawLine(p(18, 50), p(38, 50), strokeP(const Color(0xFFFF6A2B), 1.7));
      canvas.drawLine(p(62, 50), p(82, 50), strokeP(const Color(0xFFFF6A2B), 1.7));
      canvas.drawLine(p(42, 46), p(48, 38), strokeP(const Color(0xFFFF6A2B), 1.6, opacity: 0.85, cap: StrokeCap.round));
      canvas.drawLine(p(58, 46), p(52, 38), strokeP(const Color(0xFFFF6A2B), 1.2, opacity: 0.65, cap: StrokeCap.round));
      canvas.drawCircle(p(30, 34), s(1), fill(const Color(0xFFFF6A2B), opacity: 0.9));
      canvas.drawCircle(p(70, 34), s(1.2), fill(const Color(0xFFFFD54A), opacity: 0.9));
      canvas.drawCircle(p(30, 66), s(1), fill(const Color(0xFFFF6A2B), opacity: 0.7));
      canvas.drawCircle(p(70, 66), s(0.9), fill(const Color(0xFFFF6A2B), opacity: 0.6));
      canvas.drawCircle(p(50, 50), s(3.5), fill(const Color(0xFFFF6A2B)));
      canvas.drawCircle(p(50, 50), s(3.5), strokeP(const Color(0xFF12100F), 0.7));
      canvas.drawCircle(p(50, 50), s(1.6), fill(const Color(0xFFFFF0C8)));
      ring(24, const Color(0xFF3A3438), 0.8, opacity: 0.4);
      break;

    default:
      _paintReticle(canvas, size, 'mk1');
  }
}
