import 'dart:math';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/game_models.dart';
import '../services/storage_service.dart';
import 'ship_painter.dart';

/// A transient cell effect (explosion / splash).
class CellFx {
  final ShotResult result;
  final DateTime start;
  CellFx(this.result) : start = DateTime.now();

  double get progress =>
      (DateTime.now().difference(start).inMilliseconds / 800).clamp(0.0, 1.0);
  bool get done => progress >= 1.0;
}

/// Lightweight event descriptor (avoids importing the controller here).
class CombatEventLike {
  final int row;
  final int col;
  final ShotResult result;
  const CombatEventLike(this.row, this.col, this.result);
}

/// Flat-cartoon 10×10 grid in the reference style: chunky rounded blue
/// cells, white crosshair targeting cursor, big bold ✕ for misses and
/// red blast for hits. Ships (when provided) render on top.
class BattleGrid extends StatefulWidget {
  final List<List<int>> shots; // 0 unknown, 1 miss, 2 hit
  final List<PlacedShip>? ships;
  final ShipSkin? skin;
  final void Function(int r, int c)? onTapCell;
  final List<CombatEventLike> recentEvents;
  final bool enabled;
  final Color glowColor;

  /// Aiming crosshair cell (targeting grid).
  final List<int>? crosshair;

  /// Placement-mode ghost preview.
  final PlacedShip? previewShip;
  final bool previewValid;

  /// Placement-mode interactions.
  final void Function(ShipKind kind, int newRow, int newCol)? onShipDragEnd;
  final void Function(ShipKind kind)? onShipTap;

  const BattleGrid({
    super.key,
    required this.shots,
    this.ships,
    this.skin,
    this.onTapCell,
    this.recentEvents = const [],
    this.enabled = true,
    this.glowColor = AppColors.water,
    this.crosshair,
    this.previewShip,
    this.previewValid = true,
    this.onShipDragEnd,
    this.onShipTap,
  });

  @override
  State<BattleGrid> createState() => _BattleGridState();
}

class _BattleGridState extends State<BattleGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fxCtrl;
  final Map<String, CellFx> _fx = {};

  // Drag state (placement)
  ShipKind? _dragKind;
  Offset _dragPos = Offset.zero;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _fxCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
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
                onTapUp: _onTap(cell),
                onPanStart: _onPanStart(cell),
                onPanUpdate: _onPanUpdate(cell),
                onPanEnd: _onPanEnd(cell),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.outline, width: 3.5),
                    color: AppColors.waterDark,
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x55000000),
                        offset: Offset(0, 4),
                        blurRadius: 0,
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      CustomPaint(
                        size: Size.square(size),
                        painter: _GridPainter(
                          shots: widget.shots,
                          fx: _fx,
                          crosshair: widget.crosshair,
                          preview: widget.previewShip,
                          previewValid: widget.previewValid,
                          gridColor: widget.glowColor,
                        ),
                      ),
                      if (widget.ships != null && widget.skin != null)
                        ..._shipWidgets(cell),
                      if (_dragging && _dragKind != null) _dragGhost(cell),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void Function(TapUpDetails)? _onTap(double cell) {
    if (!widget.enabled) return null;
    return (d) {
      final c = (d.localPosition.dx / cell).floor();
      final r = (d.localPosition.dy / cell).floor();
      if (r < 0 || r >= kBoardSize || c < 0 || c >= kBoardSize) return;
      // In placement mode, tapping a ship rotates it.
      if (widget.onShipTap != null && widget.ships != null) {
        for (final s in widget.ships!) {
          if (s.cells.any((cellPos) => cellPos[0] == r && cellPos[1] == c)) {
            widget.onShipTap!(s.spec.kind);
            return;
          }
        }
      }
      widget.onTapCell?.call(r, c);
    };
  }

  void Function(DragStartDetails)? _onPanStart(double cell) {
    if (!widget.enabled || widget.onShipDragEnd == null || widget.ships == null) {
      return null;
    }
    return (d) {
      final c = (d.localPosition.dx / cell).floor();
      final r = (d.localPosition.dy / cell).floor();
      for (final s in widget.ships!) {
        if (s.cells.any((cp) => cp[0] == r && cp[1] == c)) {
          setState(() {
            _dragKind = s.spec.kind;
            _dragging = true;
            _dragPos = d.localPosition;
          });
          return;
        }
      }
    };
  }

  void Function(DragUpdateDetails)? _onPanUpdate(double cell) {
    if (widget.onShipDragEnd == null) return null;
    return (d) {
      if (_dragging) setState(() => _dragPos = d.localPosition);
    };
  }

  void Function(DragEndDetails)? _onPanEnd(double cell) {
    if (widget.onShipDragEnd == null) return null;
    return (d) {
      if (_dragging && _dragKind != null) {
        final c = (_dragPos.dx / cell).floor().clamp(0, kBoardSize - 1);
        final r = (_dragPos.dy / cell).floor().clamp(0, kBoardSize - 1);
        widget.onShipDragEnd!(_dragKind!, r, c);
      }
      setState(() {
        _dragging = false;
        _dragKind = null;
      });
    };
  }

  List<Widget> _shipWidgets(double cell) {
    final ships = widget.ships!;
    return [
      for (final ship in ships)
        if (ship.spec.kind != _dragKind)
          Positioned(
            key: ValueKey(ship.spec.kind),
            left: ship.col * cell + 2,
            top: ship.row * cell + 2,
            width: ship.horizontal ? ship.spec.size * cell - 4 : cell - 4,
            height: ship.horizontal ? cell - 4 : ship.spec.size * cell - 4,
            child: _ShipWithRotate(
              ship: ship,
              skin: widget.skin!,
              cell: cell,
              t: _fxCtrl.value,
              showRotate: widget.onShipTap != null && !ship.isSunk,
            ),
          ),
    ];
  }

  Widget _dragGhost(double cell) {
    final spec = kFleet.firstWhere((s) => s.kind == _dragKind);
    final horizontal =
        widget.ships!.firstWhere((s) => s.spec.kind == _dragKind).horizontal;
    final w = horizontal ? spec.size * cell : cell;
    final h = horizontal ? cell : spec.size * cell;
    return Positioned(
      left: _dragPos.dx - w / 2,
      top: _dragPos.dy - h / 2,
      width: w,
      height: h,
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.75,
          child: horizontal
              ? CustomPaint(
                  painter: ShipPainter(spec: spec, skin: widget.skin!),
                )
              : RotatedBox(
                  quarterTurns: 1,
                  child: CustomPaint(
                    painter: ShipPainter(spec: spec, skin: widget.skin!),
                  ),
                ),
        ),
      ),
    );
  }
}

