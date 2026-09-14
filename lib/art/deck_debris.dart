import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'fleet_family.dart';
import 'impact_fx.dart' show fxDensity;
import 'legacy_identity.dart';

/// What a DECK throws up when something lands on it.
///
/// FEEDBACK ("on the hit and miss add particle effects too — make sure
/// they differ on different decks"): the splash and the burst already
/// vary, but they vary by the GUN that fired (see `ImpactFx`), which is
/// the right key for the shot and the wrong key for the water. Every one
/// of the fifteen boards — an ash lake, a kelp shallows, a frozen shelf,
/// a plasma field — reacted to being hit with exactly the same material,
/// so the board itself never had a say in what a shot looked like when it
/// arrived.
///
/// This is the other half of that: the gun contributes the flash and the
/// shrapnel, the deck contributes whatever the deck is MADE OF. They are
/// drawn one on top of the other, and because they are keyed to
/// different things, the same gun firing at two different boards reads
/// differently — which is the point.
///
/// PERF. Runs inside `_FxGridPainter`, the small per-frame painter that
/// exists precisely so effects do not drag the whole board into a
/// repaint. Flat vector work only — no blur, no saveLayer, two shared
/// scratch `Paint`s — bounded loops, and every count goes through
/// [fxDensity] so the graphics setting governs this the way it governs
/// the gun's own particles. An effect lives 800ms and there are rarely
/// more than three at once.

final Paint _fill = Paint();
final Paint _stroke = Paint()
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round;

Paint _f(Color c, double a) =>
    _fill..color = c.withValues(alpha: a.clamp(0.0, 1.0));

Paint _s(Color c, double a, double w) => _stroke
  ..color = c.withValues(alpha: a.clamp(0.0, 1.0))
  ..strokeWidth = w;

/// Stable per-cell jitter — same reasoning as `impact_fx.dart`'s `_jit`:
/// a cell's particles must land in the same places on every frame of the
/// same effect, which a stateful `Random` cannot promise.
double _j(int seed, int i) {
  var x = seed * 1103515245 + i * 12345 + 0x5F3759;
  x = (x ^ (x >> 13)) * 1274126177;
  return ((x ^ (x >> 16)) & 0x7FFFFFF) / 0x7FFFFFF;
}

int _n(int base) {
  final v = (base * fxDensity).round();
  return v < 1 ? 1 : v;
}

/// An angle for particle [i] of [n], spread evenly round the circle and
/// then jittered inside its own slice.
///
/// FOUND BY RENDERING: taking the angle straight from [_j] looks random
/// in the abstract but is not EVENLY random for a given seed — with five
/// or six particles, one seed's hashes happily land three of them within
/// a few degrees of each other, and the effect comes out as a lopsided
/// clump with a bare patch opposite. Giving each particle its own slice
/// and jittering within it keeps the deterministic placement while
/// guaranteeing the spread, which is what a spray needs to read as a
/// spray at every cell on the board rather than only at the lucky ones.
double _ang(int seed, int i, int n) =>
    (i + 0.2 + 0.6 * _j(seed, i)) / n * 2 * math.pi;

/// The material a board is made of, as far as an impact is concerned.
enum DeckDebris {
  /// Open sea: a foam ring and flung droplets.
  foam,

  /// Ash water: cinders that rise and wink out.
  embers,

  /// Charged field: flecks that snap along the grid lines.
  arcflecks,

  /// Kelp shallows: torn weed and rising bubbles.
  weed,

  /// Gilded water: heavy flakes that glint and sink.
  gild,

  /// Cold fog: wisps that swell and thin rather than fly.
  mist,

  /// Sunlit shallows: bright warm spray, lots of it.
  sunspray,

  /// Deep void: motes that fall INWARD toward the impact.
  motes,

  /// Toxic sludge: slow, heavy globs that plop back down.
  sludge,

  /// Timber decking: splinters thrown flat and spinning.
  splinters,

  /// Boiler works: a short jet of vented steam.
  steamjet,

  /// Ice shelf: chips that skate outward and stop.
  icechips,

