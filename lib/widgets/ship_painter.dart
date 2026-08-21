import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../art/family_ship_art.dart';
import '../art/fleet_family.dart';
import '../core/theme.dart';
import '../models/game_models.dart';
import '../services/storage_service.dart';

/// Charred "wreck" hull used to reveal a ship on the grid once it has
/// been fully sunk — deliberately drab/dark so a destroyed ship reads as
/// unmistakably different from a live one, regardless of either player's
/// equipped ship skin.
const ShipSkin wreckSkin =
    ShipSkin('wreck', 'Wreck', Color(0xFF3A4148), Color(0xFF262C32), 0);

/// Flat cartoon top-down ship painter with bold outlines,
/// matching the playful reference UI style.
class ShipPainter extends CustomPainter {
  final ShipSpec spec;
  final ShipSkin skin;
  final double wavePhase; // kept for API compatibility (gentle bob)
  final bool sunk;
  final int hitCount;

  /// Which specific local cell indices (0 = stern/first cell, size-1 =
  /// bow/last cell) have actually been hit. This is what a crater's
  /// on-screen position is driven by — NOT [hitCount] — so a hit on the
  /// third cell of a ship shows its damage on the third cell, rather than
  /// wherever the Nth crater happens to fall when counted from one end.
  ///
  /// When omitted, falls back to marking the first [hitCount] cells (0,
  /// 1, 2, ...) as hit, which is only correct when every hit ship cell is
  /// actually contiguous from index 0 — true for a fully-sunk/wrecked
  /// ship (every cell is hit) but NOT true in general for a live,
  /// partially-damaged ship. Callers that track per-cell damage (see
  /// `PlacedShip.hitIndices`) should always pass [hitIndices] explicitly.
  final Set<int> hitIndices;

  ShipPainter({
    required this.spec,
    required this.skin,
    this.wavePhase = 0,
    this.sunk = false,
    this.hitCount = 0,
    Set<int>? hitIndices,
  }) : hitIndices = hitIndices ?? (hitCount > 0
            ? Set<int>.from(List.generate(hitCount, (i) => i))
            : const <int>{});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // A thematic family brings its own five hull shapes, so it takes over
    // the whole drawing rather than tinting this one. Everything else
    // about a ship — its footprint, its damage state, the wreck it turns
    // into — is unchanged, which is why the switch is this narrow.
    final family = FleetFamilies.byKey(skin.familyKey);
    if (family != null && !sunk) {
      final bob = (wavePhase - 0.5) * h * 0.06;
      canvas.save();
      canvas.translate(0, bob);
      paintFamilyShip(canvas, size, family, spec.kind);
      canvas.restore();
      if (hitIndices.isNotEmpty) _familyDamage(canvas, w, h);
      return;
    }

