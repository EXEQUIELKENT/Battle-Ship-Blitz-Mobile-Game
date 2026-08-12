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
import '../widgets/ocean_background.dart';
import 'battle_screen.dart';

/// Ship placement phase. In local mode both players place in turns
/// (with a pass-the-device handoff). In network mode the board is
/// transmitted to the peer once confirmed.
class PlacementScreen extends StatefulWidget {
  final bool isPlayer2; // local mode: second player's turn

  const PlacementScreen({super.key, this.isPlayer2 = false});

  @override
  State<PlacementScreen> createState() => _PlacementScreenState();
}

class _PlacementScreenState extends State<PlacementScreen> {
  int _selectedIndex = 0; // index into kFleet of ship being placed
  bool _horizontal = true;
  List<int>? _hover;
  late Board _board;
  bool _showHandoff = false;

  @override
  void initState() {
    super.initState();
    final controller = context.read<GameController>();
    _board = widget.isPlayer2 ? controller.boards[1] : controller.boards[0];
    // Skip already placed ships (e.g. after randomize)
    _selectedIndex = kFleet.indexWhere(
        (s) => _board.shipOfKind(s.kind) == null);
    if (_selectedIndex < 0) _selectedIndex = 0;
  }

  ShipSpec? get _currentSpec {
    for (final spec in kFleet) {
      if (_board.shipOfKind(spec.kind) == null) return spec;
    }
    return null;
  }

  bool get _allPlaced => _board.isComplete;

  void _onCellTap(int r, int c) {
    final spec = _currentSpec;
    if (spec == null) return;
    if (_board.canPlace(spec, r, c, _horizontal)) {
      _board.place(spec, r, c, _horizontal);
      SoundService.instance.place();
      setState(() {});
    } else {
      // Tapping an existing ship removes it for repositioning
      final existing = _board.shipAt(r, c);
      if (existing != null) {
        _board.removeShip(existing.spec.kind);
        SoundService.instance.click();
        setState(() {});
      } else {
        SoundService.instance.denied();
      }
    }
  }

  void _randomize() {
    SoundService.instance.click();
    setState(() {
      _board.ships.clear();
      final fresh = Board.random();
      _board.ships.addAll(fresh.ships);
    });
  }

  void _clear() {
    SoundService.instance.click();
    setState(() => _board.ships.clear());
  }

  PlacedShip? get _preview {
    final spec = _currentSpec;
    if (spec == null || _hover == null) return null;
    return PlacedShip(
      spec: spec,
      row: _hover![0],
      col: _hover![1],
      horizontal: _horizontal,
    );
  }

