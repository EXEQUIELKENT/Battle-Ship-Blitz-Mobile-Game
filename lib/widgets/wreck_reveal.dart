import 'dart:math';

import 'package:flutter/material.dart';

/// How a fleet goes down — one destruction motion per ship skin.
///
/// FEEDBACK ("create different animation transition to the ships when
/// destroyed since it is all the same popping out animation to all the
/// ships"): every wreck on every board used to play one shared 480ms
/// fade + `easeOutBack` scale, so a Toxic Wrecker hulk and a Rime Warden
/// icebreaker died in exactly the same way. Each of the fifteen hulls now
/// owns a motion that matches how that fleet reads: iron capsizes, ice
/// freezes stiff into place, magma slumps, sci-fi collapses inward.
///
/// The motion is chosen by the SUNK hull's own skin (unlike the impact FX,
/// which are keyed to the shooter's gun) — it is that fleet's ships being
/// destroyed, so it is that fleet's character that should show.
enum WreckMotion {
  settle,
  listRoll,
  swell,
  coinDrop,
  phase,
  crack,
  drift,
  wipe,
  bubbleUp,
  splinter,
  capsize,
  ventBurst,
  freezeIn,
  sag,
  collapseIn,
}

const Map<String, WreckMotion> _byShipSkin = {
  // ---- Legacy hulls ----
  'steel': WreckMotion.settle,
  'crimson': WreckMotion.listRoll,
  'emerald': WreckMotion.swell,
  'gold': WreckMotion.coinDrop,
  'abyss': WreckMotion.phase,
  'arctic': WreckMotion.crack,
  'coral': WreckMotion.drift,
  'midnight': WreckMotion.wipe,
  'toxic': WreckMotion.bubbleUp,
  // ---- Family fleets ----
  'f_pirate': WreckMotion.splinter,
  'f_naval': WreckMotion.capsize,
  'f_steam': WreckMotion.ventBurst,
  'f_arctic': WreckMotion.freezeIn,
  'f_volcanic': WreckMotion.sag,
  'f_scifi': WreckMotion.collapseIn,
};

/// The destruction motion for [shipSkinId], or the plain settle for an
/// unknown/absent hull.
WreckMotion wreckMotionForShipSkin(String? shipSkinId) =>
    _byShipSkin[shipSkinId] ?? WreckMotion.settle;

/// How long that motion takes. Heavier fleets take longer to go down.
Duration wreckRevealDuration(WreckMotion m) => switch (m) {
      WreckMotion.settle => const Duration(milliseconds: 480),
      WreckMotion.listRoll => const Duration(milliseconds: 560),
      WreckMotion.swell => const Duration(milliseconds: 620),
      WreckMotion.coinDrop => const Duration(milliseconds: 640),
      WreckMotion.phase => const Duration(milliseconds: 700),
      WreckMotion.crack => const Duration(milliseconds: 420),
      WreckMotion.drift => const Duration(milliseconds: 720),
      WreckMotion.wipe => const Duration(milliseconds: 320),
      WreckMotion.bubbleUp => const Duration(milliseconds: 660),
      WreckMotion.splinter => const Duration(milliseconds: 560),
      WreckMotion.capsize => const Duration(milliseconds: 700),
      WreckMotion.ventBurst => const Duration(milliseconds: 520),
      WreckMotion.freezeIn => const Duration(milliseconds: 760),
      WreckMotion.sag => const Duration(milliseconds: 680),
      WreckMotion.collapseIn => const Duration(milliseconds: 460),
    };

/// One frame of a wreck animation. Composed into a single [Matrix4] by
/// [WreckReveal] rather than a stack of nested `Transform` widgets, so a
/// board full of wrecks stays one transform each.
@immutable
class WreckFrame {
  final double scaleX;
  final double scaleY;
  final double rotation;
  final double dx;
  final double dy;
  final double opacity;

  const WreckFrame({
    this.scaleX = 1,
    this.scaleY = 1,
    this.rotation = 0,
    this.dx = 0,
    this.dy = 0,
    this.opacity = 1,
  });
}

/// Damped oscillation used by the shudder/bounce motions: starts at ±1 and
/// rings down to 0 by t == 1.
double _ring(double t, double cycles) =>
    sin(t * cycles * 2 * pi) * (1 - t) * (1 - t);

