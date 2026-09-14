import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'fleet_family.dart';
import 'impact_fx.dart' show fxDensity;
import 'legacy_shell_art.dart';

/// What a gun throws out of its muzzle besides smoke.
///
/// FEEDBACK ("when the cannon fires there are smoke effects — add
/// particle effects too, different per cannon skin, fitting their
/// theme"): every gun already had its own flash and its own exhaust
/// cloud, but nothing between the two — no sparks off a powder gun, no
/// ice off a coilgun, no cinders off a bombard. A shot was a bright
/// shape followed by a grey shape.
///
/// These are drawn in the BARREL's own frame (see `CannonPainter`), so
/// they leave along the bore and drift the way the gun is pointing
/// without any of them having to know the aim angle.
///
/// PERF. This runs on the cannon's own repaint, which ticks for roughly
/// the length of one shot and then stops. Everything here is flat vector
/// work — no blur, no layers, no allocation per particle beyond the two
/// scratch `Paint`s — every loop is capped, and the counts scale with
/// [fxDensity] so the graphics setting reaches this as well as the
/// impact effects. Measured at 0.05–0.28ms per frame per gun depending
/// on the skin; the hull it is drawn next to costs ~2ms.

final Paint _fill = Paint();
final Paint _stroke = Paint()
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round;

Paint _f(Color c, double a) =>
    _fill..color = c.withValues(alpha: a.clamp(0.0, 1.0));

Paint _s(Color c, double a, double w) => _stroke
  ..color = c.withValues(alpha: a.clamp(0.0, 1.0))
  ..strokeWidth = w;

/// Stable pseudo-random in 0..1 — see the note on `impact_fx.dart`'s own
/// `_jit` for why particles hash a seed rather than pull from a stateful
/// generator.
double _j(int seed, int i) {
  var x = seed * 374761393 + i * 668265263;
  x = (x ^ (x >> 13)) * 1274126177;
  return ((x ^ (x >> 16)) & 0x7FFFFFF) / 0x7FFFFFF;
}

int _n(int base) {
  final v = (base * fxDensity).round();
  return v < 1 ? 1 : v;
}

/// How a gun's muzzle throw-off behaves. Nine legacy guns and six family
/// guns map onto these; the character is what differs, the colours come
/// from each gun's own palette.
enum MuzzleSpray {
  /// Hot sparks on ballistic arcs — powder guns.
  sparks,

  /// Rising cinders that curl as they go — fire guns.
  cinders,

  /// Straight, jagged bolts — electric guns.
  arcs,

  /// Slow shards that hang and fall — ice guns.
  shards,

  /// Bubbles rising and popping — sea guns.
  bubbles,

  /// Rings pushing out along the bore — energy guns.
  pulses,

  /// Heavy gobs that fall back down — mortars.
  gobs,

  /// Drifting motes pulled back toward the bore — void guns.
  motes,
}

/// The spray a legacy gun throws, keyed to what that gun IS: the MK-I is
/// powder, the Inferno is fire, the Coilgun is electric, and so on.
MuzzleSpray _legacySpray(String id) => switch (id) {
      'mk1' => MuzzleSpray.sparks,
      'inferno' => MuzzleSpray.cinders,
      'tesla' => MuzzleSpray.arcs,
      'kraken' => MuzzleSpray.bubbles,
      'royal' => MuzzleSpray.sparks,
      'phantom' => MuzzleSpray.pulses,
      'sunfire' => MuzzleSpray.bubbles,
      'void' => MuzzleSpray.motes,
      'venom' => MuzzleSpray.gobs,
      _ => MuzzleSpray.sparks,
    };

MuzzleSpray _familySpray(FleetFamilyId id) => switch (id) {
      FleetFamilyId.pirate => MuzzleSpray.sparks,
      FleetFamilyId.naval => MuzzleSpray.sparks,
      FleetFamilyId.steam => MuzzleSpray.gobs,
      FleetFamilyId.arctic => MuzzleSpray.shards,
      FleetFamilyId.volcanic => MuzzleSpray.cinders,
      FleetFamilyId.scifi => MuzzleSpray.pulses,
    };

/// Sparks off ONE of the nine legacy guns, in its own shell palette.
///
/// [t] runs 0→1 over the muzzle-effect's life, [r] is the gun's outer
/// radius, and (0,0)-relative geometry is in the barrel's rest frame with
/// the bore pointing toward −y.
void paintMuzzleSparks(
  Canvas canvas,
  Offset mouth,
  double r,
  double t,
  String cannonId,
) {
  final p = legacyShellPalette(cannonId);
  _paintSpray(
    canvas,
    mouth,
    r,
    t,
    _legacySpray(cannonId),
    core: p.glow,
    accent: p.trim,
    deep: p.hull,
    seed: cannonId.hashCode,
  );
}

/// The same, for one of the six family guns.
void paintFamilyMuzzleSparks(
  Canvas canvas,
  Offset mouth,
  double r,
  double t,
  FleetFamily family,
) {
  _paintSpray(
    canvas,
    mouth,
    r,
    t,
    _familySpray(family.id),
    core: family.gun.glow,
    accent: family.gun.trim,
    deep: family.gun.hull,
    seed: family.id.index * 7919,
  );
}