  Future<void> _confirm() async {
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
          // Hand device to player 2
          setState(() => _showHandoff = true);
        } else {
          controller.beginBattle(enemyBoard: controller.boards[1]);
          _goBattle();
        }
        break;
      case GameMode.hotspot:
      case GameMode.online:
        // Send board to peer; wait for theirs.
        controller.network.sendBoard(_board);
        _waitForPeerBoard(controller);
        break;
    }
  }

  void _waitForPeerBoard(GameController controller) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        late StreamSubscription sub;
        sub = controller.network.messages.listen((msg) {
          if (msg['type'] == 'board') {
            final enemyBoard = Board.fromJson(
                Map<String, dynamic>.from(msg['b'] as Map));
            sub.cancel();
            if (ctx.mounted) Navigator.pop(ctx);
            controller.attachNetwork();
            controller.beginBattle(enemyBoard: enemyBoard);
            _goBattle();
          }
        });
        return AlertDialog(
          backgroundColor: AppColors.deepSea,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: AppColors.sonar.withValues(alpha: 0.5)),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.sonar),
              const SizedBox(height: 16),
              Text('WAITING FOR OPPONENT\'S FLEET…',
                  style: AppText.label(color: AppColors.radar)),
            ],
          ),
        );
      },
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
      return _HandoffScreen(
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
      body: OceanBackground(
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 10),
              // ---- Header ----
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: AppColors.steel),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text('DEPLOY YOUR FLEET',
                              style: AppText.heading(
                                  size: 16, color: AppColors.radar)),
                          Text(
                            '$playerLabel • ${_board.ships.length}/5 SHIPS',
                            style: AppText.label(size: 10),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Rotate',
                      icon: Icon(
                        _horizontal ? Icons.swap_horiz : Icons.swap_vert,
                        color: AppColors.ember,
                      ),
                      onPressed: () {
                        SoundService.instance.click();
                        setState(() => _horizontal = !_horizontal);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              // ---- Grid ----
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: BattleGrid(
                      shots: List.generate(
                          kBoardSize, (_) => List.filled(kBoardSize, 0)),
                      ships: _board.ships,
                      skin: profile.shipSkin,
                      onTapCell: _onCellTap,
                      onHoverCell: (r, c, hover) {
                        setState(() => _hover = hover ? [r, c] : null);
                      },
                      hoverCell: _hover,
                      previewShip: _preview,
                      previewValid: _preview != null &&
                          _board.canPlace(_preview!.spec, _preview!.row,
                              _preview!.col, _preview!.horizontal),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // ---- Current ship hint ----
              Text(
                _currentSpec == null
                    ? 'FLEET READY — TAP A SHIP TO MOVE IT'
                    : 'TAP GRID TO PLACE: ${_currentSpec!.name.toUpperCase()} (${_currentSpec!.size})  •  ${_horizontal ? "HORIZONTAL" : "VERTICAL"}',
                style: AppText.label(size: 10, color: AppColors.ember),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              // ---- Fleet tray ----
              SizedBox(
                height: 62,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  itemCount: kFleet.length,
                  itemBuilder: (context, i) {
                    final spec = kFleet[i];
                    final placed = _board.shipOfKind(spec.kind) != null;
                    final isNext = _currentSpec?.kind == spec.kind;
                    return Container(
                      width: 86,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: placed
                            ? AppColors.victory.withValues(alpha: 0.12)
                            : isNext
                                ? AppColors.ember.withValues(alpha: 0.15)
                                : AppColors.ink.withValues(alpha: 0.5),
                        border: Border.all(
                          color: placed
                              ? AppColors.victory.withValues(alpha: 0.7)
                              : isNext
                                  ? AppColors.ember
                                  : AppColors.fog.withValues(alpha: 0.4),
                          width: isNext ? 1.6 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            placed ? Icons.check_circle : Icons.directions_boat,
                            size: 16,
                            color: placed ? AppColors.victory : AppColors.steel,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${spec.shortName} · ${spec.size}',
                            style: AppText.label(
                              size: 9,
                              color: placed ? AppColors.victory : AppColors.mist,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              // ---- Actions ----
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                child: Row(
                  children: [
                    NeonButton(
                      label: 'RANDOM',
                      icon: Icons.shuffle,
                      color: AppColors.radar,
                      compact: true,
                      onPressed: _randomize,
                    ),
                    const SizedBox(width: 10),
                    NeonButton(
                      label: 'CLEAR',
                      icon: Icons.delete_outline,
                      color: AppColors.danger,
                      compact: true,
                      onPressed: _clear,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: NeonButton(
                        label: _allPlaced ? 'TO BATTLE ⚔️' : 'PLACE ALL SHIPS',
                        color: AppColors.ember,
                        compact: true,
                        onPressed: _allPlaced ? _confirm : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Interstitial shown when passing the device between local players.
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
    return _HandoffScreen(
      title: title,
      subtitle: subtitle,
      buttonLabel: buttonLabel,
      onReady: onReady,
    );
  }
}

class _HandoffScreen extends StatelessWidget {
  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback onReady;

  const _HandoffScreen({
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onReady,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: OceanBackground(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.screen_rotation,
                      size: 64, color: AppColors.sonar),
                  const SizedBox(height: 24),
                  Text(title, style: AppText.title(size: 22)),
                  const SizedBox(height: 12),
                  Text(
                    subtitle,
                    style: AppText.body(),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  NeonButton(
                    label: buttonLabel,
                    icon: Icons.play_arrow,
                    color: AppColors.victory,
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
