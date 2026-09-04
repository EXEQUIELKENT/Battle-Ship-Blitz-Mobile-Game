import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'legacy_identity.dart';
import 'svg_replay.dart';

/// Converts a [Color] to the `#RRGGBB` form the replayed SVG markup wants.
/// Used to drop each skin's `legacyIdentityFor` accent (a real [Color],
/// shared with `Catalog.legacySets`' UI swatches) into the markup strings
/// below without keeping a second, hand-typed copy of the same hex.
String _hex(Color c) {
  int ch(double v) => (v * 255).round().clamp(0, 255);
  String h(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
  return '#${h(ch(c.r))}${h(ch(c.g))}${h(ch(c.b))}';
}

/// The nine legacy cannon bodies, replayed verbatim from `uploads/New
/// Design/Cannon/c-*.svg` via [paintSvgFragment] rather than hand-copied
/// shape-by-shape — the earlier hand transcription got each cannon's
/// overall silhouette right but lost fine detail along the way (ring
/// separator strokes recoloured to the theme instead of staying dark ink,
/// a hand-authored rivet spiral approximated as a plain circle of dots at
/// the wrong radius, a highlight-dot cluster dropped entirely). Replaying
/// the source markup directly means every rivet, highlight and stroke
/// colour is exactly what the design authored, permanently, with no
/// re-transcription risk.
///
/// Every one of the nine shares the exact same ring/mount structure (only
/// its three theme colours differ, plus MK-I alone carries a small extra
/// highlight-dot cluster) — [_ringMarkup] is that shared template with the
/// per-skin colours substituted in, matching every source file exactly.
/// The turret above it is genuinely unique per skin, so each one is
/// embedded as its own literal fragment in [_turretMarkup].
///
/// Recentred and rescaled so the ring's own centre (design point (60,72))
/// lands exactly on the caller's `center` and its own radius (34 design
/// units) lands exactly on `outerR` — the same contract the previous
/// generic ring/barrel held, so nothing about `CannonWidget`'s own sizing
/// needs to change.
///
/// [cooldown] is the reload sweep: 1 = loaded (nothing drawn), <1 draws
/// that fraction of the ring filled in, clockwise from the barrel.
///
/// [recoil] is the raw 0-1 shot animation ([recoilPull] is the same value
/// already turned into a pixel offset). Only the Abyss Railgun reads it —
/// see [_paintAbyssSlug] — so every other skin ignores it entirely.
Offset paintLegacyCannon(
  Canvas canvas,
  Offset center,
  double outerR,
  String cannonId, {
  double recoilPull = 0,
  double cooldown = 1,
  double recoil = 0,
}) {
  final scale = outerR / 34;
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.scale(scale);
  canvas.translate(-60, -72);

  paintSvgFragmentCached(canvas, _ringMarkup(cannonId));

  // FEEDBACK (reload ring): drawn HERE — after the ring plate, before the
  // turret — so the barrel reads as standing on top of the ring rather
  // than being sliced across by it, which is what a sweep painted after
  // the whole gun looked like. Traced on the ring's own accent circle in
  // the shared design space (centre (60,72), radius 20.5 of the shared
  // 34-radius ring plate), so it lands in exactly the same place on all
  // nine skins and the barrel always rises out of its 12 o'clock — NOT
  // the off-centre `ringCx/ringCy/ringRadius` the `New Cannons` source
  // files carry, which describe that design tool's own preview canvas
  // rather than this widget's.
  if (cooldown < 0.999) {
    canvas.drawArc(
      Rect.fromCircle(center: const Offset(60, 72), radius: 20.5),
      -math.pi / 2,
      2 * math.pi * cooldown,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 34 * 0.12
        ..strokeCap = StrokeCap.round,
    );
  }

  canvas.save();
  // recoilPull is given in canvas pixels (matching the old contract the
  // caller's recoil math is written against); translating by
  // recoilPull/scale here, inside the scale(scale) frame just applied
  // above, nets out to exactly recoilPull pixels of on-screen shift.
  canvas.translate(0, recoilPull / scale);
  paintSvgFragmentCached(canvas, _turretMarkup(cannonId));
  // Drawn here, inside the recoil translate, so the round rides the barrel
  // exactly as it would if it were still part of the markup above.
  if (cannonId == 'phantom') {
    _paintAbyssSlug(canvas, cooldown, recoil);
  }
  canvas.restore();

  canvas.restore();
  return center + Offset(0, (_tipY(cannonId) - 72) * scale + recoilPull);
}

/// How far THIS legacy skin's own muzzle tip sits from the ring's centre,
/// as a fraction of the widget's own size — the exact same role
/// `CannonWidget.muzzleFraction`/`FleetFamily.muzzleFrac` play, computed
/// once here from each turret's own design-space muzzle point so
/// `paintLegacyCannon`'s internal recoil math and
/// `CannonWidget.muzzleFractionOf`'s external contract (read by
/// `battle_screen.dart` to spawn the actual cannonball) always agree on
/// the same point without computing it twice.
///
/// Derivation: a design point's canvas distance from the ring centre is
/// `(72 - y) * (outerR/34)`; `outerR` is `0.48 * size.width`, so as a
/// fraction of `size.width` alone that's `(72 - y) * 0.48 / 34`.
double legacyMuzzleFractionOf(String id) => (72 - _tipY(id)) * 0.48 / 34;

double _tipY(String id) => switch (id) {
      'mk1' => 12.0,
      'inferno' => 20.0,
      'kraken' => 18.0,
      'phantom' => 12.0,
      'royal' => 9.0,
      'sunfire' => 14.0,
      'tesla' => 6.0,
      'venom' => 16.0,
      'void' => 16.0,
      _ => 12.0,
    };

/// The ring/mount structure every legacy cannon shares, verbatim from the
/// source SVGs up to (and including) the mount collar's two highlight
/// rivets — the exact point every one of the nine files stops being
/// identical and the turret above it takes over.
String _ringMarkup(String id) {
  // FEEDBACK: accent (ring3 + the two mount highlight rivets) recoloured
  // per `legacy_identity.dart`'s Adjustments-sourced palette — a targeted
  // "pop colour" swap; the base/mid-tone body colours below (mid, mount)
  // are left exactly as transcribed from the original cannon SVGs.
  //
  // FEEDBACK (round two): MK-I, Arctic (tesla), Abyss (phantom) and
  // Coral (sunfire) were then re-imported from `uploads/New Design/New
  // Cannons/{steel,arctic,abyss,coral}-fire-reload_cannon_fx.dart`, which
  // — unlike the colour-only `Adjustments` stubs — carry the full cannon
  // SVG. MK-I came back byte-identical to what was already here (a useful
  // confirmation the transcription pipeline is faithful); the other three
  // genuinely restyle their body tones, and two of them give the ring's
  // own accent circle a LIGHTER tint (`bright`) than the identity accent,
  // which stays what it was — those same files' own
  // `CannonFireProfile.ringColor` is the unchanged identity accent, so it
  // is still the right colour for the reload sweep, crosshair and hit
  // glow. `bright` is null wherever the two are the same colour.
  final (mid, mount, bright, extra) = switch (id) {
    'mk1' => ('#64748B', '#5A6B78', null, true),
    'inferno' => ('#7C2D12', '#5A1E0F', null, false),
    'kraken' => ('#0F766E', '#0B4A42', null, false),
    'phantom' => ('#1A2138', '#10162A', null, false),
    'royal' => ('#78350F', '#5A2A0A', null, false),
    'sunfire' => ('#C1543F', '#3A1710', '#FF9E7A', false),
    'tesla' => ('#24404F', '#152933', '#E8F7FF', false),
    'venom' => ('#365314', '#24410A', null, false),
    'void' => ('#111827', '#0F0F1A', null, false),
    _ => ('#64748B', '#5A6B78', null, true),
  };
  final accent = bright ?? _hex(legacyIdentityFor(id).accent);
  return '<ellipse cx="60" cy="102" rx="38" ry="8" fill="black" opacity="0.22"></ellipse>'
      '<circle cx="60" cy="72" r="34" fill="#1E2A36" stroke="#1E2A36" stroke-width="3"></circle>'
      '<path d="M 38 52 A34 34 0 0 1 60 38" stroke="white" stroke-width="3.2" opacity="0.09" stroke-linecap="round" fill="none"></path>'
      '<circle cx="60" cy="72" r="28.5" fill="$mid" stroke="#1E2A36" stroke-width="2"></circle>'
      '<circle cx="60" cy="72" r="20.5" fill="$accent" stroke="#1E2A36" stroke-width="1.8" opacity="0.9"></circle>'
      '<circle cx="60" cy="72" r="20.5" fill="none" stroke="white" stroke-width="0.7" opacity="0.10"></circle>'
      '<g fill="#1E2A36" opacity="0.55">'
      '<circle cx="60" cy="39.5" r="1.25"></circle><circle cx="69.8" cy="42.2" r="1.25"></circle>'
      '<circle cx="77.2" cy="49" r="1.25"></circle><circle cx="80" cy="59" r="1.25"></circle>'
      '<circle cx="77.2" cy="69" r="1.25"></circle><circle cx="69.8" cy="76.5" r="1.25"></circle>'
      '<circle cx="60" cy="79.5" r="1.25"></circle><circle cx="50.2" cy="76.5" r="1.25"></circle>'
      '<circle cx="42.8" cy="69" r="1.25"></circle><circle cx="40" cy="59" r="1.25"></circle>'
      '</g>'
      '${extra ? '<g fill="white" opacity="0.28"><circle cx="59.3" cy="38.9" r="0.5"></circle><circle cx="69.1" cy="41.6" r="0.5"></circle><circle cx="76.5" cy="48.4" r="0.5"></circle></g>' : ''}'
      '<circle cx="60" cy="64" r="13.5" fill="$mount" stroke="#1E2A36" stroke-width="2.2"></circle>'
      '<circle cx="45.5" cy="65.5" r="3.2" fill="#1E2A36"></circle>'
      '<circle cx="74.5" cy="65.5" r="3.2" fill="#1E2A36"></circle>'
      '<circle cx="45.5" cy="65.5" r="1.6" fill="$accent" opacity="0.9"></circle>'
      '<circle cx="74.5" cy="65.5" r="1.6" fill="$accent" opacity="0.9"></circle>';
}

String _turretMarkup(String id) => switch (id) {
      'mk1' => _turretMk1,
      'inferno' => _turretInferno,
      'kraken' => _turretKraken,
      'phantom' => _turretPhantom,
      'royal' => _turretRoyal,
      'sunfire' => _turretSunfire,
      'tesla' => _turretTesla,
      'venom' => _turretVenom,
      'void' => _turretVoid,
      _ => _turretMk1,
    };

const _turretMk1 = '<path d="M54 66 L50 22 L70 22 L66 66 Z" fill="#64748B" stroke="#1E2A36" stroke-width="3" stroke-linejoin="round"></path><path d="M54 66 H66" stroke="#1E2A36" stroke-width="2"></path><rect x="49" y="36" width="22" height="5" rx="2" fill="#94A3B8" stroke="#1E2A36" stroke-width="1.8"></rect><rect x="50" y="50" width="20" height="4.5" rx="2" fill="#94A3B8" stroke="#1E2A36" stroke-width="1.6"></rect><circle cx="52" cy="32" r="1.8" fill="#1E2A36"></circle><circle cx="68" cy="32" r="1.8" fill="#1E2A36"></circle><circle cx="54" cy="46" r="1.4" fill="#1E2A36"></circle><circle cx="66" cy="46" r="1.4" fill="#1E2A36"></circle><path d="M56 28 L54 52" stroke="white" stroke-width="1.4" opacity="0.20" stroke-linecap="round"></path><rect x="44" y="12" width="32" height="12" rx="3" fill="#94A3B8" stroke="#1E2A36" stroke-width="3"></rect><ellipse cx="60" cy="12" rx="11.5" ry="4" fill="#1E2A36"></ellipse><ellipse cx="60" cy="11" rx="7" ry="2.2" fill="#0E151C"></ellipse><path d="M 49.5 10.5 A7.5 2 0 0 1 60 8.6" stroke="white" stroke-width="1" opacity="0.22" stroke-linecap="round" fill="none"></path>';

const _turretInferno = '<path d="M52 72 L44 42 L76 42 L68 72 Z" fill="#7C2D12" stroke="#1E2A36" stroke-width="3" stroke-linejoin="round"></path><path d="M44 42 L42 30 L78 30 L76 42 Z" fill="#EF4444" stroke="#1E2A36" stroke-width="3" stroke-linejoin="round"></path><path d="M52 72 H68" stroke="#1E2A36" stroke-width="2"></path><rect x="48" y="54" width="24" height="4" rx="1.5" fill="#FFD54A" stroke="#1E2A36" stroke-width="1.6"></rect><circle cx="51" cy="60" r="1.4" fill="#1E2A36"></circle><circle cx="69" cy="60" r="1.4" fill="#1E2A36"></circle><path d="M44 48 L36 36" stroke="#FFD54A" stroke-width="2.2" stroke-linecap="round"></path><path d="M76 48 L84 36" stroke="#FFD54A" stroke-width="2.2" stroke-linecap="round"></path><path d="M52 38 L48 28" stroke="#FFD54A" stroke-width="1.6" stroke-linecap="round" opacity="0.9"></path><path d="M68 38 L72 28" stroke="#FFD54A" stroke-width="1.6" stroke-linecap="round" opacity="0.9"></path><rect x="40" y="20" width="40" height="12" rx="3" fill="#FFD54A" stroke="#1E2A36" stroke-width="3"></rect><ellipse cx="60" cy="20" rx="14" ry="4" fill="#1E2A36"></ellipse><ellipse cx="60" cy="19" rx="8.5" ry="2.2" fill="#FFD54A"></ellipse><path d="M41 48 L33 55 L41 62 Z" fill="#EF4444" stroke="#1E2A36" stroke-width="1.8" stroke-linejoin="round"></path><path d="M79 48 L87 55 L79 62 Z" fill="#EF4444" stroke="#1E2A36" stroke-width="1.8" stroke-linejoin="round"></path><rect x="41" y="48" width="6" height="14" rx="2" fill="#EF4444" stroke="#1E2A36" stroke-width="1.8"></rect><rect x="73" y="48" width="6" height="14" rx="2" fill="#EF4444" stroke="#1E2A36" stroke-width="1.8"></rect>';

const _turretKraken = '<rect x="48" y="30" width="24" height="48" rx="8" fill="#0F766E" stroke="#1E2A36" stroke-width="3"></rect><path d="M48 72 H72" stroke="#1E2A36" stroke-width="2"></path><rect x="46" y="54" width="28" height="4" rx="1.5" fill="#5EEAD4" stroke="#1E2A36" stroke-width="1.6" opacity="0.9"></rect><circle cx="52" cy="60" r="1.5" fill="#1E2A36"></circle><circle cx="68" cy="60" r="1.5" fill="#1E2A36"></circle><circle cx="52" cy="40" r="5" fill="#5EEAD4" stroke="#1E2A36" stroke-width="1.8"></circle><circle cx="68" cy="44" r="4" fill="#5EEAD4" stroke="#1E2A36" stroke-width="1.8"></circle><circle cx="54" cy="62" r="3.5" fill="#5EEAD4" stroke="#1E2A36" stroke-width="1.6"></circle><circle cx="68" cy="66" r="4.5" fill="#5EEAD4" stroke="#1E2A36" stroke-width="1.8"></circle><path d="M42 46 C30 40 22 52 30 62" stroke="#5EEAD4" stroke-width="3" stroke-linecap="round" fill="none"></path><path d="M78 46 C90 40 98 52 90 62" stroke="#5EEAD4" stroke-width="3" stroke-linecap="round" fill="none"></path><circle cx="30" cy="62" r="3" fill="#B6FFF1" stroke="#1E2A36" stroke-width="1.4"></circle><circle cx="90" cy="62" r="3" fill="#B6FFF1" stroke="#1E2A36" stroke-width="1.4"></circle><rect x="44" y="18" width="32" height="16" rx="6" fill="#5EEAD4" stroke="#1E2A36" stroke-width="3"></rect><ellipse cx="60" cy="18" rx="14" ry="4" fill="#1E2A36"></ellipse><ellipse cx="60" cy="17" rx="8" ry="1.8" fill="#072E2A"></ellipse>';

// The round itself — `<path d="M54 28 L60 12 L66 28 Z">` and the
// `<circle cx="60" cy="16" r="2.5">` spark at its tip — is deliberately
// NOT in here. It is the one piece of ammunition any of the nine guns
// carries in the open, so it is drawn per-frame by [_paintAbyssSlug]
// instead, which can show it leave on the shot and rebuild over the
// reload. Everything else about the gun is verbatim, and the round sits
// clear above the fins below, so lifting it out of this string does not
// disturb the drawing order.
const _turretPhantom = '<path d="M56 72 L52 28 L68 28 L64 72 Z" fill="#1A2138" stroke="#1E2A36" stroke-width="3" stroke-linejoin="round"></path><path d="M56 72 H64" stroke="#1E2A36" stroke-width="2"></path><rect x="52" y="52" width="16" height="4" rx="1.5" fill="#7C6BC4" stroke="#1E2A36" stroke-width="1.6"></rect><circle cx="54" cy="58" r="1.5" fill="#1E2A36"></circle><circle cx="66" cy="58" r="1.5" fill="#1E2A36"></circle><ellipse cx="60" cy="44" rx="14" ry="4" fill="none" stroke="#7C6BC4" stroke-width="1.8"></ellipse><ellipse cx="60" cy="56" rx="16" ry="5" fill="none" stroke="#7C6BC4" stroke-width="1.4" opacity="0.7"></ellipse><path d="M54 72 L44 88 L54 84 Z" fill="#7C6BC4" stroke="#1E2A36" stroke-width="2" stroke-linejoin="round"></path><path d="M66 72 L76 88 L66 84 Z" fill="#7C6BC4" stroke="#1E2A36" stroke-width="2" stroke-linejoin="round"></path>';

/// Geometry and paints for [_paintAbyssSlug], hoisted to the top level
/// because that runs on a painter which repaints for every frame of a
/// recoil and every tick of a reload — allocating a `Path` and four
/// `Paint`s each time would be the only per-frame garbage in this file.
/// The paints' colours are assigned at the point of use (the alphas are
/// what animate); nothing else about them ever changes.
final Path _abyssSlugPath = Path()
  ..moveTo(54, 28)
  ..lineTo(60, 12)
  ..lineTo(66, 28)
  ..close();
final Paint _abyssSlugFill = Paint();
final Paint _abyssSlugSpark = Paint();
final Paint _abyssSlugInk = Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = 2.2
  ..strokeJoin = StrokeJoin.round;
final Paint _abyssRailPaint = Paint()..style = PaintingStyle.stroke;

/// Abyss Railgun's loaded round: the dart standing in the rails, and the
/// spark at its tip.
///
/// FEEDBACK ("the abyss cannon has that projectile visible on it — make it
/// go off when it fires, and build back up while it reloads"). Every other
/// legacy gun keeps its ammunition inside a barrel, so there is nothing on
/// them to show; this one carries the round in the open between two
/// accelerator rails, and drawing it as part of the fixed art meant the
/// gun looked fully loaded at every moment — including the several seconds
/// it very much was not.
///
/// [charge] is the reload fraction (0 just fired, 1 loaded). [discharge]
/// is the recoil, which does two things a cooldown alone cannot: it clears
/// the round the *instant* the shot goes off, rather than at whichever of
/// the game's 100ms cooldown ticks lands next, and it lights the rails for
/// the shot itself.
///
/// PERF: at [charge] 1 with no [discharge] — a loaded gun, which is most
/// of what is ever on screen — this draws exactly the two shapes the SVG
/// did, at the same size, in the same colours, so nothing about a waiting
/// cannon changed or costs more. Mid-reload it adds at most four more
/// plain fills and strokes to a painter already repainting for the
/// cooldown ring beside it: no `saveLayer`, no blur, nothing that can
/// force an offscreen pass.
void _paintAbyssSlug(Canvas canvas, double charge, double discharge) {
  final fired = discharge.clamp(0.0, 1.0);
  final t = charge.clamp(0.0, 1.0) * (1 - fired);

  // The rails carry the charge: dark at the moment of the shot, brightest
  // halfway through the reload, and back to the art's own plain violet by
  // the time the round is seated — so a fully loaded gun is the drawing
  // the design authored, untouched.
  final rails = math.max(math.sin(math.pi * t) * 0.45, fired * 0.9);
  if (rails > 0.01) {
    _abyssRailPaint.color = const Color(0xFFF1E3FF).withValues(alpha: rails);
    _abyssRailPaint.strokeWidth = 1.8;
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(60, 44), width: 28, height: 8),
      _abyssRailPaint,
    );
    _abyssRailPaint.strokeWidth = 1.4;
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(60, 56), width: 32, height: 10),
      _abyssRailPaint,
    );
  }

  if (t <= 0.01) return;

  // Grown from the base of the rails upward rather than faded in on the
  // spot, so it reads as the round being assembled between them.
  canvas.save();
  canvas.translate(60, 28);
  canvas.scale(0.55 + 0.45 * t, 0.35 + 0.65 * t);
  canvas.translate(-60, -28);
  _abyssSlugFill.color = const Color(0xFF7C6BC4).withValues(alpha: t);
  _abyssSlugInk.color = const Color(0xFF1E2A36).withValues(alpha: t);
  canvas.drawPath(_abyssSlugPath, _abyssSlugFill);
  canvas.drawPath(_abyssSlugPath, _abyssSlugInk);
  // The tip lights only at the end of the reload. That spark is the gun's
  // "loaded" tell, so it must not be showing while the round is still
  // forming — that is the whole cue this animation exists to give.
  final spark = ((t - 0.55) / 0.45).clamp(0.0, 1.0);
  if (spark > 0) {
    _abyssSlugSpark.color =
        const Color(0xFFF1E3FF).withValues(alpha: spark);
    canvas.drawCircle(const Offset(60, 16), 2.5 * spark, _abyssSlugSpark);
  }
  canvas.restore();
}