    // Destroyed version: charred toward near-black instead of just faded,
    // so a sunk ship reads clearly as "wrecked" rather than a ghostly
    // washed-out copy of the live one.
    final hullColor = sunk
        ? Color.lerp(skin.hull, const Color(0xFF14181C), 0.72)!
        : skin.hull;
    final trimColor = sunk
        ? Color.lerp(skin.trim, const Color(0xFF14181C), 0.72)!
        : skin.trim;
    final outlinePaint = Paint()
      ..color = AppColors.outline.withValues(alpha: sunk ? 0.85 : 1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round;
    final fillPaint = Paint()..color = hullColor;
    final detailPaint = Paint()
      ..color = trimColor
      ..style = PaintingStyle.fill;
    final detailStroke = Paint()
      ..color = AppColors.outline.withValues(alpha: sunk ? 0.85 : 1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Gentle bob (tiny, keeps the flat look clean)
    final bob = sunk ? 0.0 : (wavePhase - 0.5) * h * 0.06;
    canvas.save();
    canvas.translate(0, bob);

    switch (spec.kind) {
      case ShipKind.carrier:
        _carrier(canvas, w, h, fillPaint, detailPaint, outlinePaint, detailStroke);
        break;
      case ShipKind.battleship:
        _battleship(canvas, w, h, fillPaint, detailPaint, outlinePaint, detailStroke);
        break;
      case ShipKind.cruiser:
        _cruiser(canvas, w, h, fillPaint, detailPaint, outlinePaint, detailStroke);
        break;
      case ShipKind.submarine:
        _submarine(canvas, w, h, fillPaint, detailPaint, outlinePaint, detailStroke);
        break;
      case ShipKind.destroyer:
        _destroyer(canvas, w, h, fillPaint, detailPaint, outlinePaint, detailStroke);
        break;
    }

    // Hit damage marks: little dark X craters, one per actually-hit cell,
    // positioned at THAT cell's spot along the hull rather than counted
    // in from the bow.
    if (hitIndices.isNotEmpty) {
      final crater = Paint()
        ..color = AppColors.outline.withValues(alpha: 0.85)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      for (final i in hitIndices) {
        if (i < 0 || i >= spec.size) continue;
        final cx = w * (0.18 + 0.64 * (i / math.max(1, spec.size - 1)));
        final cy = h * 0.5 + (i.isOdd ? h * 0.12 : -h * 0.12);
        const d = 4.5;
        canvas.drawLine(Offset(cx - d, cy - d), Offset(cx + d, cy + d), crater);
        canvas.drawLine(Offset(cx - d, cy + d), Offset(cx + d, cy - d), crater);
      }
    }

    // Destroyed version: a few soft smoke wisps drifting off the wreck.
    // Seeded by ship kind so the puffs stay put (no per-frame flicker).
    if (sunk) {
      final smokeRng = math.Random(spec.kind.index * 97 + 11);
      final smoke = Paint()..color = Colors.white.withValues(alpha: 0.30);
      for (var i = 0; i < 3; i++) {
        final sx = w * (0.20 + 0.6 * smokeRng.nextDouble());
        final sy = h * (0.20 - i * 0.09);
        final sr = h * (0.13 - i * 0.02);
        canvas.drawCircle(Offset(sx, sy), sr, smoke);
      }
    }
    canvas.restore();
  }

  /// The same dark X craters the flat skins get.
  ///
  /// Damage is deliberately NOT themed: a player has to read "this hull
  /// has been hit" at a glance on an opponent's board, and making that
  /// signal depend on which fleet they happen to have bought would put a
  /// gameplay read behind a cosmetic. The ships change; the wounds don't.
  void _familyDamage(Canvas canvas, double w, double h) {
    final crater = Paint()
      ..color = AppColors.outline.withValues(alpha: 0.85)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (final i in hitIndices) {
      if (i < 0 || i >= spec.size) continue;
      final cx = w * (0.18 + 0.64 * (i / math.max(1, spec.size - 1)));
      final cy = h * 0.5 + (i.isOdd ? h * 0.12 : -h * 0.12);
      const d = 4.5;
      canvas.drawLine(Offset(cx - d, cy - d), Offset(cx + d, cy + d), crater);
      canvas.drawLine(Offset(cx - d, cy + d), Offset(cx + d, cy - d), crater);
    }
  }

  void _drawHull(Canvas canvas, double w, double h, Paint fill, Paint outline) {
    final path = Path()
      ..moveTo(w * 0.06, h * 0.24)
      ..quadraticBezierTo(w * 0.02, h * 0.5, w * 0.06, h * 0.76)
      ..lineTo(w * 0.78, h * 0.76)
      ..quadraticBezierTo(w * 0.95, h * 0.68, w * 0.99, h * 0.5) // bow tip
      ..quadraticBezierTo(w * 0.95, h * 0.32, w * 0.78, h * 0.24)
      ..close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, outline);
  }

