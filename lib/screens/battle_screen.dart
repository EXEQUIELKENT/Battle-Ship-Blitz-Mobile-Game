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
import '../widgets/ocean_background.dart';
import 'result_screen.dart';

/// The real-time battle arena.
class BattleScreen extends StatefulWidget {
  const BattleScreen({super.key});

  @override
  State<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends State<BattleScreen> {
  final _cannon1Fire = StreamController<void>.broadcast();
  final _cannon2Fire = StreamController<void>.broadcast();
  bool _p2View = false; // local mode: show P2 perspective
  bool _navigatedToResult = false;

  @override
  void initState() {
    super.initState();
    final controller = context.read<GameController>();
    controller.addListener(_onUpdate);
  }

  void _onUpdate() {
    final controller = context.read<GameController>();
    // Cannon recoil when the most recent event is from that player
    if (controller.events.isNotEmpty) {
      final e = controller.events.last;
      if (DateTime.now().difference(e.time).inMilliseconds < 150) {
        if (e.byPlayer) {
          _cannon1Fire.add(null);
        } else {
          _cannon2Fire.add(null);
        }
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

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GameController>();
    final profile = context.watch<ProfileStore>();
    final isLocal = controller.mode == GameMode.local;

    // Decide which perspective renders the big grids.
    final showingP1 = !isLocal || !_p2View;

    final trackingGrid = showingP1 ? controller.myShots : controller.p2Shots;
    final ownBoard = showingP1 ? controller.boards[0] : controller.boards[1];
    final enemyTracking = showingP1 ? controller.p2Shots : controller.myShots;
    final cooldown = showingP1 ? controller.cooldownFraction1 : controller.cooldownFraction2;
    final cannonStream = showingP1 ? _cannon1Fire : _cannon2Fire;

    return Scaffold(
      body: OceanBackground(
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 8),
              // ---------- HUD ----------
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    HudChip(
                      icon: Icons.timer,
                      text: controller.timerText,
                      color: controller.timeLeft <= 30
                          ? AppColors.danger
                          : AppColors.sonar,
                      pulse: controller.timeLeft <= 30,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _FleetStatus(
                        mySunk: showingP1 ? controller.mySunk : controller.enemySunk,
                        enemySunk: showingP1 ? controller.enemySunk : controller.mySunk,
                        label: showingP1
                            ? profile.playerName.toUpperCase()
                            : 'PLAYER 2',
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _confirmSurrender(controller),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.ink.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppColors.danger.withValues(alpha: 0.6)),
                        ),
                        child: const Icon(Icons.flag,
                            color: AppColors.danger, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // ---------- Local-mode perspective toggle ----------
              if (isLocal)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: GestureDetector(
                    onTap: () {
                      SoundService.instance.click();
                      setState(() => _p2View = !_p2View);
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: (_p2View ? AppColors.victory : AppColors.sonar)
                            .withValues(alpha: 0.15),
                        border: Border.all(
                          color: _p2View ? AppColors.victory : AppColors.sonar,
                          width: 1.2,
                        ),
                      ),
                      child: Text(
                        _p2View
                            ? '🎮 PLAYER 2 CONSOLE — TAP TO SWITCH'
                            : '🎮 PLAYER 1 CONSOLE — TAP TO SWITCH',
                        textAlign: TextAlign.center,
                        style: AppText.label(
                          size: 10,
                          color: _p2View ? AppColors.victory : AppColors.radar,
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),

              // ---------- Target grid (fire here) ----------
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      Text(
                        '⌖ ENEMY WATERS — TAP TO FIRE',
                        style: AppText.label(size: 10, color: AppColors.ember),
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: Center(
                          child: BattleGrid(
                            shots: trackingGrid,
                            glowColor: AppColors.ember,
                            recentEvents: _eventsFor(controller, showingP1),
                            onTapCell: controller.battling
                                ? (r, c) {
                                    final res = showingP1
                                        ? controller.fireAt(r, c)
                                        : controller.p2FireAt(r, c);
                                    if (res == ShotResult.cooldown) {
                                      _toast('⏳ Cannon reloading…');
                                    } else if (res == ShotResult.duplicate) {
                                      _toast('Already fired there!');
                                    }
                                  }
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // ---------- Own fleet (mini) + cannon + log ----------
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Own fleet grid
                      Expanded(
                        flex: 5,
                        child: Column(
                          children: [
                            Text('YOUR FLEET',
                                style: AppText.label(
                                    size: 9, color: AppColors.sonar)),
                            const SizedBox(height: 4),
                            Expanded(
                              child: BattleGrid(
                                shots: enemyTracking,
                                ships: ownBoard.ships,
                                skin: profile.shipSkin,
                                enabled: false,
                                glowColor: AppColors.sonar,
                                recentEvents:
                                    _eventsFor(controller, !showingP1),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Cannon + cooldown
                      Expanded(
                        flex: 4,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CannonWidget(
                              skin: profile.cannonSkin,
                              cooldownFraction: cooldown,
                              enabled: controller.battling,
                              label: showingP1 ? 'FIRE' : 'P2 FIRE',
                              fireTrigger: cannonStream.stream,
                            ),
                            const SizedBox(height: 6),
                            _CooldownBar(fraction: cooldown),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Combat log
                      Expanded(
                        flex: 5,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.ink.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color:
                                    AppColors.sonarDim.withValues(alpha: 0.5)),
                          ),
                          child: ListView.builder(
                            reverse: false,
                            itemCount: controller.combatLog.length,
                            itemBuilder: (context, i) => Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text(
                                controller.combatLog[i],
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 9,
                                  height: 1.25,
                                  color: AppColors.mist,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        backgroundColor: AppColors.ink,
        duration: const Duration(milliseconds: 900),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: AppColors.ember.withValues(alpha: 0.6)),
        ),
      ));
  }

  void _confirmSurrender(GameController controller) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.deepSea,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.danger.withValues(alpha: 0.6)),
        ),
        title: Text('SURRENDER?',
            style: AppText.heading(size: 15, color: AppColors.danger)),
        content: Text(
          'Strike your colors and abandon the battle?\nThis counts as a loss.',
          style: AppText.body(size: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('FIGHT ON', style: AppText.label(color: AppColors.sonar)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              controller.surrender();
            },
            child: Text('SURRENDER', style: AppText.label(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }
}

/// Slim linear cooldown bar under the cannon.
class _CooldownBar extends StatelessWidget {
  final double fraction;
  const _CooldownBar({required this.fraction});

  @override
  Widget build(BuildContext context) {
    final ready = fraction >= 1;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 8,
        decoration: BoxDecoration(
          color: AppColors.ink,
          border: Border.all(color: AppColors.fog.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: fraction.clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: ready
                    ? [AppColors.ember, AppColors.gold]
                    : [AppColors.sonarDim, AppColors.sonar],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fleet destruction status: 5 pips per side.
class _FleetStatus extends StatelessWidget {
  final int mySunk; // enemy ships I destroyed
  final int enemySunk; // my ships destroyed
  final String label;

  const _FleetStatus({
    required this.mySunk,
    required this.enemySunk,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    Widget pips(int destroyed, Color alive, Color dead) => Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(5, (i) {
            final isDead = i < destroyed;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Icon(
                Icons.directions_boat,
                size: 13,
                color: isDead ? dead : alive,
              ),
            );
          }),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.ink.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.sonarDim.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.label(size: 8, color: AppColors.radar)),
              ),
              pips(enemySunk, AppColors.sonar, AppColors.danger),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('ENEMY', style: AppText.label(size: 8, color: AppColors.ember)),
              pips(mySunk, AppColors.ember, AppColors.danger),
            ],
          ),
        ],
      ),
    );
  }
}
