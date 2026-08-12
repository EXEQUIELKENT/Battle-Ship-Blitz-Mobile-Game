import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../services/game_controller.dart';
import '../services/storage_service.dart';
import '../widgets/neon_widgets.dart';
import '../widgets/ocean_background.dart';

/// Victory / defeat screen with animated RP reveal and confetti.
class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen>
    with TickerProviderStateMixin {
  late final AnimationController _confettiCtrl;
  late final AnimationController _revealCtrl;
  final List<_Confetti> _confetti = [];
  final Random _rng = Random();

  @override
  void initState() {
    super.initState();
    _confettiCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
    _revealCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    for (var i = 0; i < 60; i++) {
      _confetti.add(_Confetti(_rng));
    }
  }

  @override
  void dispose() {
    _confettiCtrl.dispose();
    _revealCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.read<GameController>();
    final profile = context.watch<ProfileStore>();
    final won = controller.iWon;

    return Scaffold(
      body: OceanBackground(
        showSonar: false,
        child: SafeArea(
          child: AnimatedBuilder(
            animation: _confettiCtrl,
            builder: (context, child) {
              return CustomPaint(
                painter: _ConfettiPainter(
                  _confetti,
                  _confettiCtrl.value,
                  active: won,
                ),
                child: child,
              );
            },
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ---- Banner ----
                    ScaleTransition(
                      scale: CurvedAnimation(
                        parent: _revealCtrl,
                        curve: Curves.elasticOut,
                      ),
                      child: Column(
                        children: [
                          Text(
                            won ? '🏆' : '☠️',
                            style: const TextStyle(fontSize: 64),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            won ? 'VICTORY!' : 'DEFEAT',
                            style: AppText.title(
                              size: 36,
                              color: won ? AppColors.gold : AppColors.danger,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            controller.endReason,
                            style: AppText.body(size: 13),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 26),

                    // ---- RP reveal ----
                    FadeTransition(
                      opacity: CurvedAnimation(
                        parent: _revealCtrl,
                        curve: const Interval(0.4, 1),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 14),
                        decoration: BoxDecoration(
                          color: AppColors.ink.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: (controller.rpDelta >= 0
                                    ? AppColors.gold
                                    : AppColors.danger)
                                .withValues(alpha: 0.7),
                            width: 1.4,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text('RANK POINTS',
                                style: AppText.label(size: 10)),
                            const SizedBox(height: 6),
                            Text(
                              '${controller.rpDelta >= 0 ? '+' : ''}${controller.rpDelta} RP',
                              style: AppText.title(
                                size: 30,
                                color: controller.rpDelta >= 0
                                    ? AppColors.gold
                                    : AppColors.danger,
                              ),
                            ),
                            if (won && profile.streak >= 2) ...[
                              const SizedBox(height: 4),
                              Text(
                                '🔥 STREAK x${profile.streak}  (+${profile.streakBonus} bonus)',
                                style: AppText.label(
                                    size: 10, color: AppColors.fire),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Text(
                              '${profile.rankTitle}  •  ${profile.rp} RP',
                              style:
                                  AppText.body(size: 12, color: AppColors.radar),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),

                    // ---- Battle summary ----
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _summaryPip('ENEMY SUNK', '${controller.mySunk}/5',
                            AppColors.ember),
                        const SizedBox(width: 16),
                        _summaryPip('FLEET LOST', '${controller.enemySunk}/5',
                            AppColors.sonar),
                      ],
                    ),
                    const SizedBox(height: 30),

                    // ---- Actions ----
                    Row(
                      children: [
                        Expanded(
                          child: NeonButton(
                            label: 'REMATCH',
                            icon: Icons.refresh,
                            color: AppColors.victory,
                            onPressed: () {
                              controller.reset();
                              Navigator.of(context)
                                  .popUntil((route) => route.isFirst);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: NeonButton(
                            label: 'MAIN MENU',
                            icon: Icons.home,
                            color: AppColors.sonar,
                            onPressed: () {
                              controller.reset();
                              Navigator.of(context)
                                  .popUntil((route) => route.isFirst);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _summaryPip(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: AppText.heading(size: 20, color: color)),
        const SizedBox(height: 2),
        Text(label, style: AppText.label(size: 9)),
      ],
    );
  }
}

class _Confetti {
  double x, y, speed, size, rot, rotSpeed;
  Color color;

  _Confetti(Random rng)
      : x = rng.nextDouble(),
        y = rng.nextDouble() * -1,
        speed = 0.3 + rng.nextDouble() * 0.7,
        size = 4 + rng.nextDouble() * 6,
        rot = rng.nextDouble() * 2 * pi,
        rotSpeed = (rng.nextDouble() - 0.5) * 4,
        color = [
          const Color(0xFFFBBF24),
          const Color(0xFF22D3EE),
          const Color(0xFFFF6B35),
          const Color(0xFF34D399),
          const Color(0xFFE11D48),
        ][rng.nextInt(5)];
}

class _ConfettiPainter extends CustomPainter {
  final List<_Confetti> confetti;
  final double t;
  final bool active;

  _ConfettiPainter(this.confetti, this.t, {required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    if (!active) return;
    for (final c in confetti) {
      final y = ((c.y + t * c.speed * 2) % 1.3) * size.height;
      final x = c.x * size.width + sin(t * 4 + c.rot) * 22;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(c.rot + t * c.rotSpeed);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: c.size, height: c.size * 0.6),
        Paint()..color = c.color.withValues(alpha: 0.85),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) => true;
}