const _turretRoyal = '<path d="M50 72 L44 30 L76 30 L70 72 Z" fill="#92400E" stroke="#1E2A36" stroke-width="3" stroke-linejoin="round"></path><path d="M50 72 H70" stroke="#1E2A36" stroke-width="2"></path><rect x="42" y="46" width="36" height="10" rx="5" fill="#FBBF24" stroke="#1E2A36" stroke-width="2"></rect><circle cx="50" cy="51" r="2" fill="#1E2A36"></circle><circle cx="60" cy="51" r="2" fill="#FFF3C4"></circle><circle cx="70" cy="51" r="2" fill="#1E2A36"></circle><circle cx="52" cy="60" r="1.5" fill="#1E2A36"></circle><circle cx="68" cy="60" r="1.5" fill="#1E2A36"></circle><path d="M44 30 L42 13 L52 20.5 L60 9 L68 20.5 L78 13 L76 30 Z" fill="#FBBF24" stroke="#1E2A36" stroke-width="2.5" stroke-linejoin="round"></path><circle cx="42" cy="12" r="2.4" fill="#FBBF24" stroke="#1E2A36" stroke-width="1.6"></circle><circle cx="60" cy="8" r="2.8" fill="#FFF3C4" stroke="#1E2A36" stroke-width="1.6"></circle><circle cx="78" cy="12" r="2.4" fill="#FBBF24" stroke="#1E2A36" stroke-width="1.6"></circle><rect x="43" y="25" width="34" height="8" rx="2" fill="#FBBF24" stroke="#1E2A36" stroke-width="2"></rect><circle cx="52" cy="29" r="1.7" fill="#FFF3C4" stroke="#1E2A36" stroke-width="1.2"></circle><circle cx="60" cy="29" r="1.9" fill="#FFF3C4" stroke="#1E2A36" stroke-width="1.2"></circle><circle cx="68" cy="29" r="1.7" fill="#FFF3C4" stroke="#1E2A36" stroke-width="1.2"></circle><path d="M44 52 Q38 50 40 60" stroke="#FBBF24" stroke-width="1.8" stroke-linecap="round" fill="none"></path><path d="M76 52 Q82 50 80 60" stroke="#FBBF24" stroke-width="1.8" stroke-linecap="round" fill="none"></path>';

