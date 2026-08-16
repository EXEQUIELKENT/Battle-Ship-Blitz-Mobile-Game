import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/game_models.dart';
import '../services/game_controller.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../widgets/battle_grid.dart';
import '../widgets/neon_widgets.dart';
import '../widgets/ship_painter.dart';
import 'battle_screen.dart';

/// Red / blue flat skins matching the 1:1 gameplay video.
const _p1PlaceSkin = ShipSkin('p1v', 'P1', AppColors.shipRed, AppColors.shipRedDark, 0);
const _p2PlaceSkin = ShipSkin('p2v', 'P2', AppColors.shipBlue, AppColors.shipBlueDark, 0);

/// "Deploy your ships" — reference-style placement:
/// drag ships from the top dock onto the grid (or tap an empty cell),
/// tap a placed ship to rotate it, RANDOM + green SAVE buttons.
class PlacementScreen extends StatefulWidget {
  final bool isPlayer2;

  const PlacementScreen({super.key, this.isPlayer2 = false});

  @override
  State<PlacementScreen> createState() => _PlacementScreenState();
}

class _PlacementScreenState extends State<PlacementScreen> {
  late Board _board;
  ShipKind? _selected; // currently chosen dock ship
  bool _showHandoff = false;
  static const double _dockH = 64;

  /// True while a RANDOM-triggered reshuffle is staggering ships into
  /// their new spots (see [_randomize]) — disables the RANDOM/SAVE
  /// buttons and drag/tap interaction so the player can't yank a ship or
  /// fire off a second shuffle mid-animation.
  bool _randomizing = false;

  /// Live "where will this land" highlight — driven by whichever drag is
  /// currently active: a fresh ship being dragged in from the dock tray,
  /// or an already-placed ship being repositioned on the grid.
  PlacedShip? _previewShip;
  bool _previewValid = true;