/// A ship drawn on the grid, with cartoon rotate arrows beneath it
/// (placement mode only).
class _ShipWithRotate extends StatelessWidget {
  final PlacedShip ship;
  final ShipSkin skin;
  final double cell;
  final double t;
  final bool showRotate;

  const _ShipWithRotate({
    required this.ship,
    required this.skin,
    required this.cell,
    required this.t,
    required this.showRotate,
  });

  @override
  Widget build(BuildContext context) {
    final painter = ShipPainter(
      spec: ship.spec,
      skin: skin,
      wavePhase: t,
      sunk: ship.isSunk,
      hitCount: ship.hitIndices.length,
    );
    final body = ship.horizontal
        ? CustomPaint(painter: painter)
        : RotatedBox(quarterTurns: 1, child: CustomPaint(painter: painter));

    if (!showRotate) return body;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: body),
        // Rotate arrows hugging the ship (like the reference UI)
        Positioned(
          left: -cell * 0.22,
          top: ship.horizontal ? -cell * 0.22 : cell,
          child: const _RotateArrow(Icons.rotate_left),
        ),
        Positioned(
          right: -cell * 0.22,
          bottom: ship.horizontal ? -cell * 0.22 : cell,
          child: const _RotateArrow(Icons.rotate_right),
        ),
      ],
    );
  }
}

class _RotateArrow extends StatelessWidget {
  final IconData icon;
  const _RotateArrow(this.icon);

  @override
  Widget build(BuildContext context) {
    return Icon(
      icon,
      size: 26,
      color: AppColors.outline,
      shadows: const [Shadow(color: Colors.white, blurRadius: 2)],
    );
  }
}

class _GridPainter extends CustomPainter {
  final List<List<int>> shots;
  final Map<String, CellFx> fx;
  final List<int>? crosshair;
  final PlacedShip? preview;
  final bool previewValid;
  final Color gridColor;

  _GridPainter({
    required this.shots,
    required this.fx,
    this.crosshair,
    this.preview,
    this.previewValid = true,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / kBoardSize;

    // ---- Chunky rounded water cells ----
    final cellPaint = Paint()..color = gridColor;
    final cellStroke = Paint()
      ..color = AppColors.cellBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    for (var r = 0; r < kBoardSize; r++) {
      for (var c = 0; c < kBoardSize; c++) {
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
              c * cell + 1.6, r * cell + 1.6, cell - 3.2, cell - 3.2),
          Radius.circular(cell * 0.14),
        );
        canvas.drawRRect(rect, cellPaint);
        canvas.drawRRect(rect, cellStroke);
      }
    }

