import 'dart:math';

import 'package:flutter/material.dart';

import '../art/family_board_art.dart';
import '../art/fleet_family.dart';
import '../core/theme.dart';
import '../models/game_models.dart';
import '../services/storage_service.dart';
import 'ship_painter.dart';

/// A transient cell effect (explosion / splash).
class CellFx {
  final int row;
  final int col;
  final ShotResult result;
  final DateTime start;
  final Random rng; // cached so explosion particles are stable per-frame

  CellFx(this.row, this.col, this.result)
    : start = DateTime.now(),
      rng = Random(row * 31 + col);

  double get progress =>
      (DateTime.now().difference(start).inMilliseconds / 800).clamp(0.0, 1.0);
  bool get done => progress >= 1.0;

  int get key => row * kBoardSize + col;
}

/// Lightweight event descriptor (avoids importing the controller here).
class CombatEventLike {
  final int row;
  final int col;
  final ShotResult result;
  final String? sunkShipName;
  const CombatEventLike(this.row, this.col, this.result, {this.sunkShipName});
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

  /// Thematic family whose battlefield replaces the flat cells and
  /// printed gridlines. Null keeps the original painted grid.
  final FleetFamily? boardFamily;
  final Color gridLineColor;

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

  /// Which ships may be dragged or rotated right now. `null` means "all of
  /// them", which is what deployment wants. MANOEUVRE mode passes the
  /// still-undamaged hulls, so a ship that has taken a hit neither offers
  /// a rotate handle nor responds to a drag — the rule is visible in the
  /// controls rather than only enforced after the fact.
  final Set<ShipKind>? movableShips;

  /// Whether a ship mounting for the FIRST time (no prior element for its
  /// `ValueKey` — see `_animatedShipBox`) should ease in with a fade +
  /// settle-scale instead of just appearing at full size instantly.
  ///
  /// Defaults to false, which keeps ordinary drag-and-drop placement
  /// exactly as it always was — the drag gesture itself already supplies
  /// the motion, so a first-mount pop there is unnoticeable. The deploy
  /// screen turns this on only for the RANDOM button's very first deal
  /// onto an empty board, where there is no drag and no prior position
  /// for `AnimatedPositioned` to ease FROM, so all five ships would
  /// otherwise just blink onto the grid at once. See
  /// `PlacementScreen._runRandomize`.
  final bool animateEntrance;

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
    this.boardFamily,
    this.gridLineColor = AppColors.steelBlueLight,
    this.previewShip,
    this.previewValid = true,
    this.aimCell,
    this.onShipDragEnd,
    this.onShipTap,
    this.onShipDragUpdate,
    this.movableShips,
    this.animateEntrance = false,
    this.clip = true,
  });

  /// When false the grid does not clip its children — used on the deploy
  /// screen so the RANDOM deal can visibly slide ships in from the dock
  /// tray above the board instead of popping in from just underneath it.
  final bool clip;

  @override
  State<BattleGrid> createState() => _BattleGridState();
}

