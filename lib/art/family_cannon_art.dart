import 'package:flutter/material.dart';

import 'fleet_family.dart';
import 'svg_path.dart';

/// The six family cannons, ported from `ThemedCannon.dc.html`.
///
/// All six are authored in the same `-40 -108 220 216` box, which is what
/// lets a stubby magma mortar and a long naval autoloader drop into the
/// identical mount without the battle screen knowing which is which. The
/// box extends well above the origin because the barrel points *up*: the
/// muzzle sits at negative y, and the mount sits around y≈40.
///
/// The barrel is drawn along the box's vertical centre (x≈70), so
/// `muzzleFraction` in the family registry stays the single source of
/// truth for where a shell is born — the value `battle_screen` already
/// reads to place the cannonball.
const Rect _gunBox = Rect.fromLTWH(-40, -108, 220, 216);

/// Aspect ratio of the authored box, so callers can size a cannon
/// correctly (the design's own `boxW`/`boxH` maths).
const double kGunBoxAspect = 220 / 216;

void paintFamilyCannon(
  Canvas canvas,
  Size size,
  FleetFamily family, {
  GunPalette? paletteOverride,
  bool shadow = true,
}) {
  final p = paletteOverride ?? family.gun;
  final c = FamilyCanvas.fit(canvas, size, _gunBox);
  if (shadow) {
    c.ellipse(70, 70, 74, 30, fillColor: Colors.black, fillOpacity: 0.20);
  }
  switch (family.id) {
    case FleetFamilyId.pirate:
      _pirate(c, p);
      break;
    case FleetFamilyId.naval:
      _naval(c, p);
      break;
    case FleetFamilyId.steam:
      _steam(c, p);
      break;
    case FleetFamilyId.arctic:
      _arctic(c, p);
      break;
    case FleetFamilyId.volcanic:
      _volcanic(c, p);
      break;
    case FleetFamilyId.scifi:
      _scifi(c, p);
      break;
  }
}