/// The wreck ARRIVING on the deck — the moment a hull is confirmed sunk.
///
/// [t] is the raw 0..1 controller value; each motion applies its own
/// curves. [span] is the ship's short-axis size in logical pixels, used to
/// scale translations so a destroyer and a carrier move by the same
/// visual proportion rather than the same absolute distance.
WreckFrame wreckRevealFrame(WreckMotion m, double t, double span) {
  switch (m) {
    case WreckMotion.settle:
      // The original shared motion, kept as Steel Fleet's own.
      final s = 0.72 + 0.28 * Curves.easeOutBack.transform(t);
      return WreckFrame(
        scaleX: s,
        scaleY: s,
        opacity: Curves.easeOut.transform((t / 0.6).clamp(0.0, 1.0)),
      );

    case WreckMotion.listRoll:
      // Rolls over to port and rights itself, dropping in as it goes.
      final e = Curves.easeOutBack.transform(t);
      return WreckFrame(
        scaleX: 0.85 + 0.15 * e,
        scaleY: 0.85 + 0.15 * e,
        rotation: -0.34 * (1 - Curves.easeOutCubic.transform(t)),
        dy: -span * 0.35 * (1 - Curves.easeOutCubic.transform(t)),
        opacity: Curves.easeOut.transform((t / 0.5).clamp(0.0, 1.0)),
      );

    case WreckMotion.swell:
      // Surges up from under the surface, stretching then settling.
      final rise = Curves.easeOutCubic.transform(t);
      final wob = _ring(t, 1.5) * 0.12;
      return WreckFrame(
        scaleX: 1 - wob,
        scaleY: (0.8 + 0.2 * rise) + wob,
        dy: span * 0.55 * (1 - rise),
        opacity: Curves.easeOut.transform((t / 0.45).clamp(0.0, 1.0)),
      );

    case WreckMotion.coinDrop:
      // Falls in and bounces twice, like something heavy and solid.
      final fall = Curves.easeInCubic.transform((t / 0.45).clamp(0.0, 1.0));
      final bounce = t <= 0.45 ? 0.0 : _ring((t - 0.45) / 0.55, 1.5).abs() * 0.22;
      return WreckFrame(
        scaleX: 1 + bounce * 0.4,
        scaleY: 1 - bounce * 0.4,
        dy: -span * 0.9 * (1 - fall) - span * bounce,
        opacity: (t / 0.25).clamp(0.0, 1.0),
      );

    case WreckMotion.phase:
      // Never scales — bleeds into existence from an after-image that
      // drifts in sideways, and flickers once on the way.
      final e = Curves.easeOutCubic.transform(t);
      final flicker = t < 0.55 ? 0.55 + 0.45 * sin(t * 22) : 1.0;
      return WreckFrame(
        dx: -span * 0.5 * (1 - e),
        // A linear ramp, not an ease-in: over this motion's long 700ms an
        // ease-in left the wreck effectively invisible for the first
        // ~280ms, which read as the reveal being broken rather than slow.
        opacity: (t * flicker).clamp(0.0, 1.0),
      );

    case WreckMotion.crack:
      // Arrives instantly at full size and shakes hard as it fractures.
      final shake = _ring(t, 4.5);
      return WreckFrame(
        scaleX: 1 + shake * 0.05,
        scaleY: 1 - shake * 0.05,
        rotation: shake * 0.07,
        dx: shake * span * 0.16,
        opacity: (t / 0.12).clamp(0.0, 1.0),
      );

    case WreckMotion.drift:
      // The slowest of the set — floats in on the current and rights.
      final e = Curves.easeOutSine.transform(t);
      return WreckFrame(
        scaleX: 0.92 + 0.08 * e,
        scaleY: 0.92 + 0.08 * e,
        rotation: 0.18 * (1 - e) * cos(t * 2.2),
        dx: span * 0.7 * (1 - e),
        dy: span * 0.18 * (1 - e),
        opacity: Curves.easeOut.transform((t / 0.7).clamp(0.0, 1.0)),
      );

    case WreckMotion.wipe:
      // Midnight Ops: no theatrics — it is simply there.
      return WreckFrame(
        scaleX: 0.98 + 0.02 * t,
        scaleY: 0.98 + 0.02 * t,
        opacity: Curves.easeOut.transform(t),
      );

    case WreckMotion.bubbleUp:
      // Rises on a jittery column of gas, opacity guttering as it comes.
      // The gutter is cut off before the end (as in [WreckMotion.phase]'s
      // flicker) so the wreck settles at EXACTLY opaque — an `Opacity`
      // that lands on 0.95 instead of 1.0 keeps its offscreen layer alive
      // for the rest of the match, on every wreck, forever.
      final rise = Curves.easeOutCubic.transform(t);
      final jit = _ring(t, 3.5);
      final gutter = t < 0.7 ? 0.85 + 0.15 * cos(t * 18) : 1.0;
      return WreckFrame(
        scaleX: 0.88 + 0.12 * rise + jit * 0.04,
        scaleY: 0.88 + 0.12 * rise - jit * 0.04,
        dx: jit * span * 0.1,
        dy: span * 0.4 * (1 - rise),
        opacity: ((t / 0.4).clamp(0.0, 1.0) * gutter).clamp(0.0, 1.0),
      );

    case WreckMotion.splinter:
      // Timber shudder: comes in oversized and rattles down to size.
      final e = Curves.easeOutCubic.transform(t);
      final shudder = _ring(t, 3.0);
      return WreckFrame(
        scaleX: 1.18 - 0.18 * e,
        scaleY: 1.18 - 0.18 * e,
        rotation: shudder * 0.11,
        dy: shudder * span * 0.12,
        opacity: (t / 0.3).clamp(0.0, 1.0),
      );

    case WreckMotion.capsize:
      // Heavy iron: a long, unhurried roll with no overshoot at all.
      final e = Curves.easeOutCubic.transform(t);
      return WreckFrame(
        scaleX: 0.9 + 0.1 * e,
        scaleY: 0.9 + 0.1 * e,
        rotation: -0.62 * (1 - e),
        dy: span * 0.3 * (1 - e),
        opacity: Curves.easeOut.transform((t / 0.55).clamp(0.0, 1.0)),
      );

    case WreckMotion.ventBurst:
      // Pressure release: pops well past size, then settles on a second,
      // smaller bounce.
      final pop = Curves.easeOutCubic.transform(t);
      final over = _ring(t, 1.25) * 0.2;
      return WreckFrame(
        scaleX: (0.7 + 0.3 * pop) + over,
        scaleY: (0.7 + 0.3 * pop) + over * 0.6,
        opacity: (t / 0.22).clamp(0.0, 1.0),
      );

    case WreckMotion.freezeIn:
      // Stiff and slow — linear-ish, no bounce, nothing organic.
      final e = Curves.easeInOutSine.transform(t);
      return WreckFrame(
        scaleX: 0.86 + 0.14 * e,
        scaleY: 0.86 + 0.14 * e,
        opacity: e,
      );

    case WreckMotion.sag:
      // Molten slump: starts tall and narrow, melts down and spreads.
      final e = Curves.easeOutCubic.transform(t);
      final settle = _ring(t, 1.0) * 0.08;
      return WreckFrame(
        scaleX: (0.82 + 0.18 * e) - settle,
        scaleY: (1.35 - 0.35 * e) + settle,
        dy: span * 0.2 * (1 - e),
        opacity: Curves.easeOut.transform((t / 0.5).clamp(0.0, 1.0)),
      );

    case WreckMotion.collapseIn:
      // Field collapse: implodes from oversized, strobing as it locks in.
      final e = Curves.easeInCubic.transform(t);
      final strobe = t < 0.7 ? (sin(t * 30) > 0 ? 1.0 : 0.45) : 1.0;
      return WreckFrame(
        // Starts at 1.45, not 1.75: `Transform` does not clip, so a wreck
        // that begins much larger than its own footprint paints over the
        // cells around it for the length of the animation.
        scaleX: 1.45 - 0.45 * e,
        scaleY: 1.45 - 0.45 * e,
        opacity: ((t / 0.35).clamp(0.0, 1.0) * strobe).clamp(0.0, 1.0),
      );
  }
}

