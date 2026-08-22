import 'package:flutter/material.dart';

import 'fleet_family.dart' show ShellPalette;
import 'svg_path.dart';

/// The nine original cannons' projectiles.
///
/// Before this, the "nine original guns" (`Catalog.cannonSkins` entries
/// with no `familyKey`) were nine barrel recolours that all fired the
/// same flat iron ball — so "Blazing fire shells", "Electric plasma
/// bolts" and "Dark-matter launcher" were just sentences on a card,
/// never anything the card actually showed. The six thematic families
/// solved exactly this problem for themselves (`family_shell_art.dart`);
/// this file does the same job for the originals, one shell per gun,
/// keyed off the cannon's own catalogue id rather than a `FleetFamily` —
/// the legacy nine were never given one and don't need one just to earn
/// a shell.
///
/// Authored in the same 120×132 box `family_shell_art.dart` uses, so a
/// legacy shell sits at the same size and weight as a family one wherever
/// the two might appear side by side (the CANNONS tab shows both).
const Rect _shellBox = Rect.fromLTWH(0, 0, 120, 132);

/// One palette per original cannon, in catalogue order. Reuses
/// [ShellPalette] rather than inventing a parallel type — a shell's
/// colours are a shell's colours whether the gun that fires it belongs
/// to a family or not.
const Map<String, ShellPalette> _legacyShellPalettes = {
  'mk1': ShellPalette(
    hull: Color(0xFF4B5563),
    trim: Color(0xFF9CA3AF),
    ink: Color(0xFF1B2027),
    glow: Color(0xFFE5E9EE),
    inkW: 3,
  ),
  'inferno': ShellPalette(
    hull: Color(0xFF7C2D12),
    trim: Color(0xFFEF4444),
    ink: Color(0xFF3A1206),
    glow: Color(0xFFFFD54A),
    inkW: 3,
  ),
  'tesla': ShellPalette(
    hull: Color(0xFF0E7490),
    trim: Color(0xFF22D3EE),
    ink: Color(0xFF0B2530),
    glow: Color(0xFFE0FBFF),
    inkW: 3,
  ),
  'venom': ShellPalette(
    hull: Color(0xFF365314),
    trim: Color(0xFF84CC16),
    ink: Color(0xFF1A2A0A),
    glow: Color(0xFFD4F98A),
    inkW: 3,
  ),
  'royal': ShellPalette(
    hull: Color(0xFF92400E),
    trim: Color(0xFFFBBF24),
    ink: Color(0xFF3A2408),
    glow: Color(0xFFFFF3C4),
    inkW: 3,
  ),
  'phantom': ShellPalette(
    hull: Color(0xFF312E81),
    trim: Color(0xFFC084FC),
    ink: Color(0xFF181433),
    glow: Color(0xFFF1E3FF),
    inkW: 2.5,
  ),
  'kraken': ShellPalette(
    hull: Color(0xFF0F766E),
    trim: Color(0xFF5EEAD4),
    ink: Color(0xFF072E2A),
    glow: Color(0xFFB6FFF1),
    inkW: 3,
  ),
  'sunfire': ShellPalette(
    hull: Color(0xFFB45309),
    trim: Color(0xFFFDE047),
    ink: Color(0xFF432B03),
    glow: Color(0xFFFFF8D6),
    inkW: 3,
  ),
  'void': ShellPalette(
    hull: Color(0xFF111827),
    trim: Color(0xFFEC4899),
    ink: Color(0xFF000000),
    glow: Color(0xFFFBCFE8),
    inkW: 2.5,
  ),
};

/// The palette a given original cannon's shell (and, per
/// `cannon_widget.dart`, its muzzle exhaust) is drawn in. Exposed
/// separately from [paintLegacyShell] since the exhaust needs the raw
/// colours, not a finished drawing.
ShellPalette legacyShellPalette(String cannonId) =>
    _legacyShellPalettes[cannonId] ?? _legacyShellPalettes['mk1']!;

