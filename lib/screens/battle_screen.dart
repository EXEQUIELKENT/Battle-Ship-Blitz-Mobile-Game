import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/game_models.dart';
import '../services/game_controller.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../widgets/battle_grid.dart';
import '../widgets/cannon_widget.dart';
import '../widgets/neon_widgets.dart';
import '../widgets/ship_painter.dart';
import 'result_screen.dart';

/// Battle arena in the reference layout:
///  • Enemy waters grid (top) — TAP A CELL TO FIRE instantly.
///  • Middle dock band — ship status + big animated cannon button(s).
///  • Your fleet grid (bottom) — same size as the top grid.
/// In local pass-and-play, the viewing player's own fleet stays hidden
/// until they fire, then the screen flips to the other player.
class BattleScreen extends StatefulWidget {
  const BattleScreen({super.key});

  @override
  State<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends State<BattleScreen> {
  final _cannon1Fire = StreamController<void>.broadcast();
  final _cannon2Fire = StreamController<void>.broadcast();
  bool _p2View = false; // local mode perspective
  bool _navigatedToResult = false;

  /// Local mode: whether the viewing player has revealed their fleet
  /// (their grid stays hidden until they fire at least once).
  bool _p1Revealed = false;
  bool _p2Revealed = false;

  @override
  void initState() {
    super.initState();
    context.read<GameController>().addListener(_onUpdate);
  }

  void _onUpdate() {
    final controller = context.read<GameController>();
    if (controller.events.isNotEmpty) {
      final e = controller.events.last;
      if (DateTime.now().difference(e.time).inMilliseconds < 150) {
        (e.byPlayer ? _cannon1Fire : _cannon2Fire).add(null);
      }
    }
    if (controller.phase == BattlePhase.finished && !_navigatedToResult) {
      _navigatedToResult = true;
      Future.delayed(const Duration(milliseconds: 1400), () {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ResultScreen()),
        );
      });
    }
  }

  @override
  void dispose() {
    _cannon1Fire.close();
    _cannon2Fire.close();
    super.dispose();
  }

  List<CombatEventLike> _eventsFor(GameController c, bool p1) => c.events
      .where((e) => e.byPlayer == p1)
      .map((e) => CombatEventLike(e.row, e.col, e.result))
      .toList();

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.navy,
        duration: const Duration(milliseconds: 900),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.outline, width: 2),
        ),
      ));
  }

  /// Tap-to-fire: tapping a cell on the enemy grid fires immediately.
  void _fireAtCell(GameController controller, bool showingP1, int r, int c) {
    final trackingGrid = showingP1 ? controller.myShots : controller.p2Shots;
    if (trackingGrid[r][c] != 0) {
      _toast('Already fired there!');
      SoundService.instance.denied();
      return;
    }
    final res =
        showingP1 ? controller.fireAt(r, c) : controller.p2FireAt(r, c);
    if (res == ShotResult.cooldown) {
      _toast('Cannon reloading…');
      return;
    }
    if (res == ShotResult.duplicate) {
      _toast('Already fired there!');
      return;
    }
    // Local pass-and-play: mark this player's fleet as revealed, then
    // hand the device to the other player after a beat so they can see
    // the result of their shot first.
    if (controller.mode == GameMode.local) {
      setState(() {
        if (showingP1) {
          _p1Revealed = true;
        } else {
          _p2Revealed = true;
        }
      });
      Future.delayed(const Duration(milliseconds: 650), () {
        if (!mounted || controller.phase != BattlePhase.battling) return;
        setState(() => _p2View = !_p2View);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GameController>();
    final profile = context.watch<ProfileStore>();
    final isLocal = controller.mode == GameMode.local;
    final showingP1 = !isLocal || !_p2View;

    final trackingGrid = showingP1 ? controller.myShots : controller.p2Shots;
    final ownBoard = showingP1 ? controller.boards[0] : controller.boards[1];
    final enemyTracking = showingP1 ? controller.p2Shots : controller.myShots;
    final cooldown =
        showingP1 ? controller.cooldownFraction1 : controller.cooldownFraction2;
    final cannonStream = showingP1 ? _cannon1Fire : _cannon2Fire;
    final boardForStatus =
        showingP1 ? controller.boards[1] : controller.boards[0];

    // Local mode: the viewing player's own fleet stays hidden until they
    // fire their first shot (keeps ship locations secret on hand-off).
    final ownRevealed = !isLocal || (showingP1 ? _p1Revealed : _p2Revealed);

    // In local pass-and-play, player 2 sits on the opposite side of the
    // device — flip the whole play area 180° so it reads upright for them.
    final flipped = isLocal && !showingP1;

    final playArea = Column(
      children: [
        const SizedBox(height: 8),
        // ---------- HUD (no timer — RP + turn chip + exit) ----------
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              HudChip(
                icon: Icons.star,
                text: '${profile.rp} RP',
                color: AppColors.gold,
              ),
              const SizedBox(width: 8),
              HudChip(
                icon: Icons.person,
                text: isLocal
                    ? (showingP1 ? 'P1 TURN' : 'P2 TURN')
                    : profile.playerName.toUpperCase(),
                color: showingP1 ? AppColors.blue : AppColors.green,
              ),
              const Spacer(),
              _ExitButton(onTap: () => _confirmSurrender(controller)),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // ---------- Enemy waters (tap to fire) ----------
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: BattleGrid(
                  key: ValueKey('enemy-$showingP1'),
                  shots: trackingGrid,
                  glowColor: AppColors.water,
                  recentEvents: _eventsFor(controller, showingP1),
                  enabled: controller.battling,
                  onTapCell: (r, c) =>
                      _fireAtCell(controller, showingP1, r, c),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),

        // ---------- Middle band: status dots + big cannon ----------
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: const BoxDecoration(
            color: AppColors.coralLight,
            border: Border(
              top: BorderSide(color: AppColors.outline, width: 3),
              bottom: BorderSide(color: AppColors.outline, width: 3),
            ),
          ),
          child: Row(
            children: [
              _StatusDot(
                  color: AppColors.green, count: 5 - controller.enemySunk),
              const SizedBox(width: 6),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final spec in kFleet)
                        _DockStatusIcon(
                          spec: spec,
                          skin: profile.shipSkin,
                          sunk: boardForStatus
                                  .shipOfKind(spec.kind)
                                  ?.isSunk ??
                              false,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _StatusDot(color: AppColors.hit, count: 5 - controller.mySunk),
              const SizedBox(width: 10),
              CannonWidget(
                skin: profile.cannonSkin,
                cooldownFraction: cooldown,
                enabled: controller.battling,
                size: 84,
                fireTrigger: cannonStream.stream,
                onFire: () => _toast('Tap the enemy grid to fire!'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),

        // ---------- Your fleet (same size; hidden until you fire) ----------
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: ownRevealed
                    ? BattleGrid(
                        key: ValueKey('own-$showingP1'),
                        shots: enemyTracking,
                        ships: ownBoard.ships,
                        skin: profile.shipSkin,
                        enabled: false,
                        glowColor: AppColors.waterLight,
                        recentEvents: _eventsFor(controller, !showingP1),
                      )
                    : _HiddenFleet(
                        label:
                            '${showingP1 ? 'PLAYER 1' : 'PLAYER 2'}\nTAP THE TOP GRID TO FIRE',
                      ),
              ),
            ),
          ),
        ),
      ],
    );

    return Scaffold(
      body: Container(
        color: AppColors.coral,
        child: SafeArea(
          child: flipped
              ? RotatedBox(quarterTurns: 2, child: playArea)
              : playArea,
        ),
      ),
    );
  }

  void _confirmSurrender(GameController controller) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navy,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.outline, width: 3),
        ),
        title: Text('SURRENDER?', style: AppText.heading(size: 16)),
        content: Text(
          'Abandon the battle?\nThis counts as a loss.',
          style: AppText.body(size: 13, color: AppColors.cream.withValues(alpha: 0.85)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('FIGHT ON', style: AppText.label(color: AppColors.green)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              controller.surrender();
            },
            child: Text('SURRENDER', style: AppText.label(color: AppColors.hit)),
          ),
        ],
      ),
    );
  }
}

