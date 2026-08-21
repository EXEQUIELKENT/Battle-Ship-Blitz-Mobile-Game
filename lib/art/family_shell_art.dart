import 'package:flutter/material.dart';

import 'fleet_family.dart';
import 'svg_path.dart';

/// The six projectiles, ported from `ThemedShell.dc.html`.
///
/// A shell belongs to its cannon, not to the board: equipping the Ion
/// Lance means plasma bolts fly, whatever hulls or water are in play. The
/// design pairs them explicitly ("the shell sits on the disc beside its
/// gun, so the pairing is visible before purchase"), so both are keyed off
/// the same family and there is no way to end up firing round shot out of
/// a railgun.
///
/// Authored in a 120×132 box — taller than wide, because several of them
/// trail something below the body (naval fins, sci-fi energy tail,
/// volcanic embers). The extra height is deliberate and is what makes the
/// projectile read as *travelling* rather than just hanging there.
const Rect _shellBox = Rect.fromLTWH(0, 0, 120, 132);

/// Aspect ratio of the authored box (the design's `size * 1.1`).
const double kShellBoxAspect = 120 / 132;

void paintFamilyShell(
  Canvas canvas,
  Size size,
  FleetFamily family, {
  ShellPalette? paletteOverride,
}) {
  final p = paletteOverride ?? family.shell;
  final c = FamilyCanvas.fit(canvas, size, _shellBox);
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

// Round Shot — cast-iron sphere, off-round, casting sprue still attached.
void _pirate(FamilyCanvas c, ShellPalette p) {
  c.shape(
    'M60,16 C84,16 104,36 104,60 C104,86 82,104 60,104 '
    'C36,104 16,84 16,60 C16,34 38,16 60,16 Z',
    fillColor: p.hull,
    inkColor: p.ink,
    inkWidth: p.inkW,
  );
  c.ellipse(60, 60, 43, 12, inkColor: p.ink, inkWidth: 3, inkOpacity: 0.45);
  c.line(38, 40, 46, 46, p.ink, 3.5, opacity: 0.55, cap: StrokeCap.round);
  c.line(76, 76, 84, 70, p.ink, 3.5, opacity: 0.55, cap: StrokeCap.round);
  c.line(44, 80, 52, 74, p.ink, 3.5, opacity: 0.55, cap: StrokeCap.round);
  c.rotated(-28, 45, 41, () {
    c.ellipse(45, 41, 11, 8, fillColor: Colors.white, fillOpacity: 0.4);
  });
  // The sprue.
  c.rect(52, 8, 16, 10,
      r: 3, fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
}

// Sabot Shell — ogive nose, twin drive bands, four tail fins, tracer eye.
void _naval(FamilyCanvas c, ShellPalette p) {
  c.shape('M60,4 C74,18 84,34 84,52 L84,96 L36,96 L36,52 C36,34 46,18 60,4 Z',
      fillColor: p.hull, inkColor: p.ink, inkWidth: p.inkW);
  c.rect(34, 52, 52, 9, fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
  c.rect(34, 72, 52, 9, fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
  c.shape('M36,96 L24,118 L40,110 L44,96 Z',
      fillColor: p.hull, inkColor: p.ink, inkWidth: p.inkW);
  c.shape('M84,96 L96,118 L80,110 L76,96 Z',
      fillColor: p.hull, inkColor: p.ink, inkWidth: p.inkW);
  c.shape('M52,96 L60,122 L68,96 Z',
      fillColor: p.hull, inkColor: p.ink, inkWidth: p.inkW);
  c.line(48, 24, 52, 46, Colors.white, 5, opacity: 0.35, cap: StrokeCap.round);
  c.circle(60, 88, 7, fillColor: p.glow, inkColor: p.ink, inkWidth: 2);
}

// Governor Sphere — toothed gear ring around a riveted core.
void _steam(FamilyCanvas c, ShellPalette p) {
  c.circle(60, 60, 46, inkColor: p.trim, inkWidth: 14, dash: const [9, 12]);
  c.circle(60, 60, 38, fillColor: p.hull, inkColor: p.ink, inkWidth: p.inkW);
  c.circle(60, 60, 38, inkColor: p.trim, inkWidth: 6);
  c.circle(60, 60, 17, fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
  c.circle(60, 60, 7, fillColor: p.glow);
  for (final r in const [
    [60.0, 34.0],
    [60.0, 86.0],
    [34.0, 60.0],
    [86.0, 60.0],
  ]) {
    c.circle(r[0], r[1], 3.6, fillColor: p.ink, fillOpacity: 0.6);
  }
  // Two pressure vents.
  c.rotated(-38, 79, 42, () {
    c.rect(72, 40, 14, 5, r: 2.5, fillColor: p.ink);
  });
  c.rotated(-38, 41, 78, () {
    c.rect(34, 76, 14, 5, r: 2.5, fillColor: p.ink);
  });
  c.rotated(-32, 46, 46, () {
    c.ellipse(46, 46, 9, 6, fillColor: Colors.white, fillOpacity: 0.35);
  });
}

// Rime Shard — faceted hexagonal crystal shedding splinters in flight.
void _arctic(FamilyCanvas c, ShellPalette p) {
  c.shape('M60,6 L98,32 L92,86 L60,116 L28,86 L22,32 Z',
      fillColor: p.hull, inkColor: p.ink, inkWidth: p.inkW);
  c.shape('M60,6 L98,32 L60,54 Z',
      fillColor: p.trim,
      fillOpacity: 0.85,
      inkColor: p.ink,
      inkWidth: 2,
      inkOpacity: 0.5);
  c.shape('M60,54 L92,86 L60,116 Z',
      fillColor: p.trim,
      fillOpacity: 0.85,
      inkColor: p.ink,
      inkWidth: 2,
      inkOpacity: 0.5);
  c.stroke('M60,20 L60,100', p.glow, 3.5, cap: StrokeCap.round);
  c.stroke('M34,40 L60,54 L86,40', p.glow, 3.5, cap: StrokeCap.round);
  c.stroke('M32,76 L60,60 L88,76', p.glow, 3.5, cap: StrokeCap.round);
  // Splinters.
  c.shape('M98,32 L118,24 L100,44 Z',
      fillColor: p.glow, inkColor: p.ink, inkWidth: 2);
  c.shape('M22,32 L2,26 L20,46 Z',
      fillColor: p.glow, inkColor: p.ink, inkWidth: 2);
  c.shape('M60,116 L54,132 L70,130 Z',
      fillColor: p.glow, inkColor: p.ink, inkWidth: 2);
}

// Ember Slug — irregular rock, molten core, trailing ember cluster.
void _volcanic(FamilyCanvas c, ShellPalette p) {
  c.shape('M58,8 L88,18 L106,44 L100,78 L74,104 L40,102 L18,80 L14,44 L32,18 Z',
      fillColor: p.hull, inkColor: p.ink, inkWidth: p.inkW);
  c.shape('M56,26 L74,34 L84,54 L76,74 L54,84 L36,70 L32,48 L40,32 Z',
      fillColor: p.trim, inkColor: p.ink, inkWidth: 2.5, inkOpacity: 0.6);
  c.stroke('M34,22 L48,44 L36,64 L52,84', p.glow, 5, cap: StrokeCap.round);
  c.stroke('M92,30 L74,48 L86,70', p.glow, 5, cap: StrokeCap.round);
  c.stroke('M60,10 L64,32', p.glow, 5, cap: StrokeCap.round);
  c.circle(58, 56, 14, fillColor: p.glow);
  c.circle(58, 56, 7, fillColor: const Color(0xFFFFF3D0));
  c.circle(16, 102, 6, fillColor: p.glow, fillOpacity: 0.9);
  c.circle(102, 98, 4.5, fillColor: p.glow, fillOpacity: 0.8);
  c.circle(60, 118, 5, fillColor: p.glow, fillOpacity: 0.65);
  c.circle(34, 118, 3, fillColor: p.glow, fillOpacity: 0.5);
}

// Plasma Bolt — hex prism, containment core, two field rings, energy tail.
void _scifi(FamilyCanvas c, ShellPalette p) {
  const hex = 'M60,4 L100,28 L100,76 L60,100 L20,76 L20,28 Z';
  c.shape(hex, fillColor: p.hull, inkColor: p.trim, inkWidth: 2.5);
  c.stroke(hex, p.glow, 7, opacity: 0.55);
  c.ellipse(60, 52, 44, 13, inkColor: p.glow, inkWidth: 3.5);
  c.ellipse(60, 52, 30, 30,
      inkColor: p.trim, inkWidth: 3, dash: const [16, 10]);
  c.circle(60, 52, 20, fillColor: p.glow, fillOpacity: 0.35);
  c.circle(60, 52, 12, fillColor: p.glow);
  c.circle(60, 52, 5, fillColor: Colors.white);
  c.line(44, 104, 52, 126, p.glow, 4, cap: StrokeCap.round);
  c.line(60, 104, 60, 132, p.glow, 4, cap: StrokeCap.round);
  c.line(76, 104, 68, 126, p.glow, 4, cap: StrokeCap.round);
}