/// Paints the projectile the original cannon [cannonId] fires. Unknown
/// ids (there shouldn't be any — every non-family `CannonSkin` in the
/// catalogue has an entry above) fall back to the MK-I's plain shot
/// rather than drawing nothing.
void paintLegacyShell(Canvas canvas, Size size, String cannonId) {
  final p = legacyShellPalette(cannonId);
  final c = FamilyCanvas.fit(canvas, size, _shellBox);
  switch (cannonId) {
    case 'inferno':
      _fireball(c, p);
      break;
    case 'tesla':
      _plasmaOrb(c, p);
      break;
    case 'venom':
      _toxicWarhead(c, p);
      break;
    case 'royal':
      _giltShot(c, p);
      break;
    case 'phantom':
      _railSlug(c, p);
      break;
    case 'kraken':
      _krakenShell(c, p);
      break;
    case 'sunfire':
      _sunfireOrb(c, p);
      break;
    case 'void':
      _voidOrb(c, p);
      break;
    case 'mk1':
    default:
      _ironShot(c, p);
  }
}

// MK-I Standard — plain, unadorned iron shot. Round and machined rather
// than cast-and-sprued (that's the pirate family's Round Shot, a
// different gun with a different story): a crisp equatorial seam and
// four flush rivets instead of an off-round hand-cast surface.
void _ironShot(FamilyCanvas c, ShellPalette p) {
  c.circle(60, 64, 40, fillColor: p.hull, inkColor: p.ink, inkWidth: p.inkW);
  c.line(24, 64, 96, 64, p.trim, 2, opacity: 0.35);
  for (final dx in [-30.0, -10.0, 10.0, 30.0]) {
    c.circle(60 + dx, 64, 2.4, fillColor: p.trim, fillOpacity: 0.55);
  }
  c.ellipse(60, 100, 26, 6, inkColor: p.ink, inkWidth: 2.5, inkOpacity: 0.4);
  c.rotated(-28, 46, 44, () {
    c.ellipse(46, 44, 11, 8, fillColor: Colors.white, fillOpacity: 0.4);
  });
}

// Inferno Cannon — a burning shell: three flame tongues licking up off a
// white-hot core, embers trailing below.
void _fireball(FamilyCanvas c, ShellPalette p) {
  c.shape('M44,52 C36,40 34,24 44,8 C42,26 50,34 50,48 Z',
      fillColor: p.trim, inkColor: p.ink, inkWidth: 2, inkOpacity: 0.4);
  c.shape('M60,50 C56,32 60,14 60,2 C66,16 68,34 62,50 Z',
      fillColor: p.trim, inkColor: p.ink, inkWidth: 2, inkOpacity: 0.4);
  c.shape('M76,52 C82,38 86,22 78,8 C78,26 70,34 70,48 Z',
      fillColor: p.trim, inkColor: p.ink, inkWidth: 2, inkOpacity: 0.4);
  c.circle(60, 68, 34, fillColor: p.hull, inkColor: p.ink, inkWidth: p.inkW);
  c.circle(60, 68, 23, fillColor: p.trim, fillOpacity: 0.85);
  c.circle(60, 68, 13, fillColor: p.glow);
  c.circle(60, 68, 6, fillColor: const Color(0xFFFFF3D0));
  c.circle(30, 106, 4, fillColor: p.glow, fillOpacity: 0.85);
  c.circle(90, 110, 3, fillColor: p.glow, fillOpacity: 0.7);
  c.circle(60, 122, 3.5, fillColor: p.trim, fillOpacity: 0.6);
}

