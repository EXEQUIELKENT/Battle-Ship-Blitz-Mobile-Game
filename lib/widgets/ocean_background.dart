import 'dart:math';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'ambient_loop.dart';

/// Flat coral "deck" background with subtle cartoon details:
/// faint tile grid and drifting wave squiggles. [child] sits on top.
class OceanBackground extends StatefulWidget {
  final Widget child;
  final bool showSonar;

  const OceanBackground({super.key, required this.child, this.showSonar = true});

  @override
  State<OceanBackground> createState() => _OceanBackgroundState();
}

class _OceanBackgroundState extends State<OceanBackground> {
  // A ten-second drift, so a vsync-driven controller would be spending
  // frames on motion nobody can resolve — see [AmbientLoop].
  final _ctrl = AmbientLoop(period: const Duration(seconds: 10));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ctrl.enabled = TickerMode.valuesOf(context).enabled;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// PERF: this used to be one `CustomPaint` whose painter redrew the whole
  /// background every frame with `shouldRepaint => true`, with the entire
  /// screen's UI as its child. Two costs came out of that, on every screen
  /// in the app, for the whole time it was open:
  ///
  ///  * The tile grid was redrawn 60 times a second despite being
  ///    completely static — nothing in it depends on the clock. Only the
  ///    three wave squiggles actually move.
  ///  * Nothing separated the painter from the child, so they shared one
  ///    layer: repainting the background marked that layer dirty, and the
  ///    whole screen — every button, label and ship on top of it — was
  ///    re-rastered each frame to animate a squiggle.
  ///
  /// Splitting them into their own repaint boundaries lets the static grid
  /// raster once, the UI raster only when it actually changes, and just the
  /// thin wave layer redraw per frame. The picture on screen is identical.
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.coral,
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: const _TilePainter()),
            ),
          ),
          if (widget.showSonar)
            Positioned.fill(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _ctrl,
                  builder: (context, _) =>
                      CustomPaint(painter: _WavePainter(_ctrl.value)),
                ),
              ),
            ),
          // FEEDBACK ("scrolling the main menu is janky and everything
          // blurs"): this used to be wrapped in a `RepaintBoundary`. That
          // made the whole screen's content a cached raster layer, and a
          // cached layer redrawn at a fractional scroll offset is
          // RESAMPLED rather than repainted — which is the blur, on every
          // element at once, for as long as the list is moving. It cost
          // rather than saved, too: the content changes every frame while
          // scrolling, so the cache was re-rasterized each frame and never
          // reused. The two layers behind it keep their boundaries because
          // they genuinely are independent of this one.
          widget.child,
        ],
      ),
    );
  }
}

/// The faint checker tiles (the reference's coral grid floor). Static —
/// it only ever depends on the size it is given.
class _TilePainter extends CustomPainter {
  const _TilePainter();

  @override
  void paint(Canvas canvas, Size size) {
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
  }

  @override
  bool shouldRepaint(_TilePainter oldDelegate) => false;
}

/// The gentle drifting squiggles — the only part of the background that
/// actually moves.
class _WavePainter extends CustomPainter {
  final double t;

  const _WavePainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
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

  @override
  bool shouldRepaint(_WavePainter oldDelegate) => oldDelegate.t != t;
}
