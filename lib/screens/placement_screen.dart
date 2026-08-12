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

  @override
  void initState() {
    super.initState();
    final controller = context.read<GameController>();
    _board = widget.isPlayer2 ? controller.boards[1] : controller.boards[0];
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
    if (r == ship.row && c == ship.col) return;
    _board.removeShip(kind);
    if (_board.canPlace(ship.spec, r, c, ship.horizontal)) {
      _board.place(ship.spec, r, c, ship.horizontal);
      SoundService.instance.place();
    } else {
      _board.place(ship.spec, ship.row, ship.col, ship.horizontal);
      SoundService.instance.denied();
    }
    setState(() {});
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

  void _randomize() {
    SoundService.instance.click();
    setState(() {
      _selected = null;
      _board.ships.clear();
      _board.ships.addAll(Board.random().ships);
    });
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

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileStore>();
    final controller = context.read<GameController>();
    final playerLabel = controller.mode == GameMode.local
        ? (widget.isPlayer2 ? 'PLAYER 2' : 'PLAYER 1')
        : profile.playerName.toUpperCase();

    if (_showHandoff) {
      return HandoffScreen(
        title: 'PASS THE DEVICE',
        subtitle: 'Player 2 — deploy your fleet in secret!',
        buttonLabel: 'PLAYER 2 READY',
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
        color: AppColors.coral,
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
                          onTap: () => Navigator.pop(context),
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
                      '$playerLabel — drag to move, tap ship to rotate',
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
                          onPressed: _randomize,
                        ),
                        const SizedBox(width: 12),
                        NeonButton(
                          label: _allPlaced
                              ? 'SAVE'
                              : 'SAVE  ${_board.ships.length}/5',
                          icon: Icons.bolt,
                          color: _allPlaced ? AppColors.green : AppColors.inkSoft,
                          onPressed: _allPlaced ? _save : null,
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
                        skin: profile.shipSkin,
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
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: DragTarget<({ShipKind kind, bool horizontal})>(
                      onWillAcceptWithDetails: (_) => true,
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
                          setState(() => _selected = null);
                        } else {
                          SoundService.instance.denied();
                        }
                      },
                      builder: (context, candidates, rejected) {
                        return Container(
                          key: _gridKey,
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: BattleGrid(
                            shots: List.generate(kBoardSize,
                                (_) => List.filled(kBoardSize, 0)),
                            ships: _board.ships,
                            skin: profile.shipSkin,
                            onTapCell: _onGridTap,
                            onShipTap: _rotateShip,
                            onShipDragEnd: _moveShip,
                          ),
                        );
                      },
                    ),
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
  final VoidCallback onTap;

  const _DockShip({
    required this.spec,
    required this.skin,
    required this.placed,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final icon = AnimatedShip(spec: spec, skin: skin, size: 56);

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
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.85,
          child: AnimatedShip(spec: spec, skin: skin, size: 90),
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
        color: AppColors.navy,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.screen_rotation,
                      size: 64, color: AppColors.cream),
                  const SizedBox(height: 24),
                  Text(title,
                      style: AppText.title(size: 24), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  Text(
                    subtitle,
                    style: AppText.body(color: AppColors.cream.withValues(alpha: 0.8)),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  NeonButton(
                    label: buttonLabel,
                    icon: Icons.play_arrow,
                    color: AppColors.green,
                    onPressed: onReady,
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