// Tesla Coilgun — a charged orb, dashed field ring, jagged arcs crossing
// the surface and forked bolts kicking off it.
void _plasmaOrb(FamilyCanvas c, ShellPalette p) {
  c.circle(60, 62, 38, fillColor: p.hull, inkColor: p.ink, inkWidth: p.inkW);
  c.circle(60, 62, 38,
      inkColor: p.trim, inkWidth: 2.5, inkOpacity: 0.5, dash: const [8, 6]);
  c.circle(60, 62, 16, fillColor: p.glow, fillOpacity: 0.9);
  c.circle(60, 62, 7, fillColor: Colors.white, fillOpacity: 0.9);
  c.stroke('M30,44 L48,58 L38,64 L66,86', p.glow, 3, cap: StrokeCap.round);
  c.stroke('M92,50 L72,60 L84,68 L54,42', p.glow, 3, cap: StrokeCap.round);
  c.line(60, 24, 52, 8, p.trim, 3, opacity: 0.75, cap: StrokeCap.round);
  c.line(60, 24, 68, 6, p.trim, 3, opacity: 0.75, cap: StrokeCap.round);
  c.line(96, 74, 112, 84, p.trim, 3, opacity: 0.6, cap: StrokeCap.round);
  c.line(24, 78, 8, 86, p.trim, 3, opacity: 0.6, cap: StrokeCap.round);
}

// Venom Launcher — a squat warhead drum with a domed cap, three hazard
// spikes fanning off the top, and toxin dripping from the base.
void _toxicWarhead(FamilyCanvas c, ShellPalette p) {
  c.shape('M28,44 C28,20 92,20 92,44 Z',
      fillColor: p.hull, inkColor: p.ink, inkWidth: p.inkW);
  c.rect(28, 40, 64, 62,
      r: 14, fillColor: p.hull, inkColor: p.ink, inkWidth: p.inkW);
  c.rect(28, 56, 64, 10, fillColor: p.trim, fillOpacity: 0.85);
  c.rect(28, 78, 64, 10, fillColor: p.trim, fillOpacity: 0.85);
  c.rotated(-24, 40, 22, () {
    c.rect(36, 8, 8, 20, r: 3, fillColor: p.glow);
  });
  c.rotated(24, 80, 22, () {
    c.rect(76, 8, 8, 20, r: 3, fillColor: p.glow);
  });
  c.rect(56, 4, 8, 22, r: 3, fillColor: p.glow);
  c.shape('M36,102 C36,112 30,118 30,124 C30,116 42,116 36,102 Z',
      fillColor: p.glow, fillOpacity: 0.85);
  c.shape('M84,102 C84,110 90,114 88,122 C88,114 78,114 84,102 Z',
      fillColor: p.glow, fillOpacity: 0.85);
  c.circle(60, 66, 6, fillColor: p.glow);
}

// Royal Broadside — a gilded round shot: a filigree band studded with
// gems around the equator and a small crown point on top.
void _giltShot(FamilyCanvas c, ShellPalette p) {
  c.circle(60, 66, 40, fillColor: p.hull, inkColor: p.ink, inkWidth: p.inkW);
  c.ellipse(60, 66, 40, 13, inkColor: p.trim, inkWidth: 4);
  c.ellipse(60, 66, 40, 13, inkColor: p.glow, inkWidth: 1.4, inkOpacity: 0.8);
  for (final o in [
    [-38.0, 0.0],
    [-22.0, 10.0],
    [0.0, 13.0],
    [22.0, 10.0],
    [38.0, 0.0],
  ]) {
    c.circle(60 + o[0], 66 + o[1], 3, fillColor: p.trim);
  }
  c.shape('M52,28 L60,8 L68,28 Z',
      fillColor: p.trim, inkColor: p.ink, inkWidth: 2);
  c.circle(60, 8, 4, fillColor: p.glow);
  c.rotated(-20, 42, 48, () {
    c.ellipse(42, 48, 11, 7, fillColor: Colors.white, fillOpacity: 0.45);
  });
}

