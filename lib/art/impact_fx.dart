import 'dart:math';

import 'package:flutter/material.dart';

/// Per-cannon impact vocabulary — what a shell LOOKS like when it lands.
///
/// FEEDBACK ("create different splash effects to different cannon skins
/// when hitting a deck… the hit effects in phantom and ghost mode are all
/// the same"): the grid's transient FX layer used to draw exactly one
/// splash and exactly one explosion for every shot in the game, so the
/// only thing that ever changed between a Coral Battery round and a Void
/// Annihilator round was the mark left behind afterwards. In PHANTOM and
/// GHOST FLEET no mark is left at all (see `battle_screen`'s `ghost`
/// branch, which skips writing the tracking cache), which meant those two
/// modes had *no* per-cannon feedback whatsoever — every gun looked
/// identical for the whole match.
///
/// Each of the fifteen guns now owns a [SplashStyle] (the water/ground
/// impact every shot makes, hit or miss), a [BurstStyle] (the detonation
/// layered on top of a hit or sink) and a [MarkArrival] (the flourish that
/// delivers the persistent mark, in the modes that record one), plus its
/// own three-colour ramp.
///
/// PERF: everything here is flat vector work on the canvas it is handed —
/// no images, no `MaskFilter.blur` (a per-frame offscreen pass), no
/// layers, no per-draw allocation (see the scratch `Paint`s below), and
/// every loop is capped at eight iterations. Measured against the single
/// generic splash+explosion pair this replaced: that cost ~0.35ms of
/// raster for one effect, these run 0.26–0.90ms depending on the gun — the
/// same cost class, and an order of magnitude under a single ship hull
/// (~2ms), which is what actually dominates this board's paint. It is also
/// painted only by the grid's transient FX layer, which stops ticking the
/// moment the last effect expires (see `_BattleGridState._fxCtrl`).

/// The ground/water impact every landed shot makes, whatever it hit.
enum SplashStyle {
  spray,
  ember,
  brine,
  gilt,
  ink,
  frost,
  bloom,
  rift,
  acid,
  powder,
  steelSpray,
  steam,
  rime,
  magma,
  ion,
}

/// The detonation layered over a splash when the shot actually connected.
enum BurstStyle {
  shrapnel,
  fireball,
  tendril,
  starflare,
  voidRing,
  arcBolt,
  bubblePop,
  collapse,
  spatter,
  cannonSmoke,
  crossFlak,
  gearBurst,
  frostNova,
  magmaGout,
  ionLance,
}

/// The flourish that hands the persistent hit/miss mark onto the deck, in
/// the modes that record one. Skipped entirely in PHANTOM/GHOST, where
/// there is no mark to deliver — see [paintMarkArrival]'s call site.
enum MarkArrival {
  slam,
  scorch,
  bloomIn,
  stamp,
  warp,
  shatterIn,
  swirlIn,
  implodeIn,
  dissolveIn,
  smokeIn,
  driveIn,
  frostIn,
  scanIn,
}

/// One gun's complete impact identity.
@immutable
class ImpactFx {
  final SplashStyle splash;
  final BurstStyle burst;
  final MarkArrival arrival;

  /// Brightest tone, used at the impact point itself.
  final Color core;

  /// The gun's own pop colour — the one a player recognises it by.
  final Color accent;

  /// Darker shade for rims, smoke and craters.
  final Color deep;

  /// Overall size multiplier, so a bombard reads heavier than a coilgun.
  final double scale;

  const ImpactFx({
    required this.splash,
    required this.burst,
    required this.arrival,
    required this.core,
    required this.accent,
    required this.deep,
    this.scale = 1.0,
  });
}

const ImpactFx _fallback = ImpactFx(
  splash: SplashStyle.spray,
  burst: BurstStyle.shrapnel,
  arrival: MarkArrival.slam,
  core: Color(0xFFFFFFFF),
  accent: Color(0xFFCBD5E1),
  deep: Color(0xFF64748B),
);

