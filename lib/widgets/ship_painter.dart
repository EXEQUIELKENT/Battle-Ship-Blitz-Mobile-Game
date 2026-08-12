import 'dart:math';

import 'package:flutter/material.dart';

import '../models/game_models.dart';
import '../services/storage_service.dart';

/// Draws a cartoon-ish warship for a given ship spec, with a gentle
/// bobbing animation driven externally via [wavePhase].
class ShipPainter extends CustomPainter {
  final ShipSpec spec;
  final ShipSkin skin;
  final double wavePhase; // 0..1 looping
  final bool sunk;
  final int hitCount;

  ShipPainter({
    required this.spec,
    required this.skin,
    required this.wavePhase,
    this.sunk = false,
    this.hitCount = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    // Bob + slight roll
    final bob = sin(wavePhase * 2 * pi) * size.height * 0.05;
    final roll = sin(wavePhase * 2 * pi + 1) * 0.05;
    canvas.translate(size.width / 2, size.height / 2 + bob);
    canvas.rotate(sunk ? 0.5 : roll);
    canvas.translate(-size.width / 2, -size.height / 2);
    if (sunk) {
      canvas.translate(0, size.height * 0.25);
    }

    final hull = sunk ? skin.hull.withValues(alpha: 0.35) : skin.hull;
    final trim = sunk ? skin.trim.withValues(alpha: 0.35) : skin.trim;

    final w = size.width;
    final h = size.height;

    // ---- Hull ----
    final hullPath = Path()
      ..moveTo(w * 0.02, h * 0.55)
      ..lineTo(w * 0.12, h * 0.85)
      ..lineTo(w * 0.88, h * 0.85)
      ..lineTo(w * 0.98, h * 0.55)
      ..close();
    final hullPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [trim, hull, hull.withValues(alpha: 0.8)],
      ).createShader(Rect.fromLTWH(0, h * 0.5, w, h * 0.4));
    canvas.drawPath(hullPath, hullPaint);
    canvas.drawPath(
      hullPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.black.withValues(alpha: 0.5),
    );

    // ---- Deck structures per ship type ----
    final deckPaint = Paint()..color = hull.withValues(alpha: 0.95);
    final deckStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = trim;

    switch (spec.kind) {
      case ShipKind.carrier:
        // Flat flight deck + island tower
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(w * 0.06, h * 0.42, w * 0.88, h * 0.15),
              const Radius.circular(3)),
          Paint()..color = trim.withValues(alpha: 0.9),
        );
        canvas.drawRect(Rect.fromLTWH(w * 0.62, h * 0.18, w * 0.14, h * 0.26), deckPaint);
        canvas.drawRect(Rect.fromLTWH(w * 0.62, h * 0.18, w * 0.14, h * 0.26), deckStroke);
        // Runway stripes
        final stripe = Paint()
          ..color = Colors.white.withValues(alpha: 0.35)
          ..strokeWidth = 1.4;
        for (var i = 0; i < 4; i++) {
          final x = w * (0.14 + i * 0.14);
          canvas.drawLine(Offset(x, h * 0.46), Offset(x + w * 0.06, h * 0.46), stripe);
        }
        break;
      case ShipKind.battleship:
        // Two turrets + bridge tower
        _turret(canvas, w * 0.28, h * 0.42, w * 0.16, trim, hull);
        _turret(canvas, w * 0.62, h * 0.42, w * 0.16, trim, hull);
        canvas.drawRect(Rect.fromLTWH(w * 0.42, h * 0.20, w * 0.16, h * 0.24), deckPaint);
        canvas.drawRect(Rect.fromLTWH(w * 0.42, h * 0.20, w * 0.16, h * 0.24), deckStroke);
        break;
      case ShipKind.cruiser:
        _turret(canvas, w * 0.30, h * 0.44, w * 0.13, trim, hull);
        canvas.drawRect(Rect.fromLTWH(w * 0.48, h * 0.26, w * 0.13, h * 0.2), deckPaint);
        canvas.drawRect(Rect.fromLTWH(w * 0.48, h * 0.26, w * 0.13, h * 0.2), deckStroke);
        _mast(canvas, w * 0.68, h * 0.44, h * 0.24, trim);
        break;
      case ShipKind.submarine:
        // Sleek body + conning tower
        canvas.drawOval(Rect.fromLTWH(w * 0.04, h * 0.42, w * 0.92, h * 0.4), hullPaint);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(w * 0.42, h * 0.16, w * 0.16, h * 0.3),
              const Radius.circular(4)),
          deckPaint,
        );
        canvas.drawLine(Offset(w * 0.5, h * 0.16), Offset(w * 0.5, h * 0.04),
            Paint()..color = trim..strokeWidth = 2);
        break;
      case ShipKind.destroyer:
        _turret(canvas, w * 0.26, h * 0.46, w * 0.12, trim, hull);
        _mast(canvas, w * 0.5, h * 0.46, h * 0.3, trim);
        canvas.drawRect(Rect.fromLTWH(w * 0.60, h * 0.30, w * 0.12, h * 0.18), deckPaint);
        canvas.drawRect(Rect.fromLTWH(w * 0.60, h * 0.30, w * 0.12, h * 0.18), deckStroke);
        break;
    }

    // ---- Damage smoke / fire on hit sections ----
    if (hitCount > 0 && !sunk) {
      final rng = Random(spec.kind.index * 7 + 3);
      for (var i = 0; i < hitCount; i++) {
        final fx = w * (0.2 + rng.nextDouble() * 0.6);
        final fy = h * (0.4 + rng.nextDouble() * 0.2);
        final flicker = 0.5 + 0.5 * sin(wavePhase * 2 * pi * 2 + i * 1.7);
        final firePaint = Paint()
          ..color = Colors.orange.withValues(alpha: 0.55 + 0.35 * flicker)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
        canvas.drawCircle(Offset(fx, fy), h * (0.06 + 0.03 * flicker), firePaint);
      }
    }

    canvas.restore();

    // ---- Sunk overlay: skull-ish X ----
    if (sunk) {
      final p = Paint()
        ..color = Colors.red.withValues(alpha: 0.7)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(w * 0.2, h * 0.2), Offset(w * 0.8, h * 0.8), p);
      canvas.drawLine(Offset(w * 0.8, h * 0.2), Offset(w * 0.2, h * 0.8), p);
    }
  }

  void _turret(Canvas canvas, double x, double y, double s, Color trim, Color hull) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(x - s / 2, y - s / 3, s, s * 0.66),
          Radius.circular(s * 0.2)),
      Paint()..color = hull.withValues(alpha: 1),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(x - s / 2, y - s / 3, s, s * 0.66),
          Radius.circular(s * 0.2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = trim,
    );
    // Barrel
    canvas.drawLine(
      Offset(x, y),
      Offset(x + s * 0.9, y - s * 0.28),
      Paint()
        ..color = trim
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
  }

  void _mast(Canvas canvas, double x, double y, double hgt, Color trim) {
    canvas.drawLine(
      Offset(x, y),
      Offset(x, y - hgt),
      Paint()
        ..color = trim
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      Offset(x, y - hgt),
      2.4,
      Paint()..color = Colors.redAccent,
    );
  }

  @override
  bool shouldRepaint(ShipPainter oldDelegate) =>
      oldDelegate.wavePhase != wavePhase ||
      oldDelegate.sunk != sunk ||
      oldDelegate.hitCount != hitCount ||
      oldDelegate.skin.hull != skin.hull;
}

/// Standalone animated ship widget (used in customization & placement tray).
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
        final child = CustomPaint(painter: painter, size: Size(widget.size, widget.size * 0.55));
        if (!widget.vertical) return child;
        return RotatedBox(quarterTurns: 1, child: child);
      },
    );
  }
}