const _turretSunfire = '<path d="M51 60 L51 28 L69 28 L69 60 Z" fill="#C1543F" stroke="#1E2A36" stroke-width="3" stroke-linejoin="round"></path><rect x="51" y="34" width="18" height="4.5" rx="1.5" fill="#FF9E7A" stroke="#1E2A36" stroke-width="1.5"></rect><circle cx="54.5" cy="42" r="1.4" fill="#1E2A36"></circle><circle cx="65.5" cy="42" r="1.4" fill="#1E2A36"></circle><rect x="41" y="42" width="10.5" height="6" rx="2" fill="#FF9E7A" stroke="#1E2A36" stroke-width="1.8"></rect><rect x="68.5" y="42" width="10.5" height="6" rx="2" fill="#FF9E7A" stroke="#1E2A36" stroke-width="1.8"></rect><circle cx="60" cy="64" r="16" fill="#C1543F" stroke="#1E2A36" stroke-width="3"></circle><circle cx="60" cy="64" r="10.5" fill="none" stroke="#EAB308" stroke-width="1.8"></circle><circle cx="60" cy="64" r="2.2" fill="#FF9E7A"></circle><path d="M77 62 L82 64 L77 66 Z" fill="#FF9E7A" stroke="#1E2A36" stroke-width="1.2" stroke-linejoin="round"></path><path d="M43 62 L38 64 L43 66 Z" fill="#FF9E7A" stroke="#1E2A36" stroke-width="1.2" stroke-linejoin="round"></path><path d="M70.6 50.6 L73.4 53.4 L74.9 49.2 Z" fill="#FF9E7A" stroke="#1E2A36" stroke-width="1.2" stroke-linejoin="round"></path><path d="M49.4 50.6 L46.6 53.4 L45.1 49.2 Z" fill="#FF9E7A" stroke="#1E2A36" stroke-width="1.2" stroke-linejoin="round"></path><path d="M49.4 77.4 L46.6 74.6 L45.1 78.8 Z" fill="#FF9E7A" stroke="#1E2A36" stroke-width="1.2" stroke-linejoin="round"></path><path d="M70.6 77.4 L73.4 74.6 L74.9 78.8 Z" fill="#FF9E7A" stroke="#1E2A36" stroke-width="1.2" stroke-linejoin="round"></path><rect x="49" y="25" width="22" height="5" rx="2" fill="#C1543F" stroke="#1E2A36" stroke-width="2"></rect><rect x="46" y="14" width="28" height="12" rx="5" fill="#FF9E7A" stroke="#1E2A36" stroke-width="3"></rect><ellipse cx="60" cy="14" rx="10" ry="3.6" fill="#1E2A36"></ellipse><ellipse cx="60" cy="13" rx="6" ry="1.8" fill="#FFF8D6"></ellipse><circle cx="60" cy="13" r="1" fill="white"></circle><path d="M44 20 H37" stroke="#FF9E7A" stroke-width="2" stroke-linecap="round"></path><path d="M76 20 H83" stroke="#FF9E7A" stroke-width="2" stroke-linecap="round"></path><path d="M47 12 L42 7" stroke="#FF9E7A" stroke-width="2" stroke-linecap="round"></path><path d="M73 12 L78 7" stroke="#FF9E7A" stroke-width="2" stroke-linecap="round"></path>';

