import 'dart:math';

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Flat coral "deck" background with subtle cartoon details:
/// faint tile grid and drifting wave squiggles. [child] sits on top.
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

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 10))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.coral,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          return CustomPaint(
            painter: _DeckPainter(_ctrl.value, widget.showSonar),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _DeckPainter extends CustomPainter {
  final double t;
  final bool showSonar;

  _DeckPainter(this.t, this.showSonar);

  @override
  void paint(Canvas canvas, Size size) {
    // Faint checker tiles (like the reference's coral grid floor)
    final tile = size.width / 9;
    final tilePaint = Paint()..color = AppColors.coralDeep.withValues(alpha: 0.20);
    for (var r = 0; r * tile < size.height; r++) {
      for (var c = 0; c * tile < size.width; c++) {
        if ((r + c) % 2 == 0) continue;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(c * tile + 3, r * tile + 3, tile - 6, tile - 6),
            const Radius.circular(8),
          ),
          tilePaint,
        );
      }
    }

    // Gentle drifting squiggle waves
    if (showSonar) {
      final wavePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = AppColors.coralLight.withValues(alpha: 0.55);
      for (var band = 0; band < 3; band++) {
        final yBase = size.height * (0.2 + band * 0.3);
        final phase = t * 2 * pi + band * 2.1;
        final path = Path();
        for (var x = 0.0; x <= size.width; x += 14) {
          final y = yBase + sin((x / size.width) * 2 * pi * 3 + phase) * 6;
          if (x == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        canvas.drawPath(path, wavePaint);
      }
    }
  }

  @override
  bool shouldRepaint(_DeckPainter oldDelegate) => true;
}
