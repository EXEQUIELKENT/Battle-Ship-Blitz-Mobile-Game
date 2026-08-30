import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../art/fleet_family.dart';
import '../core/theme.dart';
import '../models/game_models.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import 'ship_painter.dart';

/// The main menu's hero "water dock": a redesigned home for the player's
/// flagship that turns what used to be a static plate into a small toy.
///
/// This widget only choreographs and decorates — it never redraws the
/// ship itself. [AnimatedShip]/[ShipPainter] are used completely
/// unmodified; everything here (the gradient water, the drifting foam,
/// the wake ripples, the bob/rock, the drag, the hull carousel) lives in
/// the plate around it.
///
///  - **Idle**: the hull bobs and gently rocks on a continuous sine wave,
///    like it's actually sitting on water.
///  - **Drag**: pressing and dragging the hull slides it anywhere inside
///    the dock — bounded so it can't ride up over the plate's border —
///    and the wake ripples follow it.
///  - **Tap**: tapping the hull (without dragging) cycles through the
///    five shipyard hull classes (carrier, battleship, cruiser,
///    submarine, destroyer) — always in [equippedSkin], the one skin the
///    player actually has equipped in the Shipyard. This never browses
///    other skins; it's a size/silhouette preview of the fleet they've
///    already chosen, not a shop window.
class HeroShipDock extends StatefulWidget {
  final ShipSkin equippedSkin;
  final double shipSize;
  final double height;

  const HeroShipDock({
    super.key,
    required this.equippedSkin,
    this.shipSize = 190,
    this.height = 160,
  });

  @override
  State<HeroShipDock> createState() => _HeroShipDockState();
}