const _turretTesla = '<rect x="50" y="22" width="20" height="56" rx="4" fill="#24404F" stroke="#1E2A36" stroke-width="3"></rect><path d="M50 72 H70" stroke="#1E2A36" stroke-width="2"></path><rect x="46" y="30" width="28" height="8" rx="3" fill="#E8F7FF" stroke="#1E2A36" stroke-width="2"></rect><rect x="46" y="46" width="28" height="8" rx="3" fill="#E8F7FF" stroke="#1E2A36" stroke-width="2"></rect><rect x="46" y="62" width="28" height="8" rx="3" fill="#E8F7FF" stroke="#1E2A36" stroke-width="2"></rect><rect x="48" y="32" width="24" height="4" rx="1.5" fill="#E0FBFF" opacity="0.9"></rect><rect x="48" y="48" width="24" height="4" rx="1.5" fill="#E0FBFF" opacity="0.9"></rect><circle cx="52" cy="58" r="1.6" fill="#1E2A36"></circle><circle cx="68" cy="58" r="1.6" fill="#1E2A36"></circle><path d="M54 22 L45 6 L53 6 Z" fill="#E0FBFF" stroke="#1E2A36" stroke-width="1.8" stroke-linejoin="round"></path><path d="M66 22 L75 6 L67 6 Z" fill="#E0FBFF" stroke="#1E2A36" stroke-width="1.8" stroke-linejoin="round"></path><circle cx="38" cy="50" r="2.5" fill="#1E2A36"></circle><circle cx="82" cy="50" r="2.5" fill="#1E2A36"></circle>';