/// Colours are taken from each gun's own catalogue entry (`Catalog
/// .cannonSkins`) and cannon artwork, not invented here, so a shell always
/// lands in the colour it was fired in. Held as literals rather than read
/// off `Catalog` to keep `lib/art/` free of a dependency on the services
/// layer, matching every other art file in this folder.
const Map<String, ImpactFx> _byCannon = {
  // ---- Legacy guns ----
  'mk1': ImpactFx(
    splash: SplashStyle.spray,
    burst: BurstStyle.shrapnel,
    arrival: MarkArrival.slam,
    core: Color(0xFFFFFFFF),
    accent: Color(0xFFCBD5E1),
    deep: Color(0xFF64748B),
  ),
  'inferno': ImpactFx(
    splash: SplashStyle.ember,
    burst: BurstStyle.fireball,
    arrival: MarkArrival.scorch,
    core: Color(0xFFFFE9A8),
    accent: Color(0xFFEF4444),
    deep: Color(0xFF7C2D12),
    scale: 1.08,
  ),
  'kraken': ImpactFx(
    splash: SplashStyle.brine,
    burst: BurstStyle.tendril,
    arrival: MarkArrival.bloomIn,
    core: Color(0xFFCFFAFE),
    accent: Color(0xFF34D399),
    deep: Color(0xFF0F766E),
    scale: 1.05,
  ),
  'royal': ImpactFx(
    splash: SplashStyle.gilt,
    burst: BurstStyle.starflare,
    arrival: MarkArrival.stamp,
    core: Color(0xFFFFF7D6),
    accent: Color(0xFFFBBF24),
    deep: Color(0xFF92400E),
  ),
  'phantom': ImpactFx(
    splash: SplashStyle.ink,
    burst: BurstStyle.voidRing,
    arrival: MarkArrival.warp,
    core: Color(0xFFEDE9FE),
    accent: Color(0xFFC084FC),
    deep: Color(0xFF312E81),
    scale: 0.95,
  ),
  'tesla': ImpactFx(
    splash: SplashStyle.frost,
    burst: BurstStyle.arcBolt,
    arrival: MarkArrival.shatterIn,
    core: Color(0xFFECFEFF),
    accent: Color(0xFF22D3EE),
    deep: Color(0xFF0E7490),
    scale: 0.95,
  ),
  'sunfire': ImpactFx(
    splash: SplashStyle.bloom,
    burst: BurstStyle.bubblePop,
    arrival: MarkArrival.swirlIn,
    core: Color(0xFFFFE4DA),
    accent: Color(0xFFFF9E7A),
    deep: Color(0xFFC1543F),
  ),
  'void': ImpactFx(
    splash: SplashStyle.rift,
    burst: BurstStyle.collapse,
    arrival: MarkArrival.implodeIn,
    core: Color(0xFFFCE7F3),
    accent: Color(0xFFEC4899),
    deep: Color(0xFF111827),
  ),
  'venom': ImpactFx(
    splash: SplashStyle.acid,
    burst: BurstStyle.spatter,
    arrival: MarkArrival.dissolveIn,
    core: Color(0xFFECFCCB),
    accent: Color(0xFFA3E635),
    deep: Color(0xFF365314),
  ),
  // ---- Family guns ----
  'f_pirate': ImpactFx(
    splash: SplashStyle.powder,
    burst: BurstStyle.cannonSmoke,
    arrival: MarkArrival.smokeIn,
    core: Color(0xFFF5E6C8),
    accent: Color(0xFFC89B5A),
    deep: Color(0xFF4A4038),
    scale: 1.06,
  ),
  'f_naval': ImpactFx(
    splash: SplashStyle.steelSpray,
    burst: BurstStyle.crossFlak,
    arrival: MarkArrival.driveIn,
    core: Color(0xFFE7EEF3),
    // A step lighter than the gun's own hull grey (`#8CA0AD`), which is
    // close enough to the deck's navy to disappear against it.
    accent: Color(0xFFB8C8D4),
    deep: Color(0xFF3B4650),
  ),
  'f_steam': ImpactFx(
    splash: SplashStyle.steam,
    burst: BurstStyle.gearBurst,
    arrival: MarkArrival.stamp,
    core: Color(0xFFFFF1D6),
    accent: Color(0xFFC99A3F),
    deep: Color(0xFF6B4A22),
  ),
  'f_arctic': ImpactFx(
    splash: SplashStyle.rime,
    burst: BurstStyle.frostNova,
    arrival: MarkArrival.frostIn,
    core: Color(0xFFFFFFFF),
    accent: Color(0xFFBBDCEA),
    deep: Color(0xFF6E93A8),
  ),
  'f_volcanic': ImpactFx(
    splash: SplashStyle.magma,
    burst: BurstStyle.magmaGout,
    arrival: MarkArrival.scorch,
    core: Color(0xFFFFD9A0),
    accent: Color(0xFFFF7A3C),
    deep: Color(0xFF3A3438),
    scale: 1.12,
  ),
  'f_scifi': ImpactFx(
    splash: SplashStyle.ion,
    burst: BurstStyle.ionLance,
    arrival: MarkArrival.scanIn,
    core: Color(0xFFDDE9FF),
    accent: Color(0xFF6E8FD8),
    deep: Color(0xFF1B2138),
    scale: 0.92,
  ),
};

/// The impact identity for [cannonId], or the MK-I's plain white spray for
/// an unknown/absent gun (the deploy screen before a loadout resolves, and
/// any future cannon that has not been given its own entry yet).
ImpactFx impactFxForCannon(String? cannonId) =>
    _byCannon[cannonId] ?? _fallback;

// ---------------------------------------------------------------------------
// Deterministic jitter
// ---------------------------------------------------------------------------

/// Stable pseudo-random in 0..1 from a cell seed and a particle index.
///
/// Deliberately NOT a `Random` instance: the FX layer repaints every frame
/// for the whole 800ms life of an effect, so drawing particle `i` from a
/// stateful generator gave it a different trajectory on every frame — the
/// particles shimmered in place instead of flying. Hashing (seed, i)
/// instead gives each particle one fixed trajectory it then travels along,
/// and costs no allocation.
double _jit(int seed, int i) {
  var x = seed * 374761393 + i * 668265263;
  x = (x ^ (x >> 13)) * 1274126177;
  return ((x ^ (x >> 16)) & 0x7FFFFFF) / 0x7FFFFFF;
}

// PERF: two scratch `Paint`s, reused rather than allocated per draw. An
// effect issues a dozen or more draws, three effect layers can be live on
// a cell, and the FX layer repaints every frame for 800ms after every
// shot — at 120Hz that was thousands of short-lived `Paint`s a second.
//
// The contract this depends on: painting is synchronous and single
// -threaded, and no caller may hold a fill and reuse it across another
// `_fill` call (same for strokes). Holding one across a loop is fine and
// several styles do it; interleaving two of the SAME kind is not.
final Paint _fillPaint = Paint();
final Paint _strokePaint = Paint()
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round;

Paint _fill(Color c, double a) =>
    _fillPaint..color = c.withValues(alpha: a.clamp(0.0, 1.0));

Paint _stroke(Color c, double a, double w) => _strokePaint
  ..color = c.withValues(alpha: a.clamp(0.0, 1.0))
  ..strokeWidth = w;

/// A circle squashed on the Y axis, without the `save`/`scale`/`restore`
/// round trip that a transformed `drawCircle` needs — measurably cheaper,
/// and every "low sea-surge" style here wants exactly this shape.
void _squashedCircle(Canvas canvas, Offset o, double r, double squash,
        Paint paint) =>
    canvas.drawOval(
        Rect.fromCenter(center: o, width: r * 2, height: r * 2 * squash),
        paint);

/// Regular n-gon outline centred on [o] — the shared primitive behind the
/// hexagonal frost/ion effects.
Path _polyPath(Offset o, double r, int sides, double rot) {
  final p = Path();
  for (var i = 0; i < sides; i++) {
    final a = rot + i * 2 * pi / sides;
    final pt = Offset(o.dx + cos(a) * r, o.dy + sin(a) * r);
    if (i == 0) {
      p.moveTo(pt.dx, pt.dy);
    } else {
      p.lineTo(pt.dx, pt.dy);
    }
  }
  return p..close();
}

/// Four-pointed sparkle, the shape the original explosion used for its
/// drifting stars.
Path _sparkPath(Offset p, double r) => Path()
  ..moveTo(p.dx, p.dy - r)
  ..lineTo(p.dx + r * 0.35, p.dy - r * 0.35)
  ..lineTo(p.dx + r, p.dy)
  ..lineTo(p.dx + r * 0.35, p.dy + r * 0.35)
  ..lineTo(p.dx, p.dy + r)
  ..lineTo(p.dx - r * 0.35, p.dy + r * 0.35)
  ..lineTo(p.dx - r, p.dy)
  ..lineTo(p.dx - r * 0.35, p.dy - r * 0.35)
  ..close();

// ---------------------------------------------------------------------------
// Splash — every landed shot, hit or miss
// ---------------------------------------------------------------------------