/// The wreck LEAVING the deck — GHOST FLEET and PHANTOM show a sinking
/// hull for a moment and then take it away again rather than leaving a
/// permanent wreck (see `_GhostSinkingShip`). Same fleet character as
/// [wreckRevealFrame], played as a departure: everything sinks and fades,
/// but each fleet rolls, squashes and lists its own way on the way down.
WreckFrame wreckSinkFrame(WreckMotion m, double t, double span) {
  final sink = Curves.easeInCubic.transform(t);
  final fade = 1 - Curves.easeIn.transform(((t - 0.35) / 0.65).clamp(0.0, 1.0));
  // Per-fleet character on the way down: (roll, extra squash, wobble).
  final (roll, squash, wobble) = switch (m) {
    WreckMotion.settle => (0.0, 0.0, 0.0),
    WreckMotion.listRoll => (-0.45, 0.0, 0.0),
    WreckMotion.swell => (0.0, 0.14, 1.5),
    WreckMotion.coinDrop => (0.0, 0.0, 2.5),
    WreckMotion.phase => (0.0, 0.0, 0.0),
    WreckMotion.crack => (0.10, 0.0, 5.0),
    WreckMotion.drift => (0.26, 0.0, 1.0),
    WreckMotion.wipe => (0.0, 0.0, 0.0),
    WreckMotion.bubbleUp => (0.0, 0.10, 3.5),
    WreckMotion.splinter => (0.20, 0.0, 3.0),
    WreckMotion.capsize => (-0.85, 0.0, 0.0),
    WreckMotion.ventBurst => (0.0, -0.16, 1.25),
    WreckMotion.freezeIn => (0.0, 0.0, 0.0),
    WreckMotion.sag => (0.0, 0.30, 0.0),
    WreckMotion.collapseIn => (0.0, 0.0, 0.0),
  };
  final wob = wobble == 0 ? 0.0 : sin(t * wobble * 2 * pi) * (1 - t) * 0.06;
  // Phase and collapse dissolve rather than sink, so they barely move.
  final drops = m != WreckMotion.phase && m != WreckMotion.collapseIn;
  final shrink = m == WreckMotion.collapseIn ? 1 - 0.45 * sink : 1 - 0.08 * sink;
  return WreckFrame(
    scaleX: shrink - squash * sink + wob,
    scaleY: shrink + squash * sink - wob,
    rotation: roll * sink,
    dy: drops ? span * 0.55 * sink : 0,
    opacity: m == WreckMotion.phase ? (1 - t).clamp(0.0, 1.0) : fade,
  );
}