const _turretVenom = '<path d="M53 60 L50 28 L70 28 L67 60 Z" fill="#365314" stroke="#1E2A36" stroke-width="3" stroke-linejoin="round"></path><rect x="50.5" y="34" width="19" height="4.5" rx="1.5" fill="#84CC16" stroke="#1E2A36" stroke-width="1.5"></rect><circle cx="54" cy="42" r="1.4" fill="#1E2A36"></circle><circle cx="66" cy="42" r="1.4" fill="#1E2A36"></circle><rect x="44" y="52" width="32" height="24" rx="8" fill="#365314" stroke="#1E2A36" stroke-width="3"></rect><rect x="45.5" y="58" width="29" height="5" fill="#84CC16"></rect><rect x="46.5" y="65" width="27" height="5" fill="#84CC16"></rect><rect x="44" y="16" width="32" height="12" rx="3" fill="#84CC16" stroke="#1E2A36" stroke-width="3"></rect><ellipse cx="60" cy="16" rx="11.5" ry="3.8" fill="#1E2A36"></ellipse><ellipse cx="60" cy="15" rx="7" ry="2" fill="#D4F98A"></ellipse><rect x="52" y="72" width="16" height="14" rx="3" fill="#84CC16" stroke="#1E2A36" stroke-width="2.5"></rect><circle cx="60" cy="88" r="4" fill="#D4F98A" stroke="#1E2A36" stroke-width="1.8"></circle>';

