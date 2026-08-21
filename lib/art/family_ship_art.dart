import 'package:flutter/material.dart';

import '../models/game_models.dart';
import 'fleet_family.dart';
import 'svg_path.dart';

/// The five hull classes for each of the six families.
///
/// Every path string here is copied verbatim from the design source
/// (`ThemedShip.dc.html`), which authors all thirty hulls in one
/// 300×100 box with `preserveAspectRatio="none"` — so the same drawing
/// stretches to a 5-cell carrier or a 2-cell destroyer and the class
/// silhouette survives either way. [FamilyCanvas.stretch] reproduces that
/// exactly, including the non-scaling strokes that keep the ink readable
/// when a ship is drawn at grid size.
///
/// Two rules the design sets and this file follows:
///
///  * **Everything except the submarine sits on a shared family hull.**
///    Submarines draw their own body, because a conning tower on a
///    surface hull would read as a different class, not a different
///    family.
///  * **Class identity is structural.** A pirate carrier is three canvas
///    blocks; a naval one is an angled flight deck with an island; a
///    steam one is two paddle wheels. None of them are the same shape in
///    a different colour, which is the whole point of the system.
const Rect _shipBox = Rect.fromLTWH(0, 0, 300, 100);

void paintFamilyShip(
  Canvas canvas,
  Size size,
  FleetFamily family,
  ShipKind kind, {
  ShipPalette? paletteOverride,
}) {
  final p = paletteOverride ?? family.ship;
  final c = FamilyCanvas.stretch(canvas, size, _shipBox);
  switch (family.id) {
    case FleetFamilyId.pirate:
      _pirate(c, kind, p);
      break;
    case FleetFamilyId.naval:
      _naval(c, kind, p);
      break;
    case FleetFamilyId.steam:
      _steam(c, kind, p);
      break;
    case FleetFamilyId.arctic:
      _arctic(c, kind, p);
      break;
    case FleetFamilyId.volcanic:
      _volcanic(c, kind, p);
      break;
    case FleetFamilyId.scifi:
      _scifi(c, kind, p);
      break;
  }
}

// ============================================================== PIRATE ===
// Wood, rope and bronze. Sail area IS the silhouette.