/// Cover panel shown over the viewing player's fleet until they fire.
/// Renders an empty water grid (so the layout matches) with a centered
/// lock + instruction chip on top.
class _HiddenFleet extends StatelessWidget {
  final String label;
  const _HiddenFleet({required this.label});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Empty water grid underneath (same chunky cells, no ships).
        BattleGrid(
          shots: List.generate(kBoardSize, (_) => List.filled(kBoardSize, 0)),
          enabled: false,
          glowColor: AppColors.waterLight,
        ),
        // Frosted cover.
        Container(
          decoration: BoxDecoration(
            color: AppColors.navyDeep.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.cream,
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: AppColors.outline, width: 3),
                  ),
                  child: const Icon(Icons.visibility_off,
                      color: AppColors.outline, size: 34),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.navy,
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: AppColors.outline, width: 2.5),
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: AppText.label(size: 11, color: AppColors.cream),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Small round score dot (green = your fleet alive count, red = enemy).
class _StatusDot extends StatelessWidget {
  final Color color;
  final int count;
  const _StatusDot({required this.color, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: AppColors.cream,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.outline, width: 2.5),
      ),
      child: Center(
        child: Text(
          '$count',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 14,
            color: color,
          ),
        ),
      ),
    );
  }
}

/// Tiny flat ship icon in the status dock. Alive = full color,
/// sunk = faded with an X.
class _DockStatusIcon extends StatelessWidget {
  final ShipSpec spec;
  final ShipSkin skin;
  final bool sunk;

  const _DockStatusIcon({
    required this.spec,
    required this.skin,
    required this.sunk,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: sunk ? 0.25 : 1,
            child: AnimatedShip(spec: spec, skin: skin, size: 44),
          ),
          if (sunk)
            const Icon(Icons.close, color: AppColors.hit, size: 26),
        ],
      ),
    );
  }
}

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
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: AppColors.cream,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.outline, width: 2.5),
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
                fontSize: 10,
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
