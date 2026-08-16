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
/// cells, big bold ✕ for misses and red blast for hits. A quick tap
/// pulses a ripple at the tapped cell (no persistent aiming cursor is
/// needed — you just tap the grid to shoot). Ships (when provided) render
/// on top.
class BattleGrid extends StatefulWidget {
  final List<List<int>> shots; // 0 unknown, 1 miss, 2 hit
  final List<PlacedShip>? ships;
  final ShipSkin? skin;
  final void Function(int r, int c)? onTapCell;
  final List<CombatEventLike> recentEvents;
  final bool enabled;
  final Color glowColor;

  /// Ships that have been fully sunk and should be revealed on this grid
  /// in their destroyed form — shown regardless of [ships]/[skin], since a
  /// sunk ship's kind and position are common knowledge to both players.
  final List<PlacedShip> destroyedShips;

  /// Cell fill color (defaults to the video's steel blue).
  final Color cellColor;

  /// Placement-mode ghost preview.
  final PlacedShip? previewShip;
  final bool previewValid;

  /// Cell a cannonball is currently locked onto — drawn as a targeting
  /// reticle from the moment it's set until the shot actually lands (the
  /// caller clears it as soon as the ball impacts), so firing always
  /// shows exactly where the shot is headed until it hits the grid.
  final List<int>? aimCell;

  /// Placement-mode interactions.
  final void Function(ShipKind kind, int newRow, int newCol)? onShipDragEnd;
  final void Function(ShipKind kind)? onShipTap;

  /// Fired continuously while an already-placed ship is being dragged
  /// around the grid (before the drag ends), with the candidate cell the
  /// ship would land on if released right now. Lets the parent screen
  /// drive [previewShip]/[previewValid] so a highlight tracks the ship
  /// live under the player's finger, not just at drop time.
  final void Function(ShipKind kind, int row, int col)? onShipDragUpdate;

  const BattleGrid({
    super.key,
    required this.shots,
    this.ships,
    this.skin,
    this.onTapCell,
    this.recentEvents = const [],
    this.enabled = true,
    this.destroyedShips = const [],
    this.glowColor = AppColors.water,
    this.cellColor = AppColors.steelBlue,
    this.previewShip,
    this.previewValid = true,
    this.aimCell,
    this.onShipDragEnd,
    this.onShipTap,
    this.onShipDragUpdate,
  });

  @override
  State<BattleGrid> createState() => _BattleGridState();
}

