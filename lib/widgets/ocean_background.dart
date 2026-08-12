import 'dart:math';

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Animated ocean background: gradient depths, drifting waves,
/// rising bubbles and occasional sonar pings.
class OceanBackground extends StatefulWidget {
  final Widget child;
  final bool showSonar;

  const OceanBackground({super.key, required this.child, this.showSonar = true});

  @override
  State<OceanBackground> createState() => _OceanBackgroundState();
}

class _OceanBackgroundState extends State<OceanBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  final List<_Bubble> _bubbles = [];
  final Random _rng = Random();

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 12))
      ..repeat();
    for (var i = 0; i < 18; i++) {
      _bubbles.add(_Bubble(_rng));
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: AppColors.oceanGradient,
        ),
      ),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          return CustomPaint(
            painter: _OceanPainter(_ctrl.value, _bubbles, widget.showSonar),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _Bubble {
  double x;
  double y;
  double r;
  double speed;

  _Bubble(Random rng)
      : x = rng.nextDouble(),
        y = rng.nextDouble(),
        r = 1 + rng.nextDouble() * 3,
        speed = 0.02 + rng.nextDouble() * 0.05;
}

class _OceanPainter extends CustomPainter {
  final double t;
  final List<_Bubble> bubbles;
  final bool showSonar;

  _OceanPainter(this.t, this.bubbles, this.showSonar);

  @override
  void paint(Canvas canvas, Size size) {
    // --- Drifting wave bands ---
    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (var band = 0; band < 4; band++) {
      final yBase = size.height * (0.18 + band * 0.22);
      final path = Path();
      final phase = t * 2 * pi + band * 1.3;
      for (var x = 0.0; x <= size.width; x += 8) {
        final y = yBase + sin((x / size.width) * 2 * pi * 2 + phase) * 7;
        if (x == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      wavePaint.color = AppColors.sonar.withValues(alpha: 0.05 + band * 0.015);
      canvas.drawPath(path, wavePaint);
    }

    // --- Rising bubbles ---
    final bubblePaint = Paint()..style = PaintingStyle.stroke;
    for (final b in bubbles) {
      final y = ((b.y - t * b.speed * 12) % 1.0 + 1.0) % 1.0;
      final pos = Offset(b.x * size.width, y * size.height);
      bubblePaint.color = AppColors.radar.withValues(alpha: 0.10);
      bubblePaint.strokeWidth = 1;
      canvas.drawCircle(pos, b.r, bubblePaint);
    }

    // --- Sonar ping rings from corners ---
    if (showSonar) {
      final centers = [
        Offset(size.width * 0.85, size.height * 0.12),
        Offset(size.width * 0.12, size.height * 0.82),
      ];
      for (var i = 0; i < centers.length; i++) {
        final cyc = (t * 2 + i * 0.5) % 1.0;
        final radius = cyc * size.width * 0.45;
        final alpha = (1 - cyc) * 0.14;
        final p = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = AppColors.sonar.withValues(alpha: alpha);
        canvas.drawCircle(centers[i], radius, p);
      }
    }

    // --- Vignette ---
    final vignette = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.45),
        ],
        stops: const [0.55, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), vignette);
  }

  @override
  bool shouldRepaint(_OceanPainter oldDelegate) => true;
}
