import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../art/cannon_fire_profile.dart';
import '../art/family_cannon_art.dart';
import '../art/fleet_family.dart';
import '../art/legacy_cannon_art.dart';
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
  /// REDESIGN: the nine originals used to be one drawing in nine
  /// colourways, so they all shared [muzzleFraction] — but
  /// `paintLegacyCannon` gives each of them its own turret with its own
  /// actual barrel length now, so each reads its own value from
  /// [legacyMuzzleFractionOf] (computed from that same art, so the two
  /// can never drift apart) instead. The thematic families are six
  /// genuinely different guns with six different barrel lengths, each
  /// measured off its own artwork (see `FleetFamily.muzzleY`). Since this
  /// is the single value `battle_screen`'s `_cannonMouth` uses to spawn
  /// the shell, honouring it is what makes a long gun actually throw from
  /// further out instead of the ball popping out of the middle of the
  /// barrel — or, for the longest gun, out of thin air above it.
  static double muzzleFractionOf(CannonSkin skin) =>
      FleetFamilies.byKey(skin.familyKey)?.muzzleFrac ??
      legacyMuzzleFractionOf(skin.id);

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
  StreamSubscription<void>? _fireSub;
  StreamSubscription<void>? _readySub;

  late final AnimationController _recoil;
  late final AnimationController _pulse;

  // BUGFIX (turn handoff looked like a shot): `readyFlash()` used to
  // share `_recoil` with `fire()` — but `_recoil` is also what
  // `CannonPainter` reads to draw the muzzle flash and pull the barrel
  // back (see `recoil:` below). Sharing it meant every turn handoff
  // played a full double muzzle-flash, which read as "this gun just
  // fired" at exactly the moment it hadn't. `_readyKick` drives the same
  // widget-level squash/nudge feel for the ready cue, but is never
  // passed to the painter — only `_recoil` (now fire-only) triggers the
  // flash/smoke/barrel-retract.
  late final AnimationController _readyKick;

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

  /// This gun's own recoil "personality" — see `cannon_fire_profile.dart`.
  /// Kept in sync with `widget.skin` in `didUpdateWidget` (a cannon can be
  /// swapped without leaving this widget — the deploy screen's GEAR
  /// dialog does exactly that).
  late CannonFireProfile _profile;

  @override
  void initState() {
    super.initState();
    _profile = fireProfileFor(widget.skin);
    _recoil = AnimationController(
      vsync: this,
      duration: _profile.recoilDuration,
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _smoke = AnimationController(
      vsync: this,
      duration: _profile.muzzleFxDuration,
    );
    _readyKick = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
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
    _readyKick.addListener(_maybeSetState);
    final rng = math.Random();
    _puffs = List.generate(5, (i) {
      return _SmokePuff(
        dx: (rng.nextDouble() - 0.5) * 0.9,
        delay: i * 0.06 + rng.nextDouble() * 0.05,
        sizeMul: 0.75 + rng.nextDouble() * 0.5,
        rise: 0.55 + rng.nextDouble() * 0.4,
      );
    });
    // BUGFIX (a swapped-out cannon kept listening): these subscriptions
    // used to be started and then dropped on the floor. Every screen that
    // lets the equipped cannon change without leaving it — the deploy
    // screen's GEAR dialog is the live one — swaps this widget behind an
    // `AnimatedSwitcher`, so the OLD state stayed subscribed to the same
    // broadcast trigger after being disposed. The next shot then reached
    // a dead state and called `forward()` on its disposed controllers,
    // and every swap since the screen opened added one more.
    _fireSub = widget.fireTrigger?.listen((_) => fire());
    _readySub = widget.readyTrigger?.listen((_) => readyFlash());
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
    if (oldWidget.skin.id != widget.skin.id) {
      _profile = fireProfileFor(widget.skin);
      // Only retimed while at rest — resizing an AnimationController's
      // duration mid-flight would warp whatever fraction of the old shot
      // was still playing.
      if (!_recoil.isAnimating) _recoil.duration = _profile.recoilDuration;
      if (!_smoke.isAnimating) _smoke.duration = _profile.muzzleFxDuration;
    }
  }

  @override
  void dispose() {
    _fireSub?.cancel();
    _readySub?.cancel();
    _recoil.dispose();
    _pulse.dispose();
    _smoke.dispose();
    _readyKick.dispose();
    super.dispose();
  }

  /// The whole point of this method is that it's what makes a shot
  /// actually LOOK like it happened. Previously this was called from
  /// `BattleScreen._resolveImpact`, at the moment a shot's IMPACT was
  /// confirmed — up to 750ms (a full ball flight) plus network latency
  /// after `SoundService.instance.cannonFire()` had already played at
  /// launch, and only when the shot was a hit (a miss never animated the
  /// gun at all). It is now called at launch instead, right alongside
  /// that same sound — see `BattleScreen._launchBall` /
  /// `_launchOpponentBall` — so the recoil, muzzle flash and smoke all
  /// start with the boom, on every shot.
  void fire() {
    _recoil.forward(from: 0).then((_) => _recoil.reverse());
    _smoke.forward(from: 0);
  }

  /// Pronounced ready-flash: a quick double-pulse to signal "your cannon
  /// is loaded — fire!" without interrupting the flow with a popup. Uses
  /// its own controller — see the doc on `_readyKick` for why it must
  /// not share `_recoil` with an actual shot.
  void readyFlash() {
    _readyKick.forward(from: 0).then((_) => _readyKick.reverse()).then((_) {
      if (mounted) {
        _readyKick.forward(from: 0).then((_) => _readyKick.reverse());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ready = widget.cooldownFraction >= 1 && widget.enabled;
    // The widget-level squash/kick/lateral reacts to whichever of the two
    // is actually playing — a real shot (`_recoil`, shaped by this gun's
    // own `_profile.character`) or the plain ready-flash (`_readyKick`,
    // deliberately left unshaped — it is a neutral turn-handoff cue, not
    // part of any one gun's firing identity) — but only `_recoil` reaches
    // the painter below, so the muzzle flash/smoke/barrel-retract only
    // ever draw for a real shot. See the doc on `_readyKick`.
    final fireShape = shapeRecoil(_profile.character, _recoil.value);
    // These never really overlap in practice (a gun that's mid-shot isn't
    // also flashing ready), so summing rather than `max`-ing preserves a
    // character like `suck`'s brief negative dip instead of a `max`
    // against `_readyKick`'s always-non-negative 0 clobbering it back to 0.
    final vertical = (fireShape.vertical + _readyKick.value)
        .clamp(-0.5, 1.4);
    final squash = 1 - vertical * 0.14 * _profile.squashMultiplier;
    final pulseScale = ready ? 1 + _pulse.value * 0.05 : 1.0;
    // Small downward kick synced to the same value that drives the
    // squash, so firing (or the ready cue) reads as a real jolt rather
    // than just a shrink-and-grow pulse. `lateral` is 0 for every
    // character except the two shake-based ones.
    final kick = vertical * _profile.kickMultiplier * widget.size * 0.05;
    final lateral = fireShape.lateral * widget.size * 0.035;
    final family = FleetFamilies.byKey(widget.skin.familyKey);
    return GestureDetector(
      onTap: ready ? widget.onFire : null,
      child: Opacity(
        opacity: fireShape.opacity,
        child: Transform.translate(
          offset: Offset(lateral, kick),
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
                  kickMultiplier: _profile.kickMultiplier,
                  ready: ready,
                  smoke: _smoke.value,
                  smokePuffs: _puffs,
                ),
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

  /// Scales how far the barrel pulls back into the mount on recoil — this
  /// gun's own `CannonFireProfile.kickMultiplier` (see
  /// `cannon_fire_profile.dart`), so a heavy-hitting gun like Inferno
  /// visibly punches back further than a ghostly one like Phantom.
  final double kickMultiplier;
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
    this.kickMultiplier = 1,
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

    // FEEDBACK (two shadows under every legacy gun): a generic ground
    // ellipse used to be drawn here, on top of the one each cannon's own
    // SVG already carries (`<ellipse cx="60" cy="102" rx="38" ry="8"
    // fill="black" opacity="0.22">` — see `_ringMarkup`). The two are
    // different shapes in different places: the design's sits low and
    // wide UNDER the gun, while this one was centred only 0.34×outerR
    // below the mount, so its top half fell across the gun's own body
    // and its ends stuck out past the ring on both sides. Removed
    // entirely rather than reconciled — the art already ships the
    // shadow it was drawn with, and that is the one to keep.

    // The nine originals' own illustrated ring + turret, replayed
    // verbatim from the design's own SVG markup — see `paintLegacyCannon`'s
    // doc for how it's recentred/rescaled onto exactly this [outerR], and
    // why [recoilPull] only ever moves the turret, never the ring. Its
    // return is this skin's own actual muzzle tip, already carrying the
    // recoil pull, so the flash/smoke/cooldown-ring code below (unchanged
    // from the old generic gun) reads it exactly like it used to read the
    // old fixed barrel's tip.
    final id = legacyCannonId ?? 'mk1';
    final recoilPull =
        size.width * legacyMuzzleFractionOf(id) * 0.16 * recoil * kickMultiplier;
    // FEEDBACK (reload ring sliced across the barrel): the cooldown
    // sweep moved INTO `paintLegacyCannon`, which is the only place that
    // can order it correctly — ring plate, then the sweep, then the
    // barrel on top of it. See its own doc; the sweep geometry (design
    // centre (60,72), radius 20.5) is unchanged, so it still traces each
    // skin's own accent ring exactly as before.
    //
    // FEEDBACK (2): a reloading gun used to be wrapped in a whitening
    // `ColorFilter` as well — a `Color.lerp(c, inkSoft, 0.6)` per pixel,
    // the same trick `ShipPainter._sunkFilter` uses for a wrecked hull.
    // On a wreck that reads as "destroyed"; on a gun that is simply
    // between shots it just washed every skin out to the same pale grey,
    // so for the ~55% of a match a cannon spends reloading you could not
    // tell WHICH gun was bolted on. The sweep alone already says
    // "reloading", and says it more precisely (it shows how far along),
    // so the gun now keeps its own colours the whole time.
    final muzzleCenter = paintLegacyCannon(
      canvas,
      center,
      outerR,
      id,
      recoilPull: recoilPull,
      // Only visible while actually reloading. When a shot misses the gun
      // stays instantly ready (cooldown 1.0) and the circle timer is
      // hidden entirely, so a miss produces no reload visuals at all.
      cooldown: cooldown,
    );

    // `mouthCenter`/`mouthR` anchor the muzzle flash and smoke below —
    // no bore-hole is drawn here any more. Each turret's own replayed
    // SVG art already carries its own genuine bore/rim detail (e.g.
    // MK-I's own `<ellipse cx="60" cy="11" .../>` mouth), so this used to
    // draw a second, generic dark circle right on top of it — the
    // "stray dot" every legacy skin showed at its muzzle.
    final mouthCenter = muzzleCenter;
    final mouthR = outerR * 0.12;

    // Muzzle flash while recoiling — see [_paintLegacyFlash].
    if (recoil > 0.05) {
      _paintLegacyFlash(
        canvas,
        mouthCenter - Offset(0, mouthR * (1.2 + recoil)),
        outerR * (0.34 + recoil * 0.5),
      );
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

  /// The bang itself, one per legacy gun.
  ///
  /// FEEDBACK ("the fire animation is the same on all of the cannons"):
  /// it genuinely was. [_paintLegacyExhaust] below has given each of the
  /// nine its own smoke since the shell rework, but the flash in FRONT
  /// of that smoke — the brightest, first thing a shot shows — stayed
  /// one hardcoded white-and-gold six-ray starburst for every gun, so
  /// the difference in the smoke behind it never got a chance to
  /// register. Colours now come from the same [legacyShellPalette] the
  /// shell and the exhaust already share, so a gun's muzzle, its smoke
  /// and its projectile finally all agree; the SHAPE of the burst varies
  /// too, because nine tints of the same starburst would still read as
  /// one animation.
  void _paintLegacyFlash(Canvas canvas, Offset c, double r) {
    final id = legacyCannonId ?? 'mk1';
    final p = legacyShellPalette(id);
    final fade = 1 - recoil;

    void disc(double radius, Color color, double alpha) => canvas.drawCircle(
        c, radius, Paint()..color = color.withValues(alpha: alpha.clamp(0, 1)));

    void rays(int count, double spread, double len, Color color, double width,
        {double alpha = 1, double skip = 0}) {
      final paint = Paint()
        ..color = color.withValues(alpha: (fade * alpha).clamp(0, 1))
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < count; i++) {
        final a = -math.pi / 2 + (i - (count - 1) / 2) * spread;
        final dir = Offset(math.cos(a), math.sin(a));
        canvas.drawLine(c + dir * (r * skip), c + dir * len, paint);
      }
    }

    // Shared bloom behind every burst, in this gun's own glow.
    disc(r * 1.35, p.glow, fade * 0.18);

    switch (id) {
      // Storm Circuit: no fireball at all — a white-hot core throwing
      // long, thin arcs well past the muzzle.
      case 'tesla':
        disc(r * 0.62, p.glow, fade);
        rays(5, 0.55, r * 2.1 * recoil, p.trim, 2.2, alpha: 0.95);
        rays(5, 0.55, r * 1.3 * recoil, p.glow, 1.0);
        break;

      // Ember Field: a big, hot, ragged fireball — the most fire of the
      // nine, with sparks thrown wide.
      case 'inferno':
        disc(r * 1.05, p.hull, fade * 0.8);
        disc(r * 0.9, p.trim, fade * 0.95);
        disc(r * 0.45, p.glow, fade);
        rays(9, 0.36, r * 1.5 * recoil, p.trim, 3.4);
        rays(5, 0.5, r * 2.0 * recoil, p.glow, 1.6, alpha: 0.8);
        break;

      // Shadow Veil: barely a flash — a hollow ring pushing outward,
      // matching the gun that fires rings rather than shells.
      case 'phantom':
        for (var i = 0; i < 2; i++) {
          canvas.drawCircle(
            c,
            r * (0.5 + 0.7 * recoil + i * 0.35),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = r * 0.16 * (1 - i * 0.4)
              ..color = p.trim.withValues(alpha: fade * (0.8 - i * 0.35)),
          );
        }
        disc(r * 0.32, p.glow, fade * 0.9);
        break;

      // Gilded Waters: a ceremonial eight-point star, long and short
      // rays alternating like a decoration.
      case 'royal':
        disc(r * 0.85, p.trim, fade * 0.95);
        disc(r * 0.42, p.glow, fade);
        rays(4, math.pi / 2, r * 1.8 * recoil, p.glow, 3.0);
        rays(4, math.pi / 2, r * 1.1 * recoil, p.trim, 2.4)
            ;
        break;

      // Toxic Marsh: a low, wide splatter with droplets falling off it
      // rather than a clean burst.
      case 'venom':
        disc(r * 0.85, p.trim, fade * 0.9);
        disc(r * 0.4, p.glow, fade);
        rays(4, 0.7, r * 1.35 * recoil, p.trim, 3.8);
        for (var i = 0; i < 3; i++) {
          final a = -math.pi / 2 + (i - 1) * 0.9;
          canvas.drawCircle(
            c + Offset(math.cos(a), math.sin(a)) * r * 1.5 * recoil,
            r * 0.16 * (1 - recoil * 0.4),
            Paint()..color = p.glow.withValues(alpha: fade * 0.8),
          );
        }
        break;

      // Deep-sea siege: a broad, soft pressure bloom — more shove than
      // spark, so almost no rays and a wide body.
      case 'kraken':
        disc(r * 1.25, p.hull, fade * 0.45);
        disc(r * 0.8, p.trim, fade * 0.85);
        disc(r * 0.36, p.glow, fade);
        rays(3, 0.85, r * 1.15 * recoil, p.glow, 2.6, alpha: 0.7);
        break;

      // High-energy golden shell: an even sunburst, rays all the way
      // round rather than a forward cone.
      case 'sunfire':
        disc(r * 0.8, p.trim, fade * 0.9);
        disc(r * 0.38, p.glow, fade);
        rays(8, math.pi / 4, r * 1.6 * recoil, p.trim, 2.8);
        rays(8, math.pi / 4, r * 0.95 * recoil, p.glow, 1.4);
        break;

      // Dark-matter launcher: an implosion. A dark core with a bright
      // rim, and its rays point INWARD.
      case 'void':
        disc(r * 0.95, p.ink, fade * 0.9);
        canvas.drawCircle(
          c,
          r * 0.95,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.18
            ..color = p.trim.withValues(alpha: fade),
        );
        disc(r * 0.22, p.glow, fade);
        rays(6, math.pi / 3, r * 1.0, p.trim, 2.2, alpha: 0.75, skip: 2.1);
        break;

      // MK-I and anything unrecognised: the plain powder flash the gun
      // has always had, just in its own palette rather than a fixed gold.
      case 'mk1':
      default:
        disc(r, p.trim, fade * 0.95);
        disc(r * 0.55, p.glow, fade);
        rays(6, 0.42, r * 1.25 * recoil, p.glow, 3.6);
        break;
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
    final recoilPull = barrelLen * 0.16 * recoil * kickMultiplier;

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

    // Ground shadow — per-family silhouette, not a single legacy oval.
    // The old family shadow reused the legacy oval (platformR*2.2) for
    // all six families. That fits a round mount but not the new
    // silhouettes: Pirate's spoked wheels sit 40px outside the plate,
    // Steam's bypass pipe and Volcanic's rock slab overhang the disc,
    // while Sci-Fi floats and needs a tighter, softer contact patch.
    // Each family now draws a shadow whose footprint matches its own
    // base width/height so no overhanging part appears shadowless.
    final shadowPaint = Paint()..color = Colors.black.withValues(alpha: 0.24);
    switch (fam.id) {
      case FleetFamilyId.pirate:
        // Wide timber carriage + two wheels: main plate shadow plus
        // two wheel contact patches.
        canvas.drawOval(
          Rect.fromCenter(
            center: mountCenter + Offset(0, platformR * 0.38),
            width: platformR * 3.4,
            height: platformR * 1.05,
          ),
          shadowPaint,
        );
        // Wheel shadows
        for (final dx in const [-1.05, 1.05]) {
          canvas.drawOval(
            Rect.fromCenter(
              center: mountCenter + Offset(dx * platformR, platformR * 0.52),
              width: platformR * 0.95,
              height: platformR * 0.55,
            ),
            Paint()..color = Colors.black.withValues(alpha: 0.18),
          );
        }
        break;
      case FleetFamilyId.naval:
        canvas.drawOval(
          Rect.fromCenter(
            center: mountCenter + Offset(0, platformR * 0.34),
            width: platformR * 2.75,
            height: platformR * 0.95,
          ),
          shadowPaint,
        );
        break;
      case FleetFamilyId.steam:
        // Broad boiler base + bypass pipe overhang
        canvas.drawOval(
          Rect.fromCenter(
            center: mountCenter + Offset(0, platformR * 0.36),
            width: platformR * 3.05,
            height: platformR * 1.0,
          ),
          shadowPaint,
        );
        break;
      case FleetFamilyId.arctic:
        canvas.drawOval(
          Rect.fromCenter(
            center: mountCenter + Offset(0, platformR * 0.36),
            width: platformR * 2.9,
            height: platformR * 1.0,
          ),
          shadowPaint,
        );
        break;
      case FleetFamilyId.volcanic:
        // Rock slab is widest and most irregular
        canvas.drawOval(
          Rect.fromCenter(
            center: mountCenter + Offset(0, platformR * 0.38),
            width: platformR * 3.2,
            height: platformR * 1.15,
          ),
          shadowPaint,
        );
        break;
      case FleetFamilyId.scifi:
        // Floating segments — smaller, softer contact patch
        canvas.drawOval(
          Rect.fromCenter(
            center: mountCenter + Offset(0, platformR * 0.30),
            width: platformR * 2.55,
            height: platformR * 0.82,
          ),
          Paint()..color = Colors.black.withValues(alpha: 0.20),
        );
        break;
    }

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
    // Sweep arc only while reloading — misses leave the gun at 1.0
    // and show no moving timer, matching the removed recoil animation.
    if (cooldown < 0.999) {
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
    }

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
      oldDelegate.kickMultiplier != kickMultiplier ||
      oldDelegate.ready != ready ||
      oldDelegate.family != family ||
      oldDelegate.legacyCannonId != legacyCannonId ||
      oldDelegate.smoke != smoke;
}