class _BattleGridState extends State<BattleGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fxCtrl;
  final Map<String, CellFx> _fx = {};

  /// Instant tap-feedback ripples (cell → time tapped). Short-lived and
  /// self-clearing; this is what replaced the old persistent crosshair.
  final Map<String, DateTime> _tapFx = {};

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
    );
    // PERF: no continuous animation by default (ships no longer bob) — the
    // ticker only turns on for the ~1s a hit/miss/tap effect is actually
    // playing, and turns itself back off the moment nothing is animating.
    // Previously this ticker ran forever at 60fps and repainted the WHOLE
    // board (every past hit/miss mark) every single frame, which is why
    // the game visibly slowed down the more shots piled up on a grid.
    _fxCtrl.addListener(() {
      if (_fx.isEmpty && _tapFx.isEmpty) return;
      _fx.removeWhere((_, fx) => fx.done);
      _tapFx.removeWhere((_, started) =>
          DateTime.now().difference(started).inMilliseconds >= 260);
      if (_fx.isEmpty && _tapFx.isEmpty && _fxCtrl.isAnimating) {
        _fxCtrl.stop();
      }
    });
  }

  void _ensureTickerRunning() {
    if (!_fxCtrl.isAnimating) {
      _fxCtrl.repeat();
    }
  }

  @override
  void didUpdateWidget(BattleGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    var addedNew = false;
    for (final e in widget.recentEvents) {
      final key = '${e.row},${e.col}';
      if (!_fx.containsKey(key)) {
        _fx[key] = CellFx(e.result);
        addedNew = true;
      }
    }
    _fx.removeWhere((_, fx) => fx.done);
    if (addedNew) _ensureTickerRunning();
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
                          tapFx: _tapFx,
                          preview: widget.previewShip,
                          previewValid: widget.previewValid,
                          aimCell: widget.aimCell,
                          gridColor: widget.glowColor,
                          cellColor: widget.cellColor,
                        ),
                      ),
                      if (widget.destroyedShips.isNotEmpty)
                        ..._destroyedShipWidgets(cell),
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
      if (widget.onTapCell != null) _pulseTap(r, c);
      widget.onTapCell?.call(r, c);
    };
  }

  /// Instant ripple at the tapped cell — the tap IS the shot, so this is
  /// the only "targeting" feedback the grid needs (no persistent cursor).
  void _pulseTap(int r, int c) {
    final key = '$r,$c';
    _tapFx[key] = DateTime.now();
    _ensureTickerRunning();
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
      if (!_dragging) return;
      setState(() => _dragPos = d.localPosition);
      final kind = _dragKind;
      if (kind != null && widget.onShipDragUpdate != null) {
        final c = (_dragPos.dx / cell).floor().clamp(0, kBoardSize - 1);
        final r = (_dragPos.dy / cell).floor().clamp(0, kBoardSize - 1);
        widget.onShipDragUpdate!(kind, r, c);
      }
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
            left: ship.col * cell + 1,
            top: ship.row * cell + 1,
            width: ship.horizontal ? ship.spec.size * cell - 2 : cell - 2,
            height: ship.horizontal ? cell - 2 : ship.spec.size * cell - 2,
            child: _ShipWithRotate(
              ship: ship,
              skin: widget.skin!,
              cell: cell,
              // Fixed neutral phase: ships are static now (no bobbing).
              t: 0.5,
              showRotate: widget.onShipTap != null && !ship.isSunk,
            ),
          ),
    ];
  }

  /// Reveals a fully-sunk ship on the grid in its destroyed form. Rendered
  /// independently of [_shipWidgets] so it also appears on the "empty"
  /// battle grids (where [ships] is null and only hit/miss markers would
  /// otherwise show).
  List<Widget> _destroyedShipWidgets(double cell) {
    return [
      for (final ship in widget.destroyedShips)
        Positioned(
          key: ValueKey('wreck-${ship.spec.kind}-${ship.row}-${ship.col}'),
          left: ship.col * cell + 1,
          top: ship.row * cell + 1,
          width: ship.horizontal ? ship.spec.size * cell - 2 : cell - 2,
          height: ship.horizontal ? cell - 2 : ship.spec.size * cell - 2,
          child: IgnorePointer(
            child: ship.horizontal
                ? CustomPaint(
                    painter: ShipPainter(
                      spec: ship.spec,
                      skin: wreckSkin,
                      sunk: true,
                      hitCount: ship.spec.size,
                    ),
                  )
                : RotatedBox(
                    quarterTurns: 1,
                    child: CustomPaint(
                      painter: ShipPainter(
                        spec: ship.spec,
                        skin: wreckSkin,
                        sunk: true,
                        hitCount: ship.spec.size,
                      ),
                    ),
                  ),
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
  final Map<String, DateTime> tapFx;
  final PlacedShip? preview;
  final bool previewValid;
  final List<int>? aimCell;
  final Color gridColor;
  final Color cellColor;

  _GridPainter({
    required this.shots,
    required this.fx,
    this.tapFx = const {},
    this.preview,
    this.previewValid = true,
    this.aimCell,
    required this.gridColor,
    this.cellColor = AppColors.steelBlue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / kBoardSize;

    // ---- Flat steel-blue cells with thin lighter grid lines (video style) ----
    canvas.drawRect(Offset.zero & size, Paint()..color = cellColor);
    final linePaint = Paint()
      ..color = AppColors.steelBlueLight.withValues(alpha: 0.55)
      ..strokeWidth = 1.1;
    for (var i = 1; i < kBoardSize; i++) {
      canvas.drawLine(
          Offset(i * cell, 0), Offset(i * cell, size.height), linePaint);
      canvas.drawLine(
          Offset(0, i * cell), Offset(size.width, i * cell), linePaint);
    }

    // ---- Placement highlight: shows exactly which cells a ship will
    // occupy before it's dropped (drag-from-dock or repositioning an
    // already-placed ship) — a filled tint plus a crisp outline so it
    // reads clearly as "landing here", not just a faint tint. ----
    if (preview != null) {
      final highlight = previewValid ? AppColors.green : AppColors.hit;
      final fill = Paint()..color = highlight.withValues(alpha: 0.50);
      final outline = Paint()
        ..color = highlight.withValues(alpha: 0.95)
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.06;
      for (final cp in preview!.cells) {
        final rrect = RRect.fromRectAndRadius(
          Rect.fromLTWH(cp[1] * cell + 2, cp[0] * cell + 2, cell - 4, cell - 4),
          Radius.circular(cell * 0.14),
        );
        canvas.drawRRect(rrect, fill);
        canvas.drawRRect(rrect, outline);
      }
    }

    // ---- Shot markers (video style) ----
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

    // ---- Instant tap ripple: a quick "yes, that tap registered" pulse
    // right where the finger landed. ----
    final now = DateTime.now();
    tapFx.forEach((key, started) {
      final t = now.difference(started).inMilliseconds / 260;
      if (t >= 1.0) return;
      final parts = key.split(',');
      final r = int.parse(parts[0]);
      final c = int.parse(parts[1]);
      final center = Offset(c * cell + cell / 2, r * cell + cell / 2);
      _drawTapRipple(canvas, center, cell, t.clamp(0.0, 1.0));
    });

    // ---- Firing crosshair: locks onto the targeted cell the instant a
    // shot is fired and stays put — the caller clears [aimCell] the
    // moment the cannonball actually impacts, so the reticle disappears
    // exactly when the shot hits the grid instead of on a fixed timer. ----
    if (aimCell != null) {
      final r = aimCell![0];
      final c = aimCell![1];
      final center = Offset(c * cell + cell / 2, r * cell + cell / 2);
      _drawCrosshair(canvas, center, cell);
    }
  }

  /// Miss marker (video): slightly darker cell + tiny grey ✕.
  void _drawMiss(Canvas canvas, Offset center, double cell) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: cell * 0.92, height: cell * 0.92),
        Radius.circular(cell * 0.12),
      ),
      Paint()..color = AppColors.steelBlueDark,
    );
    final s = cell * 0.15;
    final mark = Paint()
      ..color = AppColors.cellGrey
      ..strokeWidth = cell * 0.085
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center - Offset(s, s), center + Offset(s, s), mark);
    canvas.drawLine(center + Offset(-s, s), center + Offset(s, -s), mark);
  }

  /// Hit marker (video): black square cell + small yellow diamond inside.
  void _drawHit(Canvas canvas, Offset center, double cell) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: cell * 0.92, height: cell * 0.92),
        Radius.circular(cell * 0.10),
      ),
      Paint()..color = AppColors.outline,
    );
    final d = cell * 0.20;
    final diamond = Path()
      ..moveTo(center.dx, center.dy - d)
      ..lineTo(center.dx + d, center.dy)
      ..lineTo(center.dx, center.dy + d)
      ..lineTo(center.dx - d, center.dy)
      ..close();
    canvas.drawPath(diamond, Paint()..color = AppColors.burst);
  }

  /// Impact flash (video): yellow starburst core + white sparkle stars
  /// flying outward; sinks into the persistent black-square marker.
  void _drawExplosion(Canvas canvas, Offset center, double cell, double t,
      {bool big = false}) {
    final rng = Random(center.dx.toInt() * 31 + center.dy.toInt());
    final scale = big ? 1.5 : 1.0;
    // Yellow starburst (8 rounded rays) — flashes in, then fades.
    final burstAlpha = (1 - t * 1.35).clamp(0.0, 1.0);
    if (burstAlpha > 0) {
      final grow = 0.45 + t * 0.75;
      final ray = Paint()
        ..color = AppColors.burst.withValues(alpha: burstAlpha)
        ..strokeWidth = cell * 0.16 * scale * (1 - t * 0.5)
        ..strokeCap = StrokeCap.round;
      final len = cell * 0.62 * scale * grow;
      for (var i = 0; i < 8; i++) {
        final ang = i * pi / 4;
        canvas.drawLine(center,
            center + Offset(cos(ang) * len, sin(ang) * len), ray);
      }
      canvas.drawCircle(
        center,
        cell * 0.34 * scale * grow,
        Paint()..color = AppColors.burst.withValues(alpha: burstAlpha),
      );
      canvas.drawCircle(
        center,
        cell * 0.20 * scale * grow,
        Paint()..color = Colors.white.withValues(alpha: burstAlpha),
      );
    }
    // White sparkle stars drifting outward.
    final sparkAlpha = (1 - t).clamp(0.0, 1.0);
    for (var i = 0; i < (big ? 8 : 5); i++) {
      final ang = rng.nextDouble() * 2 * pi;
      final dist = cell * scale * (0.25 + 0.75 * t) * (0.6 + rng.nextDouble() * 0.5);
      final p = center + Offset(cos(ang) * dist, sin(ang) * dist);
      final sr = cell * 0.11 * (1 - t * 0.6);
      final sp = Paint()
        ..color = Colors.white.withValues(alpha: sparkAlpha * 0.95);
      canvas.drawPath(
        Path()
          ..moveTo(p.dx, p.dy - sr)
          ..lineTo(p.dx + sr * 0.35, p.dy - sr * 0.35)
          ..lineTo(p.dx + sr, p.dy)
          ..lineTo(p.dx + sr * 0.35, p.dy + sr * 0.35)
          ..lineTo(p.dx, p.dy + sr)
          ..lineTo(p.dx - sr * 0.35, p.dy + sr * 0.35)
          ..lineTo(p.dx - sr, p.dy)
          ..lineTo(p.dx - sr * 0.35, p.dy - sr * 0.35)
          ..close(),
        sp,
      );
    }
  }

  /// Miss splash (video): quick white droplet burst, no big rings.
  void _drawSplash(Canvas canvas, Offset center, double cell, double t) {
    final rng = Random(center.dx.toInt() * 17 + center.dy.toInt());
    final alpha = (1 - t).clamp(0.0, 1.0);
    final dot = Paint()
      ..color = Colors.white.withValues(alpha: alpha * 0.9);
    for (var i = 0; i < 6; i++) {
      final ang = rng.nextDouble() * 2 * pi;
      final dist = cell * 0.5 * t * (0.5 + rng.nextDouble() * 0.6);
      final p = center + Offset(cos(ang) * dist, sin(ang) * dist);
      canvas.drawCircle(p, cell * 0.07 * (1 - t * 0.5), dot);
    }
  }

  /// Quick expanding-ring "tap registered" pulse — replaces the old
  /// persistent aiming crosshair. Fades out over ~260ms.
  void _drawTapRipple(Canvas canvas, Offset center, double cell, double t) {
    final alpha = (1 - t) * 0.85;
    final ringR = cell * (0.16 + 0.42 * Curves.easeOut.transform(t));
    canvas.drawCircle(
      center,
      ringR,
      Paint()
        ..color = Colors.white.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.09 * (1 - t * 0.5),
    );
    canvas.drawCircle(
      center,
      cell * 0.05,
      Paint()..color = Colors.white.withValues(alpha: alpha),
    );
  }

  /// Targeting reticle: a ring with four outward tick marks and a center
  /// dot, locked onto the cell a cannonball is currently flying toward.
  void _drawCrosshair(Canvas canvas, Offset center, double cell) {
    final ringPaint = Paint()
      ..color = AppColors.hit
      ..style = PaintingStyle.stroke
      ..strokeWidth = cell * 0.06;
    final tickPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = cell * 0.06
      ..strokeCap = StrokeCap.round;
    final ringR = cell * 0.30;
    canvas.drawCircle(center, ringR, ringPaint);
    const dirs = [Offset(0, -1), Offset(1, 0), Offset(0, 1), Offset(-1, 0)];
    final tickGap = cell * 0.08;
    final tickLen = cell * 0.16;
    for (final d in dirs) {
      final start = center + d * (ringR + tickGap);
      final end = center + d * (ringR + tickGap + tickLen);
      canvas.drawLine(start, end, tickPaint);
    }
    canvas.drawCircle(center, cell * 0.035, Paint()..color = AppColors.hit);
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) {
    // While anything transient is animating, its visual progress is driven
    // by wall-clock time (see CellFx.progress), not by field identity, so
    // we must keep repainting every tick.
    if (fx.isNotEmpty || tapFx.isNotEmpty) return true;
    // Otherwise only repaint when something that actually affects pixels
    // changed — this is what stops the board from being fully redrawn on
    // every 100ms game-cooldown tick once nothing is animating.
    return !identical(oldDelegate.shots, shots) ||
        oldDelegate.preview != preview ||
        oldDelegate.previewValid != previewValid ||
        oldDelegate.cellColor != cellColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.aimCell?[0] != aimCell?[0] ||
        oldDelegate.aimCell?[1] != aimCell?[1];
  }
}
