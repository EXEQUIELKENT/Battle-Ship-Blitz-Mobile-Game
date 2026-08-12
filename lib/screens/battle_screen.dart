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
/// enemy targeting grid on top (crosshair + big FIRE button),
/// ship-status dock in the middle, your fleet grid at the bottom.
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
  List<int>? _aim1; // P1 crosshair cell
  List<int>? _aim2; // P2 crosshair cell

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
    final aim = showingP1 ? _aim1 : _aim2;
    final boardForStatus =
        showingP1 ? controller.boards[1] : controller.boards[0];

    return Scaffold(
      body: Container(
        color: AppColors.coral,
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
                          ? AppColors.hit
                          : AppColors.navy,
                      pulse: controller.timeLeft <= 30,
                    ),
                    const SizedBox(width: 8),
                    HudChip(
                      icon: Icons.star,
                      text: '${profile.rp} RP',
                      color: AppColors.gold,
                    ),
                    const Spacer(),
                    if (isLocal)
                      GestureDetector(
                        onTap: () {
                          SoundService.instance.click();
                          setState(() => _p2View = !_p2View);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: _p2View ? AppColors.green : AppColors.blue,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: AppColors.outline, width: 2.5),
                            boxShadow: const [
                              BoxShadow(
                                  color: Color(0x44000000),
                                  offset: Offset(0, 3)),
                            ],
                          ),
                          child: Text(
                            _p2View ? 'P2 🎮' : 'P1 🎮',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              color: AppColors.cream,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    _ExitButton(onTap: () => _confirmSurrender(controller)),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // ---------- Enemy waters (targeting) ----------
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Center(
                    child: BattleGrid(
                      shots: trackingGrid,
                      glowColor: AppColors.water,
                      crosshair: aim,
                      recentEvents: _eventsFor(controller, showingP1),
                      enabled: controller.battling,
                      onTapCell: (r, c) {
                        if (trackingGrid[r][c] != 0) {
                          _toast('Already fired there!');
                          SoundService.instance.denied();
                          return;
                        }
                        SoundService.instance.click();
                        setState(() {
                          if (showingP1) {
                            _aim1 = [r, c];
                          } else {
                            _aim2 = [r, c];
                          }
                        });
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // ---------- Ship status dock + FIRE button ----------
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                        color: AppColors.green,
                        count: 5 - controller.enemySunk),
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
                                revealed: _shipRevealed(
                                    controller, boardForStatus, spec),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _StatusDot(
                        color: AppColors.hit, count: 5 - controller.mySunk),
                    const SizedBox(width: 8),
                    // Big FIRE button
                    CannonWidget(
                      skin: profile.cannonSkin,
                      cooldownFraction: cooldown,
                      enabled: controller.battling,
                      size: 76,
                      fireTrigger: cannonStream.stream,
                      onFire: () {
                        final target = showingP1 ? _aim1 : _aim2;
                        if (target == null) {
                          _toast('Tap the enemy grid to aim first!');
                          SoundService.instance.denied();
                          return;
                        }
                        final res = showingP1
                            ? controller.fireAt(target[0], target[1])
                            : controller.p2FireAt(target[0], target[1]);
                        if (res == ShotResult.cooldown) {
                          _toast('⏳ Cannon reloading…');
                        } else if (res == ShotResult.duplicate) {
                          _toast('Already fired there!');
                        } else {
                          setState(() {
                            if (showingP1) {
                              _aim1 = null;
                            } else {
                              _aim2 = null;
                            }
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // ---------- Your fleet ----------
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  child: Center(
                    child: BattleGrid(
                      shots: enemyTracking,
                      ships: ownBoard.ships,
                      skin: profile.shipSkin,
                      enabled: false,
                      glowColor: AppColors.waterLight,
                      recentEvents: _eventsFor(controller, !showingP1),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _shipRevealed(GameController c, Board enemyBoard, ShipSpec spec) {
    // For local/AI modes the enemy board is known locally — only reveal
    // fully sunk ships in the dock; network mode marks sunk ships too.
    final ship = enemyBoard.shipOfKind(spec.kind);
    return ship?.isSunk ?? false;
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
  final bool revealed;

  const _DockStatusIcon({
    required this.spec,
    required this.skin,
    required this.sunk,
    required this.revealed,
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