const _turretVoid = '<rect x="50" y="30" width="20" height="44" rx="6" fill="#111827" stroke="#1E2A36" stroke-width="3"></rect><path d="M50 72 H70" stroke="#1E2A36" stroke-width="2"></path><rect x="48" y="56" width="24" height="3" rx="1.5" fill="#EC4899" stroke="#1E2A36" stroke-width="1.4" opacity="0.85"></rect><circle cx="52" cy="61" r="1.5" fill="#1E2A36"></circle><circle cx="68" cy="61" r="1.5" fill="#1E2A36"></circle><ellipse cx="60" cy="52" rx="18" ry="6" fill="none" stroke="#EC4899" stroke-width="2"></ellipse><ellipse cx="60" cy="52" rx="18" ry="6" fill="none" stroke="#FBCFE8" stroke-width="0.7" opacity="0.6"></ellipse><path d="M42 48 C38 50 38 56 42 58" stroke="#EC4899" stroke-width="1.4" fill="none" stroke-linecap="round" opacity="0.6"></path><path d="M78 48 C82 50 82 56 78 58" stroke="#EC4899" stroke-width="1.4" fill="none" stroke-linecap="round" opacity="0.6"></path><circle cx="38" cy="52" r="4" fill="none" stroke="#EC4899" stroke-width="1.4" opacity="0.6"></circle><circle cx="82" cy="52" r="4" fill="none" stroke="#EC4899" stroke-width="1.4" opacity="0.6"></circle><rect x="46" y="16" width="28" height="16" rx="6" fill="#EC4899" stroke="#1E2A36" stroke-width="3"></rect><ellipse cx="60" cy="16" rx="12" ry="4" fill="#1E2A36"></ellipse><ellipse cx="60" cy="15" rx="6" ry="1.8" fill="black"></ellipse><circle cx="60" cy="15" r="1.2" fill="#FBCFE8"></circle><circle cx="82" cy="68" r="1.2" fill="#FBCFE8" opacity="0.6"></circle>';