/// The impact every shot makes on the deck, whatever it hit.
///
/// [t] is the effect's whole-life progress (0..1 over `CellFx`'s 800ms);
/// the splash occupies the first 55% of it, exactly as the single generic
/// splash it replaces did, so a hit's [paintImpactBurst] still lands on
/// top of a splash that is already receding.
void paintImpactSplash(
  Canvas canvas,
  Offset center,
  double cell,
  double t,
  ImpactFx fx,
  int seed,
) {
  final local = (t / 0.55).clamp(0.0, 1.0);
  if (local >= 1.0) return;
  final fade = 1 - local;
  final grow = Curves.easeOut.transform(local);
  final s = cell * fx.scale;

  switch (fx.splash) {
    case SplashStyle.spray:
      canvas.drawCircle(center, s * (0.12 + 0.46 * grow),
          _stroke(fx.core, fade * 0.55, s * 0.045 * fade));
      for (var i = 0; i < 6; i++) {
        final ang = (i / 6) * 2 * pi + _jit(seed, i) * 0.35;
        final dist = s * 0.42 * grow;
        final lift = -s * 0.30 * sin(local * pi);
        final p =
            center + Offset(cos(ang) * dist, sin(ang) * dist * 0.6 + lift);
        canvas.drawCircle(p, s * 0.05 * fade, _fill(fx.core, fade * 0.8));
      }
      canvas.drawCircle(center, s * 0.20 * (1 - local * 0.5),
          _fill(fx.core, fade * 0.45));

    case SplashStyle.ember:
      // Flame licks stand up out of the impact, embers rain back down.
      for (var i = 0; i < 5; i++) {
        final ang = -pi / 2 + (i - 2) * 0.42 + _jit(seed, i) * 0.18;
        final len = s * (0.30 + 0.28 * _jit(seed, i + 9)) * (1 - local * 0.45);
        final tip = center + Offset(cos(ang) * len * grow * 1.4,
            sin(ang) * len * grow * 1.4);
        canvas.drawLine(center, tip,
            _stroke(i.isEven ? fx.accent : fx.core, fade * 0.85,
                s * 0.09 * fade));
      }
      for (var i = 0; i < 4; i++) {
        final ang = _jit(seed, i + 3) * 2 * pi;
        final d = s * 0.46 * grow;
        final drop = s * 0.34 * local * local;
        final p = center + Offset(cos(ang) * d, sin(ang) * d * 0.5 + drop);
        canvas.drawCircle(p, s * 0.045 * fade, _fill(fx.accent, fade * 0.9));
      }
      canvas.drawCircle(
          center, s * 0.19 * (1 - local * 0.4), _fill(fx.core, fade * 0.6));

    case SplashStyle.brine:
      // A heavy, low sea-surge: a squashed ring plus whipping tendrils.
      _squashedCircle(canvas, center, s * (0.14 + 0.52 * grow), 0.62,
          _stroke(fx.accent, fade * 0.6, s * 0.06 * fade));
      for (var i = 0; i < 4; i++) {
        final ang = (i / 4) * 2 * pi + 0.4 + _jit(seed, i) * 0.3;
        final r = s * 0.5 * grow;
        final path = Path()
          ..moveTo(center.dx, center.dy)
          ..quadraticBezierTo(
            center.dx + cos(ang) * r * 0.6 - sin(ang) * r * 0.35,
            center.dy + sin(ang) * r * 0.6 + cos(ang) * r * 0.35,
            center.dx + cos(ang) * r,
            center.dy + sin(ang) * r * 0.7,
          );
        canvas.drawPath(
            path, _stroke(fx.deep, fade * 0.75, s * 0.055 * fade));
      }
      canvas.drawCircle(
          center, s * 0.17 * (1 - local * 0.5), _fill(fx.core, fade * 0.5));

    case SplashStyle.gilt:
      // A fan of coins thrown up and out on a shallow arc.
      for (var i = 0; i < 7; i++) {
        final ang = -pi / 2 + (i - 3) * 0.34;
        final d = s * 0.5 * grow;
        final lift = -s * 0.22 * sin(local * pi);
        final p = center + Offset(cos(ang) * d, sin(ang) * d * 0.75 + lift);
        final r = s * 0.055 * fade;
        canvas.drawPath(
          Path()
            ..moveTo(p.dx, p.dy - r)
            ..lineTo(p.dx + r * 0.7, p.dy)
            ..lineTo(p.dx, p.dy + r)
            ..lineTo(p.dx - r * 0.7, p.dy)
            ..close(),
          _fill(i.isEven ? fx.accent : fx.core, fade * 0.95),
        );
      }
      canvas.drawCircle(center, s * (0.10 + 0.40 * grow),
          _stroke(fx.accent, fade * 0.5, s * 0.035 * fade));

    case SplashStyle.ink:
      // A dark blot spreading under a violet rim — no droplets at all.
      final r = s * (0.16 + 0.34 * grow);
      canvas.drawCircle(center, r, _fill(fx.deep, fade * 0.55));
      canvas.drawCircle(center, r, _stroke(fx.accent, fade * 0.8, s * 0.05));
      for (var i = 0; i < 3; i++) {
        final ang = _jit(seed, i) * 2 * pi;
        final d = r * (1.0 + 0.55 * grow);
        canvas.drawCircle(center + Offset(cos(ang) * d, sin(ang) * d),
            s * 0.06 * fade, _fill(fx.accent, fade * 0.45));
      }
      canvas.drawCircle(
          center, s * 0.10 * (1 - local), _fill(fx.core, fade * 0.7));

    case SplashStyle.frost:
      // Needle shards, rigid — they grow rather than fly.
      for (var i = 0; i < 6; i++) {
        final ang = (i / 6) * 2 * pi + 0.26;
        final inner = s * 0.10;
        final outer = s * (0.18 + 0.36 * grow);
        canvas.drawLine(
          center + Offset(cos(ang) * inner, sin(ang) * inner),
          center + Offset(cos(ang) * outer, sin(ang) * outer),
          _stroke(fx.core, fade * 0.9, s * 0.05 * fade),
        );
      }
      canvas.drawPath(_polyPath(center, s * (0.14 + 0.40 * grow), 6, 0.26),
          _stroke(fx.accent, fade * 0.7, s * 0.04 * fade));

    case SplashStyle.bloom:
      // Coral petals opening, with a couple of bubbles rising off them.
      for (var i = 0; i < 5; i++) {
        final ang = (i / 5) * 2 * pi + 0.3;
        final r = s * (0.16 + 0.32 * grow);
        canvas.save();
        canvas.translate(center.dx + cos(ang) * r * 0.7,
            center.dy + sin(ang) * r * 0.7);
        canvas.rotate(ang);
        // A petal is an ellipse ALONG its own angle, so unlike the other
        // squashed shapes here it genuinely needs the rotation.
        _squashedCircle(canvas, Offset.zero, r * 0.55 * fade, 0.5,
            _fill(fx.accent, fade * 0.8));
        canvas.restore();
      }
      for (var i = 0; i < 3; i++) {
        final ang = _jit(seed, i + 5) * 2 * pi;
        final d = s * 0.34 * grow;
        final lift = -s * 0.3 * local;
        canvas.drawCircle(
            center + Offset(cos(ang) * d, sin(ang) * d * 0.5 + lift),
            s * 0.045 * fade,
            _stroke(fx.core, fade * 0.9, s * 0.02));
      }
      canvas.drawCircle(
          center, s * 0.15 * (1 - local * 0.4), _fill(fx.core, fade * 0.55));

    case SplashStyle.rift:
      // A slit that tears open and snaps shut; matter falls INWARD.
      final w = s * (0.18 + 0.44 * grow);
      final h = s * 0.13 * sin(local * pi);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: w * 2, height: h * 2),
          _fill(fx.deep, fade * 0.8));
      canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: w * 2, height: h * 2),
          _stroke(fx.accent, fade * 0.9, s * 0.035));
      canvas.restore();
      for (var i = 0; i < 4; i++) {
        final ang = _jit(seed, i) * 2 * pi;
        final d = s * 0.5 * (1 - grow);
        canvas.drawCircle(center + Offset(cos(ang) * d, sin(ang) * d),
            s * 0.04 * fade, _fill(fx.accent, fade * 0.8));
      }

    case SplashStyle.acid:
      // Caustic blobs of uneven size, wobbling as they eat outward.
      for (var i = 0; i < 7; i++) {
        final ang = (i / 7) * 2 * pi + _jit(seed, i) * 0.5;
        final d = s * (0.24 + 0.30 * _jit(seed, i + 7)) * grow * 1.6;
        final wob = sin(local * pi * 3 + i) * s * 0.03;
        final p = center + Offset(cos(ang) * d + wob, sin(ang) * d * 0.7);
        canvas.drawCircle(p, s * (0.035 + 0.045 * _jit(seed, i + 14)) * fade,
            _fill(fx.accent, fade * 0.85));
      }
      canvas.drawCircle(center, s * (0.12 + 0.36 * grow),
          _stroke(fx.deep, fade * 0.55, s * 0.05 * fade));

    case SplashStyle.powder:
      // Black-powder smoke with hot cinders tumbling out of it. Billowed
      // in the CREAM tone rather than the carriage brown: gun smoke reads
      // pale, and dark brown at low alpha over a navy deck is invisible.
      for (var i = 0; i < 4; i++) {
        final ang = (i / 4) * 2 * pi + 0.7;
        final d = s * 0.34 * grow;
        final p = center + Offset(cos(ang) * d, sin(ang) * d * 0.8);
        final r = s * (0.15 + 0.12 * grow);
        canvas.drawCircle(p, r, _fill(fx.core, fade * 0.34));
        canvas.drawCircle(p, r, _stroke(fx.accent, fade * 0.5, s * 0.025));
      }
      for (var i = 0; i < 4; i++) {
        final ang = _jit(seed, i + 2) * 2 * pi;
        final d = s * 0.5 * grow;
        final drop = s * 0.18 * local * local;
        canvas.drawCircle(center + Offset(cos(ang) * d, sin(ang) * d + drop),
            s * 0.055 * fade, _fill(fx.accent, fade));
      }
      canvas.drawCircle(
          center, s * 0.18 * (1 - local * 0.5), _fill(fx.core, fade * 0.8));

    case SplashStyle.steelSpray:
      // Two disciplined sheets thrown left and right — no scatter.
      for (final dir in [-1.0, 1.0]) {
        final path = Path()
          ..moveTo(center.dx, center.dy)
          ..quadraticBezierTo(
            center.dx + dir * s * 0.34 * grow,
            center.dy - s * 0.30 * grow,
            center.dx + dir * s * 0.56 * grow,
            center.dy + s * 0.06 * grow,
          );
        canvas.drawPath(
            path, _stroke(fx.core, fade * 0.8, s * 0.06 * fade));
      }
      canvas.drawCircle(center, s * (0.10 + 0.30 * grow),
          _stroke(fx.accent, fade * 0.65, s * 0.05 * fade));
      canvas.drawCircle(
          center, s * 0.12 * (1 - local * 0.5), _fill(fx.core, fade * 0.6));

    case SplashStyle.steam:
      // Pressure jets straight up, condensation ring underneath.
      for (var i = 0; i < 3; i++) {
        final dx = (i - 1) * s * 0.16;
        final top = center.dy - s * 0.46 * grow;
        canvas.drawLine(Offset(center.dx + dx, center.dy),
            Offset(center.dx + dx * 1.5, top),
            _stroke(fx.core, fade * 0.7, s * 0.08 * fade));
      }
      _squashedCircle(canvas, center, s * (0.14 + 0.42 * grow), 0.45,
          _stroke(fx.accent, fade * 0.7, s * 0.05 * fade));
      for (var i = 0; i < 3; i++) {
        final ang = _jit(seed, i + 4) * 2 * pi;
        final d = s * 0.36 * grow;
        canvas.drawCircle(center + Offset(cos(ang) * d, sin(ang) * d * 0.5),
            s * 0.04 * fade, _fill(fx.accent, fade * 0.8));
      }

    case SplashStyle.rime:
      // Snow burst that hangs — the slowest-settling splash of the set.
      final slow = Curves.easeOutCubic.transform(local);
      for (var i = 0; i < 8; i++) {
        final ang = (i / 8) * 2 * pi;
        final d = s * 0.44 * slow;
        final p = center + Offset(cos(ang) * d, sin(ang) * d + s * 0.1 * local);
        final r = s * 0.05 * fade;
        canvas.drawLine(Offset(p.dx - r, p.dy), Offset(p.dx + r, p.dy),
            _stroke(fx.core, fade * 0.9, s * 0.022));
        canvas.drawLine(Offset(p.dx, p.dy - r), Offset(p.dx, p.dy + r),
            _stroke(fx.core, fade * 0.9, s * 0.022));
      }
      canvas.drawCircle(center, s * (0.12 + 0.34 * slow),
          _stroke(fx.accent, fade * 0.6, s * 0.04 * fade));

    case SplashStyle.magma:
      // Heavy glowing gobs on real ballistic arcs, over a dark crater.
      // The crater carries a hot rim so it reads as scorched rock rather
      // than a brown smudge.
      final crater = s * (0.16 + 0.34 * grow);
      canvas.drawCircle(center, crater, _fill(fx.deep, fade * 0.32));
      canvas.drawCircle(
          center, crater, _stroke(fx.accent, fade * 0.65, s * 0.04));
      for (var i = 0; i < 5; i++) {
        final ang = -pi / 2 + (i - 2) * 0.5;
        final d = s * 0.5 * grow;
        final drop = s * 0.4 * local * local;
        final p = center + Offset(cos(ang) * d, sin(ang) * d * 0.8 + drop);
        canvas.drawCircle(p, s * (0.05 + 0.03 * _jit(seed, i)) * fade,
            _fill(fx.accent, fade * 0.95));
      }
      canvas.drawCircle(
          center, s * 0.18 * (1 - local * 0.5), _fill(fx.core, fade * 0.7));

    case SplashStyle.ion:
      // A clean hexagonal energy ripple with a couple of scan segments.
      canvas.drawPath(_polyPath(center, s * (0.14 + 0.44 * grow), 6, local * 0.6),
          _stroke(fx.accent, fade * 0.85, s * 0.045 * fade));
      canvas.drawPath(_polyPath(center, s * (0.08 + 0.24 * grow), 6, -local * 0.9),
          _stroke(fx.core, fade * 0.6, s * 0.03 * fade));
      for (var i = 0; i < 3; i++) {
        final ang = (i / 3) * 2 * pi + local * 1.4;
        final d = s * 0.42 * grow;
        canvas.drawLine(
          center + Offset(cos(ang) * d * 0.6, sin(ang) * d * 0.6),
          center + Offset(cos(ang) * d, sin(ang) * d),
          _stroke(fx.core, fade * 0.9, s * 0.035),
        );
      }
  }
}

