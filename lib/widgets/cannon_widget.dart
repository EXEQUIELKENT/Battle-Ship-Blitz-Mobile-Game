import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/storage_service.dart';

/// Big round cartoon FIRE button (reference-style): thick black ring,
/// cannon-barrel center, cooldown sweep around the rim, recoil squash.
class CannonWidget extends StatefulWidget {
  final CannonSkin skin;
  final double cooldownFraction; // 0 = reloading, 1 = ready
  final bool enabled;
  final VoidCallback? onFire;
  final String label;
  final double size;
  final Stream<void>? fireTrigger;

  const CannonWidget({
    super.key,
    required this.skin,
    required this.cooldownFraction,
    this.enabled = true,
    this.onFire,
    this.label = 'FIRE',
    this.size = 92,
    this.fireTrigger,
  });

  @override
  State<CannonWidget> createState() => _CannonWidgetState();
}

class _CannonWidgetState extends State<CannonWidget>
    with TickerProviderStateMixin {
  late final AnimationController _recoil;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _recoil = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    widget.fireTrigger?.listen((_) => fire());
  }

  @override
  void dispose() {
    _recoil.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void fire() {
    _recoil.forward(from: 0).then((_) => _recoil.reverse());
  }

  @override
  Widget build(BuildContext context) {
    final ready = widget.cooldownFraction >= 1 && widget.enabled;
    return AnimatedBuilder(
      animation: Listenable.merge([_recoil, _pulse]),
      builder: (context, _) {
        final squash = 1 - _recoil.value * 0.12;
        final pulseScale = ready ? 1 + _pulse.value * 0.04 : 1.0;
        return GestureDetector(
          onTap: ready ? widget.onFire : null,
          child: Transform.scale(
            scale: squash * pulseScale,
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: CustomPaint(
                painter: _FireButtonPainter(
                  skin: widget.skin,
                  cooldown: widget.cooldownFraction,
                  recoil: _recoil.value,
                  ready: ready,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FireButtonPainter extends CustomPainter {
  final CannonSkin skin;
  final double cooldown;
  final double recoil;
  final bool ready;

  _FireButtonPainter({
    required this.skin,
    required this.cooldown,
    required this.recoil,
    required this.ready,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = size.width * 0.48;

    // Soft ground shadow ellipse (reference style)
    canvas.drawOval(
      Rect.fromCenter(
        center: center + Offset(0, outerR * 0.30),
        width: outerR * 2.3,
        height: outerR * 1.0,
      ),
      Paint()..color = AppColors.coralDeep.withValues(alpha: 0.55),
    );

    // Thick outer black ring
    canvas.drawCircle(center, outerR, Paint()..color = AppColors.outline);

    // Cooldown progress ring inside the black ring
    final ringR = outerR * 0.86;
    canvas.drawCircle(
      center,
      ringR,
      Paint()
        ..color = AppColors.navyDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = outerR * 0.16,
    );
    final progressPaint = Paint()
      ..color = ready ? skin.projectile : AppColors.waterLight
      ..style = PaintingStyle.stroke
      ..strokeWidth = outerR * 0.16
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: ringR),
      -math.pi / 2,
      2 * math.pi * cooldown,
      false,
      progressPaint,
    );

    // Inner dome (cannon mouth)
    final domeR = outerR * 0.62;
    canvas.drawCircle(
        center, domeR, Paint()..color = ready ? AppColors.navy : AppColors.inkSoft);
    canvas.drawCircle(
      center,
      domeR,
      Paint()
        ..color = AppColors.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    // Barrel slit
    final slit = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center - Offset(0, domeR * 0.12),
        width: domeR * 0.5,
        height: domeR * 1.05,
      ),
      Radius.circular(domeR * 0.22),
    );
    canvas.drawRRect(slit, Paint()..color = AppColors.outline);
    // Highlight dot
    canvas.drawCircle(
      center + Offset(-domeR * 0.3, -domeR * 0.38),
      domeR * 0.16,
      Paint()..color = Colors.white.withValues(alpha: ready ? 0.5 : 0.2),
    );

    // Muzzle flash while recoiling
    if (recoil > 0.05) {
      final flashCenter = center - Offset(0, outerR * 1.15);
      canvas.drawCircle(
        flashCenter,
        outerR * (0.30 + recoil * 0.45),
        Paint()..color = skin.projectile.withValues(alpha: (1 - recoil) * 0.9),
      );
      final star = Paint()
        ..color = Colors.white.withValues(alpha: (1 - recoil))
        ..strokeWidth = 3.4
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 6; i++) {
        final a = -math.pi / 2 + (i - 2.5) * 0.4;
        final l = outerR * 0.4 * recoil;
        canvas.drawLine(flashCenter,
            flashCenter + Offset(math.cos(a) * l, math.sin(a) * l), star);
      }
    }
  }

  @override
  bool shouldRepaint(_FireButtonPainter oldDelegate) => true;
}