class _HeroShipDockState extends State<HeroShipDock>
    with TickerProviderStateMixin {
  /// Drives the idle bob/rock, the foam drift and the wake ripples — one
  /// shared ticker so all three stay in phase instead of fighting.
  late final AnimationController _waveCtrl;

  /// A short, one-shot "pop" played whenever the previewed hull changes.
  late final AnimationController _swapCtrl;

  /// The shipyard's five hull classes, largest (carrier) first — the
  /// same fleet the Shipyard itself previews, always in [widget.
  /// equippedSkin].
  static const List<ShipSpec> _hulls = kFleet;
  int _hullIndex = 0;

  /// Offset the hull has been dragged from the dock's center, clamped to
  /// stay inside the plate every time it changes.
  Offset _drag = Offset.zero;
  Size _plateSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _swapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
  }

  @override
  void dispose() {
    _waveCtrl.dispose();
    _swapCtrl.dispose();
    super.dispose();
  }

  /// Every hull silhouette in [ShipPainter] is drawn as fractions of
  /// whatever width/height it's given, at a fixed ~1.8:1 aspect — so the
  /// only safe way to make the carrier read as visibly bigger than the
  /// destroyer is to scale width AND height together. Scaling width alone
  /// (while holding height constant) changes that aspect ratio per hull
  /// and warps the smaller ones into a squashed, stubby shape instead of
  /// a smaller boat.
  ///
  /// Scale runs from 0.62x (destroyer, the smallest hull) up to 1.0x
  /// (carrier, the largest) so every class stays clearly readable while
  /// still differing in size — matching their relative footprint on the
  /// actual battle grid without distorting any of them.
  double _hullScale(ShipSpec spec) {
    final cellSizes = _hulls.map((s) => s.size);
    final minCells = cellSizes.reduce(math.min);
    final maxCells = cellSizes.reduce(math.max);
    final t = maxCells == minCells
        ? 1.0
        : (spec.size - minCells) / (maxCells - minCells);
    return 0.62 + 0.38 * t;
  }

  double _hullWidth(ShipSpec spec) => widget.shipSize * _hullScale(spec);

  /// Whether [widget.equippedSkin] is one of the six themed families
  /// (pirate, naval, steam, arctic, volcanic, sci-fi) rather than one of
  /// the original nine flat-recolour "legacy" skins.
  bool get _isFamilySkin =>
      FleetFamilies.byKey(widget.equippedSkin.familyKey) != null;

  /// The legacy hulls in [ShipPainter] have no shared reference box —
  /// every silhouette (`_carrier`, `_battleship`, ...) is hand-drawn
  /// straight from whatever w/h fractions this widget hands it, which is
  /// exactly why [_hullScale]'s doc says every class MUST share one fixed
  /// aspect here: varying it per hull would warp those hand-tuned curves.
  ///
  /// The themed families are the opposite case. All five of a family's
  /// hulls are authored once in one shared 300×100 box and non-uniformly
  /// stretched to fill whatever box `paintFamilyShip`/`FamilyCanvas
  /// .stretch` is given — so a box with the wrong aspect doesn't just
  /// look "off-model", it visibly balloons circles/turrets into ellipses
  /// and reads as a bloated hull instead of a lean one. That's exactly
  /// what forcing every family hull through the legacy 1.8:1 box below
  /// caused here: a themed carrier or battleship (long, lean classes)
  /// got squashed into the same squat box as a themed destroyer.
  ///
  /// The Shipyard's own hull-class row already renders every themed hull
  /// correctly, sizing each one to `(9.5 * spec.size + 10)` wide by a
  /// fixed 22 tall — so a 5-cell carrier reads meaningfully longer,
  /// relative to its own beam, than a 2-cell destroyer. Reusing that
  /// same per-class aspect here keeps a themed hull exactly as long/lean
  /// on the hero dock as it already is on the Shipyard, instead of
  /// forcing it through a ratio it was never drawn for.
  double _familyAspect(ShipSpec spec) => (9.5 * spec.size + 10) / 22;

  double _hullHeight(ShipSpec spec) {
    final width = _hullWidth(spec);
    if (_isFamilySkin) return width / _familyAspect(spec);
    return width * 0.55;
  }

  void _cycleHull() {
    SoundService.instance.click();
    setState(() {
      _hullIndex = (_hullIndex + 1) % _hulls.length;
      // Fresh hull, fresh spot — also keeps a smaller hull (say, the
      // destroyer) from landing outside its own tighter drag bounds if
      // it inherits a big offset the carrier was just parked at.
      _drag = Offset.zero;
    });
    _swapCtrl.forward(from: 0);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_plateSize == Size.zero) return;
    // Keeps the hull's outline from ever riding up over the dock's own
    // border, on any edge.
    const inset = 16.0;
    final hull = _hulls[_hullIndex];
    final maxX =
        math.max(0.0, (_plateSize.width - _hullWidth(hull)) / 2 - inset);
    final maxY =
        math.max(0.0, (_plateSize.height - _hullHeight(hull)) / 2 - inset);
    setState(() {
      _drag = Offset(
        (_drag.dx + details.delta.dx).clamp(-maxX, maxX),
        (_drag.dy + details.delta.dy).clamp(-maxY, maxY),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final hull = _hulls[_hullIndex];

    return LayoutBuilder(
      builder: (context, constraints) {
        _plateSize = Size(constraints.maxWidth, widget.height);
        return Container(
          width: double.infinity,
          height: widget.height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.waterDark,
                AppColors.water,
                AppColors.waterLight,
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.outline, width: 3),
            boxShadow: const [
              BoxShadow(
                color: Color(0x55000000),
                offset: Offset(0, 4),
                blurRadius: 0,
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Drifting foam bands + wake ripples that trail wherever
              // the hull has been dragged. Purely decorative.
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _waveCtrl,
                  builder: (context, _) => CustomPaint(
                    painter: _HeroWaterPainter(_waveCtrl.value, _drag),
                  ),
                ),
              ),

              // ---- The ship: bobs on its own, follows a drag, and
              // cycles hull classes on tap. AnimatedShip/ShipPainter are
              // untouched — only this wrapper moves and resizes it.
              AnimatedBuilder(
                animation: Listenable.merge([_waveCtrl, _swapCtrl]),
                builder: (context, _) {
                  final bob = math.sin(_waveCtrl.value * 2 * math.pi) * 7;
                  final rock =
                      math.sin(_waveCtrl.value * 2 * math.pi + 0.7) * 0.04;
                  final pop =
                      1.0 + 0.12 * math.sin(_swapCtrl.value * math.pi);
                  return Transform.translate(
                    offset: Offset(_drag.dx, _drag.dy + bob),
                    child: Transform.rotate(
                      angle: rock,
                      child: Transform.scale(
                        scale: pop,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: _cycleHull,
                          onPanUpdate: _onPanUpdate,
                          child: AnimatedShip(
                            spec: hull,
                            skin: widget.equippedSkin,
                            width: _hullWidth(hull),
                            height: _hullHeight(hull),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Drifting foam bands (a wave-squiggle texture on the water itself) plus
/// concentric wake ripples centered under wherever the hull currently
/// sits. Both are driven by the same looping `t` the hull's bob uses, so
/// the whole plate reads as one continuous motion instead of several
/// independent animations.
class _HeroWaterPainter extends CustomPainter {
  final double t;
  final Offset shipOffset;

  _HeroWaterPainter(this.t, this.shipOffset);

  @override
  void paint(Canvas canvas, Size size) {
    // The plate's Container clips to the *outer* edge of its rounded
    // border, so foam bands drawn edge-to-edge (see the x loop below)
    // could cross right through the border's corner curve and sit on
    // top of its black outline. Clipping to a rect inset from the
    // border keeps every wave/ripple stroke clearly inside it instead.
    const inset = 8.0;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height).deflate(inset),
      Radius.circular(math.max(0, 20 - inset)),
    ));

    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (var band = 0; band < 4; band++) {
      final yBase = size.height * (0.12 + band * 0.24);
      final speed = 1.0 + band * 0.35;
      final phase = t * 2 * math.pi * speed + band * 1.7;
      final alpha = (0.30 - band * 0.045).clamp(0.05, 1.0);
      wavePaint.color = AppColors.cream.withValues(alpha: alpha);
      final path = Path();
      for (var x = -20.0; x <= size.width + 20; x += 10) {
        final y =
            yBase + math.sin((x / size.width) * 2 * math.pi * 2.4 + phase) * 5;
        if (x == -20) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, wavePaint);
    }

    final center = Offset(
      size.width / 2 + shipOffset.dx,
      size.height / 2 + shipOffset.dy + 16,
    );
    final ripplePaint = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.6;
    for (var i = 0; i < 3; i++) {
      final ringT = (t + i / 3) % 1.0;
      final radiusX = 24 + ringT * 44;
      final radiusY = radiusX * 0.32;
      final alpha = ((1 - ringT) * 0.28).clamp(0.0, 1.0);
      ripplePaint.color = AppColors.cream.withValues(alpha: alpha);
      canvas.drawOval(
        Rect.fromCenter(
            center: center, width: radiusX * 2, height: radiusY * 2),
        ripplePaint,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HeroWaterPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.shipOffset != shipOffset;
}
