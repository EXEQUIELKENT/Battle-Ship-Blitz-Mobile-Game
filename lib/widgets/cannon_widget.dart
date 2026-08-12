import 'dart:math';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/storage_service.dart';

/// Animated cannon turret with:
///  - radial cooldown sweep
///  - aim rotation toward last tapped cell
///  - recoil + muzzle flash on fire
class CannonWidget extends StatefulWidget {
  final CannonSkin skin;
  final double cooldownFraction; // 0 = reloading, 1 = ready
  final bool enabled;
  final VoidCallback? onFire; // tap when ready fires forward
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
    this.size = 84,
    this.fireTrigger,
  });

  @override
  State<CannonWidget> createState() => _CannonWidgetState();
}

class _CannonWidgetState extends State<CannonWidget>
    with TickerProviderStateMixin {
  late final AnimationController _recoil;
  late final AnimationController _glow;
  double _aim = 0; // radians, 0 = straight up
  double _targetAim = 0;

  @override
  void initState() {
    super.initState();
    _recoil = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    widget.fireTrigger?.listen((_) => fire());
  }

  @override
  void didUpdateWidget(CannonWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cooldownFraction < 1 && widget.cooldownFraction >= 1) {
      // Ready flash
      _recoil.forward(from: 0).then((_) => _recoil.reverse());
    }
  }

  @override
  void dispose() {
    _recoil.dispose();
    _glow.dispose();
    super.dispose();
  }

  void aimAt(double radians) => setState(() => _targetAim = radians.clamp(-0.9, 0.9));

  void fire() {
    _recoil.forward(from: 0).then((_) => _recoil.reverse());
  }

  @override
  Widget build(BuildContext context) {
    final ready = widget.cooldownFraction >= 1;
    _aim += (_targetAim - _aim) * 0.25;

    return AnimatedBuilder(
      animation: Listenable.merge([_recoil, _glow]),
      builder: (context, _) {
        return GestureDetector(
          onTap: widget.enabled && ready ? widget.onFire : null,
          child: SizedBox(
            width: widget.size,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: widget.size,
                  height: widget.size,
                  child: CustomPaint(
                    painter: _CannonPainter(
                      skin: widget.skin,
                      cooldown: widget.cooldownFraction,
                      aim: _aim,
                      recoil: _recoil.value,
                      glowT: _glow.value,
                      ready: ready && widget.enabled,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  ready
                      ? widget.label
                      : 'RELOAD ${(widget.cooldownFraction * 100).round()}%',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                    color: ready ? AppColors.ember : AppColors.steel,
                    shadows: ready
                        ? [
                            Shadow(
                              color: AppColors.ember.withValues(alpha: 0.7),
                              blurRadius: 8,
                            )
                          ]
                        : null,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CannonPainter extends CustomPainter {
  final CannonSkin skin;
  final double cooldown;
  final double aim;
  final double recoil;
  final double glowT;
  final bool ready;

  _CannonPainter({
    required this.skin,
    required this.cooldown,
    required this.aim,
    required this.recoil,
    required this.glowT,
    required this.ready,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseR = size.width * 0.34;

    // ---- Cooldown sweep ring ----
    final ringR = size.width * 0.47;
    canvas.drawCircle(
      center,
      ringR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = AppColors.fog.withValues(alpha: 0.35),
    );
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round
      ..color = ready ? AppColors.ember : AppColors.sonar;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: ringR),
      -pi / 2,
      2 * pi * cooldown,
      false,
      arcPaint,
    );

    // ---- Ready glow pulse ----
    if (ready) {
      canvas.drawCircle(
        center,
        ringR * (1.0 + 0.06 * glowT),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = AppColors.ember.withValues(alpha: 0.35 + 0.3 * glowT),
      );
    }

    // ---- Rotating turret ----
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(aim);
    final kick = recoil * size.width * 0.07;

    // Barrel
    final barrelPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [skin.barrel.withValues(alpha: 0.95), Colors.black87],
      ).createShader(Rect.fromLTWH(-baseR * 0.16, -size.height * 0.44 + kick,
          baseR * 0.32, size.height * 0.44));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
            -baseR * 0.16, -size.height * 0.46 + kick, baseR * 0.32, size.height * 0.42),
        Radius.circular(baseR * 0.12),
      ),
      barrelPaint,
    );
    // Barrel stripes
    final stripe = Paint()..color = skin.projectile.withValues(alpha: 0.8);
    canvas.drawRect(
      Rect.fromLTWH(-baseR * 0.16, -size.height * 0.30 + kick, baseR * 0.32, 2.4),
      stripe,
    );
    canvas.drawRect(
      Rect.fromLTWH(-baseR * 0.16, -size.height * 0.40 + kick, baseR * 0.32, 2.4),
      stripe,
    );

    // Muzzle flash while recoiling
    if (recoil > 0.05) {
      final flashPaint = Paint()
        ..color = skin.projectile.withValues(alpha: (1 - recoil) * 0.95)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(
        Offset(0, -size.height * 0.48 + kick),
        size.width * 0.13 * recoil + 4,
        flashPaint,
      );
      // Star burst
      final star = Paint()
        ..color = Colors.white.withValues(alpha: (1 - recoil))
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 5; i++) {
        final a = -pi / 2 + (i - 2) * 0.45;
        final l = size.width * 0.16 * recoil;
        canvas.drawLine(
          Offset(0, -size.height * 0.48 + kick),
          Offset(cos(a) * l, -size.height * 0.48 + kick + sin(a) * l),
          star,
        );
      }
    }

    // Turret dome
    final domePaint = Paint()
      ..shader = RadialGradient(
        colors: [skin.barrel, Colors.black87],
        stops: const [0.2, 1],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: baseR));
    canvas.drawCircle(Offset.zero, baseR, domePaint);
    canvas.drawCircle(
      Offset.zero,
      baseR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = skin.projectile.withValues(alpha: 0.9),
    );
    // Rivets
    final rivet = Paint()..color = Colors.black54;
    for (var i = 0; i < 6; i++) {
      final a = i * pi / 3;
      canvas.drawCircle(
          Offset(cos(a) * baseR * 0.72, sin(a) * baseR * 0.72), 2, rivet);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CannonPainter oldDelegate) => true;
}