    // ---- Placement ghost ----
    if (preview != null) {
      final p = Paint()
        ..color = (previewValid ? AppColors.green : AppColors.hit)
            .withValues(alpha: 0.45);
      for (final cp in preview!.cells) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(cp[1] * cell + 2, cp[0] * cell + 2, cell - 4, cell - 4),
            Radius.circular(cell * 0.14),
          ),
          p,
        );
      }
    }

    // ---- Shot markers ----
    for (var r = 0; r < kBoardSize; r++) {
      for (var c = 0; c < kBoardSize; c++) {
        final v = shots[r][c];
        if (v == 0) continue;
        final center = Offset(c * cell + cell / 2, r * cell + cell / 2);
        if (v == 2) {
          _drawHit(canvas, center, cell);
        } else {
          _drawMiss(canvas, center, cell);
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
      if (effect.result == ShotResult.hit || effect.result == ShotResult.sunk) {
        _drawExplosion(canvas, center, cell, prog,
            big: effect.result == ShotResult.sunk);
      } else if (effect.result == ShotResult.miss) {
        _drawSplash(canvas, center, cell, prog);
      }
    });

    // ---- Crosshair cursor ----
    if (crosshair != null) {
      final center = Offset(
          crosshair![1] * cell + cell / 2, crosshair![0] * cell + cell / 2);
      _drawCrosshair(canvas, center, cell);
    }
  }

  void _drawMiss(Canvas canvas, Offset center, double cell) {
    final s = cell * 0.26;
    // White halo then bold navy X (reference style)
    final halo = Paint()
      ..color = Colors.white.withValues(alpha: 0.65)
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    final mark = Paint()
      ..color = AppColors.navy
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    for (final p in [halo, mark]) {
      canvas.drawLine(center - Offset(s, s), center + Offset(s, s), p);
      canvas.drawLine(center + Offset(-s, s), center + Offset(s, -s), p);
    }
  }

  void _drawHit(Canvas canvas, Offset center, double cell) {
    final s = cell * 0.30;
    // Red blast circle + dark core + white X
    canvas.drawCircle(center, s * 1.15, Paint()..color = AppColors.hit);
    canvas.drawCircle(center, s * 0.7, Paint()..color = AppColors.hitGlow);
    canvas.drawCircle(center, s * 0.42, Paint()..color = AppColors.outline);
    final cross = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final d = s * 0.24;
    canvas.drawLine(center - Offset(d, d), center + Offset(d, d), cross);
    canvas.drawLine(center + Offset(-d, d), center + Offset(d, -d), cross);
  }

  void _drawExplosion(Canvas canvas, Offset center, double cell, double t,
      {bool big = false}) {
    final rng = Random(center.dx.toInt() * 31 + center.dy.toInt());
    final maxR = cell * (big ? 1.5 : 1.0) * (0.35 + t * 0.8);
    // Expanding ring
    canvas.drawCircle(
      center,
      maxR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5 * (1 - t)
        ..color = AppColors.hit.withValues(alpha: (1 - t) * 0.9),
    );
    // Flash core
    canvas.drawCircle(
      center,
      maxR * 0.55,
      Paint()
        ..color = Color.lerp(Colors.white, AppColors.gold, t)!
            .withValues(alpha: 1 - t * 0.85),
    );
    // Sparks
    final spark = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = AppColors.gold.withValues(alpha: 1 - t);
    for (var i = 0; i < (big ? 10 : 6); i++) {
      final ang = rng.nextDouble() * 2 * pi;
      final len = maxR * (0.5 + rng.nextDouble() * 0.7) * t;
      canvas.drawLine(
          center, center + Offset(cos(ang) * len, sin(ang) * len), spark);
    }
  }

  void _drawSplash(Canvas canvas, Offset center, double cell, double t) {
    final r = cell * 0.6 * (0.3 + t);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4 * (1 - t)
        ..color = Colors.white.withValues(alpha: (1 - t) * 0.95),
    );
    canvas.drawCircle(
      center,
      r * 0.55,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4 * (1 - t)
        ..color = AppColors.waterLight.withValues(alpha: (1 - t) * 0.9),
    );
  }

  void _drawCrosshair(Canvas canvas, Offset center, double cell) {
    final paint = Paint()
      ..color = AppColors.crosshair
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round;
    final ringR = cell * 0.30;
    paint.style = PaintingStyle.stroke;
    canvas.drawCircle(center, ringR, paint);
    final tick = cell * 0.16;
    final gap = cell * 0.08;
    final line = Paint()
      ..color = AppColors.crosshair
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center - Offset(ringR + gap + tick, 0),
        center - Offset(ringR + gap, 0), line);
    canvas.drawLine(center + Offset(ringR + gap + tick, 0),
        center + Offset(ringR + gap, 0), line);
    canvas.drawLine(center - Offset(0, ringR + gap + tick),
        center - Offset(0, ringR + gap), line);
    canvas.drawLine(center + Offset(0, ringR + gap + tick),
        center + Offset(0, ringR + gap), line);
    canvas.drawCircle(
        center, 2.6, Paint()..color = AppColors.crosshair);
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => true;
}
