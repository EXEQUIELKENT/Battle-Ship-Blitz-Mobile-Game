import 'dart:math';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/game_models.dart';
import '../services/storage_service.dart';
import 'ship_painter.dart';

/// A transient effect attached to a cell (explosion / splash / pulse).
class CellFx {
  final ShotResult result;
  final DateTime start;
  CellFx(this.result) : start = DateTime.now();

  double get progress =>
      (DateTime.now().difference(start).inMilliseconds / 900).clamp(0.0, 1.0);
  bool get done => progress >= 1.0;
}

/// The interactive 10x10 battle grid.
class BattleGrid extends StatefulWidget {
  /// Shot-tracking grid: 0 unknown, 1 miss, 2 hit.
  final List<List<int>> shots;

  /// Ships to display (only on own/fleet view).
  final List<PlacedShip>? ships;
  final ShipSkin? skin;

  final void Function(int r, int c)? onTapCell;
  final List<CombatEventLike> recentEvents;
  final bool enabled;
  final bool compact;
  final Color glowColor;
  final void Function(int r, int c, bool hover)? onHoverCell;
  final List<int>? hoverCell;
  final PlacedShip? previewShip; // placement ghost
  final bool previewValid;

  const BattleGrid({
    super.key,
    required this.shots,
    this.ships,
    this.skin,
    this.onTapCell,
    this.recentEvents = const [],
    this.enabled = true,
    this.compact = false,
    this.glowColor = AppColors.sonar,
    this.onHoverCell,
    this.hoverCell,
    this.previewShip,
    this.previewValid = true,
  });

  @override
  State<BattleGrid> createState() => _BattleGridState();
}

/// Lightweight event descriptor to avoid importing the controller here.
class CombatEventLike {
  final int row;
  final int col;
  final ShotResult result;
  const CombatEventLike(this.row, this.col, this.result);
}