  /// Plasma field: an expanding hex ripple, not particles at all.
  plasma,

  /// Open ocean under a fleet: a crossed wake rather than a flat ring.
  wake,

  /// Molten rock: glowing gobs that arc up and fall back burning.
  magma,
}

/// A deck's debris style and the colours to draw it in.
class DeckFx {
  final DeckDebris debris;

  /// The water/field itself — what gets thrown up on a miss.
  final Color field;

  /// The board's pop colour — what a HIT brightens the debris toward.
  final Color accent;

  /// The board's own miss tone, for the foam and rings.
  final Color foam;

  const DeckFx({
    required this.debris,
    required this.field,
    required this.accent,
    required this.foam,
  });
}

DeckDebris _legacyDebris(String id) => switch (id) {
      'mk1' => DeckDebris.foam,
      'inferno' => DeckDebris.embers,
      'tesla' => DeckDebris.arcflecks,
      'kraken' => DeckDebris.weed,
      'royal' => DeckDebris.gild,
      'phantom' => DeckDebris.mist,
      'sunfire' => DeckDebris.sunspray,
      'void' => DeckDebris.motes,
      'venom' => DeckDebris.sludge,
      _ => DeckDebris.foam,
    };

DeckDebris _familyDebris(FleetFamilyId id) => switch (id) {
      FleetFamilyId.pirate => DeckDebris.splinters,
      FleetFamilyId.naval => DeckDebris.wake,
      FleetFamilyId.steam => DeckDebris.steamjet,
      FleetFamilyId.arctic => DeckDebris.icechips,
      FleetFamilyId.volcanic => DeckDebris.magma,
      FleetFamilyId.scifi => DeckDebris.plasma,
    };

const DeckFx _fallback = DeckFx(
  debris: DeckDebris.foam,
  field: Color(0xFF1E3A5F),
  accent: Color(0xFF94A3B8),
  foam: Color(0xFFE6F0F7),
);

/// Which board is being shot at.
///
/// Mirrors the way `BattleGrid` itself resolves its board: the family
/// first, and the legacy id only when there is no family — so a deck's
/// debris can never disagree with the deck it is landing on.
DeckFx deckFxFor({FleetFamily? family, String? legacyBoardId}) {
  if (family != null) {
    return DeckFx(
      debris: _familyDebris(family.id),
      field: family.board.field,
      accent: family.board.accent,
      foam: family.board.miss,
    );
  }
  if (legacyBoardId == null) return _fallback;
  final identity = legacyIdentityFor(legacyBoardId);
  return DeckFx(
    debris: _legacyDebris(legacyBoardId),
    field: _legacyField[legacyBoardId] ?? _fallback.field,
    accent: identity.accent,
    foam: _legacyFoam[legacyBoardId] ?? _fallback.foam,
  );
}

/// The nine legacy boards' own water tone, sampled from the base fill
/// each `_boardMarkup` in `legacy_board_art.dart` paints its field with.
/// Read here rather than re-derived so debris thrown up out of a board is
/// the colour of that board, not of a generic blue.
const Map<String, Color> _legacyField = {
  'mk1': Color(0xFF4A789A),
  'inferno': Color(0xFF2B0F0A),
  'tesla': Color(0xFF0B2432),
  'kraken': Color(0xFF0A2E2C),
  'royal': Color(0xFF1A2E4A),
  'phantom': Color(0xFF14162B),
  'sunfire': Color(0xFF3A2408),
  'void': Color(0xFF070A14),
  'venom': Color(0xFF1F2E0D),
};

/// The pale tone each board's own foam/spray reads as.
const Map<String, Color> _legacyFoam = {
  'mk1': Color(0xFFE6F0F7),
  'inferno': Color(0xFFFFD9A8),
  'tesla': Color(0xFFE0FBFF),
  'kraken': Color(0xFFCFF7E4),
  'royal': Color(0xFFFFEFC2),
  'phantom': Color(0xFFE4DCFF),
  'sunfire': Color(0xFFFFE2C4),
  'void': Color(0xFFC9D8FF),
  'venom': Color(0xFFE4FFC2),
};