// Phantom Railgun — a slender energy-wrapped slug: an ogive dart with
// glowing field rings racing up the shaft instead of mechanical drive
// bands, and thin angular tail fins.
void _railSlug(FamilyCanvas c, ShellPalette p) {
  c.shape(
      'M60,6 C68,20 72,34 72,52 L72,100 L48,100 L48,52 '
      'C48,34 52,20 60,6 Z',
      fillColor: p.hull, inkColor: p.ink, inkWidth: p.inkW);
  c.rect(46, 54, 28, 7, fillColor: p.trim, fillOpacity: 0.85);
  c.rect(46, 74, 28, 7, fillColor: p.trim, fillOpacity: 0.85);
  c.shape('M48,100 L34,124 L48,112 Z',
      fillColor: p.hull, inkColor: p.ink, inkWidth: p.inkW);
  c.shape('M72,100 L86,124 L72,112 Z',
      fillColor: p.hull, inkColor: p.ink, inkWidth: p.inkW);
  c.ellipse(60, 40, 16, 5, inkColor: p.glow, inkWidth: 2.5, inkOpacity: 0.85);
  c.ellipse(60, 66, 20, 6, inkColor: p.glow, inkWidth: 2, inkOpacity: 0.6);
  c.circle(60, 16, 5, fillColor: p.glow);
}

// Kraken Cannon — a barnacle-studded shot trailing curling tendrils,
// each tipped with a bioluminescent glow.
void _krakenShell(FamilyCanvas c, ShellPalette p) {
  c.circle(60, 64, 36, fillColor: p.hull, inkColor: p.ink, inkWidth: p.inkW);
  for (final o in [
    [-24.0, -10.0],
    [18.0, -22.0],
    [-8.0, 22.0],
    [26.0, 12.0],
  ]) {
    c.circle(60 + o[0], 64 + o[1], 5,
        fillColor: p.trim, inkColor: p.ink, inkWidth: 1.6);
  }
  c.stroke('M24,64 C10,54 8,36 20,24', p.trim, 4, cap: StrokeCap.round);
  c.stroke('M96,64 C110,54 112,36 100,24', p.trim, 4, cap: StrokeCap.round);
  c.stroke('M60,100 C50,112 52,124 62,130', p.trim, 4, cap: StrokeCap.round);
  c.circle(20, 24, 3, fillColor: p.glow);
  c.circle(100, 24, 3, fillColor: p.glow);
  c.circle(62, 130, 3, fillColor: p.glow);
  c.circle(48, 54, 3, fillColor: p.glow, fillOpacity: 0.85);
  c.circle(74, 74, 3, fillColor: p.glow, fillOpacity: 0.85);
}

// Sunfire Battery — a small sun: eight rays fanning out of a glowing
// core.
void _sunfireOrb(FamilyCanvas c, ShellPalette p) {
  for (var i = 0; i < 8; i++) {
    c.rotated(i * 45.0, 60, 64, () {
      c.shape('M60,64 L54,20 L60,4 L66,20 Z',
          fillColor: p.trim, fillOpacity: 0.9);
    });
  }
  c.circle(60, 64, 28, fillColor: p.hull, inkColor: p.ink, inkWidth: p.inkW);
  c.circle(60, 64, 20, fillColor: p.glow, fillOpacity: 0.9);
  c.circle(60, 64, 10, fillColor: Colors.white, fillOpacity: 0.85);
}

// Void Annihilator — a dark core ringed by a warped, glowing horizon,
// with stray matter arcing in toward it.
void _voidOrb(FamilyCanvas c, ShellPalette p) {
  c.ellipse(60, 64, 46, 18, inkColor: p.trim, inkWidth: 4, inkOpacity: 0.85);
  c.ellipse(60, 64, 46, 18, inkColor: p.glow, inkWidth: 1.4, inkOpacity: 0.6);
  c.circle(60, 64, 30, fillColor: p.hull, inkColor: p.ink, inkWidth: p.inkW);
  c.circle(60, 64, 30, fillColor: Colors.black, fillOpacity: 0.35);
  c.stroke('M18,50 C30,58 30,70 18,78', p.trim, 2.5,
      opacity: 0.7, cap: StrokeCap.round);
  c.stroke('M102,50 C90,58 90,70 102,78', p.trim, 2.5,
      opacity: 0.7, cap: StrokeCap.round);
  c.circle(14, 40, 2, fillColor: p.glow, fillOpacity: 0.8);
  c.circle(108, 88, 2, fillColor: p.glow, fillOpacity: 0.7);
  c.circle(60, 12, 2.2, fillColor: p.glow, fillOpacity: 0.6);
}