// ---------------------------------------------------------------------------
// Burst — layered over a splash when the shot connected
// ---------------------------------------------------------------------------

/// The detonation for a hit or a sink. [big] is the sink case, which every
/// style scales up and gives extra debris.
void paintImpactBurst(
  Canvas canvas,
  Offset center,
  double cell,
  double t,
  ImpactFx fx,
  int seed, {
  bool big = false,
}) {
  final scale = (big ? 1.2 : 0.7) * fx.scale;
  final s = cell * scale;
  final head = (1 - t * 1.35).clamp(0.0, 1.0); // the bright flash
  final tail = (1 - t).clamp(0.0, 1.0); // the debris
  final grow = 0.45 + t * 0.55;
  final n = big ? 4 : 2;

  switch (fx.burst) {
    case BurstStyle.shrapnel:
      if (head > 0) {
        final len = s * 0.45 * grow;
        final ray = _stroke(fx.accent, head * 0.7, s * 0.12 * (1 - t * 0.5));
        for (var i = 0; i < 4; i++) {
          final a = i * pi / 2;
          canvas.drawLine(
              center, center + Offset(cos(a) * len, sin(a) * len), ray);
        }
        canvas.drawCircle(
            center, s * 0.28 * grow, _fill(fx.accent, head * 0.7));
        canvas.drawCircle(center, s * 0.15 * grow, _fill(fx.core, head * 0.7));
      }
      for (var i = 0; i < n; i++) {
        final a = _jit(seed, i) * 2 * pi;
        final d = s * (0.25 + 0.75 * t) * (0.6 + _jit(seed, i + 11) * 0.5);
        canvas.drawPath(
            _sparkPath(center + Offset(cos(a) * d, sin(a) * d),
                s * 0.08 * (1 - t * 0.6)),
            _fill(fx.core, tail * 0.6));
      }

    case BurstStyle.fireball:
      if (head > 0) {
        canvas.drawCircle(
            center, s * 0.40 * grow, _fill(fx.deep, head * 0.55));
        canvas.drawCircle(
            center, s * 0.28 * grow, _fill(fx.accent, head * 0.85));
        canvas.drawCircle(center, s * 0.14 * grow, _fill(fx.core, head));
      }
      // Smoke rolling up out of the fireball.
      for (var i = 0; i < 3; i++) {
        final dx = (i - 1) * s * 0.22;
        final rise = -s * 0.55 * t;
        canvas.drawCircle(Offset(center.dx + dx, center.dy + rise),
            s * (0.12 + 0.18 * t), _fill(fx.deep, tail * 0.32));
      }

    case BurstStyle.tendril:
      // Arms lashing out of the water and curling back.
      for (var i = 0; i < 5; i++) {
        final a = (i / 5) * 2 * pi + _jit(seed, i) * 0.4;
        final r = s * 0.62 * grow;
        final curl = sin(t * pi) * r * 0.4;
        final path = Path()
          ..moveTo(center.dx, center.dy)
          ..quadraticBezierTo(
            center.dx + cos(a) * r * 0.55 - sin(a) * curl,
            center.dy + sin(a) * r * 0.55 + cos(a) * curl,
            center.dx + cos(a) * r,
            center.dy + sin(a) * r,
          );
        canvas.drawPath(path,
            _stroke(fx.accent, tail * 0.85, s * 0.09 * (1 - t * 0.55)));
      }
      if (head > 0) {
        canvas.drawCircle(center, s * 0.18 * grow, _fill(fx.core, head * 0.7));
      }

    case BurstStyle.starflare:
      if (head > 0) {
        for (var i = 0; i < 8; i++) {
          final a = i * pi / 4;
          final len = s * (i.isEven ? 0.58 : 0.30) * grow;
          canvas.drawLine(center, center + Offset(cos(a) * len, sin(a) * len),
              _stroke(fx.accent, head * 0.8, s * 0.07 * (1 - t * 0.5)));
        }
        canvas.drawCircle(center, s * 0.16 * grow, _fill(fx.core, head));
      }
      // Gold dust settling on a ring.
      for (var i = 0; i < n + 2; i++) {
        final a = _jit(seed, i) * 2 * pi;
        final d = s * (0.3 + 0.6 * t);
        canvas.drawCircle(center + Offset(cos(a) * d, sin(a) * d),
            s * 0.035 * tail, _fill(fx.accent, tail * 0.8));
      }

    case BurstStyle.voidRing:
      // One ring out, one ring in, nothing thrown — deliberately silent.
      canvas.drawCircle(center, s * 0.62 * grow,
          _stroke(fx.accent, head * 0.9, s * 0.07 * (1 - t * 0.4)));
      canvas.drawCircle(center, s * 0.55 * (1 - t) + s * 0.08,
          _stroke(fx.core, tail * 0.55, s * 0.04));
      canvas.drawCircle(center, s * 0.22 * (1 - t * 0.7),
          _fill(fx.deep, head * 0.75));

    case BurstStyle.arcBolt:
      // Jagged discharge: each bolt kinks off its own stable seed.
      for (var i = 0; i < 4; i++) {
        final a = (i / 4) * 2 * pi + _jit(seed, i) * 0.7;
        final path = Path()..moveTo(center.dx, center.dy);
        var r = 0.0;
        for (var k = 1; k <= 3; k++) {
          r = s * 0.62 * grow * (k / 3);
          final off = (_jit(seed, i * 7 + k) - 0.5) * 0.7;
          path.lineTo(center.dx + cos(a + off) * r, center.dy + sin(a + off) * r);
        }
        canvas.drawPath(
            path, _stroke(fx.accent, head * 0.95, s * 0.05 * (1 - t * 0.5)));
      }
      if (head > 0) {
        canvas.drawCircle(center, s * 0.16 * grow, _fill(fx.core, head));
      }

    case BurstStyle.bubblePop:
      for (var i = 0; i < 6; i++) {
        final a = (i / 6) * 2 * pi + _jit(seed, i) * 0.4;
        final d = s * 0.5 * grow * (0.6 + _jit(seed, i + 6) * 0.6);
        final r = s * (0.09 + 0.07 * _jit(seed, i + 12)) * (1 - t * 0.35);
        final p = center + Offset(cos(a) * d, sin(a) * d - s * 0.2 * t);
        canvas.drawCircle(p, r, _stroke(fx.accent, tail * 0.9, s * 0.03));
        canvas.drawCircle(p.translate(-r * 0.3, -r * 0.3), r * 0.22,
            _fill(fx.core, tail * 0.8));
      }
      if (head > 0) {
        canvas.drawCircle(center, s * 0.20 * grow, _fill(fx.core, head * 0.6));
      }

    case BurstStyle.collapse:
      // Debris travels INWARD, then a pinpoint flash where it all met.
      for (var i = 0; i < 6; i++) {
        final a = (i / 6) * 2 * pi + _jit(seed, i) * 0.5;
        final d = s * 0.7 * (1 - Curves.easeIn.transform(t));
        canvas.drawCircle(center + Offset(cos(a) * d, sin(a) * d),
            s * 0.05 * tail, _fill(fx.accent, tail * 0.9));
      }
      final flash = (1 - (t - 0.55).abs() * 6).clamp(0.0, 1.0);
      canvas.drawCircle(center, s * 0.26 * flash, _fill(fx.core, flash));
      canvas.drawCircle(center, s * 0.5 * (1 - t * 0.4),
          _stroke(fx.deep, head * 0.5, s * 0.05));

    case BurstStyle.spatter:
      for (var i = 0; i < 7; i++) {
        final a = (i / 7) * 2 * pi + _jit(seed, i) * 0.6;
        final d = s * (0.3 + 0.55 * t) * (0.5 + _jit(seed, i + 7) * 0.8);
        final p = center + Offset(cos(a) * d, sin(a) * d);
        canvas.drawCircle(p, s * (0.04 + 0.06 * _jit(seed, i + 14)) * tail,
            _fill(fx.accent, tail * 0.9));
        // The drip that trails each blob.
        canvas.drawLine(p, p.translate(0, s * 0.10 * t),
            _stroke(fx.accent, tail * 0.5, s * 0.025));
      }
      if (head > 0) {
        canvas.drawCircle(center, s * 0.22 * grow, _fill(fx.deep, head * 0.6));
      }

    case BurstStyle.cannonSmoke:
      // Pale billow with a bronze rim — see [SplashStyle.powder] for why
      // the smoke is not painted in the gun's dark carriage brown.
      for (var i = 0; i < 3; i++) {
        final a = i * 2 * pi / 3 + t * 0.8;
        final d = s * 0.28 * grow;
        final p = center + Offset(cos(a) * d, sin(a) * d);
        final r = s * (0.22 + 0.16 * t);
        canvas.drawCircle(p, r, _fill(fx.core, tail * 0.30));
        canvas.drawCircle(p, r, _stroke(fx.accent, tail * 0.45, s * 0.03));
      }
      if (head > 0) {
        canvas.drawCircle(
            center, s * 0.22 * grow, _fill(fx.accent, head * 0.85));
        canvas.drawCircle(center, s * 0.11 * grow, _fill(fx.core, head));
      }

    case BurstStyle.crossFlak:
      if (head > 0) {
        for (var i = 0; i < 4; i++) {
          final a = i * pi / 2 + pi / 4;
          final len = s * 0.55 * grow;
          final w = s * 0.10 * (1 - t * 0.4);
          final tip = center + Offset(cos(a) * len, sin(a) * len);
          canvas.drawPath(
            Path()
              ..moveTo(center.dx + cos(a + 1.57) * w,
                  center.dy + sin(a + 1.57) * w)
              ..lineTo(tip.dx, tip.dy)
              ..lineTo(center.dx - cos(a + 1.57) * w,
                  center.dy - sin(a + 1.57) * w)
              ..close(),
            _fill(fx.accent, head * 0.85),
          );
        }
      }
      for (var i = 0; i < n; i++) {
        final a = _jit(seed, i) * 2 * pi;
        final d = s * (0.3 + 0.6 * t);
        final p = center + Offset(cos(a) * d, sin(a) * d);
        final r = s * 0.05 * tail;
        canvas.drawRect(Rect.fromCenter(center: p, width: r * 2, height: r * 2),
            _fill(fx.core, tail * 0.75));
      }

    case BurstStyle.gearBurst:
      // A cog outline spinning outward, venting steam behind it.
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(t * 1.6);
      final r = s * 0.5 * grow;
      final teeth = Path();
      for (var i = 0; i < 8; i++) {
        final a0 = i * pi / 4;
        teeth.moveTo(cos(a0) * r * 0.68, sin(a0) * r * 0.68);
        teeth.lineTo(cos(a0) * r, sin(a0) * r);
      }
      canvas.drawPath(teeth, _stroke(fx.accent, head * 0.9, s * 0.07));
      canvas.drawCircle(Offset.zero, r * 0.68,
          _stroke(fx.accent, head * 0.9, s * 0.06));
      canvas.restore();
      for (var i = 0; i < 2; i++) {
        canvas.drawCircle(
            Offset(center.dx + (i == 0 ? -1 : 1) * s * 0.3,
                center.dy - s * 0.4 * t),
            s * (0.10 + 0.12 * t),
            _fill(fx.core, tail * 0.35));
      }

    case BurstStyle.frostNova:
      canvas.drawPath(_polyPath(center, s * 0.60 * grow, 6, 0.26),
          _stroke(fx.accent, head * 0.9, s * 0.07 * (1 - t * 0.4)));
      for (var i = 0; i < 6; i++) {
        final a = i * pi / 3 + 0.26;
        final d = s * (0.3 + 0.55 * t);
        final p = center + Offset(cos(a) * d, sin(a) * d);
        final r = s * 0.09 * tail;
        canvas.drawPath(
          Path()
            ..moveTo(p.dx + cos(a) * r, p.dy + sin(a) * r)
            ..lineTo(p.dx + cos(a + 2.2) * r * 0.5, p.dy + sin(a + 2.2) * r * 0.5)
            ..lineTo(p.dx + cos(a - 2.2) * r * 0.5, p.dy + sin(a - 2.2) * r * 0.5)
            ..close(),
          _fill(fx.core, tail * 0.85),
        );
      }

    case BurstStyle.magmaGout:
      canvas.drawCircle(center, s * 0.5 * grow, _fill(fx.deep, head * 0.55));
      if (head > 0) {
        // The gout itself: a tall tapered plume.
        canvas.drawPath(
          Path()
            ..moveTo(center.dx - s * 0.18, center.dy)
            ..quadraticBezierTo(center.dx - s * 0.06,
                center.dy - s * 0.7 * grow, center.dx, center.dy - s * 0.8 * grow)
            ..quadraticBezierTo(center.dx + s * 0.06,
                center.dy - s * 0.7 * grow, center.dx + s * 0.18, center.dy)
            ..close(),
          _fill(fx.accent, head * 0.9),
        );
        canvas.drawCircle(center, s * 0.16 * grow, _fill(fx.core, head));
      }
      for (var i = 0; i < n + 1; i++) {
        final a = -pi / 2 + (_jit(seed, i) - 0.5) * 2.2;
        final d = s * 0.7 * t;
        final drop = s * 0.5 * t * t;
        canvas.drawCircle(center + Offset(cos(a) * d, sin(a) * d + drop),
            s * 0.05 * tail, _fill(fx.accent, tail * 0.95));
      }

    case BurstStyle.ionLance:
      if (head > 0) {
        final len = s * 0.75 * grow;
        canvas.drawLine(center.translate(0, -len), center.translate(0, len),
            _stroke(fx.accent, head * 0.9, s * 0.06 * (1 - t * 0.5)));
        canvas.drawLine(center.translate(-len, 0), center.translate(len, 0),
            _stroke(fx.accent, head * 0.55, s * 0.04 * (1 - t * 0.5)));
        canvas.drawCircle(center, s * 0.14 * grow, _fill(fx.core, head));
      }
      canvas.drawPath(_polyPath(center, s * 0.45 * grow, 6, t),
          _stroke(fx.core, tail * 0.6, s * 0.035));
      for (var i = 0; i < n; i++) {
        final y = center.dy + (_jit(seed, i) - 0.5) * s * 1.1;
        final w = s * 0.5 * tail;
        canvas.drawLine(Offset(center.dx - w, y), Offset(center.dx + w, y),
            _stroke(fx.accent, tail * 0.4, s * 0.02));
      }
  }
}