  @override
  void initState() {
    super.initState();
    final controller = context.read<GameController>();
    _board = widget.isPlayer2 ? controller.boards[1] : controller.boards[0];
    // `_cellSize()` below falls back to a rough MediaQuery-based estimate
    // until the grid has actually been laid out at least once (its
    // RenderBox isn't available on the very first build). That first,
    // slightly-off estimate is what gets baked into the dock ships' drag
    // "feedback" size — and since the carrier (5 cells, first in the
    // dock) is usually the very first ship a player drags, a small
    // per-cell error is magnified 5x, producing an oversized/misaligned
    // ghost exactly on that first placement (subsequent drags are fine,
    // since by then a rebuild has already happened and picked up the
    // real size). Scheduling one harmless extra rebuild right after the
    // first frame guarantees the real, precise cell size is in place
    // before the player can interact with anything.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  ShipSpec? get _selectedSpec =>
      _selected == null ? null : kFleet.firstWhere((s) => s.kind == _selected);

  bool get _allPlaced => _board.isComplete;

  void _rotateShip(ShipKind kind) {
    final ship = _board.shipOfKind(kind);
    if (ship == null) return;
    _board.removeShip(kind);
    final newHorizontal = !ship.horizontal;
    // Try rotated at same anchor; nudge back on-grid if needed.
    var r = ship.row;
    var c = ship.col;
    if (newHorizontal && c + ship.spec.size > kBoardSize) {
      c = kBoardSize - ship.spec.size;
    }
    if (!newHorizontal && r + ship.spec.size > kBoardSize) {
      r = kBoardSize - ship.spec.size;
    }
    if (_board.canPlace(ship.spec, r, c, newHorizontal)) {
      _board.place(ship.spec, r, c, newHorizontal);
      SoundService.instance.place();
    } else {
      // Rotation blocked — put it back as it was.
      _board.place(ship.spec, ship.row, ship.col, ship.horizontal);
      SoundService.instance.denied();
    }
    setState(() {});
  }

  void _moveShip(ShipKind kind, int newRow, int newCol) {
    final ship = _board.shipOfKind(kind);
    if (ship == null) return;
    var r = newRow;
    var c = newCol;
    if (ship.horizontal && c + ship.spec.size > kBoardSize) {
      c = kBoardSize - ship.spec.size;
    }
    if (!ship.horizontal && r + ship.spec.size > kBoardSize) {
      r = kBoardSize - ship.spec.size;
    }
    if (r == ship.row && c == ship.col) {
      setState(() => _previewShip = null);
      return;
    }
    _board.removeShip(kind);
    if (_board.canPlace(ship.spec, r, c, ship.horizontal)) {
      _board.place(ship.spec, r, c, ship.horizontal);
      SoundService.instance.place();
    } else {
      _board.place(ship.spec, ship.row, ship.col, ship.horizontal);
      SoundService.instance.denied();
    }
    setState(() => _previewShip = null);
  }

  /// [Board.canPlace] but treating [ignore]'s own current footprint as
  /// unoccupied — used for the live drag highlight so a ship being
  /// repositioned doesn't flag itself as a collision.
  bool _canPlaceIgnoring(
      ShipKind ignore, ShipSpec spec, int row, int col, bool horizontal) {
    if (horizontal) {
      if (col + spec.size > kBoardSize) return false;
    } else {
      if (row + spec.size > kBoardSize) return false;
    }
    for (var i = 0; i < spec.size; i++) {
      final r = horizontal ? row : row + i;
      final c = horizontal ? col + i : col;
      final occupant = _board.shipAt(r, c);
      if (occupant != null && occupant.spec.kind != ignore) return false;
    }
    return true;
  }

  /// Live highlight while an already-placed ship is being dragged around
  /// the grid — called continuously as the finger moves, before the drag
  /// actually ends (see [_moveShip]).
  void _onShipDragPreview(ShipKind kind, int row, int col) {
    final ship = _board.shipOfKind(kind);
    if (ship == null) return;
    final spec = ship.spec;
    final horizontal = ship.horizontal;
    var r = row;
    var c = col;
    if (horizontal && c + spec.size > kBoardSize) {
      c = kBoardSize - spec.size;
    }
    if (!horizontal && r + spec.size > kBoardSize) {
      r = kBoardSize - spec.size;
    }
    setState(() {
      _previewShip =
          PlacedShip(spec: spec, row: r, col: c, horizontal: horizontal);
      _previewValid = _canPlaceIgnoring(kind, spec, r, c, horizontal);
    });
  }

  void _onGridTap(int r, int c) {
    final spec = _selectedSpec;
    if (spec == null) return;
    // Try horizontal first, then vertical.
    if (_board.canPlace(spec, r, c, true)) {
      _board.place(spec, r, c, true);
      SoundService.instance.place();
      setState(() => _selected = null);
    } else if (_board.canPlace(spec, r, c, false)) {
      _board.place(spec, r, c, false);
      SoundService.instance.place();
      setState(() => _selected = null);
    } else {
      SoundService.instance.denied();
    }
  }

  /// Deals out a fresh random layout. Rather than swapping the whole
  /// fleet in one instant `setState` (the old behavior — every ship just
  /// cut to its new spot), this staggers the ships in one at a time so
  /// each one visibly SLIDES to its new cell (the actual motion comes for
  /// free from `BattleGrid`'s `AnimatedPositioned`, keyed per ship —
  /// see `_shipWidgets`) with a placement "thunk" timed to its landing,
  /// giving the RANDOM button a satisfying "shuffle and deal" feel
  /// instead of an abrupt pop.
  void _randomize() {
    if (_randomizing) return;
    unawaited(_runRandomize());
  }

  Future<void> _runRandomize() async {
    final target = Board.random();
    // Shuffle whoosh right as the button is pressed — the cue that a new
    // layout is being dealt out, ahead of any ship actually moving.
    SoundService.instance.whir();
    setState(() {
      _randomizing = true;
      _selected = null;
      _previewShip = null;
    });
    for (final ship in target.ships) {
      if (!mounted) return;
      setState(() {
        _board.ships.removeWhere((s) => s.spec.kind == ship.spec.kind);
        _board.ships.add(ship);
      });
      SoundService.instance.place();
      await Future.delayed(const Duration(milliseconds: 90));
    }
    if (mounted) setState(() => _randomizing = false);
  }

  Future<void> _save() async {
    if (!_allPlaced) return;
    final controller = context.read<GameController>();
    SoundService.instance.victory();

    switch (controller.mode) {
      case GameMode.vsAI:
        controller.beginBattle();
        _goBattle();
        break;
      case GameMode.local:
        if (!widget.isPlayer2) {
          setState(() => _showHandoff = true);
        } else {
          controller.beginBattle(enemyBoard: controller.boards[1]);
          _goBattle();
        }
        break;
      case GameMode.hotspot:
      case GameMode.online:
        controller.network.sendBoard(_board);
        _waitForPeerBoard(controller);
        break;
    }
  }

  void _waitForPeerBoard(GameController controller) {
    late StreamSubscription sub;
    sub = controller.network.messages.listen((msg) {
      if (msg['type'] == 'board') {
        final enemyBoard =
            Board.fromJson(Map<String, dynamic>.from(msg['b'] as Map));
        sub.cancel();
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
        controller.attachNetwork();
        controller.beginBattle(enemyBoard: enemyBoard);
        _goBattle();
      }
    });
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navy,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.outline, width: 3),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.cream),
            const SizedBox(height: 16),
            Text('WAITING FOR OPPONENT…', style: AppText.label(size: 11)),
          ],
        ),
      ),
    );
  }

  void _goBattle() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const BattleScreen()),
    );
  }

  /// The real, on-screen size of one grid cell — read straight from the
  /// grid's own RenderBox (same technique `onMove`/`onAcceptWithDetails`
  /// already use) so the dock icons and the drag "feedback" ghost can be
  /// sized to match the actual board instead of a guessed constant.
  /// Previously the dock icons and the dragged ship were both fixed
  /// pixel sizes (68 / 110) that had no relationship to the grid's real
  /// cell size or to how many cells a ship actually occupies — that
  /// mismatch is why a ship being dragged looked mis-sized/misaligned
  /// against the green highlight cells underneath it.
  /// Before the grid has been laid out for the first time (very first
  /// build) the RenderBox isn't available yet, so this falls back to an
  /// estimate from the screen width, which is close enough for that one
  /// frame and self-corrects on the next rebuild.
  double _cellSize(BuildContext context) {
    final gridBox =
        _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (gridBox != null && gridBox.hasSize) {
      return gridBox.size.width / kBoardSize;
    }
    return MediaQuery.of(context).size.width / kBoardSize;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.read<GameController>();
    final isP2 = controller.mode == GameMode.local && widget.isPlayer2;
    final playerLabel = controller.mode == GameMode.local
        ? (widget.isPlayer2 ? 'PLAYER 2' : 'PLAYER 1')
        : context.watch<ProfileStore>().playerName.toUpperCase();
    final skin = isP2 ? _p2PlaceSkin : _p1PlaceSkin;
    final cellSize = _cellSize(context);

    if (_showHandoff) {
      return HandoffScreen(
        title: 'Pass the screen\nto your friend\nand don\'t look :-)',
        subtitle: 'Player 2 — deploy your fleet in secret!',
        buttonLabel: 'OK',
        onReady: () {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => const PlacementScreen(isPlayer2: true),
            ),
          );
        },
      );
    }

    return Scaffold(
      body: Container(
        color: AppColors.coralVideo,
        child: SafeArea(
          child: Column(
            children: [
              // ---------- Navy header ----------
              Container(
                width: double.infinity,
                color: AppColors.navy,
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 22),
                child: Column(
                  children: [
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            SoundService.instance.click();
                            Navigator.pop(context);
                          },
                          child: const Icon(Icons.arrow_back,
                              color: AppColors.cream),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Deploy your ships',
                            style: AppText.title(size: 24),
                          ),
                        ),
                        _ExitButton(onTap: () => Navigator.pop(context)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$playerLabel — drag to move and tap to rotate, or try random placement',
                      textAlign: TextAlign.center,
                      style: AppText.body(
                          size: 12, color: AppColors.cream.withValues(alpha: 0.75)),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        NeonButton(
                          label: 'RANDOM',
                          icon: Icons.shuffle,
                          color: AppColors.blue,
                          compact: true,
                          onPressed: _randomizing ? null : _randomize,
                        ),
                        const SizedBox(width: 12),
                        NeonButton(
                          label: _allPlaced
                              ? 'SAVE'
                              : 'SAVE  ${_board.ships.length}/5',
                          icon: Icons.bolt,
                          color: _allPlaced ? AppColors.seafoam : AppColors.inkSoft,
                          onPressed:
                              (_allPlaced && !_randomizing) ? _save : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ---------- Dock tray (draggable ship icons) ----------
              Container(
                height: _dockH,
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: const BoxDecoration(
                  color: AppColors.coralLight,
                  border: Border(
                    bottom: BorderSide(color: AppColors.outline, width: 3),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                     for (final spec in kFleet)
                       _DockShip(
                         spec: spec,
                         skin: skin,
                         cell: cellSize,
                         placed: _board.shipOfKind(spec.kind) != null,
                         selected: _selected == spec.kind,
                         onTap: () {
                           SoundService.instance.click();
                           setState(() => _selected =
                               _selected == spec.kind ? null : spec.kind);
                         },
                       ),
                  ],
                ),
              ),

              // ---------- Grid (drop target) ----------
              // No side padding and no size cap: the grid fills all the
              // room the Expanded region gives it (still a square, via
              // BattleGrid's own AspectRatio), rather than the old
              // 16px-padded, 440px-capped box.
              Expanded(
                child: Center(
                  child: DragTarget<({ShipKind kind, bool horizontal})>(
                    onWillAcceptWithDetails: (_) => true,
                    onMove: (details) {
                      final spec =
                          kFleet.firstWhere((s) => s.kind == details.data.kind);
                      final gridBox = _gridKey.currentContext
                          ?.findRenderObject() as RenderBox?;
                      if (gridBox == null) return;
                      final local = gridBox.globalToLocal(details.offset);
                      final cell = gridBox.size.width / kBoardSize;
                      var c = (local.dx / cell).floor();
                      var r = (local.dy / cell).floor();
                      final h = details.data.horizontal;
                      if (h && c + spec.size > kBoardSize) {
                        c = kBoardSize - spec.size;
                      }
                      if (!h && r + spec.size > kBoardSize) {
                        r = kBoardSize - spec.size;
                      }
                      r = r.clamp(0, kBoardSize - 1);
                      c = c.clamp(0, kBoardSize - 1);
                      setState(() {
                        _previewShip =
                            PlacedShip(spec: spec, row: r, col: c, horizontal: h);
                        _previewValid = _board.canPlace(spec, r, c, h);
                      });
                    },
                    onLeave: (_) => setState(() => _previewShip = null),
                    onAcceptWithDetails: (details) {
                      final spec =
                          kFleet.firstWhere((s) => s.kind == details.data.kind);
                      final gridBox = _gridKey.currentContext
                          ?.findRenderObject() as RenderBox?;
                      if (gridBox == null) return;
                      final local = gridBox.globalToLocal(details.offset);
                      final cell = gridBox.size.width / kBoardSize;
                      var c = (local.dx / cell).floor();
                      var r = (local.dy / cell).floor();
                      final h = details.data.horizontal;
                      if (h && c + spec.size > kBoardSize) {
                        c = kBoardSize - spec.size;
                      }
                      if (!h && r + spec.size > kBoardSize) {
                        r = kBoardSize - spec.size;
                      }
                      r = r.clamp(0, kBoardSize - 1);
                      c = c.clamp(0, kBoardSize - 1);
                      if (_board.canPlace(spec, r, c, h)) {
                        _board.place(spec, r, c, h);
                        SoundService.instance.place();
                        setState(() {
                          _selected = null;
                          _previewShip = null;
                        });
                      } else {
                        SoundService.instance.denied();
                        setState(() => _previewShip = null);
                      }
                    },
                    builder: (context, candidates, rejected) {
                      return Container(
                        key: _gridKey,
                        child: BattleGrid(
                          shots: List.generate(kBoardSize,
                              (_) => List.filled(kBoardSize, 0)),
                          ships: _board.ships,
                          skin: skin,
                          cellColor: AppColors.steelBlue,
                          glowColor: AppColors.steelBlueDark,
                          previewShip: _previewShip,
                          previewValid: _previewValid,
                          // Locked while a random shuffle is dealing ships
                          // out (`_randomizing`) so a tap/drag can't land
                          // mid-animation and fight the in-flight reshuffle.
                          onTapCell: _randomizing ? null : _onGridTap,
                          onShipTap: _randomizing ? null : _rotateShip,
                          onShipDragEnd: _randomizing ? null : _moveShip,
                          onShipDragUpdate: _onShipDragPreview,
                        ),
                      );
                    },
                  ),
                ),
              ),

              // ---------- Hint ----------
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Text(
                  _selectedSpec != null
                      ? 'TAP THE GRID TO PLACE: ${_selectedSpec!.name.toUpperCase()}'
                      : _allPlaced
                          ? 'FLEET READY — HIT SAVE TO ENTER BATTLE!'
                          : 'TAP A SHIP ABOVE, OR RANDOM TO AUTO-DEPLOY',
                  textAlign: TextAlign.center,
                  style: AppText.label(size: 11, color: AppColors.navy),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  final GlobalKey _gridKey = GlobalKey();
}

/// A dock-tray ship icon; tap to select, drag to drop onto the grid.
class _DockShip extends StatelessWidget {
  final ShipSpec spec;
  final ShipSkin skin;
  final bool placed;
  final bool selected;
  final double cell;
  final VoidCallback onTap;

  const _DockShip({
    required this.spec,
    required this.skin,
    required this.placed,
    required this.selected,
    required this.cell,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Resting dock icon: width scales with the ship's cell-length (same
    // "unit * spec.size" pattern the battle-screen fleet row uses)
    // instead of every ship — a 2-cell destroyer and a 5-cell carrier
    // alike — rendering inside the same fixed 68px box.
    const dockUnit = 11.0;
    const dockBeam = 30.0;
    final icon = AnimatedShip(
      spec: spec,
      skin: skin,
      width: dockUnit * spec.size + 14,
      height: dockBeam,
    );

    final child = GestureDetector(
      onTap: placed ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.cream.withValues(alpha: 0.5)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: selected
              ? Border.all(color: AppColors.outline, width: 2)
              : null,
        ),
        child: Opacity(opacity: placed ? 0.25 : 1, child: icon),
      ),
    );

    if (placed) return child;

    return Draggable<({ShipKind kind, bool horizontal})>(
      data: (kind: spec.kind, horizontal: true),
      // BUGFIX (placement controls): the grid's `onMove`/`onAcceptWithDetails`
      // (below) read `details.offset` — which Flutter documents as the
      // pointer's raw global position, not the feedback widget's
      // position — and treat that cell directly as the ship's TOP-LEFT
      // cell. With the default `childDragAnchorStrategy`, the feedback
      // ghost is anchored whatever point on the small dock icon you
      // happened to grab, so the ghost visually trails your finger from
      // an offset — but the drop math ignores that offset entirely and
      // places the ship's top-left wherever your finger ends up. Net
      // effect: grab a ship anywhere but its own top-left corner and it
      // lands shifted from where the ghost showed it, which reads as the
      // controls just being unreliable. `pointerDragAnchorStrategy` pins
      // the feedback's OWN top-left to the pointer instead, so the ghost
      // you see is always exactly the cell the ship will land on —
      // consistent no matter where on the dock icon you grabbed it.
      dragAnchorStrategy: pointerDragAnchorStrategy,
      // Sized to the REAL grid cell (cell * spec.size wide, one cell
      // tall) instead of a fixed 110×60.5 box every ship used to share
      // regardless of length or the device's actual cell size — that
      // mismatch is what made the ghost ship look oversized/misaligned
      // against the green/red highlight cells while dragging it onto
      // the grid.
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.85,
          child: AnimatedShip(
            spec: spec,
            skin: skin,
            width: cell * spec.size,
            height: cell,
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.25, child: child),
      child: child,
    );
  }
}

/// Round white EXIT pill (reference style).
class _ExitButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ExitButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        SoundService.instance.click();
        onTap();
      },
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.cream,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.outline, width: 3),
          boxShadow: const [
            BoxShadow(color: Color(0x44000000), offset: Offset(0, 3)),
          ],
        ),
        child: const Center(
          child: RotatedBox(
            quarterTurns: 1,
            child: Text(
              'EXIT',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 11,
                letterSpacing: 1,
                color: AppColors.outline,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Interstitial when passing the device between local players.
/// Matches the 1:1 gameplay video: full steel-blue screen, big friendly
/// message, chunky green OK button.
class HandoffScreen extends StatelessWidget {
  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback onReady;

  const HandoffScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onReady,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: AppColors.steelBlue,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title,
                      style: AppText.title(size: 30), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  Text(
                    subtitle,
                    style: AppText.body(
                        size: 16, color: AppColors.cream.withValues(alpha: 0.85)),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  NeonButton(
                    label: buttonLabel,
                    color: AppColors.seafoam,
                    onPressed: () {
                      SoundService.instance.click();
                      onReady();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