/// Debris thrown up by a shot landing on this deck.
///
/// [t] is the impact's own 0→1 progress (the same clock the splash and
/// the burst run on), [cell] the grid cell's side, and [seed] the cell's
/// stable jitter seed. [hit] brightens the material toward the board's
/// accent and throws more of it — a shell going into a hull disturbs more
/// of the board than one going into open water.
void paintDeckDebris(
  Canvas canvas,
  Offset center,
  double cell,
  double t,
  DeckFx fx,
  int seed, {
  required bool hit,
}) {
  if (t <= 0 || t >= 1) return;
  final fade = 1 - t;
  final out = Curves.easeOutCubic.transform(t);
  // A hit disturbs more of the deck than a miss does, and pulls the
  // material toward the board's own accent so the two read apart at a
  // glance even before the marker lands.
  final boost = hit ? 1 : 0;
  final tint = Color.lerp(fx.foam, fx.accent, hit ? 0.65 : 0.18)!;
  // BUGFIX (found by rendering all fifteen decks side by side): the
  // "heavy" tone — what the solid debris is drawn in: the splinters, the
  // kelp, the sludge — was mixed from the board's own FIELD, so on a miss
  // it came out within a few percent of the water it was lying on and
  // simply vanished. Pirate's splinters were invisible on Pirate's own
  // sea. It is lifted off the field toward the board's foam first, and
  // only then tinted, so it always has something to read against.
  final heavy = Color.lerp(
    Color.lerp(fx.field, fx.foam, 0.55)!,
    fx.accent,
    hit ? 0.5 : 0.18,
  )!;

  switch (fx.debris) {
    case DeckDebris.foam:
      // A ring of foam pushed out, plus droplets thrown clear of it.
      canvas.drawCircle(center, cell * (0.16 + 0.3 * out),
          _s(tint, fade * 0.5, cell * 0.05 * fade));
      final n = _n(6 + boost * 3);
      for (var i = 0; i < n; i++) {
        final a = _ang(seed, i, n);
        final d = cell * (0.2 + 0.24 * _j(seed, i + 20)) * out;
        canvas.drawCircle(center + Offset(math.cos(a) * d, math.sin(a) * d),
            cell * 0.05 * fade, _f(tint, fade * 0.8));
      }

    case DeckDebris.embers:
      // Cinders lift out of the ash and go out one at a time.
      final n = _n(7 + boost * 4);
      for (var i = 0; i < n; i++) {
        final a = _ang(seed, i, n);
        final d = cell * (0.12 + 0.22 * _j(seed, i + 7)) * out;
        final lift = cell * 0.32 * t * t;
        final life = (fade - _j(seed, i + 30) * 0.35).clamp(0.0, 1.0);
        canvas.drawCircle(
          center + Offset(math.cos(a) * d, math.sin(a) * d - lift),
          cell * 0.042 * life,
          _f(tint, life),
        );
      }

    case DeckDebris.arcflecks:
      // Flecks that snap along the grid rather than scattering: the
      // charged board conducts, so the disturbance runs square.
      //
      // Reach is deliberately budgeted so a fleck's FAR end still lands
      // inside the cell (0.3 out + 0.16 run < 0.5). The first version
      // used the full half-cell for the start point and then added the
      // fleck's own length on top, which left loose bars sitting in the
      // neighbouring square with nothing there to explain them.
      final n = _n(6 + boost * 3);
      for (var i = 0; i < n; i++) {
        final horiz = i.isEven;
        final dir = _j(seed, i) < 0.5 ? -1.0 : 1.0;
        final d = cell * 0.3 * out * dir;
        final off = (_j(seed, i + 11) - 0.5) * cell * 0.4;
        final p = horiz ? center + Offset(d, off) : center + Offset(off, d);
        final run = cell * (0.08 + 0.08 * _j(seed, i + 27)) * dir;
        canvas.drawLine(
          p,
          p + (horiz ? Offset(run, 0) : Offset(0, run)),
          _s(tint, fade * 0.95, cell * 0.036),
        );
      }
      // A single bright cross at the impact itself, so the cell reads as
      // the source of the charge rather than as scattered litter.
      final crossR = cell * 0.16 * (1 - out);
      if (crossR > 0.5) {
        canvas.drawLine(center - Offset(crossR, 0), center + Offset(crossR, 0),
            _s(tint, fade, cell * 0.034));
        canvas.drawLine(center - Offset(0, crossR), center + Offset(0, crossR),
            _s(tint, fade, cell * 0.034));
      }

    case DeckDebris.weed:
      // Torn kelp, and bubbles coming up behind it.
      final n = _n(4 + boost * 2);
      for (var i = 0; i < n; i++) {
        final a = _ang(seed, i, n);
        // Jittered length as well as angle — see the note on [motes]:
        // an even angle with a FIXED radius draws a perfect circle.
        final d = cell * (0.22 + 0.16 * _j(seed, i + 51)) * out;
        final p = center + Offset(math.cos(a) * d, math.sin(a) * d);
        final path = Path()
          ..moveTo(center.dx, center.dy)
          ..quadraticBezierTo(
            (center.dx + p.dx) / 2 + math.sin(t * 6 + i) * cell * 0.07,
            (center.dy + p.dy) / 2,
            p.dx,
            p.dy,
          );
        canvas.drawPath(path, _s(heavy, fade * 0.85, cell * 0.04));
      }
      for (var i = 0; i < _n(4); i++) {
        final x = (_j(seed, i + 40) - 0.5) * cell * 0.5;
        final rise = cell * 0.4 * t;
        canvas.drawCircle(center + Offset(x, -rise), cell * 0.035 * fade,
            _s(tint, fade * 0.8, cell * 0.014));
      }

    case DeckDebris.gild:
      // Flat flakes: bright on the way up, gone on the way down.
      final n = _n(7 + boost * 3);
      for (var i = 0; i < n; i++) {
        final a = _ang(seed, i, n);
        final d = cell * (0.16 + 0.22 * _j(seed, i + 13)) * out;
        final drop = cell * 0.22 * t * t;
        final p = center + Offset(math.cos(a) * d, math.sin(a) * d + drop);
        // Squashed to a sliver, so it reads as a flake catching the light
        // rather than as another round droplet.
        canvas.save();
        canvas.translate(p.dx, p.dy);
        canvas.rotate(a);
        canvas.drawOval(
          Rect.fromCenter(
              center: Offset.zero,
              width: cell * 0.12 * fade,
              height: cell * 0.03),
          _f(tint, fade),
        );
        canvas.restore();
      }

    case DeckDebris.mist:
      // Nothing is thrown at all — the fog just swells and thins.
      //
      // Toned right down from the first pass, which stacked four big,
      // clumped, near-opaque blobs over the cell and hid the marker
      // underneath. A haze has to stay a haze: this is the one deck whose
      // debris is meant to be barely there.
      final n = _n(5);
      for (var i = 0; i < n; i++) {
        final a = _ang(seed, i, n);
        final d = cell * (0.1 + 0.24 * _j(seed, i + 61)) * out;
        canvas.drawCircle(
          center + Offset(math.cos(a) * d, math.sin(a) * d * 0.6),
          cell * (0.07 + 0.12 * out) * (0.5 + 0.7 * _j(seed, i + 3)),
          _f(tint, fade * 0.13),
        );
      }
      // One thin rim so it still reads as an IMPACT rather than as a
      // general brightening of the cell.
      canvas.drawCircle(center, cell * (0.1 + 0.26 * out),
          _s(tint, fade * 0.34, cell * 0.022));

    case DeckDebris.sunspray:
      // Warm, bright and plenty of it — the busiest of the fifteen.
      final n = _n(9 + boost * 4);
      for (var i = 0; i < n; i++) {
        final a = _ang(seed, i, n);
        final d = cell * (0.14 + 0.28 * _j(seed, i + 17)) * out;
        final drop = cell * 0.2 * t * t;
        canvas.drawCircle(
          center + Offset(math.cos(a) * d, math.sin(a) * d + drop),
          cell * 0.04 * fade,
          _f(i.isEven ? tint : fx.accent, fade * 0.9),
        );
      }

    case DeckDebris.motes:
      // Pulled IN rather than thrown out: the void board takes the
      // disturbance back instead of spreading it.
      final n = _n(8);
      for (var i = 0; i < n; i++) {
        final a = _ang(seed, i, n);
        // FOUND BY RENDERING (second pass): spreading the angles evenly
        // fixed the clumping but, with every mote starting at the SAME
        // radius, it replaced it with the opposite problem — a flawless
        // circle of dots that reads as a piece of UI drawn on the board
        // rather than as material the board threw up. The radius has to
        // be jittered too; every style here that pulls its particles to
        // one fixed distance needs the same treatment.
        final d = cell * (0.28 + 0.2 * _j(seed, i + 71)) * (1 - out);
        canvas.drawCircle(center + Offset(math.cos(a) * d, math.sin(a) * d),
            cell * 0.03 * (hit ? 1.3 : 1.0) * fade, _f(tint, fade * 0.95));
      }

    case DeckDebris.sludge:
      // Heavy, slow, and it comes back down.
      final n = _n(5 + boost * 2);
      for (var i = 0; i < n; i++) {
        final a = -math.pi / 2 + ((i + 0.5) / n - 0.5) * 2.4;
        final d = cell * (0.16 + 0.2 * _j(seed, i + 9)) * out;
        final drop = cell * 0.4 * t * t;
        final p = center + Offset(math.cos(a) * d, math.sin(a) * d + drop);
        canvas.drawCircle(p, cell * 0.065 * fade, _f(heavy, fade * 0.92));
        canvas.drawCircle(
            p, cell * 0.065 * fade, _s(tint, fade * 0.55, cell * 0.016));
      }

    case DeckDebris.splinters:
      // Timber, thrown flat and end-over-end.
      final n = _n(6 + boost * 3);
      for (var i = 0; i < n; i++) {
        final a = _ang(seed, i, n);
        final d = cell * (0.16 + 0.24 * _j(seed, i + 23)) * out;
        final p = center + Offset(math.cos(a) * d, math.sin(a) * d);
        final spin = a + t * 5;
        final len = cell * 0.09 * fade;
        canvas.drawLine(
          p + Offset(math.cos(spin) * len, math.sin(spin) * len),
          p - Offset(math.cos(spin) * len, math.sin(spin) * len),
          _s(heavy, fade * 0.95, cell * 0.03),
        );
      }

    case DeckDebris.steamjet:
      // One short vent, straight up, over before the marker lands.
      //
      // Drawn as a stacked column — each puff further up is bigger and
      // thinner — because the first pass put one soft blob on the impact
      // and it read as a glow rather than as escaping steam.
      final jet = (t / 0.6).clamp(0.0, 1.0);
      if (jet < 1) {
        for (var i = 0; i < _n(6); i++) {
          final step = (i + 1) / 6;
          final x = (_j(seed, i) - 0.5) * cell * 0.24 * step;
          final rise = cell * 0.6 * jet * step;
          canvas.drawCircle(
            center + Offset(x, -rise),
            cell * (0.06 + 0.12 * step * jet),
            _f(tint, (1 - jet) * (1 - step * 0.55) * 0.5),
          );
        }
        // The vent mouth itself, bright and brief.
        canvas.drawCircle(
            center, cell * 0.1 * (1 - jet), _f(tint, (1 - jet) * 0.8));
      }

    case DeckDebris.icechips:
      // Chips skate out fast and stop dead rather than fading in flight.
      final n = _n(7 + boost * 3);
      for (var i = 0; i < n; i++) {
        final a = _ang(seed, i, n);
        final d = cell * (0.13 + 0.3 * _j(seed, i + 31)) * out;
        final p = center + Offset(math.cos(a) * d, math.sin(a) * d);
        final r = cell * (0.035 + 0.03 * _j(seed, i + 47)) * fade;
        // A three-sided chip, not a dot: ice breaks, it does not splash.
        final path = Path();
        for (var k = 0; k < 3; k++) {
          final ang = a + k * 2 * math.pi / 3;
          final pt = p + Offset(math.cos(ang) * r, math.sin(ang) * r);
          if (k == 0) {
            path.moveTo(pt.dx, pt.dy);
          } else {
            path.lineTo(pt.dx, pt.dy);
          }
        }
        path.close();
        canvas.drawPath(path, _f(tint, fade));
      }

    case DeckDebris.plasma:
      // A hex ripple pushing out — the field reacts, nothing is thrown.
      for (var ring = 0; ring < _n(2); ring++) {
        final phase = (out - ring * 0.22).clamp(0.0, 1.0);
        if (phase <= 0) continue;
        final r = cell * (0.12 + 0.32 * phase);
        final path = Path();
        for (var k = 0; k < 6; k++) {
          final ang = k * math.pi / 3 + t * 0.6;
          final pt = center + Offset(math.cos(ang) * r, math.sin(ang) * r);
          if (k == 0) {
            path.moveTo(pt.dx, pt.dy);
          } else {
            path.lineTo(pt.dx, pt.dy);
          }
        }
        path.close();
        canvas.drawPath(path, _s(tint, (1 - phase) * fade * 0.9, cell * 0.028));
      }

    case DeckDebris.wake:
      // FOUND BY RENDERING: Naval shared [foam] with the MK-I board and,
      // side by side, the two were indistinguishable — two of the fifteen
      // decks reacting identically defeats the point of keying this to
      // the board at all. A fleet's open ocean throws a flattened bow
      // wake: an ellipse that runs out WIDE rather than round, with two
      // bright crests on the beam.
      //
      // (The first attempt put four perpendicular bars on the axes, which
      // rendered as a square box drawn round the cell. An ellipse reads
      // as water; a box reads as UI.)
      final rw = cell * (0.16 + 0.26 * out);
      canvas.drawOval(
        Rect.fromCenter(center: center, width: rw * 2, height: rw * 1.15),
        _s(tint, fade * 0.55, cell * 0.05 * fade),
      );
      for (final dir in const [-1.0, 1.0]) {
        final p = center + Offset(rw * dir, 0);
        canvas.drawLine(
          p - Offset(0, rw * 0.3),
          p + Offset(0, rw * 0.3),
          _s(tint, fade * 0.8, cell * 0.045),
        );
      }
      final n = _n(5 + boost * 3);
      for (var i = 0; i < n; i++) {
        final a = _ang(seed, i, n);
        final d = cell * (0.12 + 0.16 * _j(seed, i + 19)) * out;
        final drop = cell * 0.24 * t * t;
        canvas.drawCircle(
          center + Offset(math.cos(a) * d * 1.3, math.sin(a) * d + drop),
          cell * 0.04 * fade,
          _f(tint, fade * 0.9),
        );
      }

    case DeckDebris.magma:
      // Same finding, the other duplicate: Volcanic and Inferno both sat
      // on [embers]. Molten rock is the heavier of the two — gobs that
      // arc up, fall back, and keep glowing on the way down, against
      // Inferno's weightless cinders that simply rise and wink out.
      final n = _n(5 + boost * 3);
      for (var i = 0; i < n; i++) {
        final a = -math.pi / 2 + ((i + 0.5) / n - 0.5) * 2.2;
        final d = cell * (0.16 + 0.2 * _j(seed, i + 21)) * out;
        final drop = cell * 0.42 * t * t;
        final p = center + Offset(math.cos(a) * d, math.sin(a) * d + drop);
        final r = cell * (0.05 + 0.03 * _j(seed, i + 33)) * fade;
        canvas.drawCircle(p, r * 1.9, _f(fx.accent, fade * 0.22));
        canvas.drawCircle(p, r, _f(tint, fade));
      }
  }
}