class _BattleGridState extends State<BattleGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fxCtrl;
  final Map<int, CellFx> _fx = {};

  /// Instant tap-feedback ripples (int cell-key → time tapped). Short-lived and
  /// self-clearing; this is what replaced the old persistent crosshair.
  final Map<int, DateTime> _tapFx = {};

  /// Only process NEW events in didUpdateWidget — avoids re-scanning the
  /// entire landed-events list on every 100ms cooldown tick (the list only
  /// grows, so tracking the last-seen length is sufficient).
  int _lastProcessedEvents = 0;

  // Drag state (placement) — repositioning an already-placed ship.
  //
  // Previously this only tracked the raw finger position (`_dragPos`) and
  // derived the ship's landing cell straight from it every frame
  // (`_dragPos / cell`). That treats wherever you happened to grab the
  // ship as its new top-left cell, so a ship grabbed anywhere but its own
  // first cell would jump the moment the drag started, and grabbing it in
  // a different spot next time produced a different, equally-wrong offset
  // — i.e. the position "bugs out" a little more accurately each time you
  // move it, exactly as reported.
  //
  // Fixed by anchoring on the DELTA between the finger's start position
  // and its current position, added to the ship's actual row/col at drag
  // start — so the ship tracks the finger 1:1 from wherever it was
  // grabbed, snapped to the grid, instead of being re-anchored to the
  // finger every frame.
  ShipKind? _dragKind;
  Offset _dragStartPos = Offset.zero;
  int _dragAnchorRow = 0;
  int _dragAnchorCol = 0;
  int _dragPreviewRow = 0;
  int _dragPreviewCol = 0;
  bool _dragging = false;

  /// Which ship kinds have already played their [_ShipEntrance] pop-in at
  /// least once, for as long as this [_BattleGridState] itself has been
  /// alive (survives ordinary rebuilds — it's State, not build-local).
  ///
  /// BUGFIX (moving a placed ship replayed the RANDOM-deal "pop"): a ship
  /// currently being dragged is deliberately left OUT of [_shipWidgets] —
  /// `_dragGhost` stands in for it — so `_onPanStart`/`_onPanEnd` toggling
  /// `_dragKind` makes that ship's `ValueKey` disappear from the built
  /// children for the duration of the drag and then reappear once it
  /// ends. That reappearance is, as far as `AnimatedPositioned`/
  /// `_ShipEntrance` can tell, a brand-new element with no prior frame to
  /// ease from — exactly the situation `_ShipEntrance` exists to animate.
  /// So on any placement session where `animateEntrance` had already
  /// turned on (i.e. after the RANDOM button's first deal onto an empty
  /// board — see `PlacementScreen._entranceDeal`), every ordinary manual
  /// drag afterward re-triggered the same fade + settle-scale "pop" the
  /// instant the ship was dropped, instead of the plain instant
  /// reposition ordinary drag-and-drop has always had.
  ///
  /// Fixed by remembering, per ship kind, whether it has already played
  /// that entrance once — the drag-exclusion remount can then only ever
  /// find a kind here and suppress the replay, while the very first
  /// mount (RANDOM's staged deal — see `_animatedShipBox`) still gets to
  /// animate exactly once, same as before.
  final Set<ShipKind> _shipsEnteredOnce = {};

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
      _tapFx.removeWhere(
        (_, started) =>
            DateTime.now().difference(started).inMilliseconds >= 260,
      );
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
    final events = widget.recentEvents;
    // The events list only grows during a match (shots are appended), but
    // can shrink if the board is reset within the same widget instance.
    // Detect that and flush stale FX state.
    if (events.length < _lastProcessedEvents) {
      _fx.clear();
      _tapFx.clear();
      _lastProcessedEvents = 0;
    }
    // Skip entirely if no new events have landed since last time — the
    // parent rebuilds every 100ms for the cooldown tick, but recentEvents
    // only grows when a shot actually lands.
    if (events.length <= _lastProcessedEvents) {
      _fx.removeWhere((_, fx) => fx.done);
      return;
    }
    for (var i = _lastProcessedEvents; i < events.length; i++) {
      final e = events[i];
      final key = e.row * kBoardSize + e.col;
      if (!_fx.containsKey(key)) {
        _fx[key] = CellFx(e.row, e.col, e.result);
        _ensureTickerRunning();
      }
    }
    _lastProcessedEvents = events.length;
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
          // PERF (mobile jank under many hit/miss/destroyed marks): this
          // used to wrap the ENTIRE grid subtree — background, all 100
          // cells' persistent hit/miss markers, every ship/wreck widget —
          // in one `AnimatedBuilder(animation: _fxCtrl, ...)`. Since
          // `_fxCtrl` ticks at 60fps for ~800ms after literally every shot
          // (any splash/explosion/tap-ripple keeps it running), that meant
          // the WHOLE board — including every mark from every PAST shot,
          // not just the one animating — was rebuilt and repainted on
          // every single frame for most of an active match. Cost grew
          // directly with how many marks had accumulated, which is
          // exactly "struggles when there are too many hit/miss/destroyed
          // ships on the grid" — imperceptible on a desktop GPU, very
          // visible on a low/mid-range phone's.
          //
          // Fixed by splitting the grid into two independent PAINT
          // LAYERS — and this is the part that's easy to get wrong: just
          // splitting the drawing code into two `CustomPainter`s is NOT
          // enough on its own. Without a `RepaintBoundary` around each
          // one, they're still two plain sibling `RenderObject`s sharing
          // whatever picture their nearest actual repaint-boundary
          // ancestor records — and a plain `CustomPaint` is NOT itself a
          // repaint boundary. Flutter's invalidation walks UP from
          // whichever child called `markNeedsPaint()` to the nearest
          // boundary and re-records that boundary's ENTIRE picture,
          // repainting every non-boundary descendant in it — including
          // siblings whose own `shouldRepaint` said no. So without an
          // explicit boundary around each layer, the fx layer ticking at
          // 60fps would still have forced the static layer (and every
          // ship/wreck) to repaint right along with it every frame — all
          // the original cost, PLUS the overhead of the extra widgets.
          // That's the actual reason an earlier version of this split
          // made real-device performance WORSE instead of better.
          //  * `_StaticGridPainter` — background, gridlines, the
          //    placement preview, and every PERSISTENT hit/miss marker.
          //    Its own `RepaintBoundary` means it only repaints when the
          //    board state actually changes (`shouldRepaint` keyed on
          //    `shots`/`preview`/etc.), and — critically — is no longer
          //    dragged into a repaint just because its FX sibling ticks.
          //  * `_FxGridPainter` — only the transient splash/explosion/
          //    tap-ripple effects, wrapped in its own small, LOCAL
          //    `AnimatedBuilder` AND its own `RepaintBoundary`. This is
          //    the only thing that still repaints at 60fps, its cost is
          //    bounded by the (small, constant) number of effects in
          //    flight rather than match history, and — now — its
          //    repainting is confined to its OWN layer instead of
          //    spilling out onto its siblings.
          // Ship/wreck widgets and the crosshair also moved OUTSIDE the
          // ticker's rebuild scope entirely (they only rebuild on a normal
          // `setState`/parent rebuild, not 60 times a second).
          //
          // IMPORTANT — boundaries are NOT free, and more is NOT better.
          // There are exactly THREE here per grid: this one, and one each
          // around the static and fx layers. Individual ships and wrecks
          // deliberately have none (see `_animatedShipBox` /
          // `_destroyedShipWidgets`): every `RepaintBoundary` is its own
          // compositing layer / offscreen render target, so putting one on
          // each ship made the layer count — and the GPU bandwidth and
          // render-pass switches that go with it — grow as ships were
          // placed and sunk. On a desktop GPU that is invisible; on a
          // low-end phone it is precisely the "gets worse the longer the
          // match runs" behavior we were trying to fix. Only put a
          // boundary around something that repaints often AND
          // independently — which is true of the fx layer, and of this
          // whole grid relative to the neighbouring animated cannon, but
          // not of a ship sitting still on the board.
          return RepaintBoundary(
            child: GestureDetector(
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
                clipBehavior: widget.clip ? Clip.antiAlias : Clip.none,
                child: Stack(
                  children: [
                    RepaintBoundary(
                      child: CustomPaint(
                        size: Size.square(size),
                        painter: _StaticGridPainter(
                          shots: widget.shots,
                          preview: widget.previewShip,
                          previewValid: widget.previewValid,
                          gridColor: widget.glowColor,
                          cellColor: widget.cellColor,
                          boardFamily: widget.boardFamily,
                          gridLineColor: widget.gridLineColor,
                          destroyedShips: widget.destroyedShips,
                        ),
                      ),
                    ),
                    RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _fxCtrl,
                        builder: (context, _) => CustomPaint(
                          size: Size.square(size),
                          painter: _FxGridPainter(fx: _fx, tapFx: _tapFx),
                        ),
                      ),
                    ),
                    if (widget.destroyedShips.isNotEmpty)
                      ..._destroyedShipWidgets(cell),
                    if (widget.ships != null && widget.skin != null)
                      ..._shipWidgets(cell),
                    if (_dragging && _dragKind != null) _dragGhost(cell),
                    // REDESIGN: the targeting reticle is now a real
                    // widget (see `_Crosshair`) instead of something
                    // hand-drawn instantly inside the grid's painter —
                    // that's what lets it smoothly animate its position/
                    // scale/opacity via AnimatedPositioned/Scale/Opacity
                    // instead of just popping onto whatever cell
                    // [aimCell] points at. Always present (not gated
                    // behind `aimCell != null`) so it can animate OUT
                    // cleanly too; it's fully invisible/inert whenever
                    // there's nothing to aim at.
                    _Crosshair(cell: cell, target: widget.aimCell),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Whether this ship is currently draggable/rotatable — see
  /// [BattleGrid.movableShips].
  bool _movable(PlacedShip s) =>
      widget.movableShips == null || widget.movableShips!.contains(s.spec.kind);

  void Function(TapUpDetails)? _onTap(double cell) {
    // `enabled` gates FIRING at this grid. Rotating your own ships is a
    // separate permission: in MANOEUVRE mode you reposition ships on your
    // own board, and your own board is never one you can fire at — so
    // gating both on the same flag would make the fleet untouchable.
    final canRotate = widget.onShipTap != null && widget.ships != null;
    if (!widget.enabled && !canRotate) return null;
    return (d) {
      final c = (d.localPosition.dx / cell).floor();
      final r = (d.localPosition.dy / cell).floor();
      if (r < 0 || r >= kBoardSize || c < 0 || c >= kBoardSize) return;
      // Tapping one of your own ships rotates it (deployment, MANOEUVRE).
      if (canRotate) {
        for (final s in widget.ships!) {
          if (s.containsCell(r, c) && _movable(s)) {
            widget.onShipTap!(s.spec.kind);
            return;
          }
        }
      }
      if (!widget.enabled) return;
      if (widget.onTapCell != null) _pulseTap(r, c);
      widget.onTapCell?.call(r, c);
    };
  }

  /// Instant ripple at the tapped cell — the tap IS the shot, so this is
  /// the only "targeting" feedback the grid needs (no persistent cursor).
  void _pulseTap(int r, int c) {
    _tapFx[r * kBoardSize + c] = DateTime.now();
    _ensureTickerRunning();
  }

  void Function(DragStartDetails)? _onPanStart(double cell) {
    // Deliberately NOT gated on `enabled` — see `_onTap`.
    if (widget.onShipDragEnd == null || widget.ships == null) {
      return null;
    }
    return (d) {
      final c = (d.localPosition.dx / cell).floor();
      final r = (d.localPosition.dy / cell).floor();
      for (final s in widget.ships!) {
        if (s.containsCell(r, c) && _movable(s)) {
          setState(() {
            _dragKind = s.spec.kind;
            _dragging = true;
            _dragStartPos = d.localPosition;
            _dragAnchorRow = s.row;
            _dragAnchorCol = s.col;
            _dragPreviewRow = s.row;
            _dragPreviewCol = s.col;
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
      final kind = _dragKind;
      if (kind == null) return;
      // Whole-cell delta between where the finger started and where it is
      // now — applied on top of the ship's own starting row/col, so the
      // grab point stays fixed relative to the ship no matter where on
      // its body it was picked up.
      final dCol = ((d.localPosition.dx - _dragStartPos.dx) / cell).round();
      final dRow = ((d.localPosition.dy - _dragStartPos.dy) / cell).round();
      final r = (_dragAnchorRow + dRow).clamp(0, kBoardSize - 1).toInt();
      final c = (_dragAnchorCol + dCol).clamp(0, kBoardSize - 1).toInt();
      setState(() {
        _dragPreviewRow = r;
        _dragPreviewCol = c;
      });
      widget.onShipDragUpdate?.call(kind, r, c);
    };
  }

  void Function(DragEndDetails)? _onPanEnd(double cell) {
    if (widget.onShipDragEnd == null) return null;
    return (d) {
      if (_dragging && _dragKind != null) {
        widget.onShipDragEnd!(_dragKind!, _dragPreviewRow, _dragPreviewCol);
      }
      setState(() {
        _dragging = false;
        _dragKind = null;
      });
    };
  }

  /// BUGFIX (ship morphs/stretches on rotation instead of rotating): this
  /// used to size the `AnimatedPositioned` box directly to the ship's own
  /// N×1 / 1×N footprint, so an orientation change linearly interpolated
  /// `width`/`height` straight from one aspect ratio to the other — the
  /// ship visibly stretched and squashed through every ratio in between.
  /// Worse, the ship's ARTWORK itself was rendered as a plain `CustomPaint`
  /// when horizontal but wrapped in a discrete `RotatedBox` when vertical —
  /// two structurally different widgets, so Flutter couldn't animate
  /// between them at all; the art just popped to its new orientation
  /// mid-morph.
  ///
  /// Fixed by giving each ship a fixed-size SQUARE positioned box (sized to
  /// the ship's own long axis, so it comfortably contains the ship in
  /// either orientation) that only ever animates POSITION — never size —
  /// and rendering the ship's artwork at a constant natural size inside it,
  /// spun a physical quarter turn with `AnimatedRotation` when vertical
  /// (see `_ShipWithRotate`). That's what makes an orientation change read
  /// as an actual rotation instead of a resize.
  List<Widget> _shipWidgets(double cell) {
    final ships = widget.ships!;
    return [
      for (final ship in ships)
        if (ship.spec.kind != _dragKind) _animatedShipBox(ship, cell),
    ];
  }

  Widget _animatedShipBox(PlacedShip ship, double cell) {
    final long = ship.spec.size * cell;
    final short = cell;
    final w = ship.horizontal ? long : short;
    final h = ship.horizontal ? short : long;
    final centerX = ship.col * cell + w / 2;
    final centerY = ship.row * cell + h / 2;
    final boxSide = long - 2; // same 2px inset the old per-orientation box used

    // Per-ship-kind latch on top of `widget.animateEntrance` — see
    // `_shipsEnteredOnce` for why the blanket widget flag alone isn't
    // enough to keep a later manual drag from replaying this. Marked the
    // instant it's consulted (not in a `setState`) so a ship's SECOND
    // mount under the same build — e.g. immediately re-queried by a
    // hot-reload or a parent rebuild before `initState` below has even
    // run — can't slip through and animate twice either.
    final playEntrance =
        widget.animateEntrance && !_shipsEnteredOnce.contains(ship.spec.kind);
    if (playEntrance) _shipsEnteredOnce.add(ship.spec.kind);

    // AnimatedPositioned (rather than a plain Positioned) so that whenever
    // a ship's row/col/orientation changes in the underlying board state —
    // a drag, a rotation, or the placement screen's RANDOM button
    // rewriting every ship's position in one setState — it's matched by
    // its stable `ValueKey(ship.spec.kind)` to the SAME element and eases
    // from its old spot to the new one instead of teleporting there
    // instantly. A brand-new ship (no prior element for that key) has no
    // old position to ease FROM, so `AnimatedPositioned` alone can't
    // animate its first appearance — `_ShipEntrance` below is what gives
    // that moment its own transition when `widget.animateEntrance` asks
    // for one. The box itself is always square (see the bugfix note above
    // `_shipWidgets`) — only its CENTER moves; the ship's actual footprint
    // change is handled entirely by the rotation inside `_ShipWithRotate`.
    return AnimatedPositioned(
      key: ValueKey(ship.spec.kind),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOutCubic,
      left: centerX - boxSide / 2,
      top: centerY - boxSide / 2,
      width: boxSide,
      height: boxSide,
      // NB: deliberately NOT wrapped in a `RepaintBoundary`. An earlier
      // pass added one per ship on the theory that it would isolate each
      // ship's repaints — but a RepaintBoundary is only a win when its
      // child repaints OFTEN and INDEPENDENTLY. These ships are static
      // once placed. What the boundary actually bought was a separate
      // compositing layer (an offscreen render target) per ship, and the
      // count of those scales with the number of ships and wrecks on the
      // board — i.e. it got worse exactly as the match progressed, which
      // is the symptom we were chasing. Extra render-pass switches and
      // the bandwidth to composite them are expensive on low-end mobile
      // GPUs in a way they simply are not on a desktop GPU, which is why
      // this looked harmless in local testing. See `build()`.
      child: _ShipEntrance(
        animate: playEntrance,
        child: _ShipWithRotate(
          ship: ship,
          skin: widget.skin!,
          cell: cell,
          showRotate:
              widget.onShipTap != null && !ship.isSunk && _movable(ship),
        ),
      ),
    );
  }

  /// Reveals a fully-sunk ship on the grid in its destroyed form. Rendered
  /// independently of [_shipWidgets] so it also appears on the "empty"
  /// battle grids (where [ships] is null and only hit/miss markers would
  /// otherwise show).
  ///
  /// The wreck is wrapped in [_ShipRevealTransition] so it eases into view
  /// (fade + settle-scale) the instant it's added to [widget.destroyedShips]
  /// instead of just popping onto the grid fully-formed.
  List<Widget> _destroyedShipWidgets(double cell) {
    return [
      for (final ship in widget.destroyedShips)
        Positioned(
          key: ValueKey('wreck-${ship.spec.kind}-${ship.row}-${ship.col}'),
          left: ship.col * cell + 1,
          top: ship.row * cell + 1,
          width: ship.horizontal ? ship.spec.size * cell - 2 : cell - 2,
          height: ship.horizontal ? cell - 2 : ship.spec.size * cell - 2,
          // NB: no `RepaintBoundary` here either — see `_animatedShipBox`.
          // Wrecks are the worst case for that mistake: they only ever
          // accumulate as the match goes on, so one offscreen layer per
          // wreck meant the GPU cost climbed with every ship sunk.
          child: IgnorePointer(
            child: _ShipRevealTransition(
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
        ),
    ];
  }

  Widget _dragGhost(double cell) {
    final spec = kFleet.firstWhere((s) => s.kind == _dragKind);
    final horizontal = widget.ships!
        .firstWhere((s) => s.spec.kind == _dragKind)
        .horizontal;
    // Same left/top/width/height formula as `_shipWidgets` (grid-anchored,
    // `-2` inset) using `_dragPreviewRow`/`_dragPreviewCol` — the exact
    // cell the ship will land on if released right now (see
    // `_onPanUpdate`) — instead of centering the ghost on the raw,
    // continuous finger position. That's what kept the ghost glued to the
    // grid cells as you drag, rather than floating free of them and only
    // "landing" correctly by chance.
    final w = horizontal ? spec.size * cell - 2 : cell - 2;
    final h = horizontal ? cell - 2 : spec.size * cell - 2;
    return Positioned(
      left: _dragPreviewCol * cell + 1,
      top: _dragPreviewRow * cell + 1,
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

/// One-shot fade + settle-scale for a ship's FIRST appearance on the grid,
/// played only when [animate] is true at the moment this element is
/// created — otherwise the child just appears instantly, unchanged from
/// how a normal drag-placed ship has always behaved.
///
/// [animate] is read once, in `initState`: since this sits directly inside
/// `_animatedShipBox`'s `AnimatedPositioned` (itself keyed to the ship's
/// kind), this widget's State is created exactly once per ship — the
/// instant that ship's key first appears in the tree — and reused on every
/// later rebuild (reshuffles, rotations, drags) without re-running
/// `initState`, so the entrance can never accidentally replay on a ship
/// that's simply moving to a new spot.
class _ShipEntrance extends StatefulWidget {
  final Widget child;
  final bool animate;
  const _ShipEntrance({required this.child, required this.animate});

  @override
  State<_ShipEntrance> createState() => _ShipEntranceState();
}

class _ShipEntranceState extends State<_ShipEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    _fade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
    );
    if (widget.animate) {
      _ctrl.forward();
    } else {
      // Same instant appearance drag-and-drop placement has always had.
      _ctrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}

/// One-shot "reveal" transition for a sunk ship's wreck graphic: fades in
/// and scales up from slightly-small with a gentle overshoot-then-settle
/// (like the wreck is bobbing up to the surface), instead of the graphic
/// just instantly appearing on the grid. Plays exactly once, starting the
/// moment this widget is first mounted — which, since the parent keys each
/// wreck by `ship.spec.kind`/row/col (see `_destroyedShipWidgets`), is
/// precisely when that ship enters `destroyedShips` for the first time.
/// Later rebuilds reuse the same element/State, so the animation is never
/// re-triggered on an already-revealed wreck.
class _ShipRevealTransition extends StatefulWidget {
  final Widget child;
  const _ShipRevealTransition({required this.child});

  @override
  State<_ShipRevealTransition> createState() => _ShipRevealTransitionState();
}

class _ShipRevealTransitionState extends State<_ShipRevealTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    // Opacity finishes ahead of the scale settle so the tail end of the
    // overshoot doesn't read as a flicker.
    _fade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}

/// A ship drawn on the grid, with cartoon rotate arrows beneath it
/// (placement mode only).
///
/// Always lays out its artwork at a fixed, constant `long × short` size —
/// the ship's NATURAL horizontal footprint — centered in whatever box its
/// parent (`_animatedShipBox`) gives it, and spins the whole assembly a
/// physical quarter turn with [AnimatedRotation] when the ship is
/// vertical. That's a real rotation (fixed content, just spun in place)
/// rather than a resize, so it never stretches/squashes, and the rotate
/// arrows — laid out as part of the SAME rotating assembly, at the
/// artwork's natural corners — swing around with the ship for free instead
/// of needing their own per-orientation position logic.
class _ShipWithRotate extends StatelessWidget {
  final PlacedShip ship;
  final ShipSkin skin;
  final double cell;
  final bool showRotate;

  const _ShipWithRotate({
    required this.ship,
    required this.skin,
    required this.cell,
    required this.showRotate,
  });

  static const _rotateDuration = Duration(milliseconds: 420);

  @override
  Widget build(BuildContext context) {
    final long = ship.spec.size * cell - 2;
    final short = cell - 2;
    final painter = ShipPainter(
      spec: ship.spec,
      skin: skin,
      sunk: ship.isSunk,
      hitCount: ship.hitIndices.length,
      // The actual local cell indices that were hit — NOT just how many —
      // so a damage crater lands on the specific grid cell that was shot
      // instead of always filling in from the bow end. See ShipPainter.
      hitIndices: ship.hitIndices,
    );

    Widget assembly = SizedBox(
      width: long,
      height: short,
      child: CustomPaint(painter: painter, size: Size(long, short)),
    );

    if (showRotate) {
      assembly = Stack(
        clipBehavior: Clip.none,
        children: [
          assembly,
          // Rotate arrows hugging the ship's natural (pre-rotation) top-left
          // / bottom-right corners — rotating with it below instead of
          // needing their own orientation-conditioned offsets.
          Positioned(
            left: -cell * 0.22,
            top: -cell * 0.22,
            child: const _RotateArrow(Icons.rotate_left),
          ),
          Positioned(
            right: -cell * 0.22,
            bottom: -cell * 0.22,
            child: const _RotateArrow(Icons.rotate_right),
          ),
        ],
      );
    }

    return Center(
      child: AnimatedRotation(
        turns: ship.horizontal ? 0.0 : 0.25,
        duration: _rotateDuration,
        curve: Curves.easeInOutCubic,
        child: assembly,
      ),
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

/// REDESIGN: white naval targeting reticle — four corner brackets, a thin
/// center cross and a small center dot, with a soft glow — locked onto the
/// cell a cannonball is currently flying toward. Replaces the old
/// painter-drawn ring (which was mostly `AppColors.hit` red, not white, and
/// simply popped into place with no transition of its own).
///
/// Always mounted (never conditionally built), so it can animate OUT
/// cleanly: [target] going from a cell back to `null` just scales/fades
/// the SAME element down at its last-known position instead of yanking a
/// whole widget out of the tree with no exit transition.
class _Crosshair extends StatefulWidget {
  final double cell;
  final List<int>? target;

  const _Crosshair({required this.cell, required this.target});

  @override
  State<_Crosshair> createState() => _CrosshairState();
}

class _CrosshairState extends State<_Crosshair> {
  List<int> _lastTarget = const [0, 0];

  @override
  void initState() {
    super.initState();
    final t = widget.target;
    if (t != null) _lastTarget = t;
  }

  @override
  void didUpdateWidget(covariant _Crosshair oldWidget) {
    super.didUpdateWidget(oldWidget);
    final t = widget.target;
    if (t != null) _lastTarget = t;
  }

  @override
  Widget build(BuildContext context) {
    final cell = widget.cell;
    final visible = widget.target != null;
    final r = visible ? widget.target![0] : _lastTarget[0];
    final c = visible ? widget.target![1] : _lastTarget[1];
    final size = cell * 0.8;
    // BUGFIX: `AnimatedPositioned` (like `Positioned`) is a
    // ParentDataWidget for `Stack` — its render-tree PARENT must be the
    // Stack itself, with nothing else that creates its own RenderObject
    // in between. `_Crosshair` (a StatelessWidget-like State build) is
    // transparent so that's fine, but `IgnorePointer` is NOT transparent —
    // it has its own RenderObject. Wrapping `AnimatedPositioned` INSIDE
    // `IgnorePointer` (the original version of this code) put
    // RenderIgnorePointer between the Stack and the Positioned data,
    // which crashes with "type 'ParentData' is not a subtype of type
    // 'StackParentData'" the moment it mounts. AnimatedPositioned must be
    // the OUTERMOST widget returned here; IgnorePointer belongs nested
    // inside its `child`, where it's just an ordinary descendant.
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      left: c * cell + cell / 2 - size / 2,
      top: r * cell + cell / 2 - size / 2,
      width: size,
      height: size,
      child: IgnorePointer(
        child: AnimatedScale(
          scale: visible ? 1.0 : 0.55,
          duration: const Duration(milliseconds: 180),
          curve: visible ? Curves.easeOutBack : Curves.easeIn,
          child: AnimatedOpacity(
            opacity: visible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 150),
            // The enclosing AnimatedPositioned already fixes this to a
            // `size × size` tight box, so CustomPaint just fills it.
            child: const CustomPaint(painter: _CrosshairPainter()),
          ),
        ),
      ),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  const _CrosshairPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final center = Offset(s / 2, s / 2);
    final bracketLen = s * 0.30;
    final inset = s * 0.13; // gap between the center and each bracket corner
    final d = s / 2 - inset;

    // PERF: this used a `MaskFilter.blur` for a soft halo. Blur is one of
    // the most expensive things you can ask a mobile GPU for under
    // Impeller (Android's default renderer since Flutter 3.16) — and this
    // one was drawn 8× per frame (two strokes per bracket, four brackets)
    // for the whole time a shot was in flight. A plain wide, translucent
    // stroke underneath the crisp one reads almost identically at this
    // size for a tiny fraction of the cost.
    final glow = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.12
      ..strokeCap = StrokeCap.round;
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.055
      ..strokeCap = StrokeCap.round;

    void bracket(Offset corner, Offset toward1, Offset toward2) {
      final p1 = corner + toward1 * bracketLen;
      final p2 = corner + toward2 * bracketLen;
      canvas.drawLine(corner, p1, glow);
      canvas.drawLine(corner, p2, glow);
      canvas.drawLine(corner, p1, stroke);
      canvas.drawLine(corner, p2, stroke);
    }

    const right = Offset(1, 0);
    const left = Offset(-1, 0);
    const down = Offset(0, 1);
    const up = Offset(0, -1);
    bracket(center + Offset(-d, -d), right, down); // top-left
    bracket(center + Offset(d, -d), left, down); // top-right
    bracket(center + Offset(-d, d), right, up); // bottom-left
    bracket(center + Offset(d, d), left, up); // bottom-right

    // Thin center cross.
    final crossLen = s * 0.11;
    canvas.drawLine(
      center - Offset(crossLen, 0),
      center + Offset(crossLen, 0),
      stroke,
    );
    canvas.drawLine(
      center - Offset(0, crossLen),
      center + Offset(0, crossLen),
      stroke,
    );

    // Small center dot.
    canvas.drawCircle(center, s * 0.028, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _CrosshairPainter oldDelegate) => false;
}

/// Background, gridlines, the placement preview, and every PERSISTENT
/// hit/miss marker. Deliberately kept independent of the transient fx
/// state — see the PERF note on `BattleGrid.build()` — so `shouldRepaint`
/// only fires when the board actually changes, not on every 60fps
/// animation tick while a splash/explosion/tap-ripple is playing
/// somewhere on the grid.
class _StaticGridPainter extends CustomPainter {
  final List<List<int>> shots;
  final PlacedShip? preview;
  final bool previewValid;
  final Color gridColor;
  final Color cellColor;

  /// Thematic family whose battlefield replaces the flat cells and
  /// printed gridlines. Null keeps the original painted grid.
  final FleetFamily? boardFamily;
  final Color gridLineColor;
  final List<PlacedShip> destroyedShips;

  _StaticGridPainter({
    required this.shots,
    this.preview,
    this.previewValid = true,
    required this.gridColor,
    this.cellColor = AppColors.steelBlue,
    this.boardFamily,
    this.gridLineColor = AppColors.steelBlueLight,
    this.destroyedShips = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / kBoardSize;
    final family = boardFamily;

    if (family != null) {
      // A themed battlefield replaces the water AND the gridlines — ice
      // floes with crack lines, basalt slabs with molten seams, riveted
      // plate with bolted seams. It is authored on the same ten-by-ten
      // 400-unit field the game already plays on, so nothing about cell
      // size, coordinates or tap targets moves.
      paintFamilyBoard(canvas, size, family);
    } else {
      // ---- Flat steel-blue cells with thin lighter grid lines (video style) ----
      canvas.drawRect(Offset.zero & size, Paint()..color = cellColor);
      final linePaint = Paint()
        ..color = gridLineColor.withValues(alpha: 0.55)
        ..strokeWidth = 1.1;
      for (var i = 1; i < kBoardSize; i++) {
        canvas.drawLine(
          Offset(i * cell, 0),
          Offset(i * cell, size.height),
          linePaint,
        );
        canvas.drawLine(
          Offset(0, i * cell),
          Offset(size.width, i * cell),
          linePaint,
        );
      }
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
    // PERF: allocate each marker Paint ONCE per repaint instead of once
    // per marked cell. The old code built 2-3 `Paint()` objects inside
    // `_drawHit`/`_drawMiss` for every single mark on the board, so a
    // late-game grid churned through ~250 short-lived Paints per repaint
    // — pure GC pressure that grew as the match went on, on exactly the
    // devices least able to absorb it.
    final missCellPaint = Paint()..color = AppColors.steelBlueDark;
    final missMarkPaint = Paint()
      ..color = AppColors.cellGrey
      ..strokeWidth = cell * 0.085
      ..strokeCap = StrokeCap.round;
    final hitCellPaint = Paint()..color = AppColors.outline;
    final hitDiamondPaint = Paint()..color = AppColors.burst;

    // PERF: flatten the destroyed-ship footprints into one cell-key set
    // up front, instead of re-scanning every destroyed ship (and every
    // cell of each) for every hit marker drawn.
    final destroyedCells = <int>{};
    for (final ship in destroyedShips) {
      for (final cp in ship.cells) {
        destroyedCells.add(cp[0] * kBoardSize + cp[1]);
      }
    }

    for (var r = 0; r < kBoardSize; r++) {
      final rowShots = shots[r];
      for (var c = 0; c < kBoardSize; c++) {
        final v = rowShots[c];
        if (v == 0) continue;
        // Hide hit markers for cells covered by a destroyed ship — the
        // destroyed ship graphic replaces all individual hit cells.
        if (v == 2 && destroyedCells.contains(r * kBoardSize + c)) continue;
        final center = Offset(c * cell + cell / 2, r * cell + cell / 2);
        if (family != null) {
          // A themed marker is still exactly one cell — a foam ring, a
          // frost star, a magma crater — so what a player has to read
          // ("that square is spent", "that square is a hit") is unchanged
          // and only the drawing differs.
          if (v == 2) {
            paintFamilyHit(canvas, center, cell, family);
          } else {
            paintFamilyMiss(canvas, center, cell, family);
          }
        } else if (v == 2) {
          _drawHit(canvas, center, cell, hitCellPaint, hitDiamondPaint);
        } else {
          _drawMiss(canvas, center, cell, missCellPaint, missMarkPaint);
        }
      }
    }
  }

  /// Miss marker (video): slightly darker cell + tiny grey ✕.
  void _drawMiss(
    Canvas canvas,
    Offset center,
    double cell,
    Paint cellPaint,
    Paint markPaint,
  ) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center,
          width: cell * 0.92,
          height: cell * 0.92,
        ),
        Radius.circular(cell * 0.12),
      ),
      cellPaint,
    );
    final s = cell * 0.15;
    canvas.drawLine(center - Offset(s, s), center + Offset(s, s), markPaint);
    canvas.drawLine(center + Offset(-s, s), center + Offset(s, -s), markPaint);
  }

  /// Hit marker (video): black square cell + small yellow diamond inside.
  void _drawHit(
    Canvas canvas,
    Offset center,
    double cell,
    Paint cellPaint,
    Paint diamondPaint,
  ) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center,
          width: cell * 0.92,
          height: cell * 0.92,
        ),
        Radius.circular(cell * 0.10),
      ),
      cellPaint,
    );
    final d = cell * 0.20;
    final diamond = Path()
      ..moveTo(center.dx, center.dy - d)
      ..lineTo(center.dx + d, center.dy)
      ..lineTo(center.dx, center.dy + d)
      ..lineTo(center.dx - d, center.dy)
      ..close();
    canvas.drawPath(diamond, diamondPaint);
  }

  @override
  bool shouldRepaint(_StaticGridPainter oldDelegate) {
    return !identical(oldDelegate.shots, shots) ||
        oldDelegate.preview != preview ||
        oldDelegate.previewValid != previewValid ||
        oldDelegate.cellColor != cellColor ||
        oldDelegate.boardFamily?.id != boardFamily?.id ||
        oldDelegate.gridColor != gridColor ||
        !identical(oldDelegate.destroyedShips, destroyedShips);
  }
}

/// Only the TRANSIENT splash/explosion/tap-ripple effects — everything
/// that actually needs to repaint every animation frame. Kept as its own
/// tiny painter (see the PERF note on `BattleGrid.build()`) so the 60fps
/// ticker only ever has to redraw a small, bounded number of active
/// effects instead of the whole board.
class _FxGridPainter extends CustomPainter {
  final Map<int, CellFx> fx;
  final Map<int, DateTime> tapFx;

  _FxGridPainter({required this.fx, this.tapFx = const {}});

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / kBoardSize;

    // REDESIGN: every impact — hit, miss, or sunk — gets a water splash
    // first (the cannonball always lands "in the water" of the grid cell
    // regardless of outcome), with hit/sunk shots additionally layering
    // the explosion burst on top. That's what gives the sequence
    // "impact → water splash → result marker → hit/sunk feedback" instead
    // of misses getting no impact effect at all.
    fx.forEach((_, effect) {
      final center = Offset(
        effect.col * cell + cell / 2,
        effect.row * cell + cell / 2,
      );
      final prog = effect.progress;
      _drawSplash(canvas, center, cell, prog, rng: effect.rng);
      if (effect.result == ShotResult.hit || effect.result == ShotResult.sunk) {
        _drawExplosion(
          canvas,
          center,
          cell,
          prog,
          big: effect.result == ShotResult.sunk,
          rng: effect.rng,
        );
      }
    });

    // ---- Instant tap ripple: a quick "yes, that tap registered" pulse
    // right where the finger landed. ----
    final now = DateTime.now();
    tapFx.forEach((key, started) {
      final t = now.difference(started).inMilliseconds / 260;
      if (t >= 1.0) return;
      final r = key ~/ kBoardSize;
      final c = key % kBoardSize;
      final center = Offset(c * cell + cell / 2, r * cell + cell / 2);
      _drawTapRipple(canvas, center, cell, t.clamp(0.0, 1.0));
    });
  }

  /// Impact flash: toned-down yellow starburst core + fewer white sparkle
  /// stars flying outward; sinks into the persistent black-square marker.
  void _drawExplosion(
    Canvas canvas,
    Offset center,
    double cell,
    double t, {
    bool big = false,
    required Random rng,
  }) {
    final scale = big ? 1.2 : 0.7;
    // Yellow starburst (4 rounded rays) — flashes in, then fades.
    final burstAlpha = (1 - t * 1.35).clamp(0.0, 1.0);
    if (burstAlpha > 0) {
      final grow = 0.45 + t * 0.55;
      final ray = Paint()
        ..color = AppColors.burst.withValues(alpha: burstAlpha * 0.7)
        ..strokeWidth = cell * 0.12 * scale * (1 - t * 0.5)
        ..strokeCap = StrokeCap.round;
      final len = cell * 0.45 * scale * grow;
      for (var i = 0; i < 4; i++) {
        final ang = i * pi / 2;
        canvas.drawLine(
          center,
          center + Offset(cos(ang) * len, sin(ang) * len),
          ray,
        );
      }
      canvas.drawCircle(
        center,
        cell * 0.28 * scale * grow,
        Paint()..color = AppColors.burst.withValues(alpha: burstAlpha * 0.7),
      );
      canvas.drawCircle(
        center,
        cell * 0.15 * scale * grow,
        Paint()..color = Colors.white.withValues(alpha: burstAlpha * 0.7),
      );
    }
    // White sparkle stars drifting outward — fewer and dimmer.
    final sparkAlpha = (1 - t).clamp(0.0, 1.0);
    for (var i = 0; i < (big ? 4 : 2); i++) {
      final ang = rng.nextDouble() * 2 * pi;
      final dist =
          cell * scale * (0.25 + 0.75 * t) * (0.6 + rng.nextDouble() * 0.5);
      final p = center + Offset(cos(ang) * dist, sin(ang) * dist);
      final sr = cell * 0.08 * (1 - t * 0.6);
      final sp = Paint()
        ..color = Colors.white.withValues(alpha: sparkAlpha * 0.6);
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

  /// Water splash: the base impact effect for EVERY landed shot (hit, miss
  /// or sunk) — the cannonball always hits "the water" of the grid cell
  /// regardless of outcome. Deliberately brief (fully faded by ~55% of the
  /// fx lifetime — see [CellFx.progress]) so it reads as a quick, punchy
  /// splash rather than lingering; hit/sunk shots layer the yellow
  /// explosion burst on top afterward (see the `fx.forEach` call site) for
  /// a clear MISS vs HIT/SUNK distinction. Pure vector draws (no images,
  /// no new particle system) — same cost class as `_drawExplosion` below,
  /// which this game already runs per-shot without issue.
  void _drawSplash(
    Canvas canvas,
    Offset center,
    double cell,
    double t, {
    required Random rng,
  }) {
    final local = (t / 0.55).clamp(0.0, 1.0);
    if (local >= 1.0) return;
    final fade = 1 - local;
    final grow = Curves.easeOut.transform(local);

    // Expanding ripple ring.
    canvas.drawCircle(
      center,
      cell * (0.12 + 0.46 * grow),
      Paint()
        ..color = Colors.white.withValues(alpha: fade * 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.045 * fade,
    );

    // Small water droplets flung outward and briefly upward before the
    // splash settles — an arc shape (sin curve) rather than a straight
    // radial fling, so they read as droplets falling back rather than
    // just dots sliding outward.
    for (var i = 0; i < 6; i++) {
      final ang = (i / 6) * 2 * pi + rng.nextDouble() * 0.35;
      final dist = cell * 0.42 * grow;
      final lift = -cell * 0.30 * sin(local * pi);
      final p = center + Offset(cos(ang) * dist, sin(ang) * dist * 0.6 + lift);
      canvas.drawCircle(
        p,
        cell * 0.05 * fade,
        Paint()..color = Colors.white.withValues(alpha: fade * 0.8),
      );
    }

    // Central white flash right at the impact point.
    canvas.drawCircle(
      center,
      cell * 0.20 * (1 - local * 0.5),
      Paint()..color = Colors.white.withValues(alpha: fade * 0.45),
    );
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

  @override
  bool shouldRepaint(_FxGridPainter oldDelegate) {
    // This painter's whole job is the transient layer, so it only ever
    // needs to repaint while there's actually something transient to
    // show — the AnimatedBuilder driving it already stops ticking (see
    // `_fxCtrl`) the instant both maps go empty, so this doesn't spin
    // forever; it just needs to say yes on every tick while it's running.
    return fx.isNotEmpty ||
        tapFx.isNotEmpty ||
        !identical(oldDelegate.fx, fx) ||
        !identical(oldDelegate.tapFx, tapFx);
  }
}
