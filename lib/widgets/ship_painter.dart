import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/game_models.dart';
import '../services/storage_service.dart';

/// Flat cartoon top-down ship painter with bold outlines,
/// matching the playful reference UI style.
class ShipPainter extends CustomPainter {
  final ShipSpec spec;
  final ShipSkin skin;
  final double wavePhase; // kept for API compatibility (gentle bob)
  final bool sunk;
  final int hitCount;

  ShipPainter({
    required this.spec,
    required this.skin,
    this.wavePhase = 0,
    this.sunk = false,
    this.hitCount = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final hullColor = sunk ? skin.hull.withValues(alpha: 0.45) : skin.hull;
    final trimColor = sunk ? skin.trim.withValues(alpha: 0.45) : skin.trim;
    final outlinePaint = Paint()
      ..color = AppColors.outline.withValues(alpha: sunk ? 0.5 : 1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round;
    final fillPaint = Paint()..color = hullColor;
    final detailPaint = Paint()
      ..color = trimColor
      ..style = PaintingStyle.fill;
    final detailStroke = Paint()
      ..color = AppColors.outline.withValues(alpha: sunk ? 0.5 : 1)
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

    // Hit damage marks: little dark X craters along the deck
    if (hitCount > 0) {
      final crater = Paint()
        ..color = AppColors.outline.withValues(alpha: 0.85)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < hitCount && i < spec.size; i++) {
        final cx = w * (0.18 + 0.64 * (i / math.max(1, spec.size - 1)));
        final cy = h * 0.5 + (i.isOdd ? h * 0.12 : -h * 0.12);
        const d = 4.5;
        canvas.drawLine(Offset(cx - d, cy - d), Offset(cx + d, cy + d), crater);
        canvas.drawLine(Offset(cx - d, cy + d), Offset(cx + d, cy - d), crater);
      }
    }
    canvas.restore();
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
      oldDelegate.skin.hull != skin.hull;
}

/// Standalone flat ship widget (dock tray, customization previews).
class AnimatedShip extends StatefulWidget {
  final ShipSpec spec;
  final ShipSkin skin;
  final double size;
  final bool vertical;

  const AnimatedShip({
    super.key,
    required this.spec,
    required this.skin,
    this.size = 120,
    this.vertical = false,
  });

  @override
  State<AnimatedShip> createState() => _AnimatedShipState();
}

class _AnimatedShipState extends State<AnimatedShip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final painter = ShipPainter(
          spec: widget.spec,
          skin: widget.skin,
          wavePhase: _ctrl.value,
        );
        final child = CustomPaint(
          painter: painter,
          size: Size(widget.size, widget.size * 0.55),
        );
        if (!widget.vertical) return child;
        return RotatedBox(quarterTurns: 1, child: child);
      },
    );
  }
}