// Bell-Mouth Broadside — timber carriage between two spoked wheels.
void _pirate(FamilyCanvas c, GunPalette p) {
  c.shape('M-16,26 L156,26 L142,84 L-2,84 Z',
      fillColor: p.deck, inkColor: p.ink, inkWidth: p.inkW);
  c.rect(8, -6, 124, 40,
      r: 6, fillColor: p.deck, inkColor: p.ink, inkWidth: p.inkW);
  for (final x in const [-8.0, 148.0]) {
    c.circle(x, 62, 34, fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
    c.circle(x, 62, 9, fillColor: p.deck, inkColor: p.ink, inkWidth: p.inkW);
    c.line(x, 28, x, 96, p.ink, 3, opacity: 0.55);
    c.line(x - 34, 62, x + 34, 62, p.ink, 3, opacity: 0.55);
  }
  c.circle(70, 34, 62, fillColor: p.hull, inkColor: p.ink, inkWidth: p.inkW);
  c.circle(70, 34, 46,
      fillColor: p.trim, inkColor: p.ink, inkWidth: 3, inkOpacity: 0.5);
  c.shape('M40,30 L100,30 L92,-58 L48,-58 Z',
      fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
  // The bell.
  c.shape('M46,-58 L94,-58 L104,-84 L36,-84 Z',
      fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
  c.rect(42, -16, 56, 12,
      r: 4, fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
  c.rect(44, -44, 52, 11,
      r: 4, fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
  c.ellipse(70, -84, 34, 11, fillColor: p.ink);
  c.ellipse(70, -86, 24, 7, fillColor: const Color(0xFF0B0906));
  c.stroke('M52,-26 q18,-8 36,0', p.glow, 4,
      opacity: 0.45, cap: StrokeCap.round);
  c.circle(16, 6, 13, inkColor: p.trim, inkWidth: 7);
  c.circle(124, 6, 13, inkColor: p.trim, inkWidth: 7);
}

// MK-IV Autoloader — long thin barrel, slotted muzzle brake.
void _naval(FamilyCanvas c, GunPalette p) {
  c.shape('M-14,34 L28,12 L112,12 L154,34 L154,74 L112,92 L28,92 L-14,74 Z',
      fillColor: p.deck, inkColor: p.ink, inkWidth: p.inkW);
  for (final b in const [
    [4.0, 28.0],
    [4.0, 80.0],
    [136.0, 28.0],
    [136.0, 80.0],
    [70.0, 86.0],
  ]) {
    c.circle(b[0], b[1], 4, fillColor: p.ink, fillOpacity: 0.5);
  }
  c.circle(70, 40, 60, fillColor: p.hull, inkColor: p.ink, inkWidth: p.inkW);
  c.shape('M14,22 L126,22 L112,-6 L28,-6 Z',
      fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
  c.circle(70, 40, 40,
      fillColor: p.trim,
      fillOpacity: 0.55,
      inkColor: p.ink,
      inkWidth: 2,
      inkOpacity: 0.4);
  c.shape('M54,24 L86,24 L82,-70 L58,-70 Z',
      fillColor: p.hull, inkColor: p.ink, inkWidth: p.inkW);
  c.rect(48, -6, 44, 10, fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
  c.rect(50, -40, 40, 9, fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
  // Muzzle brake.
  c.shape('M56,-70 L84,-70 L86,-96 L54,-96 Z',
      fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
  c.line(54, -80, 86, -80, p.ink, p.inkW);
  c.line(55, -89, 85, -89, p.ink, p.inkW);
  c.rect(60, -99, 20, 8, r: 2, fillColor: p.ink);
  c.line(70, -8, 70, -66, p.glow, 4, opacity: 0.35);
}

// Pressure Battery — three boiler drums, bypass pipe, live gauge.
void _steam(FamilyCanvas c, GunPalette p) {
  c.rect(-16, 20, 172, 62,
      r: 10, fillColor: p.deck, inkColor: p.ink, inkWidth: p.inkW);
  for (final x in const [-4.0, 144.0]) {
    c.circle(x, 30, 26, fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
    c.line(x, 6, x, 54, p.ink, 3.5, opacity: 0.6);
    c.line(x - 24, 30, x + 24, 30, p.ink, 3.5, opacity: 0.6);
    c.line(x - 17, 13, x + 17, 47, p.ink, 3.5, opacity: 0.6);
    c.line(x - 17, 47, x + 17, 13, p.ink, 3.5, opacity: 0.6);
  }
  c.circle(70, 36, 58, fillColor: p.hull, inkColor: p.ink, inkWidth: p.inkW);
  c.circle(70, 36, 42,
      fillColor: p.trim, inkColor: p.ink, inkWidth: 3, inkOpacity: 0.45);
  // Three stacked drums instead of one taper.
  c.rect(42, -18, 56, 48,
      r: 8, fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
  c.rect(46, -52, 48, 38,
      r: 6, fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
  c.rect(50, -82, 40, 32,
      r: 5, fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
  c.shape('M44,-82 L96,-82 L104,-96 L36,-96 Z',
      fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
  for (final r in const [
    [48.0, -12.0],
    [92.0, -12.0],
    [52.0, -46.0],
    [88.0, -46.0],
    [56.0, -76.0],
    [84.0, -76.0],
  ]) {
    c.circle(r[0], r[1], 3.4, fillColor: p.ink, fillOpacity: 0.55);
  }
  // Bypass pipe.
  c.stroke('M100,20 q30,-6 26,-40 q-3,-30 -22,-44', p.trim, 10,
      cap: StrokeCap.round);
  c.stroke('M100,20 q30,-6 26,-40 q-3,-30 -22,-44', p.ink, 2, opacity: 0.5);
  c.ellipse(70, -96, 34, 10, fillColor: p.ink);
  c.ellipse(70, -98, 23, 6, fillColor: const Color(0xFF0C0805));
  // The gauge — the needle leads the shot.
  c.circle(26, -4, 17, fillColor: p.glow, inkColor: p.ink, inkWidth: p.inkW);
  c.line(26, -4, 26, -15, p.ink, 3, cap: StrokeCap.round);
  c.line(26, -4, 35, 1, p.ink, 3, cap: StrokeCap.round);
}

// Icebreaker Mortar — stubby two-stage barrel behind a crystal collar.
void _arctic(FamilyCanvas c, GunPalette p) {
  c.shape('M-18,40 L18,18 L122,18 L158,40 L150,86 L-10,86 Z',
      fillColor: p.deck, inkColor: p.ink, inkWidth: p.inkW);
  for (final s in const [
    'M-18,40 L4,4 L26,40 Z',
    'M114,40 L136,2 L158,40 Z',
    'M24,54 L40,26 L56,54 Z',
    'M84,54 L100,28 L116,54 Z',
  ]) {
    c.shape(s, fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
  }
  c.circle(70, 42, 58, fillColor: p.hull, inkColor: p.ink, inkWidth: p.inkW);
  c.circle(70, 42, 41,
      fillColor: p.trim, inkColor: p.ink, inkWidth: 3, inkOpacity: 0.4);
  c.shape('M40,26 L100,26 L94,-30 L46,-30 Z',
      fillColor: p.hull, inkColor: p.ink, inkWidth: p.inkW);
  c.shape('M46,-30 L94,-30 L88,-62 L52,-62 Z',
      fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
  for (final s in const [
    'M38,-6 L46,-22 L52,-2 Z',
    'M102,-6 L94,-24 L88,-4 Z',
    'M52,-62 L60,-88 L68,-62 Z',
    'M72,-62 L80,-82 L88,-62 Z',
  ]) {
    c.shape(s, fillColor: p.glow, inkColor: p.ink, inkWidth: 2.5);
  }
  c.ellipse(70, -62, 20, 8, fillColor: p.ink);
  c.ellipse(70, -64, 13, 5, fillColor: const Color(0xFF0E1A22));
  c.fill('M22,20 q14,-9 28,-2 q-14,5 -28,2 Z', Colors.white, opacity: 0.85);
  c.fill('M92,18 q14,-8 26,0 q-13,5 -26,0 Z', Colors.white, opacity: 0.85);
}

// Magma Bombard — wide short mortar on a rock-slab collar.
void _volcanic(FamilyCanvas c, GunPalette p) {
  c.shape(
      'M-22,44 L-4,14 L44,26 L100,10 L150,32 L162,66 '
      'L128,90 L58,82 L6,92 L-16,70 Z',
      fillColor: p.deck,
      inkColor: p.ink,
      inkWidth: p.inkW);
  c.stroke('M-6,30 L14,52 L4,72', p.glow, 3.5, cap: StrokeCap.round);
  c.stroke('M140,36 L124,58 L136,80', p.glow, 3.5, cap: StrokeCap.round);
  c.stroke('M56,80 L74,90', p.glow, 3.5, cap: StrokeCap.round);
  c.circle(70, 40, 62, fillColor: p.hull, inkColor: p.ink, inkWidth: p.inkW);
  c.shape('M70,-20 L18,14 L14,54 L44,88 L96,88 L126,54 L122,14 Z',
      fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
  c.stroke('M40,66 L58,44 L52,26', p.glow, 4, cap: StrokeCap.round);
  c.stroke('M98,64 L84,46 L92,28', p.glow, 4, cap: StrokeCap.round);
  c.shape('M34,22 L106,22 L96,-42 L44,-42 Z',
      fillColor: p.hull, inkColor: p.ink, inkWidth: p.inkW);
  c.shape('M44,-42 L96,-42 L112,-78 L28,-78 Z',
      fillColor: p.hull, inkColor: p.ink, inkWidth: p.inkW);
  // Molten seams running the length of the body.
  c.stroke('M52,16 L64,-14 L58,-38', p.glow, 5, cap: StrokeCap.round);
  c.stroke('M88,14 L78,-16 L86,-40', p.glow, 5, cap: StrokeCap.round);
  c.stroke('M62,-52 L70,-70', p.glow, 5, cap: StrokeCap.round);
  c.ellipse(70, -78, 42, 13, fillColor: p.ink);
  c.ellipse(70, -80, 31, 9, fillColor: p.glow, fillOpacity: 0.9);
  c.ellipse(70, -81, 17, 5, fillColor: const Color(0xFFFFF0C8));
}

// Ion Lance — three detached segments, forked emitter, core in the ring.
void _scifi(FamilyCanvas c, GunPalette p) {
  c.shape('M-20,52 L20,24 L120,24 L160,52 L120,80 L20,80 Z',
      fillColor: p.deck, inkColor: p.trim, inkWidth: 2.5);
  c.stroke('M-12,52 L16,32', p.glow, 2.5, cap: StrokeCap.round);
  c.stroke('M152,52 L124,32', p.glow, 2.5, cap: StrokeCap.round);
  c.stroke('M-12,52 L16,72', p.glow, 2.5, cap: StrokeCap.round);
  c.stroke('M152,52 L124,72', p.glow, 2.5, cap: StrokeCap.round);
  c.circle(70, 44, 58, fillColor: p.hull, inkColor: p.trim, inkWidth: 2.5);
  c.circle(70, 44, 58, inkColor: p.glow, inkWidth: 6, inkOpacity: 0.5);
  c.shape('M70,4 L104,24 L104,64 L70,84 L36,64 L36,24 Z',
      fillColor: p.deck, inkColor: p.glow, inkWidth: 3);
  c.circle(70, 44, 15, fillColor: p.glow);
  c.circle(70, 44, 7, fillColor: Colors.white);
  // Three barrel segments with visible energy gaps.
  c.shape('M50,10 L90,10 L86,-14 L54,-14 Z',
      fillColor: p.hull, inkColor: p.trim, inkWidth: 2.5);
  c.shape('M52,-26 L88,-26 L84,-52 L56,-52 Z',
      fillColor: p.hull, inkColor: p.trim, inkWidth: 2.5);
  c.shape('M56,-64 L84,-64 L80,-88 L60,-88 Z',
      fillColor: p.hull, inkColor: p.trim, inkWidth: 2.5);
  c.line(70, -14, 70, -26, p.glow, 4, cap: StrokeCap.round);
  c.line(70, -52, 70, -64, p.glow, 4, cap: StrokeCap.round);
  // Forked emitter.
  c.line(60, -88, 52, -104, p.trim, 5, cap: StrokeCap.round);
  c.line(80, -88, 88, -104, p.trim, 5, cap: StrokeCap.round);
  c.circle(70, -94, 9, fillColor: p.glow, fillOpacity: 0.95);
  c.circle(70, -94, 17, fillColor: p.glow, fillOpacity: 0.25);
}
