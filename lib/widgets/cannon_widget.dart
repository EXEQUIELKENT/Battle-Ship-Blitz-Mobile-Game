import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/storage_service.dart';

/// Big round cartoon cannon (reference-style): thick black ring, colored
/// accent ring, dark barrel dome, hard shadow. Animates with a recoil
/// squash + muzzle flash when [fireTrigger] emits, and bobs/pulses when
/// ready. Used as the big centered cannon on the battle grids.
class CannonWidget extends StatefulWidget {
  final CannonSkin skin;
  final double cooldownFraction; // 0 = reloading, 1 = ready
  final bool enabled;
  final VoidCallback? onFire;
  final String label;
  final double size;
  final Stream<void>? fireTrigger;

  /// Overrides the ready-state accent color (e.g. per-player red/blue rings).
  final Color? accentOverride;

  /// Emits when this cannon should flash "ready" (turn handoff cue).
  final Stream<void>? readyTrigger;

  const CannonWidget({
    super.key,
    required this.skin,
    required this.cooldownFraction,
    this.enabled = true,
    this.onFire,
    this.label = 'FIRE',
    this.size = 92,
    this.fireTrigger,
    this.accentOverride,
    this.readyTrigger,
  });

  @override
  State<CannonWidget> createState() => _CannonWidgetState();
}