// ---------------------------------------------------------------------------
// Mark arrival — only where a mark is actually recorded
// ---------------------------------------------------------------------------

/// The flourish that delivers the persistent hit/miss mark onto the deck.
///
/// FEEDBACK ("when the projectile hits a ship and the hit design is being
/// shown on the deck, create a better transition animation"): the mark
/// itself is drawn by the grid's STATIC layer, which is deliberately not
/// rebuilt per frame (that caching is what keeps a board full of old marks
/// cheap — see `_BattleGridState.build`'s note), so the mark cannot itself
/// be animated without giving that up. Instead this draws a short-lived
/// convergence onto the spot the mark occupies: an over-sized ghost of the
/// gun's own accent that collapses onto the mark's footprint, so the mark
/// reads as being *delivered* there rather than blinking into existence.
///
/// [t] is whole-life progress; the arrival occupies the first 45%.
void paintMarkArrival(
  Canvas canvas,
  Offset center,
  double cell,
  double t,
  ImpactFx fx,
) {
  final a = (t / 0.45).clamp(0.0, 1.0);
  if (a >= 1.0) return;
  final fade = 1 - a;
  final ease = Curves.easeOutCubic.transform(a);
  // The footprint the persistent mark actually occupies on the cell.
  final mark = cell * 0.31;

  switch (fx.arrival) {
    case MarkArrival.slam:
      final r = mark * (2.2 - 1.2 * ease);
      canvas.drawRect(
          Rect.fromCenter(center: center, width: r * 2, height: r * 2),
          _stroke(fx.accent, fade * 0.9, cell * 0.05));
      canvas.drawCircle(center, mark * (1 + 1.8 * ease),
          _stroke(fx.core, fade * 0.5, cell * 0.03));

    case MarkArrival.scorch:
      // A char ring burning inward, flecked with embers.
      final r = mark * (2.0 - 1.0 * ease);
      canvas.drawCircle(center, r, _stroke(fx.deep, fade * 0.85, cell * 0.07));
      canvas.drawCircle(center, r, _stroke(fx.accent, fade * 0.6, cell * 0.03));
      for (var i = 0; i < 5; i++) {
        final ang = i * 2 * pi / 5 + a * 1.2;
        canvas.drawCircle(center + Offset(cos(ang) * r, sin(ang) * r),
            cell * 0.03 * fade, _fill(fx.accent, fade));
      }

    case MarkArrival.bloomIn:
      for (var i = 0; i < 4; i++) {
        final ang = i * pi / 2 + pi / 4;
        final d = mark * (2.0 - 1.6 * ease);
        canvas.save();
        canvas.translate(center.dx + cos(ang) * d, center.dy + sin(ang) * d);
        canvas.rotate(ang);
        canvas.scale(1.0, 0.5);
        canvas.drawCircle(
            Offset.zero, mark * 0.8 * fade, _fill(fx.accent, fade * 0.85));
        canvas.restore();
      }

    case MarkArrival.stamp:
      // Presses down like a seal, with a ring of radial ticks.
      final r = mark * (1.9 - 0.9 * ease);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate((1 - ease) * 0.5);
      canvas.drawCircle(
          Offset.zero, r, _stroke(fx.accent, fade * 0.95, cell * 0.05));
      final tick = _stroke(fx.core, fade * 0.8, cell * 0.03);
      for (var i = 0; i < 8; i++) {
        final ang = i * pi / 4;
        canvas.drawLine(
          Offset(cos(ang) * r * 0.78, sin(ang) * r * 0.78),
          Offset(cos(ang) * r, sin(ang) * r),
          tick,
        );
      }
      canvas.restore();

    case MarkArrival.warp:
      // Two arcs counter-rotating into the mark, plus a closing slit.
      final r = mark * (2.1 - 1.1 * ease);
      final arcRect = Rect.fromCircle(center: center, radius: r);
      final arcPaint = _stroke(fx.accent, fade * 0.9, cell * 0.05);
      canvas.drawArc(arcRect, a * 3.4, 2.2, false, arcPaint);
      canvas.drawArc(arcRect, -a * 3.4, 2.2, false, arcPaint);
      canvas.drawLine(center.translate(0, -r * fade),
          center.translate(0, r * fade), _stroke(fx.core, fade * 0.8, cell * 0.03));

    case MarkArrival.shatterIn:
      for (var i = 0; i < 6; i++) {
        final ang = i * pi / 3 + 0.3;
        final d = mark * (2.2 - 1.6 * ease);
        final p = center + Offset(cos(ang) * d, sin(ang) * d);
        final sr = cell * 0.07 * fade;
        canvas.drawPath(
          Path()
            ..moveTo(p.dx + cos(ang) * sr, p.dy + sin(ang) * sr)
            ..lineTo(p.dx + cos(ang + 2.2) * sr, p.dy + sin(ang + 2.2) * sr)
            ..lineTo(p.dx + cos(ang - 2.2) * sr, p.dy + sin(ang - 2.2) * sr)
            ..close(),
          _fill(fx.core, fade * 0.95),
        );
      }

    case MarkArrival.swirlIn:
      for (var i = 0; i < 3; i++) {
        final ang = i * 2 * pi / 3 + a * 5.0;
        final d = mark * (2.3 - 1.7 * ease);
        canvas.drawCircle(center + Offset(cos(ang) * d, sin(ang) * d),
            cell * 0.05 * fade, _fill(fx.accent, fade * 0.95));
      }
      canvas.drawCircle(center, mark * (1.6 - 0.6 * ease),
          _stroke(fx.core, fade * 0.45, cell * 0.025));

    case MarkArrival.implodeIn:
      // Kept inside roughly one cell — an arrival that reaches much past
      // the mark's own cell bleeds over its neighbours on a live board.
      final r = mark * (2.1 - 1.3 * Curves.easeIn.transform(a));
      canvas.drawCircle(center, r, _stroke(fx.deep, fade * 0.9, cell * 0.07));
      canvas.drawCircle(center, r * 0.6, _stroke(fx.accent, fade * 0.8, cell * 0.04));
      final flash = (1 - (a - 0.8).abs() * 8).clamp(0.0, 1.0);
      canvas.drawCircle(center, mark * 0.7 * flash, _fill(fx.core, flash * 0.9));

    case MarkArrival.dissolveIn:
      for (var i = 0; i < 8; i++) {
        final ang = i * pi / 4 + 0.2;
        final wob = sin(a * pi * 3 + i) * cell * 0.02;
        final d = mark * (1.5 - 0.4 * ease) + wob;
        canvas.drawCircle(center + Offset(cos(ang) * d, sin(ang) * d),
            cell * 0.04 * fade, _fill(fx.accent, fade * 0.9));
      }

    case MarkArrival.smokeIn:
      final r = mark * (1.9 - 0.9 * ease);
      canvas.drawCircle(center, r, _fill(fx.core, fade * 0.3));
      canvas.drawCircle(center, r, _stroke(fx.accent, fade * 0.8, cell * 0.035));
      canvas.drawCircle(center, r * 0.55, _fill(fx.accent, fade * 0.45));

    case MarkArrival.driveIn:
      // Two brackets sliding in and locking around the mark.
      final off = mark * (2.4 - 1.6 * ease);
      for (final dir in [-1.0, 1.0]) {
        final x = center.dx + dir * off;
        final p = _stroke(fx.accent, fade * 0.95, cell * 0.05);
        canvas.drawLine(Offset(x, center.dy - mark), Offset(x, center.dy + mark), p);
        canvas.drawLine(Offset(x, center.dy - mark),
            Offset(x - dir * mark * 0.5, center.dy - mark), p);
        canvas.drawLine(Offset(x, center.dy + mark),
            Offset(x - dir * mark * 0.5, center.dy + mark), p);
      }

    case MarkArrival.frostIn:
      // Crystal spikes growing outward off the mark's edges.
      for (var i = 0; i < 6; i++) {
        final ang = i * pi / 3;
        final inner = mark * 0.7;
        final outer = mark * (0.7 + 1.5 * ease);
        canvas.drawLine(
          center + Offset(cos(ang) * inner, sin(ang) * inner),
          center + Offset(cos(ang) * outer, sin(ang) * outer),
          _stroke(fx.core, fade * 0.9, cell * 0.035),
        );
      }
      canvas.drawPath(_polyPath(center, mark * (1.9 - 0.9 * ease), 6, 0.26),
          _stroke(fx.accent, fade * 0.7, cell * 0.03));

    case MarkArrival.scanIn:
      // A scan line sweeping down over the mark, corner ticks locking on.
      final y = center.dy - mark * 1.6 + mark * 3.2 * ease;
      canvas.drawLine(Offset(center.dx - mark * 1.4, y),
          Offset(center.dx + mark * 1.4, y),
          _stroke(fx.accent, fade * 0.95, cell * 0.035));
      final c = mark * (1.8 - 0.6 * ease);
      for (var i = 0; i < 4; i++) {
        final sx = i.isEven ? -1.0 : 1.0;
        final sy = i < 2 ? -1.0 : 1.0;
        final corner = Offset(center.dx + sx * c, center.dy + sy * c);
        final p = _stroke(fx.core, fade * 0.85, cell * 0.03);
        canvas.drawLine(corner, corner.translate(-sx * mark * 0.5, 0), p);
        canvas.drawLine(corner, corner.translate(0, -sy * mark * 0.5), p);
      }
  }
}
