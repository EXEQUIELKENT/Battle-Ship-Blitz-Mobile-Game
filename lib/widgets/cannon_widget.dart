import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../art/family_cannon_art.dart';
import '../art/fleet_family.dart';
import '../art/legacy_shell_art.dart';
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

  /// Distance from the cannon's center to its muzzle tip, as a fraction of
  /// [size], at rest (no recoil). Single source of truth shared with
  /// `CannonPainter` (which draws the barrel out to this distance) and
  /// battle_screen.dart's `_cannonMouth` (which spawns the cannonball from
  /// this same point) — see the redesign note on [CannonPainter] for why
  /// the old, much shorter value would otherwise leave the ball visibly
  /// detached from the new, longer barrel's actual tip.
  static const double muzzleFraction = 0.62;

  /// Where THIS gun's muzzle sits, as a fraction of [size].
  ///
  /// The original nine cannons are one drawing in nine colourways, so
  /// they all share [muzzleFraction]. The thematic families are six
  /// genuinely different guns with six different barrel lengths, each
  /// measured off its own artwork (see `FleetFamily.muzzleY`). Since this
  /// is the single value `battle_screen`'s `_cannonMouth` uses to spawn
  /// the shell, honouring it is what makes a long gun actually throw from
  /// further out instead of the ball popping out of the middle of the
  /// barrel — or, for the longest gun, out of thin air above it.
  static double muzzleFractionOf(CannonSkin skin) =>
      FleetFamilies.byKey(skin.familyKey)?.muzzleFrac ?? muzzleFraction;

  /// How much bigger THIS gun's widget must be drawn on the battle
  /// screen so it reads at the same on-screen size as a legacy gun
  /// sharing the same nominal `cannonSize` — 1.0 (no change) for the
  /// nine legacy skins, which this scale was never needed for.
  ///
  /// Single source of truth for the fix, read in exactly the two places
  /// that have to agree on how big a family gun really is: the widget
  /// size battle_screen.dart hands to this `CannonWidget`, and the
  /// `_cannonMouth` trajectory math that spawns the shell at
  /// `size * muzzleFractionOf(skin)`. Scaling both by the same factor
  /// is what keeps the shell leaving the barrel's actual (now bigger)
  /// tip instead of drifting off it as soon as the gun's drawn larger.
  static double gameplaySizeScaleOf(CannonSkin skin) =>
      FleetFamilies.byKey(skin.familyKey)?.gameplayScale ?? 1.0;

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
    final family = FleetFamilies.byKey(widget.skin.familyKey);
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
                family: family,
                // Only meaningful when there's no family gun — see
                // CannonPainter.legacyCannonId.
                legacyCannonId: family == null ? widget.skin.id : null,
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

  /// Set when a thematic family is equipped, in which case that family's
  /// gun is drawn instead of the standard one.
  final FleetFamily? family;

  /// The equipped cannon's own catalogue id, but ONLY when [family] is
  /// null — i.e. one of the nine originals. Used solely to tint and
  /// shape its muzzle exhaust (see [_paintLegacyExhaust]); a family gun
  /// gets its look from [family] instead and ignores this.
  final String? legacyCannonId;

  CannonPainter({
    required this.accent,
    this.family,
    this.legacyCannonId,
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

    // A family gun is its own silhouette end to end — mount, barrel and
    // muzzle — so it replaces the drawing rather than recolouring it.
    // The behaviour around it is untouched: same recoil pull, same
    // cooldown ring, same muzzle smoke, so a shot still reads and times
    // identically whichever gun is bolted on.
    final fam = family;
    if (fam != null) {
      _paintFamily(canvas, size, fam, center, outerR);
      return;
    }

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

    // ----- Naval cannon barrel -----
    // REDESIGN: the old cannon was a short, stubby round dome with a
    // recessed "mouth" sitting almost entirely INSIDE the mount ring — it
    // read as an icon, not a naval gun. This draws an actual elongated,
    // tapered barrel (wide rear chamber → narrower muzzle) protruding out
    // past the ring, with reinforcement bands and trunnion pins for a
    // heavier, more mechanical silhouette. `recoil` pulls the WHOLE barrel
    // assembly straight back down into the mount (rather than just
    // shrinking/fading it), so a shot reads as a real kick and the barrel
    // never visually detaches from its base. `muzzleCenter` is the single
    // source of truth for where the muzzle flash, smoke, and (via
    // `CannonWidget.muzzleFraction`, read externally by
    // battle_screen.dart's `_cannonMouth`) the cannonball itself spawn
    // from, so all three always agree on where the barrel tip actually is.
    final domeR = outerR * 0.58; // kept as the breech/chamber's own radius
    final barrelLen = size.width * CannonWidget.muzzleFraction;
    final recoilPull = barrelLen * 0.16 * recoil;
    final breechCenter = center + Offset(0, domeR * 0.10 + recoilPull * 0.35);
    final muzzleCenter = center - Offset(0, barrelLen - recoilPull);

    // Rear chamber (breech): a rounded knob where the barrel meets the
    // mount — heavier than the barrel itself, like a real naval gun's
    // breech block.
    final breechPaint = Paint()
      ..shader = uiGradient(
        breechCenter,
        domeR,
        const [Color(0xFF64717E), Color(0xFF394552), Color(0xFF1B222A)],
      );
    canvas.drawCircle(breechCenter, domeR, breechPaint);
    canvas.drawCircle(
      breechCenter,
      domeR,
      Paint()
        ..color = AppColors.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // Trunnion pins flanking the breech — the pivot mounts a real naval
    // gun barrel sits on.
    final trunnion = Paint()..color = AppColors.outline.withValues(alpha: 0.75);
    canvas.drawCircle(breechCenter + Offset(-domeR * 0.92, domeR * 0.05),
        domeR * 0.22, trunnion);
    canvas.drawCircle(breechCenter + Offset(domeR * 0.92, domeR * 0.05),
        domeR * 0.22, trunnion);

    // Tapered barrel body: wide at the breech, narrower at the muzzle —
    // the shape that actually reads as an elongated naval cannon rather
    // than a round dome.
    final breechHalfW = domeR * 0.60;
    final muzzleHalfW = domeR * 0.34;
    final barrelPath = Path()
      ..moveTo(breechCenter.dx - breechHalfW, breechCenter.dy)
      ..lineTo(muzzleCenter.dx - muzzleHalfW, muzzleCenter.dy)
      ..lineTo(muzzleCenter.dx + muzzleHalfW, muzzleCenter.dy)
      ..lineTo(breechCenter.dx + breechHalfW, breechCenter.dy)
      ..close();
    canvas.drawPath(
      barrelPath,
      Paint()
        ..shader = uiGradient(
          Offset.lerp(breechCenter, muzzleCenter, 0.3)!,
          barrelLen * 0.6,
          const [Color(0xFF6E7C8B), Color(0xFF3B4856), Color(0xFF1B222A)],
        ),
    );
    canvas.drawPath(
      barrelPath,
      Paint()
        ..color = AppColors.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeJoin = StrokeJoin.round,
    );

    // Reinforcement bands around the barrel — small mechanical detail
    // breaking up the plain taper, like a real gun's cast collars.
    final bandPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.30)
      ..style = PaintingStyle.stroke;
    for (final f in const [0.38, 0.70]) {
      final bp = Offset.lerp(breechCenter, muzzleCenter, f)!;
      final bw = breechHalfW + (muzzleHalfW - breechHalfW) * f;
      bandPaint.strokeWidth = bw * 0.38;
      canvas.drawLine(
          bp - Offset(bw * 0.82, 0), bp + Offset(bw * 0.82, 0), bandPaint);
    }

    // Barrel highlight streak — a soft curved gloss along the upper-left
    // edge of the barrel, closer to a polished-metal specular highlight.
    canvas.drawLine(
      Offset.lerp(breechCenter, muzzleCenter, 0.08)! -
          Offset(breechHalfW * 0.45, 0),
      Offset.lerp(breechCenter, muzzleCenter, 0.92)! -
          Offset(muzzleHalfW * 0.45, 0),
      Paint()
        ..color = Colors.white.withValues(alpha: ready ? 0.24 : 0.11)
        ..strokeWidth = domeR * 0.14
        ..strokeCap = StrokeCap.round,
    );

    // Muzzle opening at the barrel's tip, with a thin metallic highlight
    // crescent on its upper rim.
    final mouthCenter = muzzleCenter;
    final mouthR = muzzleHalfW * 0.92;
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
      mouthCenter - Offset(0, mouthR * 0.12),
      mouthR * 0.68,
      Paint()..color = const Color(0xFF0E151C),
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
    //
    // Before this, all nine originals shared this one grey cloud — the
    // same "just a recolour" gap the shell had (see
    // `legacy_shell_art.dart`). [_paintLegacyExhaust] gives each of them
    // its own exhaust; the plain rising cloud below is now specifically
    // the MK-I's ("reliable naval artillery" gets the plain powder
    // smoke) and the fallback for an unrecognised id.
    if (smoke > 0.01 && smokePuffs.isNotEmpty) {
      _paintLegacyExhaust(canvas, mouthCenter, outerR);
    }
  }

  /// The nine originals' firing storyboard, past the flash — the
  /// [_paintExhaust] counterpart for guns with no family. Same idea:
  /// fixed 850 ms timing shared by every cannon, [smokePuffs] supplying
  /// the randomized stagger; what changes per cannon is the shape of
  /// what comes out and its colour, taken from [legacyShellPalette] so
  /// exhaust and shell always agree.
  void _paintLegacyExhaust(Canvas canvas, Offset mouth, double outerR) {
    double lifeOf(_SmokePuff puff) {
      final span = (1 - puff.delay).clamp(0.0001, 1.0);
      return ((smoke - puff.delay) / span).clamp(0.0, 1.0);
    }

    void plainSmoke() {
      for (final puff in smokePuffs) {
        final t = lifeOf(puff);
        if (t <= 0) continue;
        final puffCenter = mouth +
            Offset(puff.dx * outerR * t, -puff.rise * outerR * t);
        final puffR = outerR * (0.22 + t * 0.30) * puff.sizeMul;
        canvas.drawCircle(
          puffCenter,
          puffR,
          Paint()
            ..color = const Color(0xFFB9C2CC).withValues(alpha: (1 - t) * 0.32),
        );
      }
    }

    final id = legacyCannonId;
    if (id == null || id == 'mk1') {
      plainSmoke();
      return;
    }
    final p = legacyShellPalette(id);
    switch (id) {
      // Fireburst: puffs run hotter and faster than powder smoke, with a
      // spark riding out ahead of each one.
      case 'inferno':
        for (final puff in smokePuffs) {
          final t = lifeOf(puff);
          if (t <= 0) continue;
          canvas.drawCircle(
            mouth +
                Offset(puff.dx * outerR * 0.5 * t, -puff.rise * outerR * 0.9 * t),
            outerR * (0.20 + t * 0.26) * puff.sizeMul,
            Paint()..color = p.trim.withValues(alpha: (1 - t) * 0.55),
          );
          canvas.drawCircle(
            mouth +
                Offset(
                    puff.dx * outerR * 0.9 * t, -puff.rise * outerR * 1.5 * t),
            outerR * 0.05 * (1 - t) * puff.sizeMul,
            Paint()..color = p.glow.withValues(alpha: 1 - t),
          );
        }
        break;

      // Electric discharge: jagged bolts kicked out in four directions,
      // gone almost at once, rather than any kind of cloud.
      case 'tesla':
        final t = (smoke / 0.4).clamp(0.0, 1.0);
        if (t < 1) {
          canvas.drawCircle(mouth, outerR * 0.14 * (1 - t),
              Paint()..color = p.glow.withValues(alpha: 1 - t));
          for (final a in const [-0.9, -0.3, 0.3, 0.9]) {
            final dir = Offset(math.sin(a), -math.cos(a));
            final len = outerR * (0.55 + 0.9 * t);
            final kink = mouth +
                dir * len * 0.55 +
                Offset(dir.dy, -dir.dx) * outerR * 0.12;
            final end = mouth + dir * len;
            final bolt = Path()
              ..moveTo(mouth.dx, mouth.dy)
              ..lineTo(kink.dx, kink.dy)
              ..lineTo(end.dx, end.dy);
            canvas.drawPath(
              bolt,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = outerR * 0.045 * (1 - t)
                ..strokeCap = StrokeCap.round
                ..color = p.trim.withValues(alpha: (1 - t) * 0.9),
            );
          }
        }
        break;

      // Toxic gas: a sluggish, low-rising cloud shedding drops of toxin
      // that fall rather than drift with it.
      case 'venom':
        for (final puff in smokePuffs) {
          final t = lifeOf(puff);
          if (t <= 0) continue;
          canvas.drawCircle(
            mouth +
                Offset(
                    puff.dx * outerR * 0.5 * t, -puff.rise * outerR * 0.35 * t),
            outerR * (0.22 + t * 0.30) * puff.sizeMul,
            Paint()..color = p.trim.withValues(alpha: (1 - t) * 0.42),
          );
          canvas.drawCircle(
            mouth + Offset(puff.dx * outerR * 0.6, outerR * 0.5 * t),
            outerR * 0.03 * (1 - t) * puff.sizeMul,
            Paint()..color = p.glow.withValues(alpha: (1 - t) * 0.8),
          );
        }
        break;

      // Gilded sparkle burst: small motes scattering out and up fast,
      // no cloud at all — closer to a firework than smoke.
      case 'royal':
        for (final puff in smokePuffs) {
          final t = lifeOf(puff);
          if (t <= 0) continue;
          final centre = mouth +
              Offset(
                  puff.dx * outerR * 1.3 * t, -puff.rise * outerR * 1.1 * t);
          canvas.drawCircle(centre, outerR * 0.05 * (1 - t) * puff.sizeMul,
              Paint()..color = p.trim.withValues(alpha: 1 - t));
          canvas.drawCircle(centre, outerR * 0.02 * (1 - t) * puff.sizeMul,
              Paint()..color = Colors.white.withValues(alpha: 1 - t));
        }
        break;

      // Twinned energy rings, the second chasing the first — an
      // afterimage rather than one clean pulse.
      case 'phantom':
        for (final k in const [0.0, 0.16]) {
          final t = (smoke - k).clamp(0.0, 1.0);
          if (t <= 0) continue;
          canvas.drawCircle(
            mouth,
            outerR * (0.16 + t * 0.85),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = outerR * 0.05 * (1 - t)
              ..color = p.trim.withValues(alpha: (1 - t) * 0.7),
          );
        }
        break;

      // Deep-sea report: bubbles rising and popping rather than
      // billowing, with a wisp of ink sinking against the current.
      case 'kraken':
        for (final puff in smokePuffs) {
          final t = lifeOf(puff);
          if (t <= 0) continue;
          final bubbleT = t < 0.7 ? t / 0.7 : 0.0;
          if (bubbleT > 0) {
            canvas.drawCircle(
              mouth +
                  Offset(
                      puff.dx * outerR * 0.6 * t, -puff.rise * outerR * t),
              outerR * 0.16 * bubbleT * puff.sizeMul,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = outerR * 0.02
                ..color = p.trim.withValues(alpha: (1 - bubbleT) * 0.8),
            );
          }
          canvas.drawCircle(
            mouth + Offset(-puff.dx * outerR * 0.3 * t, outerR * 0.3 * t),
            outerR * 0.10 * (1 - t) * puff.sizeMul,
            Paint()..color = p.hull.withValues(alpha: (1 - t) * 0.35),
          );
        }
        break;

      // Solar flare: rays burst outward from the muzzle and fade fast,
      // over a bright core rather than a cloud.
      case 'sunfire':
        final t = (smoke / 0.5).clamp(0.0, 1.0);
        if (t < 1) {
          for (var i = 0; i < 6; i++) {
            final a = (2 * math.pi / 6) * i;
            final dir = Offset(math.cos(a), math.sin(a));
            canvas.drawLine(
              mouth,
              mouth + dir * outerR * (0.3 + 0.9 * t),
              Paint()
                ..strokeWidth = outerR * 0.06 * (1 - t)
                ..strokeCap = StrokeCap.round
                ..color = p.trim.withValues(alpha: (1 - t) * 0.85),
            );
          }
          canvas.drawCircle(mouth, outerR * 0.22 * (1 - t),
              Paint()..color = p.glow.withValues(alpha: 1 - t));
        }
        break;

      // Void discharge: matter is pulled INTO the muzzle first — the
      // one exhaust here that converges instead of dispersing — then
      // the charge releases as a single fading ring.
      case 'void':
        if (smoke < 0.5) {
          final t = smoke / 0.5;
          for (final puff in smokePuffs) {
            final start = mouth +
                Offset(puff.dx * outerR * 1.1, -puff.rise * outerR * 0.9);
            canvas.drawCircle(
              Offset.lerp(start, mouth, t)!,
              outerR * 0.05 * puff.sizeMul,
              Paint()..color = p.trim.withValues(alpha: t),
            );
          }
        } else {
          final t = (smoke - 0.5) / 0.5;
          canvas.drawCircle(
            mouth,
            outerR * 0.5 * t,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = outerR * 0.06 * (1 - t)
              ..color = p.glow.withValues(alpha: (1 - t) * 0.85),
          );
        }
        break;

      default:
        plainSmoke();
    }
  }

  /// Draws a thematic family's gun.
  ///
  /// The art itself comes from `family_cannon_art.dart` verbatim; what
  /// happens here is everything AROUND it that has to keep behaving the
  /// same regardless of which gun is equipped:
  ///
  ///  * the barrel is pulled back into the mount on recoil, by the same
  ///    proportion of its own (family-specific) barrel length;
  ///  * the reload sweep rides that family's OWN platform — every one of
  ///    them draws a mount at its own height and radius, so a sweep on a
  ///    fixed circle sat off the artwork entirely;
  ///  * the exhaust spawns at the real muzzle, read off the drawing.
  void _paintFamily(
    Canvas canvas,
    Size size,
    FleetFamily fam,
    Offset center,
    double outerR,
  ) {
    final side = size.width;
    final barrelLen = side * fam.muzzleFrac;
    final recoilPull = barrelLen * 0.16 * recoil;

    // ----- Reload platform -----
    // The standard cannon is a barrel standing on a disc, with the
    // cooldown running round that disc: the reload reads as something
    // the MOUNTING does. Every family now gets the same thing rather
    // than an arc drawn over its own artwork — on a wide mount like the
    // Magma Bombard's rock collar, a sweep on the drawing cut straight
    // across the gun's body.
    //
    // Drawn before the art so the gun genuinely stands on it, in the
    // family's own colours so it belongs to that gun rather than
    // looking bolted on from the standard one.
    final mountCenter =
        Offset(side / 2, fam.gunY(side, fam.mountCy) + recoilPull);
    final platformR = fam.platformRadius(side);

    // Ground shadow, under the platform rather than under the gun — the
    // art's own shadow is switched off below so there is only ever one.
    //
    // Drawn as a full circle a little WIDER than the platform itself
    // (rather than a squashed oval sized to roughly match it), so a ring
    // of shadow is always visible peeking out from behind the plate all
    // the way round — the same "hard shadow" read a legacy gun gets from
    // its own ring in `CannonPainter.paint`'s "Soft ground shadow
    // ellipse" above. A shadow sized to match the plate mostly ends up
    // hidden UNDER it once the opaque disc is painted on top; oversizing
    // it here is what actually keeps it visible on every gun, not just
    // the ones with a wide enough mount to poke past a tight oval.
    canvas.drawCircle(
      mountCenter + Offset(0, platformR * 0.12),
      platformR * 1.18,
      Paint()..color = Colors.black.withValues(alpha: 0.24),
    );

    // Rim, then the plate itself — the same two-tone build as the
    // standard mount, in this family's metal.
    canvas.drawCircle(mountCenter, platformR, Paint()..color = fam.gun.ink);
    canvas.drawCircle(
      mountCenter,
      platformR * 0.93,
      Paint()
        ..shader = uiGradient(mountCenter, platformR * 0.93, [
          Color.lerp(fam.gun.hull, Colors.white, 0.20)!,
          fam.gun.hull,
          Color.lerp(fam.gun.hull, Colors.black, 0.30)!,
        ]),
    );

    final sweepR = fam.sweepRadius(side);
    final trackW = fam.sweepWidth(side);

    // Unlit track first, so the charged arc reads against the plate even
    // on the pale families — Rime's ice-blue glow on an ice-blue mount
    // would otherwise be invisible — and so the ink shows either side of
    // the sweep like a groove it runs in.
    canvas.drawCircle(
      mountCenter,
      sweepR,
      Paint()
        ..color = fam.gun.ink.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = trackW,
    );
    canvas.drawArc(
      Rect.fromCircle(center: mountCenter, radius: sweepR),
      -math.pi / 2,
      2 * math.pi * cooldown,
      false,
      Paint()
        // Charging runs the family's trim up to its glow, so the
        // platform brightens as the gun comes back online instead of
        // just filling in.
        ..color = Color.lerp(fam.gun.trim, fam.gun.glow, cooldown)!
            .withValues(alpha: ready ? 0.95 : 0.72)
        ..style = PaintingStyle.stroke
        ..strokeWidth = trackW * 0.72
        ..strokeCap = StrokeCap.round,
    );

    canvas.save();
    // The whole gun kicks back, exactly as the standard barrel does.
    canvas.translate(0, recoilPull);
    // Shrunk about the mount centre so the platform shows as a ring
    // around the base. `FleetFamily.gunY` applies the same inset, which
    // is what keeps the muzzle flash, the exhaust and the shell's spawn
    // point on the gun as it is actually drawn.
    canvas.translate(mountCenter.dx, mountCenter.dy - recoilPull);
    canvas.scale(FleetFamily.gunInset);
    canvas.translate(-mountCenter.dx, -(mountCenter.dy - recoilPull));
    paintFamilyCannon(canvas, size, fam, shadow: false);
    canvas.restore();

    final mouthCenter =
        Offset(side / 2, fam.gunY(side, fam.muzzleY) + recoilPull);

    // Muzzle flash, tinted with the family's own accent — a magma
    // bombard should not flash the same white as an ion lance.
    if (recoil > 0.02) {
      canvas.drawCircle(
        mouthCenter,
        outerR * 0.42 * recoil,
        Paint()..color = fam.gun.glow.withValues(alpha: 0.75 * recoil),
      );
      canvas.drawCircle(
        mouthCenter,
        outerR * 0.20 * recoil,
        Paint()..color = Colors.white.withValues(alpha: 0.85 * recoil),
      );
    }

    if (smoke > 0.01 && smokePuffs.isNotEmpty) {
      _paintExhaust(canvas, fam, mouthCenter, outerR);
    }
  }

  /// The design's firing storyboard, past the flash.
  ///
  /// "Same 260 ms. Different beat." — the timing is fixed for every
  /// family and lives in `_CannonWidgetState`; what varies is the shape
  /// of what comes out. Blackpowder hangs a grey cloud up and to the
  /// left; Brass throws two jets sideways rather than upward; Helios
  /// never makes smoke at all and bleeds off a ring instead. All six run
  /// off the same `smoke` 0→1 and the same fixed puff spread, so nothing
  /// here can change how long a shot takes.
  void _paintExhaust(
    Canvas canvas,
    FleetFamily fam,
    Offset mouth,
    double outerR,
  ) {
    /// Where this puff is in its own life, 0→1, after its stagger.
    double lifeOf(_SmokePuff puff) {
      final span = (1 - puff.delay).clamp(0.0001, 1.0);
      return ((smoke - puff.delay) / span).clamp(0.0, 1.0);
    }

    switch (fam.exhaust) {
      // Powder smoke: billows out, climbs, and drifts to one side as it
      // goes — the design's "grey cloud drifts up and left".
      case MuzzleExhaust.smoke:
        for (final puff in smokePuffs) {
          final t = lifeOf(puff);
          if (t <= 0) continue;
          final centre = mouth +
              Offset(
                (puff.dx - 0.55) * outerR * t,
                -puff.rise * outerR * t,
              );
          canvas.drawCircle(
            centre,
            outerR * (0.22 + t * 0.34) * puff.sizeMul,
            Paint()
              ..color = fam.exhaustColor.withValues(alpha: (1 - t) * 0.42),
          );
        }
        break;

      // Muzzle brake: the gas is vented hard sideways and it is over
      // almost at once. Short, flat, and gone by a third of the way in.
      case MuzzleExhaust.brake:
        final t = (smoke / 0.34).clamp(0.0, 1.0);
        if (t >= 1) break;
        for (final dir in const [-1.0, 1.0]) {
          for (var i = 0; i < 3; i++) {
            final spread = (i + 1) / 3;
            canvas.drawCircle(
              mouth + Offset(dir * outerR * 0.5 * spread * t, outerR * 0.05 * i),
              outerR * 0.13 * (1 - spread * 0.4),
              Paint()
                ..color = fam.exhaustColor.withValues(alpha: (1 - t) * 0.5),
            );
          }
        }
        break;

      // Two long steam jets thrown sideways rather than upward, from the
      // bypass pipe — the beat the design calls out for Brass.
      case MuzzleExhaust.steam:
        for (final dir in const [-1.0, 1.0]) {
          for (final puff in smokePuffs) {
            final t = lifeOf(puff);
            if (t <= 0) continue;
            // Reach sideways fast, rise only slightly: a jet, not a cloud.
            final centre = mouth +
                Offset(
                  dir * outerR * (0.25 + 1.25 * t) * puff.sizeMul,
                  -outerR * 0.18 * t * puff.rise + puff.dx * outerR * 0.12,
                );
            canvas.drawCircle(
              centre,
              outerR * (0.13 + t * 0.16) * puff.sizeMul,
              Paint()
                ..color = fam.exhaustColor.withValues(alpha: (1 - t) * 0.5),
            );
          }
        }
        break;

      // Vapour off a cold barrel sinks instead of rising, and sheds a few
      // ice motes on the way down.
      case MuzzleExhaust.frost:
        for (final puff in smokePuffs) {
          final t = lifeOf(puff);
          if (t <= 0) continue;
          final centre = mouth +
              Offset(
                puff.dx * outerR * 0.9 * t,
                outerR * 0.55 * t * puff.rise,
              );
          canvas.drawCircle(
            centre,
            outerR * (0.18 + t * 0.26) * puff.sizeMul,
            Paint()
              ..color = fam.exhaustColor.withValues(alpha: (1 - t) * 0.45),
          );
          canvas.drawCircle(
            centre + Offset(puff.dx * outerR * 0.4, -outerR * 0.1),
            outerR * 0.045 * (1 - t),
            Paint()..color = fam.gun.glow.withValues(alpha: (1 - t) * 0.9),
          );
        }
        break;

      // Ash cloud, dark and slow, with hot motes climbing out of it
      // faster than the ash itself.
      case MuzzleExhaust.embers:
        for (final puff in smokePuffs) {
          final t = lifeOf(puff);
          if (t <= 0) continue;
          final centre = mouth +
              Offset(puff.dx * outerR * 0.7 * t, -outerR * 0.5 * t * puff.rise);
          canvas.drawCircle(
            centre,
            outerR * (0.22 + t * 0.32) * puff.sizeMul,
            Paint()
              ..color = fam.exhaustColor.withValues(alpha: (1 - t) * 0.5),
          );
          // The mote rides the same puff but outruns it, so the cloud
          // keeps throwing sparks upward as it thins.
          canvas.drawCircle(
            mouth +
                Offset(
                  puff.dx * outerR * 1.1 * t,
                  -outerR * 1.05 * t * puff.rise,
                ),
            outerR * 0.06 * (1 - t) * puff.sizeMul,
            Paint()..color = fam.gun.glow.withValues(alpha: 1 - t),
          );
        }
        break;

      // No smoke at all. An energy weapon bleeds its charge off as an
      // expanding ring that fades — the design is explicit that "recoil
      // is a ring, not a kick".
      case MuzzleExhaust.ring:
        final r = outerR * (0.18 + smoke * 1.15);
        canvas.drawCircle(
          mouth,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = outerR * 0.12 * (1 - smoke)
            ..color = fam.exhaustColor.withValues(alpha: (1 - smoke) * 0.75),
        );
        canvas.drawCircle(
          mouth,
          r * 0.62,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = outerR * 0.07 * (1 - smoke)
            ..color = Colors.white.withValues(alpha: (1 - smoke) * 0.45),
        );
        break;
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
      oldDelegate.family != family ||
      oldDelegate.legacyCannonId != legacyCannonId ||
      oldDelegate.smoke != smoke;
}