/// The struck-cell marker for a legacy cannon's shot, ported from
/// `uploads/New Design/Hit/hit-*.svg` — a genuinely distinct glyph per
/// skin (a flame teardrop for Inferno, a tentacle curl for Kraken, a
/// crown badge for Royal, an eight-ray burst for Sunfire, a lightning
/// crosshair for Tesla, a fanged leaf for Venom, a spiky compass rose for
/// Void, a glowing hex for Phantom, a torn-plate slash for MK-I), all
/// authored in one shared 40×40 box.
void paintLegacyHit(Canvas canvas, Offset center, double cell, String cannonId) {
  final scale = cell / 40;
  Offset p(double x, double y) => center + Offset(x - 20, y - 20) * scale;
  double s(double len) => len * scale;
  Paint fill(Color c, {double opacity = 1}) => Paint()..color = c.withValues(alpha: opacity);
  Paint strokeP(Color c, double w, {double opacity = 1, StrokeCap cap = StrokeCap.butt}) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = s(w)
    ..strokeCap = cap
    ..color = c.withValues(alpha: opacity);

  switch (cannonId) {
    case 'inferno':
      canvas.drawOval(Rect.fromCenter(center: p(20, 27), width: s(22), height: s(18)), fill(const Color(0xFF1A0A06), opacity: 0.62));
      canvas.drawPath(
          (Path()
            ..moveTo(p(20, 2).dx, p(20, 2).dy)
            ..cubicTo(p(24, 10).dx, p(24, 10).dy, p(30, 12).dx, p(30, 12).dy, p(28, 20).dx, p(28, 20).dy)
            ..cubicTo(p(32, 18).dx, p(32, 18).dy, p(34, 24).dx, p(34, 24).dy, p(28, 28).dx, p(28, 28).dy)
            ..lineTo(p(20, 36).dx, p(20, 36).dy)
            ..lineTo(p(12, 28).dx, p(12, 28).dy)
            ..cubicTo(p(6, 24).dx, p(6, 24).dy, p(8, 18).dx, p(8, 18).dy, p(12, 20).dx, p(12, 20).dy)
            ..cubicTo(p(10, 12).dx, p(10, 12).dy, p(16, 10).dx, p(16, 10).dy, p(20, 2).dx, p(20, 2).dy)
            ..close()),
          fill(const Color(0xFFFF6A2B)));
      canvas.drawCircle(p(20, 24), s(3.2), fill(const Color(0xFFFFF8D0)));
      canvas.drawCircle(p(20, 24), s(1.4), fill(Colors.white, opacity: 0.9));
      break;

    case 'kraken':
      canvas.drawCircle(p(20, 20), s(12), fill(const Color(0xFF05201E)));
      canvas.drawCircle(p(20, 20), s(12), strokeP(const Color(0xFF1B4A42), 1.7));
      canvas.drawPath(
          (Path()..moveTo(p(12, 14).dx, p(12, 14).dy)..cubicTo(p(8, 16).dx, p(8, 16).dy, p(6, 20).dx, p(6, 20).dy, p(10, 24).dx, p(10, 24).dy)),
          strokeP(const Color(0xFF34D399), 1.7, opacity: 0.72, cap: StrokeCap.round));
      canvas.drawPath(
          (Path()..moveTo(p(28, 26).dx, p(28, 26).dy)..cubicTo(p(32, 24).dx, p(32, 24).dy, p(34, 20).dx, p(34, 20).dy, p(30, 16).dx, p(30, 16).dy)),
          strokeP(const Color(0xFF34D399), 1.7, opacity: 0.62, cap: StrokeCap.round));
      canvas.drawCircle(p(15, 15), s(2), fill(const Color(0xFFB6FFF1), opacity: 0.88));
      canvas.drawCircle(p(26, 24), s(1.5), fill(const Color(0xFFB6FFF1), opacity: 0.68));
      canvas.drawCircle(p(20, 20), s(2.8), fill(const Color(0xFF34D399)));
      break;

    case 'phantom':
      final hex = Path()
        ..moveTo(p(20, 3).dx, p(20, 3).dy)
        ..lineTo(p(34, 11).dx, p(34, 11).dy)
        ..lineTo(p(34, 29).dx, p(34, 29).dy)
        ..lineTo(p(20, 37).dx, p(20, 37).dy)
        ..lineTo(p(6, 29).dx, p(6, 29).dy)
        ..lineTo(p(6, 11).dx, p(6, 11).dy)
        ..close();
      canvas.drawPath(hex, fill(const Color(0xFF7C6BC4), opacity: 0.3));
      canvas.drawPath(hex, strokeP(const Color(0xFF7C6BC4), 2.5));
      canvas.drawCircle(p(20, 20), s(6), fill(const Color(0xFFF1E3FF)));
      break;

    case 'royal':
      final badge = Path()
        ..moveTo(p(20, 6).dx, p(20, 6).dy)
        ..lineTo(p(32, 10).dx, p(32, 10).dy)
        ..lineTo(p(36, 20).dx, p(36, 20).dy)
        ..lineTo(p(32, 30).dx, p(32, 30).dy)
        ..lineTo(p(20, 34).dx, p(20, 34).dy)
        ..lineTo(p(8, 30).dx, p(8, 30).dy)
        ..lineTo(p(4, 20).dx, p(4, 20).dy)
        ..lineTo(p(8, 10).dx, p(8, 10).dy)
        ..close();
      canvas.drawPath(badge, fill(const Color(0xFF0F1F33)));
      canvas.drawPath(badge, strokeP(const Color(0xFFC98A3E), 1.5));
      final crown = Path()
        ..moveTo(p(14, 18).dx, p(14, 18).dy)
        ..lineTo(p(16, 10).dx, p(16, 10).dy)
        ..lineTo(p(20, 14).dx, p(20, 14).dy)
        ..lineTo(p(24, 6).dx, p(24, 6).dy)
        ..lineTo(p(28, 14).dx, p(28, 14).dy)
        ..lineTo(p(32, 10).dx, p(32, 10).dy)
        ..lineTo(p(34, 18).dx, p(34, 18).dy)
        ..lineTo(p(28, 22).dx, p(28, 22).dy)
        ..lineTo(p(20, 26).dx, p(20, 26).dy)
        ..lineTo(p(12, 22).dx, p(12, 22).dy)
        ..close();
      canvas.drawPath(crown, fill(const Color(0xFFFBBF24)));
      canvas.drawPath(crown, strokeP(const Color(0xFF1E2A36), 1.1));
      canvas.drawCircle(p(20, 20), s(3.8), fill(const Color(0xFFFFF3C4)));
      canvas.drawCircle(p(20, 20), s(3.8), strokeP(const Color(0xFFC98A3E), 1));
      break;

    case 'sunfire':
      for (final a in const [0, 45, 90, 135, 180, 225, 270, 315]) {
        final rad = a * math.pi / 180;
        Offset rot(double x, double y) {
          final dx = x - 20, dy = y - 20;
          return p(20 + dx * math.cos(rad) - dy * math.sin(rad), 20 + dx * math.sin(rad) + dy * math.cos(rad));
        }
        canvas.drawPath(
            (Path()
              ..moveTo(rot(20, 20).dx, rot(20, 20).dy)
              ..lineTo(rot(17, 8).dx, rot(17, 8).dy)
              ..lineTo(rot(20, 4).dx, rot(20, 4).dy)
              ..lineTo(rot(23, 8).dx, rot(23, 8).dy)
              ..close()),
            fill(const Color(0xFFE0715A)));
      }
      canvas.drawCircle(p(20, 20), s(9), fill(const Color(0xFFE0715A)));
      canvas.drawCircle(p(20, 20), s(4), fill(const Color(0xFFFFF8D6)));
      break;

    case 'tesla':
      canvas.drawCircle(p(20, 20), s(16), strokeP(const Color(0xFF7FB8D6), 2, opacity: 0.8));
      canvas.drawLine(p(20, 4), p(20, 16), strokeP(const Color(0xFF7FE7FF), 3.5, cap: StrokeCap.round));
      canvas.drawLine(p(20, 24), p(20, 36), strokeP(const Color(0xFF7FE7FF), 3.5, cap: StrokeCap.round));
      canvas.drawLine(p(4, 20), p(16, 20), strokeP(const Color(0xFF7FE7FF), 3.5, cap: StrokeCap.round));
      canvas.drawLine(p(24, 20), p(36, 20), strokeP(const Color(0xFF7FE7FF), 3.5, cap: StrokeCap.round));
      canvas.drawLine(p(8, 8), p(15, 15), strokeP(const Color(0xFF7FE7FF), 3.5, cap: StrokeCap.round));
      canvas.drawLine(p(32, 8), p(25, 15), strokeP(const Color(0xFF7FE7FF), 3.5, cap: StrokeCap.round));
      canvas.drawLine(p(8, 32), p(15, 25), strokeP(const Color(0xFF7FE7FF), 3.5, cap: StrokeCap.round));
      canvas.drawLine(p(32, 32), p(25, 25), strokeP(const Color(0xFF7FE7FF), 3.5, cap: StrokeCap.round));
      canvas.drawCircle(p(20, 20), s(5), fill(const Color(0xFFE0FBFF)));
      break;

    case 'venom':
      canvas.drawPath(
          (Path()
            ..moveTo(p(20, 4).dx, p(20, 4).dy)
            ..cubicTo(p(30, 6).dx, p(30, 6).dy, p(34, 14).dx, p(34, 14).dy, p(32, 22).dx, p(32, 22).dy)
            ..cubicTo(p(36, 26).dx, p(36, 26).dy, p(30, 32).dx, p(30, 32).dy, p(24, 30).dx, p(24, 30).dy)
            ..cubicTo(p(20, 36).dx, p(20, 36).dy, p(12, 34).dx, p(12, 34).dy, p(10, 28).dx, p(10, 28).dy)
            ..cubicTo(p(4, 28).dx, p(4, 28).dy, p(4, 20).dx, p(4, 20).dy, p(8, 16).dx, p(8, 16).dy)
            ..cubicTo(p(6, 8).dx, p(6, 8).dy, p(12, 3).dx, p(12, 3).dy, p(20, 4).dx, p(20, 4).dy)
            ..close()),
          fill(const Color(0xFFA3E635), opacity: 0.9));
      canvas.drawCircle(p(33, 10), s(3), fill(const Color(0xFFA3E635)));
      canvas.drawCircle(p(8, 30), s(2.5), fill(const Color(0xFFA3E635)));
      canvas.drawCircle(p(20, 20), s(4), fill(const Color(0xFFD4F98A)));
      break;

    case 'void':
      final star = Path()
        ..moveTo(p(20, 2).dx, p(20, 2).dy)
        ..lineTo(p(22, 10).dx, p(22, 10).dy)
        ..lineTo(p(28, 6).dx, p(28, 6).dy)
        ..lineTo(p(26, 14).dx, p(26, 14).dy)
        ..lineTo(p(34, 12).dx, p(34, 12).dy)
        ..lineTo(p(30, 20).dx, p(30, 20).dy)
        ..lineTo(p(34, 28).dx, p(34, 28).dy)
        ..lineTo(p(26, 26).dx, p(26, 26).dy)
        ..lineTo(p(28, 34).dx, p(28, 34).dy)
        ..lineTo(p(20, 30).dx, p(20, 30).dy)
        ..lineTo(p(12, 34).dx, p(12, 34).dy)
        ..lineTo(p(14, 26).dx, p(14, 26).dy)
        ..lineTo(p(6, 28).dx, p(6, 28).dy)
        ..lineTo(p(10, 20).dx, p(10, 20).dy)
        ..lineTo(p(6, 12).dx, p(6, 12).dy)
        ..lineTo(p(14, 14).dx, p(14, 14).dy)
        ..close();
      canvas.drawPath(star, strokeP(const Color(0xFF4B72A8), 1.4, opacity: 0.42));
      canvas.drawOval(Rect.fromCenter(center: p(20, 20), width: s(26), height: s(12.4)),
          strokeP(const Color(0xFF4B72A8), 2.6, opacity: 0.88));
      canvas.drawCircle(p(20, 20), s(6.8), fill(const Color(0xFF0B0F1C)));
      canvas.drawCircle(p(20, 20), s(6.8), strokeP(const Color(0xFF2A0A2A), 1.2));
      canvas.drawCircle(p(20, 20), s(2.1), fill(const Color(0xFFFBCFE8)));
      break;

    case 'mk1':
    default:
      canvas.drawRect(Rect.fromLTWH(p(3, 3).dx, p(3, 3).dy, s(34), s(34)),
          fill(const Color(0xFF101820), opacity: 0.55));
      canvas.drawLine(p(8, 8), p(32, 32), strokeP(const Color(0xFFE63946), 5, cap: StrokeCap.round));
      canvas.drawLine(p(32, 8), p(8, 32), strokeP(const Color(0xFFE63946), 5, cap: StrokeCap.round));
      canvas.drawCircle(p(20, 20), s(3), fill(Colors.white));
      break;
  }
}

