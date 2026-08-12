import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../services/game_controller.dart';
import '../services/storage_service.dart';
import '../widgets/neon_widgets.dart';
import '../widgets/ocean_background.dart';

/// Victory / defeat screen — cartoon badge, RP reveal, chunky buttons.
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
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // ---- Banner badge ----
                      ScaleTransition(
                        scale: CurvedAnimation(
                          parent: _revealCtrl,
                          curve: Curves.elasticOut,
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 110,
                              height: 110,
                              decoration: BoxDecoration(
                                color:
                                    won ? AppColors.gold : AppColors.inkSoft,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: AppColors.outline, width: 4),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x55000000),
                                    offset: Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: Icon(
                                won ? Icons.emoji_events : Icons.anchor,
                                size: 56,
                                color: AppColors.cream,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              won ? 'VICTORY!' : 'DEFEAT',
                              style: AppText.title(
                                size: 36,
                                color: won ? AppColors.navy : AppColors.hit,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              controller.endReason,
                              style: AppText.body(
                                  size: 13, color: AppColors.navy),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ---- RP reveal panel ----
                      FadeTransition(
                        opacity: CurvedAnimation(
                          parent: _revealCtrl,
                          curve: const Interval(0.4, 1),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 22, vertical: 16),
                          decoration: cartoonBox(AppColors.navy, radius: 18),
                          child: Column(
                            children: [
                              Text(
                                'RANK POINTS',
                                style: AppText.label(
                                  size: 10,
                                  color:
                                      AppColors.cream.withValues(alpha: 0.75),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${controller.rpDelta >= 0 ? '+' : ''}${controller.rpDelta} RP',
                                style: AppText.title(
                                  size: 30,
                                  color: controller.rpDelta >= 0
                                      ? AppColors.gold
                                      : AppColors.hit,
                                ),
                              ),
                              if (won && profile.streak >= 2) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'STREAK x${profile.streak}  (+${profile.streakBonus} bonus)',
                                  style: AppText.label(
                                      size: 10, color: AppColors.hitGlow),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Text(
                                '${profile.rankTitle}  •  ${profile.rp} RP',
                                style: AppText.body(
                                    size: 12, color: AppColors.cream),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ---- Battle summary ----
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration:
                            cartoonBox(AppColors.coralLight, radius: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _summaryPip('ENEMY SUNK',
                                '${controller.mySunk}/5', AppColors.hit),
                            Container(
                                width: 2,
                                height: 34,
                                color: AppColors.outline),
                            _summaryPip('FLEET LOST',
                                '${controller.enemySunk}/5', AppColors.navy),
                          ],
                        ),
                      ),
                      const SizedBox(height: 26),

                      // ---- Actions ----
                      Row(
                        children: [
                          Expanded(
                            child: NeonButton(
                              label: 'REMATCH',
                              icon: Icons.refresh,
                              color: AppColors.green,
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
                              color: AppColors.blue,
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
      ),
    );
  }

  Widget _summaryPip(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: AppText.heading(size: 20, color: color)),
        const SizedBox(height: 2),
        Text(label, style: AppText.label(size: 9, color: AppColors.navy)),
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
          const Color(0xFFF7B32B), // gold
          const Color(0xFF35A3D6), // ship blue
          const Color(0xFFF25F5C), // ship red
          const Color(0xFF3CB54A), // green
          const Color(0xFFFFF4EC), // cream
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