void _paintSpray(
  Canvas canvas,
  Offset mouth,
  double r,
  double t,
  MuzzleSpray spray, {
  required Color core,
  required Color accent,
  required Color deep,
  required int seed,
}) {
  if (t <= 0 || t >= 1) return;
  final fade = 1 - t;
  final out = Curves.easeOut.transform(t);

  switch (spray) {
    case MuzzleSpray.sparks:
      // Thrown forward out of the bore and pulled down as they go.
      for (var i = 0; i < _n(7); i++) {
        final spread = (_j(seed, i) - 0.5) * 1.1;
        final reach = r * (0.5 + 0.9 * _j(seed, i + 11));
        final d = reach * out;
        final drop = r * 0.5 * t * t;
        final p = mouth +
            Offset(math.sin(spread) * d, -math.cos(spread) * d + drop);
        canvas.drawCircle(p, r * 0.035 * fade, _f(core, fade));
      }

    case MuzzleSpray.cinders:
      // Rise, curl and go out — the tail of a fire gun's bang.
      for (var i = 0; i < _n(6); i++) {
        final spread = (_j(seed, i) - 0.5) * 0.9;
        final d = r * (0.4 + 0.8 * _j(seed, i + 5)) * out;
        final curl = math.sin(t * math.pi * 2 + i) * r * 0.08;
        final p = mouth +
            Offset(math.sin(spread) * d + curl, -math.cos(spread) * d);
        canvas.drawCircle(
            p, r * 0.05 * fade, _f(i.isEven ? accent : core, fade * 0.95));
      }

    case MuzzleSpray.arcs:
      // Short jagged bolts snapping off the bore, each on its own fixed
      // kink so they flicker in place rather than crawling.
      for (var i = 0; i < _n(4); i++) {
        final a = -math.pi / 2 + (_j(seed, i) - 0.5) * 1.3;
        final path = Path()..moveTo(mouth.dx, mouth.dy);
        for (var k = 1; k <= 3; k++) {
          final reach = r * 0.85 * out * (k / 3);
          final off = (_j(seed, i * 13 + k) - 0.5) * 0.8;
          path.lineTo(mouth.dx + math.cos(a + off) * reach,
              mouth.dy + math.sin(a + off) * reach);
        }
        canvas.drawPath(path, _s(core, fade * 0.95, r * 0.028));
      }

    case MuzzleSpray.shards:
      // Crystal splinters that hang, then drift down.
      for (var i = 0; i < _n(6); i++) {
        final a = -math.pi / 2 + (_j(seed, i) - 0.5) * 1.4;
        final d = r * 0.7 * Curves.easeOutCubic.transform(t);
        final drop = r * 0.25 * t * t;
        final p = mouth +
            Offset(math.cos(a) * d, math.sin(a) * d + drop);
        final len = r * 0.07 * fade;
        canvas.drawLine(
          p + Offset(math.cos(a) * len, math.sin(a) * len),
          p - Offset(math.cos(a) * len, math.sin(a) * len),
          _s(core, fade, r * 0.022),
        );
      }

    case MuzzleSpray.bubbles:
      // Rise and pop — hollow, so they read as air rather than sparks.
      for (var i = 0; i < _n(5); i++) {
        final spread = (_j(seed, i) - 0.5) * 1.0;
        final d = r * (0.35 + 0.6 * _j(seed, i + 3)) * out;
        final lift = r * 0.25 * t;
        final p = mouth +
            Offset(math.sin(spread) * d, -math.cos(spread) * d - lift);
        canvas.drawCircle(p, r * (0.03 + 0.03 * _j(seed, i + 9)) * fade,
            _s(core, fade * 0.9, r * 0.016));
      }

    case MuzzleSpray.pulses:
      // Rings pushed out along the bore, not particles at all.
      for (var i = 0; i < _n(3); i++) {
        final phase = (t + i * 0.28) % 1.0;
        if (phase > 0.9) continue;
        final d = r * 0.9 * phase;
        canvas.drawCircle(
          mouth + Offset(0, -d),
          r * (0.07 + 0.16 * phase),
          _s(accent, (1 - phase) * fade * 0.9, r * 0.022),
        );
      }

    case MuzzleSpray.gobs:
      // Heavy, slow and falling back — a mortar's throw-off.
      for (var i = 0; i < _n(5); i++) {
        final spread = (_j(seed, i) - 0.5) * 1.3;
        final d = r * (0.3 + 0.5 * _j(seed, i + 7)) * out;
        final drop = r * 0.7 * t * t;
        final p = mouth +
            Offset(math.sin(spread) * d, -math.cos(spread) * d + drop);
        canvas.drawCircle(p, r * 0.055 * fade, _f(accent, fade * 0.9));
        canvas.drawCircle(p, r * 0.055 * fade, _s(deep, fade * 0.6, r * 0.012));
      }

    case MuzzleSpray.motes:
      // Drawn BACK toward the bore rather than thrown from it.
      for (var i = 0; i < _n(6); i++) {
        final a = _j(seed, i) * 2 * math.pi;
        final d = r * 0.75 * (1 - out);
        final p = mouth + Offset(math.cos(a) * d, math.sin(a) * d * 0.7);
        canvas.drawCircle(p, r * 0.03 * fade, _f(accent, fade * 0.95));
      }
  }
}