class _CannonWidgetState extends State<CannonWidget>
    with TickerProviderStateMixin {
  late final AnimationController _recoil;
  late final AnimationController _pulse;

  // ----- Muzzle smoke (separate, longer-lived than the recoil kick) -----
  // `_recoil` snaps up and back down in ~260ms either way — plenty for a
  // sharp kick, but too fast to read as actual smoke. `_smoke` runs once,
  // longer (850ms), driving a handful of puffs that drift up and out from
  // the barrel and fade — so the shot leaves a lingering cloud behind
  // instead of the flash just winking out with the recoil.
  late final AnimationController _smoke;

  /// Fixed per-instance spread for the smoke puffs (dx offset, start delay
  /// within the smoke animation, size, and rise distance) — randomized
  /// once so the puffs don't all move in lockstep, but stable across
  /// rebuilds/re-fires so the cannon doesn't visibly "reshuffle" its smoke
  /// pattern mid-animation.
  late final List<_SmokePuff> _puffs;

  @override
  void initState() {
    super.initState();
    _recoil = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _smoke = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    // PERF: drive rebuilds from animation ticks directly instead of
    // wrapping everything in an AnimatedBuilder. This lets us STOP the
    // ready-pulse animation entirely while the cannon is reloading (a
    // state it spends ~55% of the match in), so the widget is NOT rebuilt
    // at 60fps for nothing. Cooldown-ring updates arrive via didUpdateWidget
    // from the 100ms game ticker (~10Hz) — enough for a smooth-looking ring
    // while using ~1/6 the rebuild budget.
    _recoil.addListener(_maybeSetState);
    _smoke.addListener(_maybeSetState);
    _pulse.addListener(_maybeSetState);
    final rng = math.Random();
    _puffs = List.generate(5, (i) {
      return _SmokePuff(
        dx: (rng.nextDouble() - 0.5) * 0.9,
        delay: i * 0.06 + rng.nextDouble() * 0.05,
        sizeMul: 0.75 + rng.nextDouble() * 0.5,
        rise: 0.55 + rng.nextDouble() * 0.4,
      );
    });
    widget.fireTrigger?.listen((_) => fire());
    widget.readyTrigger?.listen((_) => readyFlash());
  }

  void _maybeSetState() {
    if (mounted) setState(() {});
  }

  /// Starts/stops the visual ready-pulse so it only burns CPU when the
  /// cannon is actually in the "ready" state — a reloaded cannon that's
  /// cooling down doesn't need its pulse animation running at 60fps.
  void _updatePulseState(bool ready) {
    if (ready && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!ready && _pulse.isAnimating) {
      _pulse.stop(canceled: false);
    }
  }

  @override
  void didUpdateWidget(CannonWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Cooldown / enabled changed via parent rebuilds (100ms game ticker).
    // Trigger a rebuild so the cooldown ring advances smoothly.
    _updatePulseState(widget.cooldownFraction >= 1 && widget.enabled);
    if (oldWidget.cooldownFraction != widget.cooldownFraction ||
        oldWidget.enabled != widget.enabled) {
      _maybeSetState();
    }
  }

  @override
  void dispose() {
    _recoil.dispose();
    _pulse.dispose();
    _smoke.dispose();
    super.dispose();
  }

  void fire() {
    _recoil.forward(from: 0).then((_) => _recoil.reverse());
    _smoke.forward(from: 0);
  }

  /// Pronounced ready-flash: a quick double-pulse to signal "your cannon
  /// is loaded — fire!" without interrupting the flow with a popup.
  void readyFlash() {
    _recoil.forward(from: 0).then((_) => _recoil.reverse()).then((_) {
      if (mounted) {
        _recoil.forward(from: 0).then((_) => _recoil.reverse());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ready = widget.cooldownFraction >= 1 && widget.enabled;
    final squash = 1 - _recoil.value * 0.14;
    final pulseScale = ready ? 1 + _pulse.value * 0.05 : 1.0;
    // Small downward kick synced to the same recoil value that drives
    // the squash and the barrel retraction in the painter, so firing
    // reads as a real jolt (the whole cannon nudges back) rather than
    // just a shrink-and-grow pulse.
    final kick = _recoil.value * widget.size * 0.05;
    return GestureDetector(
      onTap: ready ? widget.onFire : null,
      child: Transform.translate(
        offset: Offset(0, kick),
        child: Transform.scale(
          scale: squash * pulseScale,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: CustomPaint(
              painter: CannonPainter(
                accent: ready
                    ? (widget.accentOverride ?? widget.skin.projectile)
                    : AppColors.inkSoft,
                cooldown: widget.cooldownFraction,
                recoil: _recoil.value,
                ready: ready,
                smoke: _smoke.value,
                smokePuffs: _puffs,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One puff in a cannon's muzzle-smoke cloud — see `_CannonWidgetState._puffs`.
class _SmokePuff {
  /// Horizontal drift direction/distance, as a fraction of the cannon's
  /// outer radius.
  final double dx;

  /// Fraction (0–1) into the smoke animation before this puff starts
  /// growing, so puffs billow out staggered rather than all at once.
  final double delay;

  /// Per-puff size multiplier.
  final double sizeMul;

  /// How far this puff rises, as a fraction of the cannon's outer radius.
  final double rise;

  const _SmokePuff({
    required this.dx,
    required this.delay,
    required this.sizeMul,
    required this.rise,
  });
}

/// Pure painter for the cartoon cannon so it can be reused without the
/// gesture wrapper (e.g. the blurred transition overlay).
class CannonPainter extends CustomPainter {
  final Color accent;
  final double cooldown;
  final double recoil;
  final bool ready;

  /// 0 = no smoke, 1 = smoke animation finished. Drives the muzzle-smoke
  /// puffs below — separate from [recoil] since the smoke should keep
  /// drifting and fading well after the recoil kick has snapped back.
  final double smoke;

  /// Per-puff spread for the smoke cloud (empty = no smoke drawn, e.g. for
  /// the static painter reused by the transition overlay).
  final List<_SmokePuff> smokePuffs;

  CannonPainter({
    required this.accent,
    this.cooldown = 1,
    this.recoil = 0,
    this.ready = true,
    this.smoke = 0,
    this.smokePuffs = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = size.width * 0.48;

    // Soft ground shadow ellipse
    canvas.drawOval(
      Rect.fromCenter(
        center: center + Offset(0, outerR * 0.34),
        width: outerR * 2.2,
        height: outerR * 0.9,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.22),
    );

    // Thick outer ring, beveled: a base fill plus a thin lighter arc along
    // the upper-left edge so the ring reads as rounded metal, not a flat
    // disc.
    canvas.drawCircle(center, outerR, Paint()..color = AppColors.outline);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: outerR * 0.94),
      math.pi * 1.05,
      math.pi * 0.55,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = outerR * 0.10
        ..strokeCap = StrokeCap.round,
    );

    // Colored accent ring — a subtle radial gradient instead of a flat
    // fill gives it a coated-metal look, catching light toward the top.
    canvas.drawCircle(
      center,
      outerR * 0.84,
      Paint()..shader = uiGradient(center, outerR * 0.84, [
        Color.lerp(accent, Colors.white, 0.22)!,
        accent,
        Color.lerp(accent, Colors.black, 0.28)!,
      ]),
    );

    // Rivets studded evenly around the accent ring for mechanical detail.
    final rivet = Paint()..color = AppColors.outline.withValues(alpha: 0.55);
    final rivetShine = Paint()..color = Colors.white.withValues(alpha: 0.35);
    const rivetCount = 10;
    for (var i = 0; i < rivetCount; i++) {
      final a = (2 * math.pi / rivetCount) * i;
      final rp = center +
          Offset(math.cos(a), math.sin(a)) * (outerR * 0.955);
      canvas.drawCircle(rp, outerR * 0.035, rivet);
      canvas.drawCircle(
          rp - Offset(outerR * 0.01, outerR * 0.01), outerR * 0.014, rivetShine);
    }

    // Cooldown sweep arc over the accent ring
    final arcPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = outerR * 0.16
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: outerR * 0.84),
      -math.pi / 2,
      2 * math.pi * cooldown,
      false,
      arcPaint,
    );

    // Barrel dome (dark cylinder). Nudged toward the ring's center as
    // `recoil` rises — a subtle "the barrel just jerked backward into its
    // housing" retraction, on top of the whole-cannon kickback translate
    // and squash applied by the widget — then eases back out as recoil
    // decays, so firing reads as a real mechanical kick rather than just
    // a size pulse.
    final domeR = outerR * 0.58;
    final domeCenter = center - Offset(0, domeR * (0.14 - recoil * 0.05));
    final domePaint = Paint()
      ..shader = uiGradient(
        domeCenter,
        domeR,
        const [Color(0xFF64717E), Color(0xFF394552), Color(0xFF1B222A)],
      );
    canvas.drawCircle(domeCenter, domeR, domePaint);
    // Inset shadow ring at the dome's base for a touch of depth.
    canvas.drawCircle(
      domeCenter,
      domeR * 0.92,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = domeR * 0.10,
    );
    canvas.drawCircle(
      domeCenter,
      domeR,
      Paint()
        ..color = AppColors.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // Barrel mouth (darker inset circle near the top), with a thin
    // metallic highlight crescent on its upper rim.
    final mouthR = domeR * 0.52;
    final mouthCenter = center - Offset(0, domeR * (0.52 - recoil * 0.10));
    canvas.drawCircle(mouthCenter, mouthR, Paint()..color = AppColors.outline);
    canvas.drawArc(
      Rect.fromCircle(center: mouthCenter, radius: mouthR * 0.92),
      math.pi * 1.1,
      math.pi * 0.6,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = mouthR * 0.18
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      mouthCenter - Offset(0, mouthR * 0.18),
      mouthR * 0.72,
      Paint()..color = const Color(0xFF0E151C),
    );

    // Barrel highlight streak — a soft curved gloss instead of a flat
    // rounded rect, closer to a polished-metal specular highlight.
    canvas.drawArc(
      Rect.fromCenter(
        center: center + Offset(-domeR * 0.18, domeR * 0.06),
        width: domeR * 0.42,
        height: domeR * 1.15,
      ),
      math.pi * 0.75,
      math.pi * 0.5,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: ready ? 0.22 : 0.10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = domeR * 0.16
        ..strokeCap = StrokeCap.round,
    );

    // Muzzle flash while recoiling: a soft smoke puff behind a bright
    // starburst, so a shot reads as a fuller "boom" rather than one flat
    // circle.
    if (recoil > 0.05) {
      final flashCenter = mouthCenter - Offset(0, mouthR * (1.2 + recoil));
      final flashR = outerR * (0.34 + recoil * 0.5);
      canvas.drawCircle(
        flashCenter - Offset(0, flashR * 0.2),
        flashR * 1.35,
        Paint()..color = Colors.white.withValues(alpha: (1 - recoil) * 0.18),
      );
      canvas.drawCircle(
        flashCenter,
        flashR,
        Paint()..color = AppColors.gold.withValues(alpha: (1 - recoil) * 0.95),
      );
      canvas.drawCircle(
        flashCenter,
        flashR * 0.55,
        Paint()..color = Colors.white.withValues(alpha: (1 - recoil)),
      );
      final star = Paint()
        ..color = Colors.white.withValues(alpha: (1 - recoil))
        ..strokeWidth = 3.6
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 6; i++) {
        final a = -math.pi / 2 + (i - 2.5) * 0.42;
        final l = flashR * 1.25 * recoil;
        canvas.drawLine(flashCenter,
            flashCenter + Offset(math.cos(a) * l, math.sin(a) * l), star);
      }
    }

    // Muzzle smoke: soft grey puffs that billow out from the barrel and
    // drift upward, growing and fading as `smoke` runs 0→1 — independent
    // of (and outlasting) the sharp `recoil` flash above, so a shot
    // leaves a brief hanging cloud instead of the boom just vanishing.
    if (smoke > 0.01 && smokePuffs.isNotEmpty) {
      for (final puff in smokePuffs) {
        // Each puff waits out its own `delay` fraction before it starts
        // growing, so the cloud billows out staggered rather than as one
        // uniform blob.
        final span = (1 - puff.delay).clamp(0.0001, 1.0);
        final local = ((smoke - puff.delay) / span).clamp(0.0, 1.0);
        if (local <= 0) continue;
        final puffCenter = mouthCenter +
            Offset(
              puff.dx * outerR * local,
              -puff.rise * outerR * local,
            );
        final puffR = outerR * (0.22 + local * 0.30) * puff.sizeMul;
        final fade = (1 - local) * 0.32;
        canvas.drawCircle(
          puffCenter,
          puffR,
          Paint()..color = const Color(0xFFB9C2CC).withValues(alpha: fade),
        );
      }
    }
  }

  static Shader uiGradient(Offset center, double r, List<Color> colors) {
    return RadialGradient(
      colors: colors,
      center: const Alignment(0, -0.4),
      radius: 1.1,
    ).createShader(Rect.fromCircle(center: center, radius: r));
  }

  @override
  bool shouldRepaint(CannonPainter oldDelegate) =>
      oldDelegate.accent != accent ||
      oldDelegate.cooldown != cooldown ||
      oldDelegate.recoil != recoil ||
      oldDelegate.ready != ready ||
      oldDelegate.smoke != smoke;
}