/// Builds the single [Transform] (plus an [Opacity] only while it is
/// actually translucent) for one [WreckFrame].
///
/// PERF: `Opacity` allocates an offscreen layer for any value strictly
/// between 0 and 1, so it is omitted entirely once the animation has
/// settled at full opacity — which is the state a wreck spends the rest of
/// the match in, and a board can accumulate ten of them.
Widget buildWreckFrame(WreckFrame f, Widget child) {
  final transformed = Transform(
    alignment: Alignment.center,
    transform: Matrix4.identity()
      ..translateByDouble(f.dx, f.dy, 0, 1)
      ..rotateZ(f.rotation)
      ..scaleByDouble(f.scaleX, f.scaleY, 1, 1),
    child: child,
  );
  if (f.opacity >= 1.0) return transformed;
  return Opacity(opacity: f.opacity.clamp(0.0, 1.0), child: transformed);
}

/// One-shot destruction transition for a sunk ship's wreck graphic, keyed
/// to the sunk hull's own fleet (see [WreckMotion]).
///
/// Plays exactly once, starting the moment this widget is first mounted —
/// which, since the parent keys each wreck by `ship.spec.kind`/row/col
/// (see `_destroyedShipWidgets`), is precisely when that ship enters
/// `destroyedShips` for the first time. Later rebuilds reuse the same
/// element/State, so the animation is never re-triggered on an
/// already-revealed wreck.
class WreckReveal extends StatefulWidget {
  final WreckMotion motion;

  /// The ship's short-axis size in logical pixels — one grid cell. Scales
  /// the motions that translate so they read the same on any grid size.
  final double span;

  /// Fired once the motion has finished and the wreck is sitting still.
  /// The grid uses it to retire the wreck into its shared cached layer —
  /// see `_BattleGridState._destroyedShipWidgets` for why that matters.
  final VoidCallback? onSettled;

  final Widget child;

  const WreckReveal({
    super.key,
    required this.motion,
    required this.span,
    this.onSettled,
    required this.child,
  });

  @override
  State<WreckReveal> createState() => _WreckRevealState();
}

class _WreckRevealState extends State<WreckReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: wreckRevealDuration(widget.motion),
    );
    _ctrl.forward().whenComplete(() {
      if (mounted) widget.onSettled?.call();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      // PERF, and a deliberate exception to this codebase's usual rule
      // that a `RepaintBoundary` must never sit INSIDE a `Transform`.
      //
      // That rule exists because a cached raster under a changing
      // transform has to be resampled every frame, so it usually buys
      // nothing and only softens the artwork. Both halves of that
      // reasoning fail here, which is what makes this the one place it is
      // worth doing:
      //  * The content is genuinely EXPENSIVE — a wreck is the single
      //    costliest thing on the board, ~2ms of raster (a `saveLayer`
      //    for the charring filter, plus a gradient wound on every cell of
      //    the hull), against ~0.5ms for a whole impact effect. Measured.
      //  * The content is genuinely STATIC. Nothing inside changes over
      //    the animation; only the frame's scale/rotation/offset does. So
      //    the raster is recorded once instead of ~90 times over a 760ms
      //    destruction on a 120Hz screen.
      // The resampling softness only exists WHILE the wreck is in motion,
      // which is exactly when it cannot be examined — and the moment it
      // settles the grid swaps it out of here and into the shared settled
      // layer (see `_BattleGridState._destroyedShipWidgets`), where it is
      // re-rastered crisply at native resolution and this layer is gone.
      child: RepaintBoundary(child: widget.child),
      builder: (context, child) => buildWreckFrame(
        wreckRevealFrame(widget.motion, _ctrl.value, widget.span),
        child!,
      ),
    );
  }
}