class _BattleGridState extends State<BattleGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fxCtrl;
  final Map<String, CellFx> _fx = {};

  @override
  void initState() {
    super.initState();
    _fxCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void didUpdateWidget(BattleGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final e in widget.recentEvents) {
      final key = '${e.row},${e.col}';
      if (!_fx.containsKey(key)) {
        _fx[key] = CellFx(e.result);
      }
    }
    _fx.removeWhere((_, fx) => fx.done);
  }

  @override
  void dispose() {
    _fxCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.maxWidth;
          final cell = size / kBoardSize;
          return AnimatedBuilder(
            animation: _fxCtrl,
            builder: (context, _) {
              return GestureDetector(
                onTapUp: widget.enabled && widget.onTapCell != null
                    ? (d) {
                        final c = (d.localPosition.dx / cell).floor();
                        final r = (d.localPosition.dy / cell).floor();
                        if (r >= 0 && r < kBoardSize && c >= 0 && c < kBoardSize) {
                          widget.onTapCell!(r, c);
                        }
                      }
                    : null,
                onPanUpdate: widget.onHoverCell != null
                    ? (d) {
                        final c = (d.localPosition.dx / cell).floor();
                        final r = (d.localPosition.dy / cell).floor();
                        if (r >= 0 && r < kBoardSize && c >= 0 && c < kBoardSize) {
                          widget.onHoverCell!(r, c, true);
                        }
                      }
                    : null,
                onPanEnd: widget.onHoverCell != null
                    ? (_) => widget.onHoverCell!(0, 0, false)
                    : null,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: widget.glowColor.withValues(alpha: 0.8),
                      width: 1.6,
                    ),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF0B3A57), Color(0xFF051C2E)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: widget.glowColor.withValues(alpha: 0.25),
                        blurRadius: 18,
                        spreadRadius: -4,
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: CustomPaint(
                    painter: _GridPainter(
                      shots: widget.shots,
                      fx: _fx,
                      fxT: _fxCtrl.value,
                      glow: widget.glowColor,
                      hover: widget.hoverCell,
                      preview: widget.previewShip,
                      previewValid: widget.previewValid,
                    ),
                    child: widget.ships != null && widget.skin != null
                        ? _ShipsOverlay(
                            ships: widget.ships!,
                            skin: widget.skin!,
                            cell: cell,
                            t: _fxCtrl.value,
                          )
                        : null,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ShipsOverlay extends StatelessWidget {
  final List<PlacedShip> ships;
  final ShipSkin skin;
  final double cell;
  final double t;

  const _ShipsOverlay({
    required this.ships,
    required this.skin,
    required this.cell,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (final ship in ships)
          Positioned(
            left: ship.col * cell + 1,
            top: ship.row * cell + 1,
            width: ship.horizontal ? ship.spec.size * cell - 2 : cell - 2,
            height: ship.horizontal ? cell - 2 : ship.spec.size * cell - 2,
            child: ship.horizontal
                ? CustomPaint(
                    painter: ShipPainter(
                      spec: ship.spec,
                      skin: skin,
                      wavePhase: t,
                      sunk: ship.isSunk,
                      hitCount: ship.hitIndices.length,
                    ),
                  )
                : RotatedBox(
                    quarterTurns: 1,
                    child: CustomPaint(
                      painter: ShipPainter(
                        spec: ship.spec,
                        skin: skin,
                        wavePhase: t,
                        sunk: ship.isSunk,
                        hitCount: ship.hitIndices.length,
                      ),
                    ),
                  ),
          ),
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  final List<List<int>> shots;
  final Map<String, CellFx> fx;
  final double fxT;
  final Color glow;
  final List<int>? hover;
  final PlacedShip? preview;
  final bool previewValid;

  _GridPainter({
    required this.shots,
    required this.fx,
    required this.fxT,
    required this.glow,
    this.hover,
    this.preview,
    this.previewValid = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / kBoardSize;

    // ---- Water shimmer ----
    final shimmer = Paint()..color = AppColors.radar.withValues(alpha: 0.03);
    for (var r = 0; r < kBoardSize; r++) {
      for (var c = 0; c < kBoardSize; c++) {
        if ((r + c) % 2 == 0) {
          canvas.drawRect(
            Rect.fromLTWH(c * cell, r * cell, cell, cell),
            shimmer,
          );
        }
      }
    }

    // ---- Grid lines ----
    final linePaint = Paint()
      ..color = glow.withValues(alpha: 0.28)
      ..strokeWidth = 1;
    for (var i = 0; i <= kBoardSize; i++) {
      canvas.drawLine(Offset(i * cell, 0), Offset(i * cell, size.height), linePaint);
      canvas.drawLine(Offset(0, i * cell), Offset(size.width, i * cell), linePaint);
    }

    // ---- Placement preview ghost ----
    if (preview != null) {
      final p = Paint()
        ..color = (previewValid ? AppColors.victory : AppColors.danger)
            .withValues(alpha: 0.35);
      for (final cellPos in preview!.cells) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
                cellPos[1] * cell + 2, cellPos[0] * cell + 2, cell - 4, cell - 4),
            const Radius.circular(4),
          ),
          p,
        );
      }
    }

    // ---- Hover highlight ----
    if (hover != null) {
      final p = Paint()
        ..color = glow.withValues(alpha: 0.18)
        ..style = PaintingStyle.fill;
      canvas.drawRect(
        Rect.fromLTWH(hover![1] * cell, hover![0] * cell, cell, cell),
        p,
      );
    }

    // ---- Shot markers ----
    for (var r = 0; r < kBoardSize; r++) {
      for (var c = 0; c < kBoardSize; c++) {
        final v = shots[r][c];
        if (v == 0) continue;
        final center = Offset(c * cell + cell / 2, r * cell + cell / 2);
        if (v == 2) {
          _drawHitMarker(canvas, center, cell);
        } else {
          _drawMissMarker(canvas, center, cell);
        }
      }
    }

    // ---- Transient effects ----
    fx.forEach((key, effect) {
      final parts = key.split(',');
      final r = int.parse(parts[0]);
      final c = int.parse(parts[1]);
      final center = Offset(c * cell + cell / 2, r * cell + cell / 2);
      final prog = effect.progress;
      switch (effect.result) {
        case ShotResult.hit:
        case ShotResult.sunk:
          _drawExplosion(canvas, center, cell, prog,
              big: effect.result == ShotResult.sunk);
          break;
        case ShotResult.miss:
          _drawSplash(canvas, center, cell, prog);
          break;
        default:
          break;
      }
    });
  }

  void _drawHitMarker(Canvas canvas, Offset center, double cell) {
    final s = cell * 0.3;
    final glowPaint = Paint()
      ..color = AppColors.hitRed.withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(center, s * 1.25, glowPaint);
    final core = Paint()..color = AppColors.hitRed;
    canvas.drawCircle(center, s * 0.75, core);
    final ember = Paint()..color = AppColors.ember;
    canvas.drawCircle(center, s * 0.38, ember);
    final cross = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final d = s * 0.35;
    canvas.drawLine(center - Offset(d, d), center + Offset(d, d), cross);
    canvas.drawLine(center + Offset(-d, d), center + Offset(d, -d), cross);
  }

  void _drawMissMarker(Canvas canvas, Offset center, double cell) {
    final s = cell * 0.28;
    final p = Paint()
      ..color = AppColors.steel.withValues(alpha: 0.85)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center - Offset(s, s), center + Offset(s, s), p);
    canvas.drawLine(center + Offset(-s, s), center + Offset(s, -s), p);
    canvas.drawCircle(
      center,
      s * 1.3,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.fog.withValues(alpha: 0.4),
    );
  }

  void _drawExplosion(Canvas canvas, Offset center, double cell, double t,
      {bool big = false}) {
    final rng = Random(center.dx.toInt() * 31 + center.dy.toInt());
    final maxR = cell * (big ? 1.4 : 0.95) * (0.4 + t);
    // Shockwave ring
    canvas.drawCircle(
      center,
      maxR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * (1 - t)
        ..color = AppColors.fire.withValues(alpha: (1 - t) * 0.8),
    );
    // Core flash
    canvas.drawCircle(
      center,
      maxR * 0.55,
      Paint()
        ..color = Color.lerp(Colors.white, AppColors.fire, t)!
            .withValues(alpha: 1 - t * 0.85),
    );
    // Sparks
    final sparkPaint = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = AppColors.ember.withValues(alpha: 1 - t);
    for (var i = 0; i < (big ? 10 : 6); i++) {
      final ang = rng.nextDouble() * 2 * pi;
      final len = maxR * (0.5 + rng.nextDouble() * 0.7) * t;
      canvas.drawLine(
        center,
        center + Offset(cos(ang) * len, sin(ang) * len),
        sparkPaint,
      );
    }
  }

  void _drawSplash(Canvas canvas, Offset center, double cell, double t) {
    final r = cell * 0.55 * (0.3 + t);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4 * (1 - t)
        ..color = AppColors.radar.withValues(alpha: (1 - t) * 0.9),
    );
    canvas.drawCircle(
      center,
      r * 0.55,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * (1 - t)
        ..color = Colors.white.withValues(alpha: (1 - t) * 0.6),
    );
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => true;
}