  void _carrier(Canvas canvas, double w, double h, Paint fill, Paint detail,
      Paint outline, Paint detailStroke) {
    _drawHull(canvas, w, h, fill, outline);
    // Flat flight deck strip
    final deck = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.10, h * 0.34, w * 0.72, h * 0.32),
      Radius.circular(h * 0.12),
    );
    canvas.drawRRect(deck, detail);
    canvas.drawRRect(deck, detailStroke);
    // Deck dashes (runway)
    final dash = Paint()
      ..color = AppColors.outline.withValues(alpha: 0.8)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final y = h * (0.40 + i * 0.10);
      canvas.drawLine(Offset(w * 0.16, y), Offset(w * 0.30, y), dash);
    }
    // Tiny parked planes (triangles)
    final plane = Paint()..color = AppColors.outline.withValues(alpha: 0.85);
    for (var i = 0; i < 3; i++) {
      final x = w * (0.48 + i * 0.11);
      final p = Path()
        ..moveTo(x, h * 0.40)
        ..lineTo(x + w * 0.05, h * 0.50)
        ..lineTo(x, h * 0.60)
        ..close();
      canvas.drawPath(p, plane);
    }
  }

  void _battleship(Canvas canvas, double w, double h, Paint fill, Paint detail,
      Paint outline, Paint detailStroke) {
    _drawHull(canvas, w, h, fill, outline);
    // Deck inset
    final deck = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.12, h * 0.34, w * 0.66, h * 0.32),
      Radius.circular(h * 0.12),
    );
    canvas.drawRRect(deck, detail);
    canvas.drawRRect(deck, detailStroke);
    // Big round bow + stern gun turrets
    final turret = Paint()..color = AppColors.outline.withValues(alpha: 0.85);
    canvas.drawCircle(Offset(w * 0.74, h * 0.50), h * 0.11, turret);
    canvas.drawCircle(Offset(w * 0.18, h * 0.50), h * 0.11, turret);
    // Vent lines
    final vent = Paint()
      ..color = AppColors.outline.withValues(alpha: 0.7)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final y = h * (0.41 + i * 0.09);
      canvas.drawLine(Offset(w * 0.34, y), Offset(w * 0.56, y), vent);
    }
  }

  void _cruiser(Canvas canvas, double w, double h, Paint fill, Paint detail,
      Paint outline, Paint detailStroke) {
    _drawHull(canvas, w, h, fill, outline);
    final deck = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.14, h * 0.35, w * 0.60, h * 0.30),
      Radius.circular(h * 0.12),
    );
    canvas.drawRRect(deck, detail);
    canvas.drawRRect(deck, detailStroke);
    // Single stern turret + vents
    canvas.drawCircle(Offset(w * 0.22, h * 0.5), h * 0.10,
        Paint()..color = AppColors.outline.withValues(alpha: 0.85));
    final vent = Paint()
      ..color = AppColors.outline.withValues(alpha: 0.7)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final y = h * (0.42 + i * 0.08);
      canvas.drawLine(Offset(w * 0.38, y), Offset(w * 0.62, y), vent);
    }
  }

  void _submarine(Canvas canvas, double w, double h, Paint fill, Paint detail,
      Paint outline, Paint detailStroke) {
    // Long capsule body
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.05, h * 0.30, w * 0.90, h * 0.40),
      Radius.circular(h * 0.20),
    );
    canvas.drawRRect(body, fill);
    canvas.drawRRect(body, outline);
    // Conning tower bump
    final tower = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.42, h * 0.16, w * 0.20, h * 0.28),
      Radius.circular(h * 0.10),
    );
    canvas.drawRRect(tower, detail);
    canvas.drawRRect(tower, outline);
    // Portholes
    final port = Paint()..color = AppColors.outline.withValues(alpha: 0.85);
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
          Offset(w * (0.24 + i * 0.26), h * 0.50), h * 0.06, port);
    }
  }

  void _destroyer(Canvas canvas, double w, double h, Paint fill, Paint detail,
      Paint outline, Paint detailStroke) {
    _drawHull(canvas, w, h, fill, outline);
    final deck = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.16, h * 0.36, w * 0.56, h * 0.28),
      Radius.circular(h * 0.12),
    );
    canvas.drawRRect(deck, detail);
    canvas.drawRRect(deck, detailStroke);
    // Bow turret + twin vents
    canvas.drawCircle(Offset(w * 0.72, h * 0.5), h * 0.09,
        Paint()..color = AppColors.outline.withValues(alpha: 0.85));
    final vent = Paint()
      ..color = AppColors.outline.withValues(alpha: 0.7)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(w * 0.30, h * 0.44), Offset(w * 0.52, h * 0.44), vent);
    canvas.drawLine(Offset(w * 0.30, h * 0.56), Offset(w * 0.52, h * 0.56), vent);
  }

  @override
  bool shouldRepaint(ShipPainter oldDelegate) =>
      oldDelegate.wavePhase != wavePhase ||
      oldDelegate.sunk != sunk ||
      oldDelegate.hitCount != hitCount ||
      // Same hit COUNT can still mean a different cell was the one hit
      // (e.g. count stays 1 but the hit index changes) — compare the
      // actual set, not just its size, or a repaint gets skipped and the
      // crater stays stuck on the old cell.
      !_setEquals(oldDelegate.hitIndices, hitIndices) ||
      oldDelegate.skin.hull != skin.hull;

  static bool _setEquals(Set<int> a, Set<int> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }
}

/// Standalone flat ship widget (dock tray, customization previews, hero
/// art). Kept under its original name for API compatibility, but it no
/// longer bobs — it's a plain static render (see the "no ship animations"
/// pass) at a larger default size so ships read clearly at a glance.
class AnimatedShip extends StatelessWidget {
  final ShipSpec spec;
  final ShipSkin skin;
  final double size;
  final bool vertical;

  /// Explicit pixel dimensions. When provided (together with [height]),
  /// these are used instead of deriving both sides from [size] — lets a
  /// row of different ships share one constant "beam" (height) while
  /// [width] scales with [ShipSpec.size], so e.g. a 5-cell carrier icon
  /// reads clearly longer than a 2-cell destroyer icon, matching their
  /// relative footprint on the actual battle grid instead of every ship
  /// rendering inside the same fixed square.
  final double? width;
  final double? height;

  /// Renders the destroyed/wrecked version of this ship (charred hull,
  /// smoke wisps, hit-damage craters — see [ShipPainter]) instead of its
  /// normal live appearance. Used by the remaining-ships preview so a sunk
  /// ship gets an actual destroyed model rather than a generic "X" overlay.
  final bool sunk;

  /// Number of damage craters to draw (only visible once [sunk] is true,
  /// or on a still-live ship that's been partially hit).
  final int hitCount;

  const AnimatedShip({
    super.key,
    required this.spec,
    required this.skin,
    this.size = 150,
    this.vertical = false,
    this.width,
    this.height,
    this.sunk = false,
    this.hitCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    // wavePhase 0.5 is the painter's neutral/no-bob position.
    final painter = ShipPainter(
      spec: spec,
      skin: skin,
      wavePhase: 0.5,
      sunk: sunk,
      hitCount: hitCount,
    );
    final child = CustomPaint(
      painter: painter,
      size: Size(width ?? size, height ?? size * 0.55),
    );
    if (!vertical) return child;
    return RotatedBox(quarterTurns: 1, child: child);
  }
}