void _pirate(FamilyCanvas c, ShipKind k, ShipPalette p) {
  if (k != ShipKind.submarine) {
    c.shape(
      'M18,50 C18,28 66,16 146,16 C214,16 268,28 294,50 '
      'C268,72 214,84 146,84 C66,84 18,72 18,50 Z',
      fillColor: p.hull,
      inkColor: p.ink,
      inkWidth: p.inkW,
    );
    c.stroke('M26,36 C90,26 200,26 280,40', p.ink, 2, opacity: 0.35);
    c.stroke('M26,64 C90,74 200,74 280,60', p.ink, 2, opacity: 0.35);
  }

  switch (k) {
    case ShipKind.carrier:
      c.rect(26, 22, 46, 56,
          r: 7, fillColor: p.deck, inkColor: p.ink, inkWidth: p.inkW);
      c.rect(100, 12, 88, 76,
          r: 7, fillColor: p.sail, inkColor: p.ink, inkWidth: p.inkW);
      c.rect(198, 24, 52, 52,
          r: 6, fillColor: p.sail, inkColor: p.ink, inkWidth: p.inkW);
      c.line(100, 38, 188, 38, p.ink, 2.5, opacity: 0.4);
      c.line(100, 62, 188, 62, p.ink, 2.5, opacity: 0.4);
      c.line(198, 50, 250, 50, p.ink, 2.5, opacity: 0.4);
      c.ellipse(108, 50, 7, 7,
          fillColor: p.deck, inkColor: p.ink, inkWidth: p.inkW);
      c.ellipse(196, 50, 6, 6,
          fillColor: p.deck, inkColor: p.ink, inkWidth: p.inkW);
      c.rect(88, 76, 10, 7, r: 2, fillColor: p.ink, fillOpacity: 0.8);
      c.rect(66, 72, 10, 7, r: 2, fillColor: p.ink, fillOpacity: 0.8);
      c.rect(252, 42, 12, 8, r: 2, fillColor: p.ink, fillOpacity: 0.8);
      break;

    case ShipKind.battleship:
      c.rect(28, 26, 40, 48,
          r: 6, fillColor: p.deck, inkColor: p.ink, inkWidth: p.inkW);
      c.rect(104, 16, 78, 68,
          r: 6, fillColor: p.sail, inkColor: p.ink, inkWidth: p.inkW);
      c.line(104, 42, 182, 42, p.ink, 2.5, opacity: 0.4);
      c.line(104, 62, 182, 62, p.ink, 2.5, opacity: 0.4);
      c.ellipse(142, 50, 7, 7,
          fillColor: p.deck, inkColor: p.ink, inkWidth: p.inkW);
      c.shape('M262,42 L292,50 L262,58 Z',
          fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
      c.rect(78, 72, 10, 7, r: 2, fillColor: p.ink, fillOpacity: 0.8);
      c.rect(196, 70, 10, 7, r: 2, fillColor: p.ink, fillOpacity: 0.8);
      c.rect(220, 62, 10, 7, r: 2, fillColor: p.ink, fillOpacity: 0.8);
      c.rect(196, 24, 10, 7, r: 2, fillColor: p.ink, fillOpacity: 0.8);
      break;

    case ShipKind.cruiser:
      c.rect(36, 34, 44, 32,
          r: 6, fillColor: p.deck, inkColor: p.ink, inkWidth: p.inkW);
      c.shape('M112,18 L212,50 L112,82 Z',
          fillColor: p.sail, inkColor: p.ink, inkWidth: p.inkW);
      c.line(112, 18, 112, 82, p.ink, 3, opacity: 0.5);
      c.ellipse(108, 50, 6, 6,
          fillColor: p.deck, inkColor: p.ink, inkWidth: p.inkW);
      c.rect(90, 70, 10, 7, r: 2, fillColor: p.ink, fillOpacity: 0.8);
      c.rect(230, 56, 10, 7, r: 2, fillColor: p.ink, fillOpacity: 0.8);
      break;

    case ShipKind.submarine:
      c.shape(
        'M30,50 C30,34 70,26 150,26 C220,26 262,34 286,50 '
        'C262,66 220,74 150,74 C70,74 30,66 30,50 Z',
        fillColor: p.hull,
        inkColor: p.ink,
        inkWidth: p.inkW,
      );
      c.rect(116, 28, 72, 44,
          r: 20, fillColor: p.sail, inkColor: p.ink, inkWidth: p.inkW);
      c.line(60, 34, 60, 66, p.ink, 2.5, opacity: 0.45);
      c.line(84, 30, 84, 70, p.ink, 2.5, opacity: 0.45);
      c.line(212, 32, 212, 68, p.ink, 2.5, opacity: 0.45);
      c.line(240, 36, 240, 64, p.ink, 2.5, opacity: 0.45);
      c.rect(98, 18, 12, 30,
          r: 4, fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
      c.ellipse(152, 50, 9, 9, fillColor: p.ink, fillOpacity: 0.75);
      break;

    case ShipKind.destroyer:
      c.rect(96, 22, 80, 56,
          r: 6, fillColor: p.sail, inkColor: p.ink, inkWidth: p.inkW);
      c.line(96, 50, 176, 50, p.ink, 2.5, opacity: 0.4);
      c.ellipse(128, 50, 7, 7,
          fillColor: p.deck, inkColor: p.ink, inkWidth: p.inkW);
      c.rect(212, 34, 34, 26, r: 3, fillColor: p.ink);
      c.circle(224, 44, 3.4, fillColor: p.sail);
      c.circle(236, 44, 3.4, fillColor: p.sail);
      c.rect(224, 50, 12, 4, r: 1.5, fillColor: p.sail);
      c.rect(46, 38, 30, 24,
          r: 5, fillColor: p.deck, inkColor: p.ink, inkWidth: p.inkW);
      break;
  }
}

// =============================================================== NAVAL ===
// Modern steel. Faceted, bolted, symmetrical — mitred joins, no rounding.

void _naval(FamilyCanvas c, ShipKind k, ShipPalette p) {
  if (k != ShipKind.submarine) {
    c.shape('M14,30 L44,20 L232,20 L296,50 L232,80 L44,80 L14,70 Z',
        fillColor: p.hull,
        inkColor: p.ink,
        inkWidth: p.inkW,
        join: StrokeJoin.miter);
  }

  switch (k) {
    case ShipKind.carrier:
      c.rect(22, 26, 248, 46,
          fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
      c.strokeDashed('M30,68 L250,32', p.deck, 7, const [14, 10]);
      c.rect(58, 8, 46, 22,
          fillColor: p.deck, inkColor: p.ink, inkWidth: p.inkW);
      c.line(68, 8, 68, -6, p.ink, p.inkW);
      c.ellipse(88, 4, 9, 4,
          fillColor: p.deck, inkColor: p.ink, inkWidth: 2);
      c.fill('M140,36 L152,46 L140,56 Z', p.ink, opacity: 0.75);
      c.fill('M170,34 L182,44 L170,54 Z', p.ink, opacity: 0.75);
      c.fill('M200,40 L212,50 L200,60 Z', p.ink, opacity: 0.75);
      c.fill('M230,44 L242,54 L230,64 Z', p.ink, opacity: 0.75);
      break;

    case ShipKind.battleship:
      c.rect(36, 32, 46, 36,
          r: 5, fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
      c.rect(196, 32, 46, 36,
          r: 5, fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
      c.rect(146, 22, 44, 56,
          r: 4, fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
      // Triple turrets fore and aft — the class marker for this family.
      for (final l in const [
        [36.0, 40.0, 8.0, 40.0],
        [36.0, 50.0, 6.0, 50.0],
        [36.0, 60.0, 8.0, 60.0],
        [242.0, 42.0, 276.0, 42.0],
        [242.0, 50.0, 280.0, 50.0],
        [242.0, 58.0, 276.0, 58.0],
      ]) {
        c.line(l[0], l[1], l[2], l[3], p.ink, 4, cap: StrokeCap.round);
      }
      c.rect(100, 34, 34, 32,
          r: 3, fillColor: p.deck, inkColor: p.ink, inkWidth: p.inkW);
      c.line(117, 34, 117, 6, p.ink, 3.5);
      c.line(106, 14, 128, 14, p.ink, 3);
      break;

    case ShipKind.cruiser:
      c.rect(38, 34, 42, 32,
          r: 5, fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
      c.rect(196, 36, 38, 28,
          r: 4, fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
      c.rect(116, 24, 46, 52,
          fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
      c.line(38, 44, 12, 44, p.ink, 4, cap: StrokeCap.round);
      c.line(38, 56, 12, 56, p.ink, 4, cap: StrokeCap.round);
      c.line(234, 50, 266, 50, p.ink, 4, cap: StrokeCap.round);
      // Phased array panel.
      c.shape('M120,24 L158,28 L158,48 L120,44 Z',
          fillColor: p.deck, inkColor: p.ink, inkWidth: 2.5);
      // VLS block.
      for (final cell in const [
        [90.0, 34.0],
        [102.0, 34.0],
        [90.0, 46.0],
        [102.0, 46.0],
        [90.0, 58.0],
        [102.0, 58.0],
        [170.0, 58.0],
        [182.0, 58.0],
      ]) {
        c.rect(cell[0], cell[1], 9, 9,
            fillColor: p.deck, inkColor: p.ink, inkWidth: 2);
      }
      break;

    case ShipKind.submarine:
      c.shape(
        'M22,50 C22,32 60,26 140,26 C220,26 268,34 292,50 '
        'C268,66 220,74 140,74 C60,74 22,68 22,50 Z',
        fillColor: p.hull,
        inkColor: p.ink,
        inkWidth: p.inkW,
      );
      c.rect(122, 28, 48, 42,
          r: 6, fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
      c.line(40, 34, 16, 16, p.ink, p.inkW, cap: StrokeCap.round);
      c.line(40, 66, 16, 84, p.ink, p.inkW, cap: StrokeCap.round);
      c.line(146, 28, 146, 10, p.ink, p.inkW, cap: StrokeCap.round);
      c.line(60, 50, 240, 50, p.ink, 2.5, opacity: 0.35);
      break;

    case ShipKind.destroyer:
      c.rect(196, 34, 42, 32,
          r: 5, fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
      c.line(238, 44, 272, 44, p.ink, 4, cap: StrokeCap.round);
      c.line(238, 56, 272, 56, p.ink, 4, cap: StrokeCap.round);
      c.rect(130, 30, 36, 40,
          fillColor: p.deck, inkColor: p.ink, inkWidth: p.inkW);
      c.line(148, 30, 148, 8, p.ink, 3.5);
      // Helipad.
      c.ellipse(70, 50, 30, 24,
          fillColor: p.trim,
          fillOpacity: 0.5,
          inkColor: p.deck,
          inkWidth: 3,
          dash: const [10, 7]);
      c.stroke('M60,40 L60,60 M60,50 L80,50 M80,40 L80,60', p.deck, 4);
      break;
  }
}

// =============================================================== STEAM ===
// Pressure, not powder. Paddle wheels replace propellers.

void _steam(FamilyCanvas c, ShipKind k, ShipPalette p) {
  if (k != ShipKind.submarine) {
    c.shape(
      'M20,50 C20,26 52,18 120,18 L230,22 C266,26 288,36 296,50 '
      'C288,64 266,74 230,78 L120,82 C52,82 20,74 20,50 Z',
      fillColor: p.hull,
      inkColor: p.ink,
      inkWidth: p.inkW,
    );
    c.line(48, 24, 48, 76, p.ink, 2.5, opacity: 0.4);
    c.line(256, 28, 256, 72, p.ink, 2.5, opacity: 0.4);
  }

  /// A paddle wheel — the family's signature, readable at grid size.
  void wheel(double cx, double cy, double r) {
    c.ellipse(cx, cy, r, r,
        fillColor: p.deck, inkColor: p.ink, inkWidth: p.inkW);
    c.line(cx, cy - r, cx, cy + r, p.ink, 3, opacity: 0.6);
    c.line(cx - r, cy, cx + r, cy, p.ink, 3, opacity: 0.6);
    final d = r * 0.66;
    c.line(cx - d, cy - d, cx + d, cy + d, p.ink, 3, opacity: 0.6);
    c.line(cx - d, cy + d, cx + d, cy - d, p.ink, 3, opacity: 0.6);
  }

  switch (k) {
    case ShipKind.carrier:
      c.rect(66, 22, 148, 56,
          r: 14, fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
      wheel(96, 50, 32);
      wheel(180, 50, 32);
      for (final s in const [
        [42.0, 36.0],
        [42.0, 64.0],
        [236.0, 38.0],
        [236.0, 62.0],
      ]) {
        c.ellipse(s[0], s[1], 10, 10,
            fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
      }
      c.shape('M250,34 L292,50 L250,66 Z',
          fillColor: p.deck, inkColor: p.ink, inkWidth: p.inkW);
      break;

    case ShipKind.battleship:
      c.rect(56, 24, 156, 52,
          r: 10, fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
      for (final x in const [86.0, 118.0, 150.0]) {
        c.ellipse(x, 50, 12, 12,
            fillColor: p.deck, inkColor: p.ink, inkWidth: p.inkW);
      }
      c.ellipse(204, 50, 24, 24,
          inkColor: p.trim, inkWidth: 9, dash: const [8, 9]);
      c.ellipse(204, 50, 10, 10,
          fillColor: p.deck, inkColor: p.ink, inkWidth: 2.5);
      c.stroke('M240,40 q28,10 0,20', p.trim, 8, cap: StrokeCap.round);
      for (final b in const [
        [64.0, 30.0],
        [64.0, 70.0],
        [204.0, 24.0],
        [204.0, 76.0],
      ]) {
        c.circle(b[0], b[1], 3.4, fillColor: p.ink, fillOpacity: 0.55);
      }
      break;

    case ShipKind.cruiser:
      c.rect(96, 28, 112, 44,
          r: 10, fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
      wheel(62, 50, 30);
      c.ellipse(122, 50, 11, 11,
          fillColor: p.deck, inkColor: p.ink, inkWidth: p.inkW);
      c.ellipse(152, 50, 11, 11,
          fillColor: p.deck, inkColor: p.ink, inkWidth: p.inkW);
      c.line(186, 50, 246, 26, p.trim, 7, cap: StrokeCap.round);
      c.line(246, 26, 246, 46, p.ink, 3);
      break;

    case ShipKind.submarine:
      c.shape(
        'M26,50 C26,34 66,28 150,28 C226,28 268,36 290,50 '
        'C268,64 226,72 150,72 C66,72 26,66 26,50 Z',
        fillColor: p.hull,
        inkColor: p.ink,
        inkWidth: p.inkW,
      );
      c.ellipse(152, 50, 26, 24,
          fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
      for (final x in const [72.0, 104.0, 206.0, 238.0]) {
        final h = (x == 72.0 || x == 206.0) ? 36.0 : (x == 104.0 ? 40.0 : 28.0);
        c.line(x, 50 - h / 2, x, 50 + h / 2, p.ink, 3, opacity: 0.5);
      }
      // Caged screw.
      c.ellipse(40, 50, 15, 15,
          inkColor: p.trim, inkWidth: 6, dash: const [7, 7]);
      c.ellipse(264, 46, 8, 8,
          fillColor: p.deck, inkColor: p.ink, inkWidth: 2.5);
      c.ellipse(120, 50, 7, 7,
          fillColor: p.deck, inkColor: p.ink, inkWidth: 2.5);
      break;

    case ShipKind.destroyer:
      c.rect(90, 30, 94, 40,
          r: 10, fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
      c.ellipse(130, 50, 16, 16,
          fillColor: p.deck, inkColor: p.ink, inkWidth: p.inkW);
      c.ellipse(130, 20, 12, 9, fillColor: p.deck, fillOpacity: 0.7);
      c.ellipse(146, 8, 9, 7, fillColor: p.deck, fillOpacity: 0.7);
      c.stroke('M200,42 q26,8 0,16', p.trim, 7, cap: StrokeCap.round);
      c.ellipse(62, 50, 16, 16,
          inkColor: p.trim, inkWidth: 6, dash: const [7, 7]);
      break;
  }
}

// ============================================================== ARCTIC ===
// Icebreakers. Enclosed, rounded, rimed on every windward edge.

void _arctic(FamilyCanvas c, ShipKind k, ShipPalette p) {
  const rime = Color(0xFFFFFFFF);

  if (k != ShipKind.submarine) {
    c.shape(
      'M16,26 L200,20 L262,32 L296,50 L262,68 L200,80 L16,74 Q4,50 16,26 Z',
      fillColor: p.hull,
      inkColor: p.ink,
      inkWidth: p.inkW,
    );
    c.fill('M30,22 q22,-6 40,2 q-20,6 -40,-2 Z', rime, opacity: 0.75);
    c.fill('M120,20 q26,-6 46,3 q-24,6 -46,-3 Z', rime, opacity: 0.75);
    c.fill('M60,78 q24,6 44,-2 q-22,-6 -44,2 Z', rime, opacity: 0.75);
  }

  switch (k) {
    case ShipKind.carrier:
      c.rect(36, 24, 196, 52,
          r: 24, fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
      c.shape('M232,28 L286,50 L232,72 Z',
          fillColor: p.deck, inkColor: p.ink, inkWidth: p.inkW);
      c.ellipse(72, 50, 18, 18,
          fillColor: p.deck, inkColor: p.ink, inkWidth: p.inkW);
      c.line(110, 30, 110, 70, p.ink, 2.5, opacity: 0.35);
      c.line(150, 28, 150, 72, p.ink, 2.5, opacity: 0.35);
      c.line(190, 30, 190, 70, p.ink, 2.5, opacity: 0.35);
      c.shape('M124,24 L134,6 L144,24 Z',
          fillColor: p.glow, inkColor: p.ink, inkWidth: 2);
      c.shape('M168,76 L178,94 L188,76 Z',
          fillColor: p.glow, inkColor: p.ink, inkWidth: 2);
      c.fill('M44,30 q20,-8 38,0 q-18,7 -38,0 Z', rime, opacity: 0.9);
      c.fill('M196,70 q20,8 34,0 q-16,-7 -34,0 Z', rime, opacity: 0.9);
      break;

    case ShipKind.battleship:
      c.rect(40, 28, 58, 44,
          r: 16, fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
      c.rect(186, 30, 52, 40,
          r: 15, fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
      c.rect(112, 24, 60, 52,
          r: 10, fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
      c.line(40, 42, 14, 42, p.ink, 5, cap: StrokeCap.round);
      c.line(40, 58, 14, 58, p.ink, 5, cap: StrokeCap.round);
      c.line(238, 50, 268, 50, p.ink, 5, cap: StrokeCap.round);
      c.shape('M118,24 L128,4 L138,24 Z',
          fillColor: p.glow, inkColor: p.ink, inkWidth: 2);
      c.shape('M148,76 L158,96 L168,76 Z',
          fillColor: p.glow, inkColor: p.ink, inkWidth: 2);
      c.ellipse(142, 50, 9, 9,
          fillColor: p.deck, inkColor: p.ink, inkWidth: 2.5);
      break;

    case ShipKind.cruiser:
      c.rect(46, 30, 54, 40,
          r: 15, fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
      c.line(46, 42, 20, 42, p.ink, 5, cap: StrokeCap.round);
      c.line(46, 58, 20, 58, p.ink, 5, cap: StrokeCap.round);
      c.ellipse(182, 50, 30, 26,
          fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
      c.ellipse(182, 50, 14, 12,
          fillColor: p.deck, inkColor: p.ink, inkWidth: 2.5);
      c.rect(118, 34, 42, 32,
          r: 8, fillColor: p.deck, inkColor: p.ink, inkWidth: p.inkW);
      c.shape('M100,74 L110,92 L120,74 Z',
          fillColor: p.glow, inkColor: p.ink, inkWidth: 2);
      c.shape('M222,30 L232,12 L242,30 Z',
          fillColor: p.glow, inkColor: p.ink, inkWidth: 2);
      break;

    case ShipKind.submarine:
      c.shape(
        'M26,50 C26,32 70,28 150,28 C230,28 274,36 292,50 '
        'C274,64 230,72 150,72 C70,72 26,68 26,50 Z',
        fillColor: p.hull,
        inkColor: p.ink,
        inkWidth: p.inkW,
      );
      c.rect(126, 28, 50, 42,
          r: 10, fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
      c.shape('M60,24 L74,8 L88,24 L102,8 L116,24 L130,8 L144,24 Z',
          fillColor: p.glow, inkColor: p.ink, inkWidth: 2.5);
      c.fill('M180,72 q22,6 40,-2 q-20,-6 -40,2 Z', rime, opacity: 0.8);
      c.ellipse(248, 50, 9, 9,
          fillColor: p.deck, inkColor: p.ink, inkWidth: 2.5);
      break;

    case ShipKind.destroyer:
      c.rect(86, 28, 98, 44,
          r: 14, fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
      c.ellipse(130, 50, 16, 15,
          fillColor: p.deck, inkColor: p.ink, inkWidth: p.inkW);
      c.line(86, 42, 52, 42, p.ink, 5, cap: StrokeCap.round);
      c.line(86, 58, 52, 58, p.ink, 5, cap: StrokeCap.round);
      c.shape('M206,34 L232,50 L206,66 Z',
          fillColor: p.glow, inkColor: p.ink, inkWidth: 2);
      c.shape('M168,72 L178,90 L188,72 Z',
          fillColor: p.glow, inkColor: p.ink, inkWidth: 2);
      break;
  }
}

// ============================================================ VOLCANIC ===
// Jagged polygons, never curves. One glowing vent line per class.

void _volcanic(FamilyCanvas c, ShipKind k, ShipPalette p) {
  if (k != ShipKind.submarine) {
    c.shape(
      'M14,44 L30,18 L92,26 L150,14 L214,28 L262,20 L296,50 '
      'L250,80 L200,72 L140,86 L80,76 L26,82 Z',
      fillColor: p.hull,
      inkColor: p.ink,
      inkWidth: p.inkW,
    );
    c.stroke('M34,26 L46,44 L34,70', p.glow, 3, cap: StrokeCap.round);
    c.stroke('M262,28 L248,48 L258,72', p.glow, 3, cap: StrokeCap.round);
  }

  switch (k) {
    case ShipKind.carrier:
      c.shape('M40,28 L228,22 L252,50 L228,78 L40,72 L30,50 Z',
          fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
      // Three deck vents — this class's marker.
      c.stroke('M52,34 L86,50 L52,66', p.glow, 4, cap: StrokeCap.round);
      c.stroke('M100,30 L136,50 L100,70', p.glow, 4, cap: StrokeCap.round);
      c.stroke('M150,32 L188,50 L150,68', p.glow, 4, cap: StrokeCap.round);
      c.ellipse(212, 50, 17, 17,
          fillColor: p.deck, inkColor: p.ink, inkWidth: p.inkW);
      c.ellipse(212, 50, 8, 8, fillColor: p.glow);
      c.ellipse(62, 50, 9, 9,
          fillColor: p.deck, inkColor: p.ink, inkWidth: 2.5);
      c.ellipse(86, 24, 8, 8,
          fillColor: p.deck, inkColor: p.ink, inkWidth: 2.5);
      c.ellipse(120, 76, 8, 8,
          fillColor: p.deck, inkColor: p.ink, inkWidth: 2.5);
      break;

    case ShipKind.battleship:
      c.shape('M48,26 L206,22 L228,50 L206,76 L48,72 L34,50 Z',
          fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
      c.ellipse(76, 50, 22, 22,
          fillColor: p.deck, inkColor: p.ink, inkWidth: p.inkW);
      c.ellipse(178, 50, 20, 20,
          fillColor: p.deck, inkColor: p.ink, inkWidth: p.inkW);
      c.ellipse(76, 50, 11, 11, fillColor: p.glow);
      c.ellipse(178, 50, 10, 10, fillColor: p.glow);
      // The spine.
      c.line(100, 50, 154, 50, p.glow, 6, cap: StrokeCap.round);
      c.stroke('M110,30 L146,30', p.ink, 4);
      c.stroke('M110,70 L146,70', p.ink, 4);
      break;

    case ShipKind.cruiser:
      c.shape('M54,28 L196,24 L214,50 L196,74 L54,70 L42,50 Z',
          fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
      c.ellipse(84, 50, 22, 22,
          fillColor: p.deck, inkColor: p.ink, inkWidth: p.inkW);
      c.ellipse(84, 50, 11, 11, fillColor: p.glow);
      // Heat-sink comb.
      c.line(130, 26, 130, 74, p.ink, 5, cap: StrokeCap.round);
      c.line(148, 28, 148, 72, p.ink, 5, cap: StrokeCap.round);
      c.line(166, 30, 166, 70, p.ink, 5, cap: StrokeCap.round);
      c.line(184, 34, 184, 66, p.ink, 5, cap: StrokeCap.round);
      c.shape('M200,42 L232,50 L200,58 Z',
          fillColor: p.glow, inkColor: p.ink, inkWidth: 2.5);
      break;

    case ShipKind.submarine:
      c.shape(
        'M24,50 L44,30 L96,26 L160,30 L228,28 L286,50 '
        'L228,72 L160,70 L96,74 L44,70 Z',
        fillColor: p.hull,
        inkColor: p.ink,
        inkWidth: p.inkW,
      );
      c.rect(120, 30, 44, 40,
          r: 6, fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
      c.ellipse(86, 28, 10, 9,
          fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
      c.ellipse(188, 72, 10, 9,
          fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
      c.stroke('M52,42 L74,50 L52,58', p.glow, 4, cap: StrokeCap.round);
      c.stroke('M206,40 L226,50 L206,60', p.glow, 4, cap: StrokeCap.round);
      c.ellipse(262, 50, 10, 10, fillColor: p.glow);
      break;

    case ShipKind.destroyer:
      c.shape('M76,28 L180,24 L200,50 L180,74 L76,70 L62,50 Z',
          fillColor: p.trim, inkColor: p.ink, inkWidth: p.inkW);
      c.ellipse(112, 50, 20, 20,
          fillColor: p.deck, inkColor: p.ink, inkWidth: p.inkW);
      c.ellipse(112, 50, 10, 10, fillColor: p.glow);
      c.line(154, 50, 182, 50, p.glow, 6, cap: StrokeCap.round);
      c.shape('M214,40 L252,50 L214,60 Z',
          fillColor: p.glow, inkColor: p.ink, inkWidth: 2.5);
      break;
  }
}

// =============================================================== SCIFI ===
// Nothing touches anything. No black ink — the outline is the light.

void _scifi(FamilyCanvas c, ShipKind k, ShipPalette p) {
  if (k != ShipKind.submarine) {
    c.shape('M20,50 L52,22 L146,22 L212,34 L296,50 L212,66 L146,78 L52,78 Z',
        fillColor: p.hull,
        inkColor: p.trim,
        inkWidth: 2.5,
        join: StrokeJoin.miter);
    c.stroke('M20,50 L52,22 L146,22 L212,34', p.glow, 3);
  }

  switch (k) {
    case ShipKind.carrier:
      c.rect(46, 40, 200, 20,
          fillColor: p.deck, inkColor: p.trim, inkWidth: 2.5);
      // Two detached pods.
      c.shape('M70,4 L170,4 L186,16 L86,16 Z',
          fillColor: p.deck, inkColor: p.glow, inkWidth: 2.5);
      c.shape('M86,84 L186,84 L170,96 L70,96 Z',
          fillColor: p.deck, inkColor: p.glow, inkWidth: 2.5);
      c.stroke('M96,26 L124,26 L134,38 L106,38 Z', p.glow, 3);
      c.stroke('M146,26 L174,26 L184,38 L156,38 Z', p.glow, 3);
      c.stroke('M106,62 L134,62 L124,74 L96,74 Z', p.glow, 3);
      c.fill('M212,44 L232,50 L212,56 Z', p.glow);
      c.fill('M240,46 L256,50 L240,54 Z', p.glow);
      c.circle(66, 50, 9, fillColor: p.glow);
      break;

    case ShipKind.battleship:
      c.shape('M56,30 L188,26 L216,50 L188,74 L56,70 L44,50 Z',
          fillColor: p.deck, inkColor: p.trim, inkWidth: 2.5);
      // Full-length dorsal rail.
      c.line(52, 50, 262, 50, p.glow, 5, cap: StrokeCap.round);
      c.shape('M120,32 L146,42 L146,58 L120,68 L96,58 L96,42 Z',
          fillColor: p.hull, inkColor: p.glow, inkWidth: 3);
      c.circle(121, 50, 11, fillColor: p.glow);
      c.stroke('M62,34 L38,20', p.trim, 4, cap: StrokeCap.round);
      c.stroke('M62,66 L38,80', p.trim, 4, cap: StrokeCap.round);
      c.stroke('M172,30 L192,16', p.trim, 4, cap: StrokeCap.round);
      c.stroke('M172,70 L192,84', p.trim, 4, cap: StrokeCap.round);
      c.circle(36, 18, 4, fillColor: p.glow);
      c.circle(36, 82, 4, fillColor: p.glow);
      break;

    case ShipKind.cruiser:
      // Catamaran bridged by a bar.
      c.shape('M60,18 L182,14 L232,30 L176,40 L60,36 Z',
          fillColor: p.deck, inkColor: p.trim, inkWidth: 2.5);
      c.shape('M60,64 L176,60 L232,70 L182,86 L60,82 Z',
          fillColor: p.deck, inkColor: p.trim, inkWidth: 2.5);
      c.rect(104, 36, 54, 28,
          fillColor: p.hull, inkColor: p.glow, inkWidth: 3);
      c.stroke('M66,22 L172,18', p.glow, 3);
      c.stroke('M66,78 L172,64', p.glow, 3);
      c.circle(66, 50, 20, inkColor: p.glow, inkWidth: 6);
      c.circle(66, 50, 8, fillColor: p.glow, fillOpacity: 0.6);
      break;

    case ShipKind.submarine:
      c.shape(
        'M28,50 C28,32 70,26 150,26 C226,26 272,34 292,50 '
        'C272,66 226,74 150,74 C70,74 28,68 28,50 Z',
        fillColor: p.hull,
        inkColor: p.trim,
        inkWidth: 2.5,
      );
      c.stroke('M60,34 C120,26 220,30 276,46', p.glow, 3);
      c.line(70, 50, 250, 50, p.glow, 4, cap: StrokeCap.round);
      c.stroke('M56,36 L30,16', p.trim, 4, cap: StrokeCap.round);
      c.stroke('M56,64 L30,84', p.trim, 4, cap: StrokeCap.round);
      c.stroke('M96,32 L104,10', p.trim, 4, cap: StrokeCap.round);
      c.stroke('M96,68 L104,90', p.trim, 4, cap: StrokeCap.round);
      c.circle(176, 50, 13,
          fillColor: p.deck, inkColor: p.glow, inkWidth: 3);
      break;

    case ShipKind.destroyer:
      c.shape('M84,32 L176,28 L206,50 L176,72 L84,68 L70,50 Z',
          fillColor: p.deck, inkColor: p.trim, inkWidth: 2.5);
      c.shape('M126,38 L152,44 L152,56 L126,62 L108,50 Z',
          fillColor: p.hull, inkColor: p.glow, inkWidth: 3);
      c.line(160, 50, 240, 50, p.glow, 4, cap: StrokeCap.round);
      c.circle(86, 38, 6, fillColor: p.glow);
      c.circle(86, 62, 6, fillColor: p.glow);
      break;
  }
}