/// The whiffed-cell marker for a legacy cannon's shot, ported from
/// `uploads/New Design/Miss/miss-*.svg`. Deliberately quieter than the
/// hit glyph for every skin — a faint ripple, ember, or dashed ring
/// rather than a real impact.
void paintLegacyMiss(Canvas canvas, Offset center, double cell, String cannonId) {
  final scale = cell / 40;
  Offset p(double x, double y) => center + Offset(x - 20, y - 20) * scale;
  double s(double len) => len * scale;
  Paint fill(Color c, {double opacity = 1}) => Paint()..color = c.withValues(alpha: opacity);
  Paint strokeP(Color c, double w, {double opacity = 1, StrokeCap cap = StrokeCap.butt}) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = s(w)
    ..strokeCap = cap
    ..color = c.withValues(alpha: opacity);

  switch (cannonId) {
    case 'inferno':
      canvas.drawCircle(p(20, 20), s(10), strokeP(const Color(0xFFC7B4A8), 2.6, opacity: 0.95));
      canvas.drawCircle(p(20, 20), s(4.5), fill(const Color(0xFF6E5348), opacity: 0.85));
      break;
    case 'kraken':
      canvas.drawCircle(p(20, 24), s(6.2), fill(const Color(0xFF5FB5A4), opacity: 0.60));
      canvas.drawCircle(p(20, 24), s(2.3), fill(const Color(0xFFB6FFF1), opacity: 0.90));
      canvas.drawCircle(p(16, 15.5), s(2), strokeP(const Color(0xFF34D399), 1.3, opacity: 0.95));
      break;
    case 'phantom':
      canvas.save();
      canvas.translate(p(20, 20).dx, p(20, 20).dy);
      canvas.rotate(math.pi / 4);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: s(20), height: s(20)),
          strokeP(const Color(0xFFB3A6E8), 2.5, opacity: 0.95));
      canvas.restore();
      break;
    case 'royal':
      canvas.drawCircle(p(20, 20), s(9),
          strokeP(const Color(0xFFFBBF24), 1.7, opacity: 0.90)..strokeCap = StrokeCap.round);
      canvas.drawCircle(p(20, 20), s(3), fill(const Color(0xFFFBBF24)));
      break;
    case 'sunfire':
      canvas.drawCircle(p(20, 20), s(8), fill(const Color(0xFFE0715A), opacity: 0.45));
      canvas.drawCircle(p(20, 20), s(8), strokeP(const Color(0xFFFFA98F), 1.6, opacity: 0.95));
      break;
    case 'tesla':
      canvas.drawCircle(p(20, 20), s(11), strokeP(const Color(0xFFBEE6F7), 2, opacity: 0.95));
      break;
    case 'venom':
      canvas.drawCircle(p(20, 20), s(8), fill(const Color(0xFFA3E635), opacity: 0.50));
      canvas.drawCircle(p(26, 14), s(3), fill(const Color(0xFFD4F98A), opacity: 0.95));
      break;
    case 'void':
      canvas.drawOval(Rect.fromCenter(center: p(20, 20), width: s(17), height: s(8.4)),
          strokeP(const Color(0xFFB78FD6), 1.7, opacity: 0.90));
      canvas.drawCircle(p(20, 20), s(1.9), fill(const Color(0xFFFBCFE8), opacity: 0.95));
      break;
    case 'mk1':
    default:
      canvas.drawCircle(p(20, 20), s(10), strokeP(const Color(0xFFEAF2F8), 3, opacity: 0.95));
      canvas.drawCircle(p(20, 20), s(3), fill(const Color(0xFFEAF2F8), opacity: 0.80));
      break;
  }
}
