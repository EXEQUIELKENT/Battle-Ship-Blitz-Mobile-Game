import 'package:flutter/material.dart';

import '../models/game_models.dart';
import '../services/storage_service.dart';
import 'svg_path.dart';

/// The nine legacy (non-family) ship skins, one hand-drawn hull per
/// [ShipKind], ported verbatim from the design source (`Ship{Name}.dc.html`
/// — Steel/Crimson/Emerald/Gold/Abyss/Arctic/Coral/Midnight/Toxic).
///
/// Authored in the same 300×100 box the battle-grid painters already use
/// (`ShipPainter`'s own hull box), drawn bird's-eye like the family fleets:
/// each of the nine yards gives its five classes their own structure —
/// hull geometry, deck edge, bridge, weapon mounts, secondary machinery —
/// rather than one shared hull recoloured nine times. No component is
/// reused across themes, matching `family_ship_art.dart`'s own "class
/// identity is structural" rule.
const Rect _shipBox = Rect.fromLTWH(0, 0, 300, 100);

/// Converts an SVG `points="x,y x,y ..."` attribute (as used by every
/// `<polygon>` in the source) into a path `d` string, so a polygon can go
/// through the same [FamilyCanvas.shape] call as every other shape here
/// instead of needing its own drawing method.
String _poly(String points) => 'M${points.trim().replaceAll(RegExp(r'\s+'), ' L')} Z';

/// Each theme's own dark outline tone, exactly as used throughout its hull
/// in [paintLegacyShip] — reused by `ship_damage_art.dart` as the "ink"
/// token a hit's damage flourish recolours through. [ShipSkin.trim] is the
/// matching "glow" token: verified byte-identical to the design's own
/// glow hex for every skin checked (e.g. crimson/gold/toxic), which is
/// why only ink needs its own lookup here rather than a second catalog
/// field.
Color legacyShipInk(String skinId) => switch (skinId) {
      'steel' => const Color(0xFF1E2A36),
      'crimson' => const Color(0xFF2A0E0E),
      'emerald' => const Color(0xFF06251C),
      'gold' => const Color(0xFF2A1A06),
      'abyss' => const Color(0xFF10162A),
      'arctic' => const Color(0xFF24404F),
      'coral' => const Color(0xFF3A1710),
      'midnight' => const Color(0xFF0A0E15),
      'toxic' => const Color(0xFF1C210A),
      _ => const Color(0xFF1E2A36),
    };

void paintLegacyShip(Canvas canvas, Size size, ShipSkin skin, ShipKind kind) {
  _drawHull(FamilyCanvas.stretch(canvas, size, hullBounds(skin, kind)), skin, kind);
}

/// The design-space box a given hull's art ACTUALLY occupies, cached per
/// skin+class.
///
/// FEEDBACK (legacy hulls looked cramped in the previews, and a destroyer
/// placed on the board did not reach the end of its own two cells): these
/// hulls are authored in one shared 300×100 box, but almost none of them
/// fills it. Every yard's destroyer in particular starts a fifth of the
/// way in from the stern edge, because the class is drawn short inside a
/// box sized for a carrier. Mapping the whole box onto a widget hands
/// that dead margin straight to the screen — visible as a gap between the
/// hull and its footprint on the grid, and as a hull that sits small and
/// off-centre in a preview slot next to family hulls that DO fill their
/// box.
///
/// Measuring what each hull genuinely draws (see `FamilyCanvas.measuring`)
/// and mapping THAT is the fix, and it is a fix for all forty-five
/// skin/class combinations at once without renumbering any of the
/// hand-transcribed coordinates — which is the last thing that should be
/// touched, since they are verbatim from the design source.
Rect hullBounds(ShipSkin skin, ShipKind kind) => _hullBounds.putIfAbsent(
      '${skin.id}/${kind.index}',
      () {
        final probe = FamilyCanvas.measuring(_shipBox);
        _drawHull(probe, skin, kind);
        return probe.measuredBounds ?? _shipBox;
      },
    );

final Map<String, Rect> _hullBounds = {};

void _drawHull(FamilyCanvas c, ShipSkin skin, ShipKind kind) {
  switch (skin.id) {
    case 'steel':
      _steel(c, kind);
      break;
    case 'crimson':
      _crimson(c, kind);
      break;
    case 'emerald':
      _emerald(c, kind);
      break;
    case 'gold':
      _gold(c, kind);
      break;
    case 'abyss':
      _abyss(c, kind);
      break;
    case 'arctic':
      _arctic(c, kind);
      break;
    case 'coral':
      _coral(c, kind);
      break;
    case 'midnight':
      _midnight(c, kind);
      break;
    case 'toxic':
      _toxic(c, kind);
      break;
    default:
      _steel(c, kind);
  }
}

// ================================================================ STEEL ===
// The undecorated baseline every other yard is a step up from: set-square
// steel, flat chamfer bow, right angles everywhere.

void _steel(FamilyCanvas c, ShipKind k) {
  switch (k) {
    case ShipKind.carrier:
      c.shape('M18,50 L40,20 L234,16 L296,50 L234,84 L40,80 Z',
          fillColor: const Color(0xFF46526B), inkColor: const Color(0xFF1E2A36), inkWidth: 3, join: StrokeJoin.miter);
      c.fill('M28,50 L46,26 L232,23 L284,50 L232,77 L46,74 Z', const Color(0xFF64748B));
      c.rect(30, 28, 240, 44, fillColor: const Color(0xFF3E4A5C), inkColor: const Color(0xFF1E2A36), inkWidth: 2.6);
      c.rect(30, 28, 240, 8, fillColor: const Color(0xFF5A6779));
      c.strokeDashed('M42,50 L258,50', const Color(0xFFCBD5E1), 2.6, [16, 12], opacity: 0.7);
      c.rect(54, 32, 26, 16, fillColor: const Color(0xFF2A3543), inkColor: const Color(0xFF1E2A36), inkWidth: 1.8);
      c.rect(54, 54, 26, 16, fillColor: const Color(0xFF2A3543), inkColor: const Color(0xFF1E2A36), inkWidth: 1.8);
      c.shape(_poly('120,42 138,50 120,58 126,50'), fillColor: const Color(0xFFCBD5E1), inkColor: const Color(0xFF1E2A36), inkWidth: 1.6);
      c.shape(_poly('164,42 182,50 164,58 170,50'), fillColor: const Color(0xFFCBD5E1), inkColor: const Color(0xFF1E2A36), inkWidth: 1.6);
      c.shape(_poly('208,42 226,50 208,58 214,50'), fillColor: const Color(0xFFCBD5E1), inkColor: const Color(0xFF1E2A36), inkWidth: 1.6);
      c.rect(176, 10, 52, 4, fillColor: const Color(0x471E2A36));
      c.rect(174, 8, 52, 22, fillColor: const Color(0xFF5A6779), inkColor: const Color(0xFF1E2A36), inkWidth: 2.6);
      c.rect(174, 8, 52, 7, fillColor: const Color(0xFF94A3B8));
      c.rect(180, 19, 24, 5, fillColor: const Color(0xE6CBD5E1));
      c.circle(216, 21, 4.6, fillColor: const Color(0xFF3E4A5C), inkColor: const Color(0xFF1E2A36), inkWidth: 1.8);
      c.rect(236, 30, 14, 12, fillColor: const Color(0xFF3E4A5C), inkColor: const Color(0xFF1E2A36), inkWidth: 1.8);
      c.rect(236, 58, 14, 12, fillColor: const Color(0xFF3E4A5C), inkColor: const Color(0xFF1E2A36), inkWidth: 1.8);
      break;
    case ShipKind.battleship:
      c.shape('M14,50 L38,18 L230,14 L298,50 L230,86 L38,82 Z',
          fillColor: const Color(0xFF46526B), inkColor: const Color(0xFF1E2A36), inkWidth: 3, join: StrokeJoin.miter);
      c.fill('M24,50 L44,24 L228,21 L286,50 L228,79 L44,76 Z', const Color(0xFF64748B));
      c.rect(112, 26, 64, 48, fillColor: const Color(0x401E2A36));
      c.rect(112, 26, 64, 48, fillColor: const Color(0xFF3E4A5C), inkColor: const Color(0xFF1E2A36), inkWidth: 2.6);
      c.rect(112, 26, 64, 10, fillColor: const Color(0xFF5A6779));
      c.rect(120, 42, 48, 6, fillColor: const Color(0xD9CBD5E1));
      c.circle(144, 60, 7, fillColor: const Color(0xFF2A3543), inkColor: const Color(0xFF1E2A36), inkWidth: 2);
      c.rect(222, 47, 52, 6, r: 3, fillColor: const Color(0xFF1E2A36));
      c.rect(222, 38, 46, 6, r: 3, fillColor: const Color(0xFF1E2A36));
      c.rect(222, 56, 46, 6, r: 3, fillColor: const Color(0xFF1E2A36));
      c.circle(220, 50, 17, fillColor: const Color(0xFF94A3B8), inkColor: const Color(0xFF1E2A36), inkWidth: 2.8);
      c.circle(220, 50, 8, fillColor: const Color(0xFF5A6779), inkColor: const Color(0xFF1E2A36), inkWidth: 2);
      c.rect(188, 47, 34, 5, r: 2.5, fillColor: const Color(0xFF1E2A36));
      c.rect(188, 40, 30, 5, r: 2.5, fillColor: const Color(0xFF1E2A36));
      c.circle(188, 49, 12, fillColor: const Color(0xFF94A3B8), inkColor: const Color(0xFF1E2A36), inkWidth: 2.4);
      c.circle(188, 49, 5.4, fillColor: const Color(0xFF5A6779), inkColor: const Color(0xFF1E2A36), inkWidth: 1.8);
      c.rect(60, 47, 34, 5, r: 2.5, fillColor: const Color(0xFF1E2A36));
      c.rect(60, 40, 30, 5, r: 2.5, fillColor: const Color(0xFF1E2A36));
      c.circle(92, 49, 13, fillColor: const Color(0xFF94A3B8), inkColor: const Color(0xFF1E2A36), inkWidth: 2.4);
      c.circle(92, 49, 6, fillColor: const Color(0xFF5A6779), inkColor: const Color(0xFF1E2A36), inkWidth: 1.8);
      c.rect(34, 47, 26, 5, r: 2.5, fillColor: const Color(0xFF1E2A36));
      c.circle(58, 49, 10, fillColor: const Color(0xFF94A3B8), inkColor: const Color(0xFF1E2A36), inkWidth: 2.2);
      c.circle(58, 49, 4.4, fillColor: const Color(0xFF5A6779), inkColor: const Color(0xFF1E2A36), inkWidth: 1.6);
      c.rect(180, 22, 16, 12, fillColor: const Color(0xFF3E4A5C), inkColor: const Color(0xFF1E2A36), inkWidth: 1.8);
      c.rect(180, 66, 16, 12, fillColor: const Color(0xFF3E4A5C), inkColor: const Color(0xFF1E2A36), inkWidth: 1.8);
      break;
    case ShipKind.cruiser:
      c.shape('M20,50 L42,26 L228,20 L296,50 L228,80 L42,74 Z',
          fillColor: const Color(0xFF46526B), inkColor: const Color(0xFF1E2A36), inkWidth: 2.8, join: StrokeJoin.miter);
      c.fill('M30,50 L48,31 L226,26 L284,50 L226,74 L48,69 Z', const Color(0xFF64748B));
      c.circle(72, 50, 19, fillColor: const Color(0xFF3E4A5C), inkColor: const Color(0xFF1E2A36), inkWidth: 2.4);
      c.strokeDashed('M72,50 m-13,0 a13,13 0 1,0 26,0 a13,13 0 1,0 -26,0', const Color(0xFFCBD5E1), 2.2, [5, 5], opacity: 0.8);
      c.rect(68, 44, 8, 12, fillColor: const Color(0xE6CBD5E1));
      c.rect(120, 30, 52, 40, fillColor: const Color(0x401E2A36));
      c.rect(120, 30, 52, 40, fillColor: const Color(0xFF3E4A5C), inkColor: const Color(0xFF1E2A36), inkWidth: 2.4);
      c.rect(120, 30, 52, 9, fillColor: const Color(0xFF5A6779));
      c.rect(127, 44, 38, 5, fillColor: const Color(0xD9CBD5E1));
      c.rect(100, 36, 14, 12, r: 2, fillColor: const Color(0xFF2A3543), inkColor: const Color(0xFF1E2A36), inkWidth: 1.8);
      c.rect(100, 54, 14, 12, r: 2, fillColor: const Color(0xFF2A3543), inkColor: const Color(0xFF1E2A36), inkWidth: 1.8);
      c.rect(222, 47, 42, 5, r: 2.5, fillColor: const Color(0xFF1E2A36));
      c.rect(222, 40, 38, 5, r: 2.5, fillColor: const Color(0xFF1E2A36));
      c.circle(222, 49, 14, fillColor: const Color(0xFF94A3B8), inkColor: const Color(0xFF1E2A36), inkWidth: 2.6);
      c.circle(222, 49, 6.4, fillColor: const Color(0xFF5A6779), inkColor: const Color(0xFF1E2A36), inkWidth: 1.8);
      c.rect(184, 47, 30, 4.6, r: 2.3, fillColor: const Color(0xFF1E2A36));
      c.circle(188, 49, 10, fillColor: const Color(0xFF94A3B8), inkColor: const Color(0xFF1E2A36), inkWidth: 2.2);
      c.circle(188, 49, 4.6, fillColor: const Color(0xFF5A6779), inkColor: const Color(0xFF1E2A36), inkWidth: 1.6);
      c.rect(42, 42, 14, 16, fillColor: const Color(0xFF3E4A5C), inkColor: const Color(0xFF1E2A36), inkWidth: 1.8);
      break;
    case ShipKind.submarine:
      c.shape(
          'M18,50 C18,38 44,32 90,31 L240,31 C272,34 288,42 292,50 C288,58 272,66 240,69 L90,69 C44,68 18,62 18,50 Z',
          fillColor: const Color(0xFF46526B), inkColor: const Color(0xFF1E2A36), inkWidth: 2.8);
      c.fill(
          'M28,50 C28,42 50,37 92,36 L238,36 C266,38 280,44 283,50 C280,56 266,62 238,64 L92,64 C50,63 28,58 28,50 Z',
          const Color(0xFF64748B));
      c.shape('M126,32 L104,14 L96,14 L112,32 Z', fillColor: const Color(0xFF3E4A5C), inkColor: const Color(0xFF1E2A36), inkWidth: 2.2, join: StrokeJoin.miter);
      c.shape('M126,68 L104,86 L96,86 L112,68 Z', fillColor: const Color(0xFF3E4A5C), inkColor: const Color(0xFF1E2A36), inkWidth: 2.2, join: StrokeJoin.miter);
      c.rect(140, 30, 46, 40, r: 6, fillColor: const Color(0x401E2A36));
      c.rect(140, 30, 46, 40, r: 6, fillColor: const Color(0xFF3E4A5C), inkColor: const Color(0xFF1E2A36), inkWidth: 2.6);
      c.rect(140, 30, 46, 9, r: 6, fillColor: const Color(0xFF5A6779));
      c.circle(176, 50, 5, fillColor: const Color(0xFFCBD5E1), inkColor: const Color(0xFF1E2A36), inkWidth: 1.6);
      c.rect(148, 46, 18, 8, r: 2, fillColor: const Color(0xFF2A3543), inkColor: const Color(0xFF1E2A36), inkWidth: 1.6);
      c.circle(222, 50, 9, inkColor: const Color(0xFFCBD5E1), inkWidth: 2.2, inkOpacity: 0.7);
      c.circle(222, 50, 3.4, fillColor: const Color(0xFF3E4A5C), inkColor: const Color(0xFF1E2A36), inkWidth: 1.6);
      c.circle(70, 50, 7, fillColor: const Color(0xFF3E4A5C), inkColor: const Color(0xFF1E2A36), inkWidth: 1.8);
      c.circle(98, 50, 7, fillColor: const Color(0xFF3E4A5C), inkColor: const Color(0xFF1E2A36), inkWidth: 1.8);
      c.shape('M18,50 L4,38 L8,50 L4,62 Z', fillColor: const Color(0xFF3E4A5C), inkColor: const Color(0xFF1E2A36), inkWidth: 2);
      break;
    case ShipKind.destroyer:
      c.shape('M62,50 L82,30 L228,24 L296,50 L228,76 L82,70 Z',
          fillColor: const Color(0xFF46526B), inkColor: const Color(0xFF1E2A36), inkWidth: 2.8, join: StrokeJoin.miter);
      c.fill('M72,50 L88,35 L226,30 L284,50 L226,70 L88,65 Z', const Color(0xFF64748B));
      c.rect(94, 36, 46, 28, fillColor: const Color(0xFF2A3543), inkColor: const Color(0xFF1E2A36), inkWidth: 2.4);
      for (final xy in const [[99, 39], [111, 39], [123, 39], [99, 52], [111, 52], [123, 52]]) {
        c.rect(xy[0].toDouble(), xy[1].toDouble(), 8, 8, fillColor: const Color(0xFFCBD5E1));
      }
      c.rect(152, 32, 46, 36, fillColor: const Color(0x401E2A36));
      c.rect(152, 32, 46, 36, fillColor: const Color(0xFF3E4A5C), inkColor: const Color(0xFF1E2A36), inkWidth: 2.4);
      c.rect(152, 32, 46, 9, fillColor: const Color(0xFF5A6779));
      c.rect(158, 46, 34, 5, fillColor: const Color(0xD9CBD5E1));
      c.circle(175, 59, 5.4, fillColor: const Color(0xFF2A3543), inkColor: const Color(0xFF1E2A36), inkWidth: 1.8);
      c.rect(228, 47, 42, 5, r: 2.5, fillColor: const Color(0xFF1E2A36));
      c.rect(228, 40, 38, 5, r: 2.5, fillColor: const Color(0xFF1E2A36));
      c.circle(228, 49, 14, fillColor: const Color(0xFF94A3B8), inkColor: const Color(0xFF1E2A36), inkWidth: 2.6);
      c.circle(228, 49, 6.4, fillColor: const Color(0xFF5A6779), inkColor: const Color(0xFF1E2A36), inkWidth: 1.8);
      c.rect(204, 34, 12, 10, fillColor: const Color(0xFF3E4A5C), inkColor: const Color(0xFF1E2A36), inkWidth: 1.6);
      c.rect(204, 56, 12, 10, fillColor: const Color(0xFF3E4A5C), inkColor: const Color(0xFF1E2A36), inkWidth: 1.6);
      c.rect(72, 44, 16, 12, fillColor: const Color(0xFF3E4A5C), inkColor: const Color(0xFF1E2A36), inkWidth: 1.8);
      break;
  }
}

// ============================================================= CRIMSON ===
// Everything points forward. Nothing is curved: a dagger plan, spiked
// stern quarters, no arcs anywhere.

void _crimson(FamilyCanvas c, ShipKind k) {
  const ink = Color(0xFF2A0E0E);
  switch (k) {
    case ShipKind.carrier:
      c.shape('M14,50 L46,16 L208,12 L298,50 L208,88 L46,84 Z', fillColor: const Color(0xFF6E1212), inkColor: ink, inkWidth: 3, join: StrokeJoin.miter);
      c.fill('M26,50 L52,22 L206,19 L284,50 L206,81 L52,78 Z', const Color(0xFF9E1B1B));
      c.shape(_poly('46,16 26,10 46,24'), fillColor: const Color(0xFFEF4444), inkColor: ink, inkWidth: 2);
      c.shape(_poly('46,84 26,90 46,76'), fillColor: const Color(0xFFEF4444), inkColor: ink, inkWidth: 2);
      c.shape(_poly('46,32 260,26 272,50 260,74 46,68 58,50'), fillColor: const Color(0xFF5A1414), inkColor: ink, inkWidth: 2.6, join: StrokeJoin.miter);
      c.fill(_poly('46,32 260,26 264,36 48,42'), const Color(0xFF7E1A1A));
      c.line(66, 38, 256, 38, const Color(0xFF5A1414), 4);
      c.shape(_poly('90,33 90,43 82,38'), fillColor: const Color(0xFFEF4444));
      c.shape(_poly('130,33 130,43 122,38'), fillColor: const Color(0xFFEF4444));
      c.shape(_poly('170,33 170,43 162,38'), fillColor: const Color(0xFFEF4444));
      c.shape(_poly('210,33 210,43 202,38'), fillColor: const Color(0xFFEF4444));
      c.shape(_poly('256,30 278,38 256,46'), fillColor: const Color(0xFFEF4444), inkColor: ink, inkWidth: 1.8, join: StrokeJoin.miter);
      c.line(66, 50, 256, 50, const Color(0xFF5A1414), 4);
      c.shape(_poly('90,45 90,55 82,50'), fillColor: const Color(0xFFEF4444));
      c.shape(_poly('130,45 130,55 122,50'), fillColor: const Color(0xFFEF4444));
      c.shape(_poly('170,45 170,55 162,50'), fillColor: const Color(0xFFEF4444));
      c.shape(_poly('210,45 210,55 202,50'), fillColor: const Color(0xFFEF4444));
      c.shape(_poly('256,42 280,50 256,58'), fillColor: const Color(0xFFEF4444), inkColor: ink, inkWidth: 1.8, join: StrokeJoin.miter);
      c.line(66, 62, 256, 62, const Color(0xFF5A1414), 4);
      c.shape(_poly('90,57 90,67 82,62'), fillColor: const Color(0xFFEF4444));
      c.shape(_poly('130,57 130,67 122,62'), fillColor: const Color(0xFFEF4444));
      c.shape(_poly('170,57 170,67 162,62'), fillColor: const Color(0xFFEF4444));
      c.shape(_poly('210,57 210,67 202,62'), fillColor: const Color(0xFFEF4444));
      c.shape(_poly('256,54 278,62 256,70'), fillColor: const Color(0xFFEF4444), inkColor: ink, inkWidth: 1.8, join: StrokeJoin.miter);
      c.shape(_poly('248,44 296,50 248,58'), fillColor: const Color(0xFF5A1414), inkColor: ink, inkWidth: 2.2, join: StrokeJoin.miter);
      break;
    case ShipKind.battleship:
      c.shape('M10,50 L44,14 L200,10 L300,50 L200,90 L44,86 Z', fillColor: const Color(0xFF6E1212), inkColor: ink, inkWidth: 3, join: StrokeJoin.miter);
      c.fill('M22,50 L50,20 L198,17 L286,50 L198,83 L50,80 Z', const Color(0xFF9E1B1B));
      c.shape(_poly('60,50 90,26 220,26 236,50 220,74 90,74'), fillColor: const Color(0xFF5A1414), inkColor: ink, inkWidth: 2.6, join: StrokeJoin.miter);
      c.fill(_poly('60,50 90,26 220,26 226,38 66,42'), const Color(0xFF7E1A1A));
      c.fill(_poly('96,44 214,44 210,56 100,56'), const Color(0xCCEF4444));
      c.rect(228, 34, 58, 6, fillColor: ink);
      c.rect(228, 47, 66, 6, fillColor: ink);
      c.rect(228, 60, 58, 6, fillColor: ink);
      c.shape(_poly('196,28 232,34 232,66 196,72 186,50'), fillColor: const Color(0xFFEF4444), inkColor: ink, inkWidth: 2.8, join: StrokeJoin.miter);
      c.fill(_poly('196,28 232,34 230,44 194,40'), const Color(0xFFFCA5A5));
      c.rect(76, 36, 42, 5, fillColor: ink);
      c.rect(70, 47, 48, 5, fillColor: ink);
      c.rect(76, 58, 42, 5, fillColor: ink);
      c.shape(_poly('90,32 116,36 116,64 90,68 80,50'), fillColor: const Color(0xFFEF4444), inkColor: ink, inkWidth: 2.6, join: StrokeJoin.miter);
      c.fill(_poly('90,32 116,36 115,45 89,41'), const Color(0xFFFCA5A5));
      c.shape(_poly('130,30 172,28 176,38 128,40'), fillColor: const Color(0xFF5A1414), inkColor: ink, inkWidth: 2.2, join: StrokeJoin.miter);
      c.shape(_poly('128,60 176,62 172,72 130,70'), fillColor: const Color(0xFF5A1414), inkColor: ink, inkWidth: 2.2, join: StrokeJoin.miter);
      c.shape(_poly('44,14 22,6 44,24'), fillColor: const Color(0xFFEF4444), inkColor: ink, inkWidth: 2);
      c.shape(_poly('44,86 22,94 44,76'), fillColor: const Color(0xFFEF4444), inkColor: ink, inkWidth: 2);
      break;
    case ShipKind.cruiser:
      c.shape('M20,50 L52,22 L200,16 L298,50 L200,84 L52,78 Z', fillColor: const Color(0xFF6E1212), inkColor: ink, inkWidth: 2.8, join: StrokeJoin.miter);
      c.fill('M32,50 L58,28 L198,23 L282,50 L198,77 L58,72 Z', const Color(0xFF9E1B1B));
      c.shape(_poly('206,26 298,50 206,74 224,50'), fillColor: const Color(0xFF5A1414), inkColor: ink, inkWidth: 2.4, join: StrokeJoin.miter);
      c.fill(_poly('206,26 298,50 240,42 216,36'), const Color(0xFFEF4444));
      c.shape(_poly('120,30 176,24 182,34 126,40'), fillColor: const Color(0xFFEF4444), inkColor: ink, inkWidth: 2.2, join: StrokeJoin.miter);
      c.line(132, 31, 176, 27, ink, 1.6);
      c.line(134, 36, 178, 32, ink, 1.6);
      c.shape(_poly('126,60 182,66 176,76 120,70'), fillColor: const Color(0xFFEF4444), inkColor: ink, inkWidth: 2.2, join: StrokeJoin.miter);
      c.line(134, 64, 178, 68, ink, 1.6);
      c.line(132, 69, 176, 73, ink, 1.6);
      c.shape(_poly('66,34 116,30 122,50 116,70 66,66 76,50'), fillColor: const Color(0xFF5A1414), inkColor: ink, inkWidth: 2.6, join: StrokeJoin.miter);
      c.fill(_poly('66,34 116,30 118,40 68,43'), const Color(0xFF7E1A1A));
      c.fill(_poly('80,46 114,44 114,54 80,54'), const Color(0xE6FCA5A5));
      c.shape(_poly('188,44 216,50 188,56 196,50'), fillColor: const Color(0xFFFCA5A5), inkColor: ink, inkWidth: 1.6);
      c.shape(_poly('52,22 32,14 52,30'), fillColor: const Color(0xFFEF4444), inkColor: ink, inkWidth: 1.8);
      c.shape(_poly('52,78 32,86 52,70'), fillColor: const Color(0xFFEF4444), inkColor: ink, inkWidth: 1.8);
      break;
    case ShipKind.submarine:
      c.shape('M16,50 L44,30 L206,26 L292,50 L206,74 L44,70 Z', fillColor: const Color(0xFF6E1212), inkColor: ink, inkWidth: 2.8, join: StrokeJoin.miter);
      c.fill('M28,50 L50,35 L204,32 L278,50 L204,68 L50,65 Z', const Color(0xFF9E1B1B));
      c.shape(_poly('120,30 96,10 86,12 108,32'), fillColor: const Color(0xFFEF4444), inkColor: ink, inkWidth: 2.2, join: StrokeJoin.miter);
      c.shape(_poly('120,70 96,90 86,88 108,68'), fillColor: const Color(0xFFEF4444), inkColor: ink, inkWidth: 2.2, join: StrokeJoin.miter);
      c.shape(_poly('196,32 176,18 168,20 186,34'), fillColor: const Color(0xFFEF4444), inkColor: ink, inkWidth: 2, join: StrokeJoin.miter);
      c.shape(_poly('196,68 176,82 168,80 186,66'), fillColor: const Color(0xFFEF4444), inkColor: ink, inkWidth: 2, join: StrokeJoin.miter);
      c.shape(_poly('140,32 194,30 202,50 194,70 140,68 150,50'), fillColor: const Color(0xFF5A1414), inkColor: ink, inkWidth: 2.6, join: StrokeJoin.miter);
      c.fill(_poly('140,32 194,30 196,40 143,42'), const Color(0xFF7E1A1A));
      c.fill(_poly('152,46 192,44 192,54 152,54'), const Color(0xE6FCA5A5));
      c.shape(_poly('202,44 232,50 202,56'), fillColor: const Color(0xFFEF4444), inkColor: ink, inkWidth: 1.8);
      c.fill(_poly('66,42 82,50 66,58 74,50'), const Color(0xB32A0E0E));
      c.fill(_poly('94,42 110,50 94,58 102,50'), const Color(0xB32A0E0E));
      c.shape('M16,50 L2,40 L8,50 L2,60 Z', fillColor: const Color(0xFF5A1414), inkColor: ink, inkWidth: 2);
      break;
    case ShipKind.destroyer:
      c.shape('M62,50 L92,24 L204,20 L298,50 L204,80 L92,76 Z', fillColor: const Color(0xFF6E1212), inkColor: ink, inkWidth: 2.8, join: StrokeJoin.miter);
      c.fill('M74,50 L98,30 L202,27 L282,50 L202,73 L98,70 Z', const Color(0xFF9E1B1B));
      c.shape(_poly('212,30 298,50 212,70 228,50'), fillColor: const Color(0xFF5A1414), inkColor: ink, inkWidth: 2.4, join: StrokeJoin.miter);
      c.fill(_poly('212,30 298,50 244,42 222,38'), const Color(0xFFEF4444));
      c.fill(_poly('204,36 268,48 204,42'), const Color(0x8C2A0E0E));
      c.fill(_poly('204,64 268,52 204,58'), const Color(0x8C2A0E0E));
      c.shape(_poly('104,34 158,30 164,50 158,70 104,66 114,50'), fillColor: const Color(0xFF5A1414), inkColor: ink, inkWidth: 2.6, join: StrokeJoin.miter);
      c.fill(_poly('104,34 158,30 160,40 106,43'), const Color(0xFF7E1A1A));
      c.fill(_poly('116,46 156,44 156,54 116,54'), const Color(0xE6FCA5A5));
      c.rect(176, 47, 34, 5, fillColor: ink);
      c.shape(_poly('166,40 186,44 186,56 166,60 158,50'), fillColor: const Color(0xFFEF4444), inkColor: ink, inkWidth: 2.2, join: StrokeJoin.miter);
      c.shape(_poly('92,24 72,16 92,32'), fillColor: const Color(0xFFEF4444), inkColor: ink, inkWidth: 1.8);
      c.shape(_poly('92,76 72,84 92,68'), fillColor: const Color(0xFFEF4444), inkColor: ink, inkWidth: 1.8);
      c.shape(_poly('78,44 94,50 78,56'), fillColor: const Color(0xFF5A1414), inkColor: ink, inkWidth: 1.6);
      break;
  }
}

// ============================================================= EMERALD ===
// Grown in a hull-yard of living wood — a leaf blade with a central vein,
// no straight line and no corner survives.

void _emerald(FamilyCanvas c, ShipKind k) {
  const ink = Color(0xFF06251C);
  switch (k) {
    case ShipKind.carrier:
      c.shape('M18,50 C18,26 60,12 140,10 C210,8 268,24 296,50 C268,76 210,92 140,90 C60,88 18,74 18,50 Z', fillColor: const Color(0xFF064B39), inkColor: ink, inkWidth: 3);
      c.fill('M30,50 C30,32 66,20 140,18 C206,16 258,28 282,50 C258,72 206,84 140,82 C66,80 30,68 30,50 Z', const Color(0xFF0B6E52));
      c.shape('M40,50 C40,34 74,24 140,23 C200,22 246,32 268,50 C246,68 200,78 140,77 C74,76 40,66 40,50 Z', fillColor: const Color(0xFF12A177), inkColor: ink, inkWidth: 2.4);
      c.fill('M46,44 C90,32 200,32 260,46 C200,44 90,42 46,44 Z', const Color(0x80A7F3D0));
      c.shape('M44,50 C110,42 210,42 268,50 C210,58 110,58 44,50 Z', fillColor: const Color(0xFF08503C), inkColor: ink, inkWidth: 2);
      c.shape('M78,50 C82,40 92,34 104,34 C100,44 92,50 78,50 Z', fillColor: const Color(0xFFA7F3D0), inkColor: ink, inkWidth: 1.8);
      c.shape('M78,50 C82,60 92,66 104,66 C100,56 92,50 78,50 Z', fillColor: const Color(0xFFA7F3D0), inkColor: ink, inkWidth: 1.8);
      c.shape('M136,49 C140,38 152,32 164,32 C160,43 152,49 136,49 Z', fillColor: const Color(0xFFA7F3D0), inkColor: ink, inkWidth: 1.8);
      c.shape('M136,51 C140,62 152,68 164,68 C160,57 152,51 136,51 Z', fillColor: const Color(0xFFA7F3D0), inkColor: ink, inkWidth: 1.8);
      c.shape('M196,49 C200,39 212,34 224,34 C220,44 212,49 196,49 Z', fillColor: const Color(0xFFA7F3D0), inkColor: ink, inkWidth: 1.8);
      c.shape('M196,51 C200,61 212,66 224,66 C220,56 212,51 196,51 Z', fillColor: const Color(0xFFA7F3D0), inkColor: ink, inkWidth: 1.8);
      c.shape('M52,34 C46,24 50,14 60,10 C68,18 68,30 58,36 Z', fillColor: const Color(0xFF064B39), inkColor: ink, inkWidth: 2.4);
      c.shape('M52,66 C46,76 50,86 60,90 C68,82 68,70 58,64 Z', fillColor: const Color(0xFF064B39), inkColor: ink, inkWidth: 2.4);
      c.ellipse(252, 50, 16, 11, fillColor: const Color(0xFF08503C), inkColor: ink, inkWidth: 2.4);
      c.ellipse(250, 47, 10, 5, fillColor: const Color(0xFF34D399));
      c.shape('M268,50 C280,44 292,46 296,50 C292,54 280,56 268,50 Z', fillColor: const Color(0xFF34D399), inkColor: ink, inkWidth: 2);
      break;
    case ShipKind.battleship:
      c.shape('M14,50 C14,24 56,8 138,6 C212,4 272,22 298,50 C272,78 212,96 138,94 C56,92 14,76 14,50 Z', fillColor: const Color(0xFF064B39), inkColor: ink, inkWidth: 3);
      c.fill('M26,50 C26,30 62,16 138,14 C208,12 262,28 286,50 C262,72 208,88 138,86 C62,84 26,70 26,50 Z', const Color(0xFF0B6E52));
      c.stroke('M40,42 C100,26 210,26 272,44', const Color(0xFF34D399), 3, opacity: 0.75);
      c.stroke('M40,58 C100,74 210,74 272,56', const Color(0xFF34D399), 3, opacity: 0.75);
      c.fill('M226,50 C238,40 258,38 274,44 C262,52 244,54 226,50 Z', const Color(0xD906251C));
      c.fill('M226,50 C238,60 258,62 274,56 C262,48 244,46 226,50 Z', const Color(0xD906251C));
      c.ellipse(216, 50, 22, 18, fillColor: const Color(0xFF34D399), inkColor: ink, inkWidth: 2.8);
      c.ellipse(214, 44, 13, 7, fillColor: const Color(0xFFA7F3D0));
      c.fill('M148,50 C158,42 172,40 184,45 C174,52 160,53 148,50 Z', const Color(0xD906251C));
      c.fill('M148,50 C158,58 172,60 184,55 C174,48 160,47 148,50 Z', const Color(0xD906251C));
      c.ellipse(140, 50, 18, 15, fillColor: const Color(0xFF34D399), inkColor: ink, inkWidth: 2.6);
      c.ellipse(138, 45, 10, 6, fillColor: const Color(0xFFA7F3D0));
      c.fill('M76,50 C86,43 98,42 108,46 C98,52 86,53 76,50 Z', const Color(0xD906251C));
      c.fill('M76,50 C86,57 98,58 108,54 C98,48 86,47 76,50 Z', const Color(0xD906251C));
      c.ellipse(68, 50, 16, 13, fillColor: const Color(0xFF34D399), inkColor: ink, inkWidth: 2.4);
      c.ellipse(66, 46, 9, 5, fillColor: const Color(0xFFA7F3D0));
      c.shape('M180,26 C192,18 204,20 206,28 C196,34 184,34 180,26 Z', fillColor: const Color(0xFF08503C), inkColor: ink, inkWidth: 2.2);
      c.shape('M180,74 C192,82 204,80 206,72 C196,66 184,66 180,74 Z', fillColor: const Color(0xFF08503C), inkColor: ink, inkWidth: 2.2);
      c.shape('M100,28 C112,20 124,22 126,30 C116,36 104,36 100,28 Z', fillColor: const Color(0xFF08503C), inkColor: ink, inkWidth: 2.2);
      c.shape('M100,72 C112,80 124,78 126,70 C116,64 104,64 100,72 Z', fillColor: const Color(0xFF08503C), inkColor: ink, inkWidth: 2.2);
      c.shape('M26,50 C16,42 8,44 6,50 C10,56 18,58 26,50 Z', fillColor: const Color(0xFF08503C), inkColor: ink, inkWidth: 2.2);
      break;
    case ShipKind.cruiser:
      c.shape('M28,32 C28,18 62,10 132,10 C200,10 252,20 288,34 C252,44 200,50 132,48 C62,46 28,44 28,32 Z', fillColor: const Color(0xFF064B39), inkColor: ink, inkWidth: 2.8);
      c.shape('M28,68 C28,82 62,90 132,90 C200,90 252,80 288,66 C252,56 200,50 132,52 C62,54 28,56 28,68 Z', fillColor: const Color(0xFF064B39), inkColor: ink, inkWidth: 2.8);
      c.fill('M38,32 C38,22 66,16 132,16 C196,16 244,24 276,34 C244,40 196,44 132,42 C66,40 38,40 38,32 Z', const Color(0xFF0B6E52));
      c.fill('M38,68 C38,78 66,84 132,84 C196,84 244,76 276,66 C244,60 196,56 132,58 C66,60 38,60 38,68 Z', const Color(0xFF0B6E52));
      c.stroke('M60,40 C120,34 190,34 244,40', const Color(0xFF34D399), 2.4, opacity: 0.7);
      c.stroke('M60,60 C120,66 190,66 244,60', const Color(0xFF34D399), 2.4, opacity: 0.7);
      c.shape('M96,36 C110,30 138,30 150,36 L150,64 C138,70 110,70 96,64 Z', fillColor: const Color(0xFF08503C), inkColor: ink, inkWidth: 2.6);
      c.ellipse(123, 50, 18, 12, fillColor: const Color(0xFF12A177), inkColor: ink, inkWidth: 2.4);
      c.ellipse(121, 46, 11, 5.4, fillColor: const Color(0xFFA7F3D0));
      c.fill('M246,50 C258,44 274,44 288,50 C274,56 258,56 246,50 Z', const Color(0xCC06251C));
      c.ellipse(238, 50, 16, 12, fillColor: const Color(0xFF34D399), inkColor: ink, inkWidth: 2.4);
      c.ellipse(236, 46, 9, 5, fillColor: const Color(0xFFA7F3D0));
      c.shape('M176,34 C188,28 198,30 200,38 C190,42 180,42 176,34 Z', fillColor: const Color(0xFF08503C), inkColor: ink, inkWidth: 2.2);
      c.shape('M176,66 C188,72 198,70 200,62 C190,58 180,58 176,66 Z', fillColor: const Color(0xFF08503C), inkColor: ink, inkWidth: 2.2);
      c.shape('M66,44 C58,40 52,44 52,50 C52,56 58,60 66,56 Z', fillColor: const Color(0xFF08503C), inkColor: ink, inkWidth: 2.2);
      break;
    case ShipKind.submarine:
      c.shape('M40,50 C40,32 66,16 110,10 C150,4 190,14 226,30 C250,40 276,46 292,50 C276,54 250,60 226,70 C190,86 150,96 110,90 C66,84 40,68 40,50 Z', fillColor: const Color(0xFF064B39), inkColor: ink, inkWidth: 3);
      c.fill('M52,50 C52,36 74,24 112,18 C148,13 184,22 216,36 C238,44 258,48 272,50 C258,52 238,56 216,64 C184,78 148,87 112,82 C74,76 52,64 52,50 Z', const Color(0xFF0B6E52));
      c.stroke('M96,20 C120,14 152,22 186,38', const Color(0xFF34D399), 2.6, opacity: 0.6);
      c.stroke('M96,80 C120,86 152,78 186,62', const Color(0xFF34D399), 2.6, opacity: 0.6);
      c.ellipse(120, 50, 34, 24, fillColor: const Color(0xFF12A177), inkColor: ink, inkWidth: 2.6);
      c.ellipse(116, 42, 20, 9, fillColor: const Color(0xD9A7F3D0));
      c.circle(148, 50, 6, fillColor: const Color(0xFF08503C), inkColor: ink, inkWidth: 2);
      c.circle(98, 50, 5, fillColor: const Color(0xFF08503C), inkColor: ink, inkWidth: 1.8);
      c.shape('M226,30 C244,26 262,30 272,36 C258,40 240,38 226,34 Z', fillColor: const Color(0xFF08503C), inkColor: ink, inkWidth: 2.2);
      c.shape('M226,70 C244,74 262,70 272,64 C258,60 240,62 226,66 Z', fillColor: const Color(0xFF08503C), inkColor: ink, inkWidth: 2.2);
      c.shape('M40,50 C28,42 18,44 14,50 C18,56 28,58 40,50 Z', fillColor: const Color(0xFF34D399), inkColor: ink, inkWidth: 2.2);
      c.stroke('M70,36 C82,32 92,34 94,40', ink, 2, opacity: 0.5);
      c.stroke('M70,64 C82,68 92,66 94,60', ink, 2, opacity: 0.5);
      break;
    case ShipKind.destroyer:
      c.shape('M56,50 C56,30 84,18 140,16 C200,14 254,26 292,50 C254,74 200,86 140,84 C84,82 56,70 56,50 Z', fillColor: const Color(0xFF064B39), inkColor: ink, inkWidth: 2.8);
      c.fill('M68,50 C68,36 90,26 140,24 C196,22 244,32 278,50 C244,68 196,78 140,76 C90,74 68,64 68,50 Z', const Color(0xFF0B6E52));
      c.shape('M120,32 C160,22 210,28 248,44 C214,36 168,32 120,38 Z', fillColor: const Color(0xFF12A177), inkColor: ink, inkWidth: 2.2);
      c.shape('M120,68 C160,78 210,72 248,56 C214,64 168,68 120,62 Z', fillColor: const Color(0xFF12A177), inkColor: ink, inkWidth: 2.2);
      c.shape('M248,44 C266,40 280,44 288,50 C276,54 262,52 248,56 Z', fillColor: const Color(0xFF34D399), inkColor: ink, inkWidth: 2.2);
      c.ellipse(112, 50, 26, 18, fillColor: const Color(0xFF08503C), inkColor: ink, inkWidth: 2.6);
      c.ellipse(108, 44, 15, 7, fillColor: const Color(0xD9A7F3D0));
      c.circle(134, 50, 5.4, fillColor: const Color(0xFF12A177), inkColor: ink, inkWidth: 1.8);
      c.fill('M196,50 C210,45 226,45 240,50 C226,55 210,55 196,50 Z', const Color(0xCC06251C));
      c.ellipse(188, 50, 14, 11, fillColor: const Color(0xFF34D399), inkColor: ink, inkWidth: 2.4);
      c.ellipse(186, 46, 8, 4.4, fillColor: const Color(0xFFA7F3D0));
      c.shape('M74,36 C64,32 58,36 58,42 C64,44 72,42 74,36 Z', fillColor: const Color(0xFF08503C), inkColor: ink, inkWidth: 2);
      c.shape('M74,64 C64,68 58,64 58,58 C64,56 72,58 74,64 Z', fillColor: const Color(0xFF08503C), inkColor: ink, inkWidth: 2);
      break;
  }
}

// ================================================================ GOLD ===
// A parade fleet. Ornament is structure — a broad hull ringed by a gilt
// rail and colonnade ticks.

void _gold(FamilyCanvas c, ShipKind k) {
  const ink = Color(0xFF2A1A06);
  switch (k) {
    case ShipKind.carrier:
      c.shape('M20,50 C20,24 56,12 132,10 C204,8 262,24 288,42 C292,46 292,54 288,58 C262,76 204,92 132,90 C56,88 20,76 20,50 Z', fillColor: const Color(0xFF5E3C0C), inkColor: ink, inkWidth: 3);
      c.fill('M32,50 C32,30 62,20 132,18 C200,16 254,30 278,46 C280,48 280,52 278,54 C254,70 200,84 132,82 C62,80 32,70 32,50 Z', const Color(0xFF8A5A16));
      c.stroke('M40,50 C40,34 68,25 132,24 C196,23 246,34 268,48 C246,66 196,76 132,75 C68,74 40,66 40,50 Z', const Color(0xFFFBBF24), 2.6);
      c.stroke('M50,32 L50,26 M74,25 L74,19 M100,21 L100,15 M126,20 L126,14 M152,20 L152,14 M178,23 L178,17 M204,28 L204,22 M228,35 L228,29', const Color(0xFFFBBF24), 2.6);
      c.stroke('M50,68 L50,74 M74,75 L74,81 M100,79 L100,85 M126,80 L126,86 M152,80 L152,86 M178,77 L178,83 M204,72 L204,78 M228,65 L228,71', const Color(0xFFFBBF24), 2.6);
      c.shape('M46,50 C110,42 210,42 266,50 C210,58 110,58 46,50 Z', fillColor: const Color(0xFFB07C1E), inkColor: ink, inkWidth: 2.2);
      c.fill('M52,50 C112,45 206,45 258,50 C206,55 112,55 52,50 Z', const Color(0xD9FBBF24));
      c.circle(86, 50, 11, fillColor: const Color(0xFF6B4712), inkColor: const Color(0xFFFBBF24), inkWidth: 2.4);
      c.circle(86, 50, 4, fillColor: const Color(0xFFFDE68A));
      c.circle(86, 50, 7, inkColor: const Color(0xFFFBBF24), inkWidth: 1, inkOpacity: 0.85, dash: const [2, 2]);
      c.circle(134, 50, 11, fillColor: const Color(0xFF6B4712), inkColor: const Color(0xFFFBBF24), inkWidth: 2.4);
      c.circle(134, 50, 4, fillColor: const Color(0xFFFDE68A));
      c.circle(134, 50, 7, inkColor: const Color(0xFFFBBF24), inkWidth: 1, inkOpacity: 0.85, dash: const [2, 2]);
      c.circle(182, 50, 11, fillColor: const Color(0xFF6B4712), inkColor: const Color(0xFFFBBF24), inkWidth: 2.4);
      c.circle(182, 50, 4, fillColor: const Color(0xFFFDE68A));
      c.circle(182, 50, 7, inkColor: const Color(0xFFFBBF24), inkWidth: 1, inkOpacity: 0.85, dash: const [2, 2]);
      c.ellipse(52, 50, 18, 16, fillColor: const Color(0xFF6B4712), inkColor: ink, inkWidth: 2.6);
      c.ellipse(50, 44, 11, 6, fillColor: const Color(0xFFB07C1E));
      c.shape(_poly('52,34 46,26 52,30 58,22 62,30 68,26 62,34'), fillColor: const Color(0xFFFBBF24), inkColor: ink, inkWidth: 1.6);
      c.shape('M40,20 L44,10 L48,16 L52,6 L56,16 L60,10 L64,20 Z', fillColor: const Color(0xFFFBBF24), inkColor: ink, inkWidth: 1.8);
      c.circle(44, 11, 1.8, fillColor: const Color(0xFFFDE68A));
      c.circle(52, 7, 2, fillColor: const Color(0xFFFDE68A));
      c.circle(60, 11, 1.8, fillColor: const Color(0xFFFDE68A));
      c.ellipse(238, 50, 14, 11, fillColor: const Color(0xFF6B4712), inkColor: ink, inkWidth: 2.4);
      c.circle(238, 50, 5, fillColor: const Color(0xFFFBBF24));
      c.shape('M268,48 C280,44 292,46 296,50 C292,54 280,56 268,52 Z', fillColor: const Color(0xFFFBBF24), inkColor: ink, inkWidth: 2);
      break;
    case ShipKind.battleship:
      c.shape('M16,50 C16,22 52,8 130,6 C206,4 268,22 294,44 C298,47 298,53 294,56 C268,78 206,96 130,94 C52,92 16,78 16,50 Z', fillColor: const Color(0xFF5E3C0C), inkColor: ink, inkWidth: 3);
      c.fill('M28,50 C28,28 58,16 130,14 C202,12 258,28 284,48 C258,72 202,86 130,84 C58,82 28,72 28,50 Z', const Color(0xFF8A5A16));
      c.stroke('M38,50 C38,32 64,22 130,21 C198,20 250,34 272,48 C250,64 198,78 130,77 C64,76 38,68 38,50 Z', const Color(0xFFFBBF24), 2.6);
      c.stroke('M60,24 L60,17 M92,18 L92,11 M124,16 L124,9 M156,17 L156,10 M188,22 L188,15 M220,31 L220,24', const Color(0xFFFBBF24), 2.8);
      c.stroke('M60,76 L60,83 M92,82 L92,89 M124,84 L124,91 M156,83 L156,90 M188,78 L188,85 M220,69 L220,76', const Color(0xFFFBBF24), 2.8);
      c.shape('M244,44 C266,40 286,44 296,50 C286,56 266,60 244,56 Z', fillColor: const Color(0xFFB07C1E), inkColor: ink, inkWidth: 2.4);
      c.ellipse(228, 50, 24, 20, fillColor: const Color(0xFF6B4712), inkColor: ink, inkWidth: 2.8);
      c.ellipse(226, 42, 15, 8, fillColor: const Color(0xFFB07C1E));
      c.circle(228, 50, 8, fillColor: const Color(0xFFFBBF24), inkColor: ink, inkWidth: 2);
      c.shape('M162,46 C180,44 194,46 202,50 C194,54 180,56 162,54 Z', fillColor: const Color(0xFFB07C1E), inkColor: ink, inkWidth: 2.2);
      c.ellipse(150, 50, 19, 16, fillColor: const Color(0xFF6B4712), inkColor: ink, inkWidth: 2.6);
      c.ellipse(148, 44, 12, 6, fillColor: const Color(0xFFB07C1E));
      c.circle(150, 50, 6, fillColor: const Color(0xFFFBBF24), inkColor: ink, inkWidth: 1.8);
      c.shape('M90,46 C104,44 116,46 124,50 C116,54 104,56 90,54 Z', fillColor: const Color(0xFFB07C1E), inkColor: ink, inkWidth: 2.2);
      c.ellipse(78, 50, 17, 14, fillColor: const Color(0xFF6B4712), inkColor: ink, inkWidth: 2.4);
      c.ellipse(76, 45, 10, 5, fillColor: const Color(0xFFB07C1E));
      c.circle(78, 50, 5.4, fillColor: const Color(0xFFFBBF24), inkColor: ink, inkWidth: 1.6);
      c.ellipse(192, 50, 13, 11, fillColor: const Color(0xFFB07C1E), inkColor: ink, inkWidth: 2.4);
      c.shape(_poly('192,40 186,32 192,36 198,28 202,36 208,32 202,40'), fillColor: const Color(0xFFFBBF24), inkColor: ink, inkWidth: 1.6);
      c.shape('M180,26 L184,16 L188,22 L192,12 L196,22 L200,16 L204,26 Z', fillColor: const Color(0xFFFBBF24), inkColor: ink, inkWidth: 1.8);
      c.circle(184, 17, 1.8, fillColor: const Color(0xFFFDE68A));
      c.circle(192, 13, 2, fillColor: const Color(0xFFFDE68A));
      c.circle(200, 17, 1.8, fillColor: const Color(0xFFFDE68A));
      c.ellipse(42, 50, 11, 10, fillColor: const Color(0xFF6B4712), inkColor: ink, inkWidth: 2.2);
      c.circle(42, 50, 4, fillColor: const Color(0xFFFBBF24));
      break;
    case ShipKind.cruiser:
      c.shape('M26,50 C26,28 58,16 130,14 C198,12 254,26 290,48 C254,74 198,88 130,86 C58,84 26,72 26,50 Z', fillColor: const Color(0xFF5E3C0C), inkColor: ink, inkWidth: 2.8);
      c.fill('M38,50 C38,32 64,22 130,21 C194,20 244,32 276,48 C244,68 194,79 130,78 C64,77 38,68 38,50 Z', const Color(0xFF8A5A16));
      c.stroke('M46,50 C46,36 70,28 130,27 C188,26 234,36 262,48 C234,64 188,73 130,72 C70,71 46,64 46,50 Z', const Color(0xFFFBBF24), 2.4);
      c.stroke('M64,28 L64,22 M92,22 L92,16 M120,20 L120,14 M148,21 L148,15 M176,25 L176,19 M204,32 L204,26', const Color(0xFFFBBF24), 2.4);
      c.stroke('M64,72 L64,78 M92,78 L92,84 M120,80 L120,86 M148,79 L148,85 M176,75 L176,81 M204,68 L204,74', const Color(0xFFFBBF24), 2.4);
      c.shape(_poly('112,36 140,32 152,50 140,68 112,64 104,50'), fillColor: const Color(0xFF6B4712), inkColor: ink, inkWidth: 2.6);
      c.fill(_poly('112,36 140,32 144,42 110,45'), const Color(0xFFB07C1E));
      c.circle(126, 50, 8, fillColor: const Color(0xFFFBBF24), inkColor: ink, inkWidth: 2);
      c.shape('M226,38 C248,34 268,38 282,44 C266,48 246,48 226,46 Z', fillColor: const Color(0xFFB07C1E), inkColor: ink, inkWidth: 2.2);
      c.ellipse(214, 42, 15, 11, fillColor: const Color(0xFF6B4712), inkColor: ink, inkWidth: 2.4);
      c.circle(214, 42, 5, fillColor: const Color(0xFFFBBF24));
      c.shape('M226,62 C248,66 268,62 282,56 C266,52 246,52 226,54 Z', fillColor: const Color(0xFFB07C1E), inkColor: ink, inkWidth: 2.2);
      c.ellipse(214, 58, 15, 11, fillColor: const Color(0xFF6B4712), inkColor: ink, inkWidth: 2.4);
      c.circle(214, 58, 5, fillColor: const Color(0xFFFBBF24));
      c.ellipse(176, 50, 11, 9, fillColor: const Color(0xFFB07C1E), inkColor: ink, inkWidth: 2.2);
      c.shape(_poly('176,42 172,36 176,38 180,32 184,38 188,36 184,42'), fillColor: const Color(0xFFFBBF24), inkColor: ink, inkWidth: 1.4);
      c.shape('M166,30 L169,21 L173,26 L176,17 L179,26 L183,21 L186,30 Z', fillColor: const Color(0xFFFBBF24), inkColor: ink, inkWidth: 1.6);
      c.circle(169, 22, 1.6, fillColor: const Color(0xFFFDE68A));
      c.circle(176, 18, 1.8, fillColor: const Color(0xFFFDE68A));
      c.circle(183, 22, 1.6, fillColor: const Color(0xFFFDE68A));
      c.ellipse(62, 50, 14, 12, fillColor: const Color(0xFF6B4712), inkColor: ink, inkWidth: 2.4);
      c.ellipse(60, 45, 8, 4.4, fillColor: const Color(0xFFB07C1E));
      c.circle(62, 50, 4.6, fillColor: const Color(0xFFFBBF24));
      break;
    case ShipKind.submarine:
      c.shape('M22,50 C22,34 52,26 100,25 L236,25 C270,29 286,42 292,50 C286,58 270,71 236,75 L100,75 C52,74 22,66 22,50 Z', fillColor: const Color(0xFF5E3C0C), inkColor: ink, inkWidth: 2.8);
      c.fill('M34,50 C34,40 58,32 102,31 L234,31 C264,34 276,43 281,50 C276,57 264,66 234,69 L102,69 C58,68 34,60 34,50 Z', const Color(0xFF8A5A16));
      c.stroke('M74,29 L74,71 M104,26 L104,74 M196,26 L196,74 M226,28 L226,72', const Color(0xFFFBBF24), 3);
      c.stroke('M46,42 C110,36 220,36 272,44', const Color(0xFFFDE68A), 2, opacity: 0.5);
      c.ellipse(150, 50, 30, 21, fillColor: const Color(0xFF6B4712), inkColor: ink, inkWidth: 2.8);
      c.ellipse(148, 43, 19, 9, fillColor: const Color(0xFFB07C1E));
      c.circle(150, 50, 8, fillColor: const Color(0xFFFBBF24), inkColor: ink, inkWidth: 2);
      c.shape(_poly('150,29 142,20 150,24 158,14 164,24 172,20 164,29'), fillColor: const Color(0xFFFBBF24), inkColor: ink, inkWidth: 1.8);
      c.circle(142, 20, 1.8, fillColor: const Color(0xFFFDE68A));
      c.circle(158, 14, 2, fillColor: const Color(0xFFFDE68A));
      c.circle(172, 20, 1.8, fillColor: const Color(0xFFFDE68A));
      c.shape('M126,26 L112,10 L104,12 L118,28 Z', fillColor: const Color(0xFFB07C1E), inkColor: ink, inkWidth: 2.2);
      c.shape('M126,74 L112,90 L104,88 L118,72 Z', fillColor: const Color(0xFFB07C1E), inkColor: ink, inkWidth: 2.2);
      c.circle(248, 50, 9, fillColor: const Color(0xFF6B4712), inkColor: const Color(0xFFFBBF24), inkWidth: 2.4);
      c.circle(248, 50, 3.4, fillColor: const Color(0xFFFDE68A));
      c.circle(248, 50, 6.4, inkColor: const Color(0xFFFBBF24), inkWidth: 1, inkOpacity: 0.85, dash: const [2, 2]);
      c.circle(52, 50, 9, fillColor: const Color(0xFF6B4712), inkColor: const Color(0xFFFBBF24), inkWidth: 2.4);
      c.circle(52, 50, 3.4, fillColor: const Color(0xFFFDE68A));
      c.circle(52, 50, 6.4, inkColor: const Color(0xFFFBBF24), inkWidth: 1, inkOpacity: 0.85, dash: const [2, 2]);
      break;
    case ShipKind.destroyer:
      c.shape('M64,50 C64,32 92,22 152,21 C210,20 258,32 290,50 C258,68 210,80 152,79 C92,78 64,68 64,50 Z', fillColor: const Color(0xFF5E3C0C), inkColor: ink, inkWidth: 2.8);
      c.fill('M76,50 C76,38 98,30 152,29 C206,28 248,38 276,50 C248,62 206,72 152,71 C98,70 76,62 76,50 Z', const Color(0xFF8A5A16));
      c.stroke('M84,50 C84,42 104,36 152,35 C200,34 238,42 262,50 C238,58 200,66 152,65 C104,64 84,58 84,50 Z', const Color(0xFFFBBF24), 2.4);
      c.stroke('M100,34 L100,28 M132,30 L132,24 M164,30 L164,24 M196,34 L196,28', const Color(0xFFFBBF24), 2.4);
      c.stroke('M100,66 L100,72 M132,70 L132,76 M164,70 L164,76 M196,66 L196,72', const Color(0xFFFBBF24), 2.4);
      c.shape('M244,44 C262,40 280,44 292,50 C280,56 262,60 244,56 Z', fillColor: const Color(0xFFB07C1E), inkColor: ink, inkWidth: 2.4);
      c.ellipse(230, 50, 18, 14, fillColor: const Color(0xFF6B4712), inkColor: ink, inkWidth: 2.6);
      c.ellipse(228, 44, 11, 5.4, fillColor: const Color(0xFFB07C1E));
      c.circle(230, 50, 6, fillColor: const Color(0xFFFBBF24), inkColor: ink, inkWidth: 1.8);
      c.shape(_poly('130,38 158,36 166,50 158,64 130,62 124,50'), fillColor: const Color(0xFF6B4712), inkColor: ink, inkWidth: 2.4);
      c.fill(_poly('130,38 158,36 160,44 128,46'), const Color(0xFFB07C1E));
      c.circle(144, 50, 6, fillColor: const Color(0xFFFBBF24), inkColor: ink, inkWidth: 1.8);
      c.ellipse(98, 50, 13, 11, fillColor: const Color(0xFF6B4712), inkColor: ink, inkWidth: 2.4);
      c.shape(_poly('98,40 94,34 98,36 102,30 106,36 110,34 106,40'), fillColor: const Color(0xFFFBBF24), inkColor: ink, inkWidth: 1.4);
      c.circle(94, 34, 1.4, fillColor: const Color(0xFFFDE68A));
      c.circle(102, 30, 1.6, fillColor: const Color(0xFFFDE68A));
      c.circle(110, 34, 1.4, fillColor: const Color(0xFFFDE68A));
      c.circle(196, 50, 7, fillColor: const Color(0xFFB07C1E), inkColor: const Color(0xFFFBBF24), inkWidth: 2);
      break;
  }
}

// =============================================================== ABYSS ===
// Half a ship. The stern never came back — a hollow bow half solid,
// dissolving into dashed rings and shattered streamers astern.

void _abyss(FamilyCanvas c, ShipKind k) {
  const ink = Color(0xFF10162A);
  const purple = Color(0xFF7C6BC4);
  const glow = Color(0xFFC4B5FD);
  switch (k) {
    case ShipKind.carrier:
      c.shape('M26,50 C26,24 70,10 168,8 C222,6 268,22 296,50 C268,78 222,94 168,92 C70,90 26,76 26,50 Z', fillColor: const Color(0xFF1A2138), inkColor: ink, inkWidth: 3);
      c.fill('M40,50 C40,30 78,20 168,18 C216,16 254,30 280,50 C254,70 216,80 168,78 C78,76 40,70 40,50 Z', const Color(0xFF2A3550));
      c.shape(_poly('28,40 4,30 26,46'), fillColor: const Color(0xFF2A3550), inkColor: ink, inkWidth: 2, inkOpacity: 0.85, fillOpacity: 0.85);
      c.shape(_poly('28,60 4,70 26,54'), fillColor: const Color(0xFF2A3550), inkColor: ink, inkWidth: 1.8, inkOpacity: 0.6, fillOpacity: 0.6);
      c.shape(_poly('32,26 14,10 28,32'), fillColor: const Color(0xFF2A3550), inkColor: ink, inkWidth: 1.6, inkOpacity: 0.5, fillOpacity: 0.5);
      c.shape(_poly('32,74 14,90 28,68'), fillColor: const Color(0xFF2A3550), inkColor: ink, inkWidth: 1.5, inkOpacity: 0.4, fillOpacity: 0.4);
      c.strokeDashed('M20,50 Q10,52 2,48', purple, 2.2, [6, 8], opacity: 0.6);
      c.circle(62, 50, 7, inkColor: purple, inkWidth: 2, dash: const [3, 4]);
      c.strokeDashed('M44,32 L266,28', purple, 1.4, [4, 6], opacity: 0.4);
      c.strokeDashed('M44,68 L266,72', purple, 1.4, [4, 6], opacity: 0.4);
      c.circle(252, 34, 4, inkColor: purple, inkWidth: 1.6, dash: const [2, 3]);
      c.circle(252, 66, 4, inkColor: purple, inkWidth: 1.6, dash: const [2, 3]);
      c.strokeDashed('M96,32 L268,32 L280,50 L268,68 L96,68 L86,50 Z', purple, 3, [12, 7]);
      c.strokeDashed('M100,50 L266,50', glow, 2.4, [8, 10], opacity: 0.7);
      c.circle(128, 50, 12, inkColor: purple, inkWidth: 2.8);
      c.circle(128, 50, 3.4, fillColor: glow);
      c.circle(176, 50, 12, inkColor: purple, inkWidth: 2.8);
      c.circle(176, 50, 3.4, fillColor: glow);
      c.circle(224, 50, 12, inkColor: purple, inkWidth: 2.8);
      c.circle(224, 50, 3.4, fillColor: glow);
      c.shape('M256,30 L282,36 L286,50 L282,64 L256,70', fillColor: const Color(0xFF202A42), inkColor: ink, inkWidth: 2.4);
      c.circle(272, 44, 3.6, fillColor: glow);
      c.circle(272, 56, 3.6, fillColor: glow);
      c.circle(98, 50, 8, inkColor: purple, inkWidth: 2.2, dash: const [4, 4]);
      break;
    case ShipKind.battleship:
      c.shape('M24,50 C24,20 68,6 168,4 C226,2 272,20 298,50 C272,80 226,98 168,96 C68,94 24,80 24,50 Z', fillColor: const Color(0xFF1A2138), inkColor: ink, inkWidth: 3);
      c.fill('M38,50 C38,26 76,16 168,14 C220,12 258,28 284,50 C258,72 220,86 168,84 C76,82 38,74 38,50 Z', const Color(0xFF2A3550));
      c.shape(_poly('26,38 2,28 22,46'), fillColor: const Color(0xFF2A3550), inkColor: ink, inkWidth: 2, fillOpacity: 0.85, inkOpacity: 0.85);
      c.shape(_poly('26,62 2,72 22,54'), fillColor: const Color(0xFF2A3550), inkColor: ink, inkWidth: 1.8, fillOpacity: 0.6, inkOpacity: 0.6);
      c.shape(_poly('32,22 10,4 26,30'), fillColor: const Color(0xFF2A3550), inkColor: ink, inkWidth: 1.6, fillOpacity: 0.45, inkOpacity: 0.45);
      c.shape(_poly('32,78 10,96 26,70'), fillColor: const Color(0xFF2A3550), inkColor: ink, inkWidth: 1.5, fillOpacity: 0.35, inkOpacity: 0.35);
      c.strokeDashed('M20,50 Q10,52 2,48', purple, 2.2, [6, 8], opacity: 0.6);
      c.circle(60, 50, 8, inkColor: purple, inkWidth: 2, dash: const [3, 4]);
      c.strokeDashed('M42,30 L96,26', purple, 1.4, [4, 6], opacity: 0.4);
      c.strokeDashed('M42,70 L96,74', purple, 1.4, [4, 6], opacity: 0.4);
      c.line(256, 42, 294, 38, ink, 6);
      c.line(256, 58, 294, 62, ink, 6);
      c.circle(240, 50, 21, inkColor: purple, inkWidth: 3.4);
      c.circle(240, 50, 9, fillColor: const Color(0xFF202A42), inkColor: ink, inkWidth: 2.2);
      c.circle(240, 50, 3.4, fillColor: glow);
      c.line(186, 28, 212, 22, ink, 5);
      c.circle(172, 30, 15, inkColor: purple, inkWidth: 3);
      c.circle(172, 30, 6, fillColor: const Color(0xFF202A42), inkColor: ink, inkWidth: 1.8);
      c.line(186, 72, 212, 78, ink, 5);
      c.circle(172, 70, 15, inkColor: purple, inkWidth: 3);
      c.circle(172, 70, 6, fillColor: const Color(0xFF202A42), inkColor: ink, inkWidth: 1.8);
      c.line(100, 44, 74, 40, ink, 5);
      c.line(100, 56, 74, 60, ink, 5);
      c.circle(114, 50, 17, inkColor: purple, inkWidth: 3.2);
      c.circle(114, 50, 7, fillColor: const Color(0xFF202A42), inkColor: ink, inkWidth: 2);
      c.shape(_poly('144,38 196,38 204,50 196,62 144,62 136,50'), fillColor: const Color(0xFF202A42), inkColor: ink, inkWidth: 2.4);
      c.circle(158, 50, 4.4, fillColor: glow);
      c.circle(182, 50, 4.4, fillColor: glow);
      c.circle(170, 50, 26, inkColor: purple, inkWidth: 2, inkOpacity: 0.65, dash: const [5, 7]);
      break;
    case ShipKind.cruiser:
      c.shape('M133,50 C133,28 163,18 197,16 C231,14 261,27 281,50 C261,73 231,86 197,84 C163,82 133,72 133,50 Z', fillColor: const Color(0xFF1A2138), inkColor: ink, inkWidth: 2.8);
      c.fill('M145,50 C145,34 169,26 197,24 C227,22 251,33 267,50 C251,67 227,78 197,76 C169,74 145,66 145,50 Z', const Color(0xFF2A3550));
      c.shape('M20,50 C20,32 46,22 78,21 C106,20 122,32 122,50 C122,68 106,80 78,79 C46,78 20,68 20,50 Z', fillColor: const Color(0xFF1A2138), inkColor: ink, inkWidth: 2.8);
      c.fill('M34,50 C34,38 54,32 78,31 C100,30 110,38 110,50 C110,62 100,70 78,69 C54,68 34,62 34,50 Z', const Color(0xFF2A3550));
      c.stroke('M122,44 L133,44 M122,50 L133,50 M122,56 L133,56', purple, 2.4, opacity: 0.8);
      c.shape(_poly('22,42 2,26 18,50'), fillColor: const Color(0xFF2A3550), inkColor: ink, inkWidth: 1.8, fillOpacity: 0.75, inkOpacity: 0.75);
      c.shape(_poly('22,58 2,74 18,50'), fillColor: const Color(0xFF2A3550), inkColor: ink, inkWidth: 1.6, fillOpacity: 0.5, inkOpacity: 0.5);
      c.strokeDashed('M14,50 Q6,52 0,48', purple, 2, [5, 7], opacity: 0.5);
      c.circle(50, 34, 3.4, inkColor: purple, inkWidth: 1.6, dash: const [2, 3]);
      c.circle(50, 66, 3.4, inkColor: purple, inkWidth: 1.6, dash: const [2, 3]);
      c.circle(197, 32, 4, inkColor: purple, inkWidth: 1.8, dash: const [2, 3]);
      c.circle(197, 68, 4, inkColor: purple, inkWidth: 1.8, dash: const [2, 3]);
      c.line(243, 46, 277, 44, ink, 5);
      c.line(243, 54, 277, 56, ink, 5);
      c.circle(231, 50, 15, inkColor: purple, inkWidth: 3);
      c.circle(231, 50, 6, fillColor: const Color(0xFF202A42), inkColor: ink, inkWidth: 1.8);
      c.shape(_poly('173,38 211,38 217,50 211,62 173,62 167,50'), fillColor: const Color(0xFF202A42), inkColor: ink, inkWidth: 2.4);
      c.circle(183, 50, 4, fillColor: glow);
      c.circle(203, 50, 4, fillColor: glow);
      c.circle(71, 50, 14, inkColor: purple, inkWidth: 2.8);
      c.circle(71, 50, 4, fillColor: glow);
      break;
    case ShipKind.submarine:
      c.shape('M26,50 C26,30 60,20 110,19 L242,19 C276,23 290,40 296,50 C290,60 276,77 242,81 L110,81 C60,80 26,70 26,50 Z', fillColor: const Color(0xFF1A2138), inkColor: ink, inkWidth: 2.8);
      c.fill('M40,50 C40,38 66,30 112,29 L240,29 C270,32 280,43 284,50 C280,57 270,68 240,71 L112,71 C66,70 40,62 40,50 Z', const Color(0xFF2A3550));
      c.shape(_poly('28,40 2,22 24,46'), fillColor: const Color(0xFF2A3550), inkColor: ink, inkWidth: 2, fillOpacity: 0.85, inkOpacity: 0.85);
      c.shape(_poly('28,60 2,72 24,54'), fillColor: const Color(0xFF2A3550), inkColor: ink, inkWidth: 1.8, fillOpacity: 0.6, inkOpacity: 0.6);
      c.shape(_poly('34,26 14,4 28,32'), fillColor: const Color(0xFF2A3550), inkColor: ink, inkWidth: 1.6, fillOpacity: 0.45, inkOpacity: 0.45);
      c.strokeDashed('M18,50 Q8,52 0,48', purple, 2.2, [6, 8], opacity: 0.6);
      c.circle(74, 50, 8, inkColor: purple, inkWidth: 2, dash: const [3, 4]);
      c.strokeDashed('M46,42 L108,30', purple, 1.4, [4, 6], opacity: 0.4);
      c.strokeDashed('M46,58 L108,70', purple, 1.4, [4, 6], opacity: 0.4);
      c.circle(166, 50, 24, inkColor: purple, inkWidth: 3.4);
      c.circle(166, 50, 12, fillColor: const Color(0xFF202A42), inkColor: ink, inkWidth: 2.4);
      c.circle(160, 46, 3.4, fillColor: glow);
      c.circle(172, 54, 3.4, fillColor: glow);
      c.circle(120, 28, 9, inkColor: purple, inkWidth: 2.6);
      c.circle(120, 72, 9, inkColor: purple, inkWidth: 2.6);
      c.circle(216, 32, 7, inkColor: purple, inkWidth: 2.4);
      c.circle(216, 68, 7, inkColor: purple, inkWidth: 2.4);
      c.circle(252, 50, 8, inkColor: purple, inkWidth: 2.2, dash: const [4, 4]);
      c.shape('M294,50 L306,42 L302,50 L306,58 Z', fillColor: const Color(0xFF202A42), inkColor: ink, inkWidth: 2);
      break;
    case ShipKind.destroyer:
      c.shape('M60,50 C60,26 96,14 190,12 C238,10 270,28 296,50 C270,72 238,90 190,88 C96,86 60,74 60,50 Z', fillColor: const Color(0xFF1A2138), inkColor: ink, inkWidth: 2.8);
      c.fill('M76,50 C76,34 106,24 190,22 C232,20 258,34 280,50 C258,66 232,80 190,78 C106,76 76,66 76,50 Z', const Color(0xFF2A3550));
      c.shape(_poly('62,40 34,26 56,48'), fillColor: const Color(0xFF2A3550), inkColor: ink, inkWidth: 2, fillOpacity: 0.8, inkOpacity: 0.8);
      c.shape(_poly('62,60 34,74 56,52'), fillColor: const Color(0xFF2A3550), inkColor: ink, inkWidth: 1.8, fillOpacity: 0.55, inkOpacity: 0.55);
      c.shape(_poly('68,24 46,10 60,36'), fillColor: const Color(0xFF2A3550), inkColor: ink, inkWidth: 1.6, fillOpacity: 0.42, inkOpacity: 0.42);
      c.shape(_poly('68,76 46,90 60,64'), fillColor: const Color(0xFF2A3550), inkColor: ink, inkWidth: 1.5, fillOpacity: 0.33, inkOpacity: 0.33);
      c.strokeDashed('M50,46 Q38,48 28,44', purple, 2.2, [6, 8], opacity: 0.55);
      c.strokeDashed('M52,58 Q40,62 30,60', purple, 2, [5, 9], opacity: 0.4);
      c.circle(100, 50, 8, inkColor: purple, inkWidth: 2, dash: const [3, 4]);
      c.strokeDashed('M78,32 L131,32', purple, 1.4, [4, 6], opacity: 0.4);
      c.strokeDashed('M78,68 L131,68', purple, 1.4, [4, 6], opacity: 0.4);
      c.line(262, 44, 296, 42, ink, 5.5);
      c.line(262, 56, 296, 58, ink, 5.5);
      c.circle(248, 50, 17, inkColor: purple, inkWidth: 3.2);
      c.circle(248, 50, 7, fillColor: const Color(0xFF202A42), inkColor: ink, inkWidth: 2);
      c.circle(248, 50, 2.8, fillColor: glow);
      c.shape(_poly('164,38 204,38 210,50 204,62 164,62 158,50'), fillColor: const Color(0xFF202A42), inkColor: ink, inkWidth: 2.4);
      c.circle(174, 50, 4, fillColor: glow);
      c.circle(196, 50, 4, fillColor: glow);
      c.circle(140, 50, 9, inkColor: purple, inkWidth: 2.4, dash: const [4, 4]);
      break;
  }
}

// =============================================================== ARCTIC ===
// Icebreakers. Blunt, sealed, accreted — a faceted plan with an ice wedge
// frozen on the bow.

void _arctic(FamilyCanvas c, ShipKind k) {
  const ink = Color(0xFF24404F);
  const light = Color(0xFFE8F7FF);
  switch (k) {
    case ShipKind.carrier:
      c.shape('M16,50 L34,18 L206,10 L262,26 L296,50 L262,74 L206,90 L34,82 Z', fillColor: const Color(0xFF7FA6BE), inkColor: ink, inkWidth: 3, join: StrokeJoin.miter);
      c.fill('M28,50 L42,24 L204,17 L254,31 L282,50 L254,69 L204,83 L42,76 Z', const Color(0xFFA9C9DC));
      c.shape(_poly('262,26 296,50 262,74 248,50'), fillColor: light, inkColor: ink, inkWidth: 2.4, join: StrokeJoin.miter);
      c.stroke('M250,32 L260,32 L256,38 L266,38 L262,44 L272,44 L266,50 L272,56 L262,56 L266,62 L256,62 L260,68 L250,68', ink, 2);
      c.shape(_poly('44,30 96,26 100,38 46,42'), fillColor: const Color(0xFF9BC0D6), inkColor: ink, inkWidth: 2);
      c.shape(_poly('100,25 152,22 156,35 102,38'), fillColor: const Color(0xFF86AEC6), inkColor: ink, inkWidth: 2);
      c.shape(_poly('154,22 206,20 208,34 156,35'), fillColor: const Color(0xFF9BC0D6), inkColor: ink, inkWidth: 2);
      c.shape(_poly('206,20 246,26 246,38 208,34'), fillColor: const Color(0xFF86AEC6), inkColor: ink, inkWidth: 2);
      c.shape(_poly('44,70 96,74 100,62 46,58'), fillColor: const Color(0xFF9BC0D6), inkColor: ink, inkWidth: 2);
      c.shape(_poly('100,75 152,78 156,65 102,62'), fillColor: const Color(0xFF86AEC6), inkColor: ink, inkWidth: 2);
      c.shape(_poly('154,78 206,80 208,66 156,65'), fillColor: const Color(0xFF9BC0D6), inkColor: ink, inkWidth: 2);
      c.shape(_poly('206,80 246,74 246,62 208,66'), fillColor: const Color(0xFF86AEC6), inkColor: ink, inkWidth: 2);
      c.stroke('M96,26 L92,50 L96,74 M152,22 L148,50 L152,78 M206,20 L210,50 L206,80', ink, 1.6, opacity: 0.55);
      c.stroke('M90,36 L98,36 M146,32 L154,32 M202,30 L210,30 M90,64 L98,64 M146,68 L154,68 M202,70 L210,70', ink, 1.4, opacity: 0.45);
      c.stroke('M20,42 L30,38 M20,58 L30,62 M24,50 L34,50', ink, 1.3, opacity: 0.4);
      c.strokeDashed('M48,50 L238,50', light, 3, [14, 10], opacity: 0.85);
      c.shape(_poly('70,47 73,50 70,53 67,50'), fillColor: light, inkColor: ink, inkWidth: 1);
      c.shape(_poly('110,47 113,50 110,53 107,50'), fillColor: light, inkColor: ink, inkWidth: 1);
      c.shape(_poly('150,47 153,50 150,53 147,50'), fillColor: light, inkColor: ink, inkWidth: 1);
      c.shape(_poly('190,47 193,50 190,53 187,50'), fillColor: light, inkColor: ink, inkWidth: 1);
      c.shape(_poly('220,47 223,50 220,53 217,50'), fillColor: light, inkColor: ink, inkWidth: 1);
      c.shape('M40,50 L20,36 L28,48 L10,42 L22,52 L4,50 L22,58 L10,64 L28,58 L20,70 L40,56 Z', fillColor: const Color(0xFFC6DEEB), inkColor: ink, inkWidth: 2);
      c.shape(_poly('34,44 18,50 34,56'), fillColor: const Color(0xFF86AEC6), inkColor: ink, inkWidth: 2);
      break;
    case ShipKind.battleship:
      c.shape('M12,50 L30,14 L198,6 L258,22 L298,50 L258,78 L198,94 L30,86 Z', fillColor: const Color(0xFF7FA6BE), inkColor: ink, inkWidth: 3, join: StrokeJoin.miter);
      c.fill('M24,50 L38,20 L196,13 L250,28 L284,50 L250,72 L196,87 L38,80 Z', const Color(0xFFA9C9DC));
      c.shape(_poly('258,22 298,50 258,78 242,50'), fillColor: light, inkColor: ink, inkWidth: 2.6, join: StrokeJoin.miter);
      c.stroke('M228,32 L238,32 L234,38 L244,38 L240,44 L250,44 L244,50 L250,56 L240,56 L244,62 L234,62 L238,68 L228,68', ink, 2);
      c.shape(_poly('40,28 92,22 96,34 42,40'), fillColor: const Color(0xFF9BC0D6), inkColor: ink, inkWidth: 2);
      c.shape(_poly('96,21 148,16 152,29 98,34'), fillColor: const Color(0xFF86AEC6), inkColor: ink, inkWidth: 2);
      c.shape(_poly('150,16 196,12 200,26 154,29'), fillColor: const Color(0xFF9BC0D6), inkColor: ink, inkWidth: 2);
      c.shape(_poly('196,12 226,20 226,34 200,26'), fillColor: const Color(0xFF86AEC6), inkColor: ink, inkWidth: 2);
      c.shape(_poly('40,72 92,78 96,66 42,60'), fillColor: const Color(0xFF9BC0D6), inkColor: ink, inkWidth: 2);
      c.shape(_poly('96,79 148,84 152,71 98,66'), fillColor: const Color(0xFF86AEC6), inkColor: ink, inkWidth: 2);
      c.shape(_poly('150,84 196,88 200,74 154,71'), fillColor: const Color(0xFF9BC0D6), inkColor: ink, inkWidth: 2);
      c.shape(_poly('196,88 226,80 226,66 200,74'), fillColor: const Color(0xFF86AEC6), inkColor: ink, inkWidth: 2);
      c.stroke('M92,22 L88,50 L92,78 M148,16 L144,50 L148,84 M196,12 L202,50 L196,88', ink, 1.6, opacity: 0.55);
      c.stroke('M84,36 L92,36 M140,30 L148,30 M188,26 L196,26 M84,64 L92,64 M140,70 L148,70 M188,74 L196,74', ink, 1.4, opacity: 0.45);
      c.stroke('M16,42 L26,38 M16,58 L26,62 M20,50 L30,50', ink, 1.3, opacity: 0.4);
      c.shape(_poly('70,47 73,50 70,53 67,50'), fillColor: light, inkColor: ink, inkWidth: 1);
      c.shape(_poly('110,47 113,50 110,53 107,50'), fillColor: light, inkColor: ink, inkWidth: 1);
      c.shape(_poly('150,47 153,50 150,53 147,50'), fillColor: light, inkColor: ink, inkWidth: 1);
      c.shape(_poly('190,47 193,50 190,53 187,50'), fillColor: light, inkColor: ink, inkWidth: 1);
      c.shape('M36,50 L16,34 L24,48 L6,40 L20,52 L2,50 L20,58 L6,64 L24,58 L16,72 L36,56 Z', fillColor: const Color(0xFFC6DEEB), inkColor: ink, inkWidth: 2);
      c.shape(_poly('30,44 14,50 30,56'), fillColor: const Color(0xFF86AEC6), inkColor: ink, inkWidth: 2);
      break;
    case ShipKind.cruiser:
      c.shape('M24,50 L44,26 L200,18 L250,32 L294,50 L250,68 L200,82 L44,74 Z', fillColor: const Color(0xFF7FA6BE), inkColor: ink, inkWidth: 2.8, join: StrokeJoin.miter);
      c.fill('M36,50 L50,32 L198,25 L244,37 L280,50 L244,63 L198,75 L50,68 Z', const Color(0xFFA9C9DC));
      c.shape(_poly('204,20 268,40 232,34'), fillColor: light, inkColor: ink, inkWidth: 2.4, join: StrokeJoin.miter);
      c.shape(_poly('204,80 268,60 232,66'), fillColor: light, inkColor: ink, inkWidth: 2.4, join: StrokeJoin.miter);
      c.shape(_poly('250,32 294,50 250,68 238,50'), fillColor: light, inkColor: ink, inkWidth: 2.4, join: StrokeJoin.miter);
      c.stroke('M225,38 L235,38 L231,44 L241,44 L237,50 L241,56 L231,56 L235,62 L225,62', ink, 1.8);
      c.shape(_poly('50,32 100,27 104,39 52,42'), fillColor: const Color(0xFF9BC0D6), inkColor: ink, inkWidth: 1.8);
      c.shape(_poly('104,26 155,21 159,34 106,39'), fillColor: const Color(0xFF86AEC6), inkColor: ink, inkWidth: 1.8);
      c.shape(_poly('158,21 200,18 204,31 160,34'), fillColor: const Color(0xFF9BC0D6), inkColor: ink, inkWidth: 1.8);
      c.shape(_poly('50,68 100,73 104,61 52,58'), fillColor: const Color(0xFF9BC0D6), inkColor: ink, inkWidth: 1.8);
      c.shape(_poly('104,74 155,79 159,66 106,61'), fillColor: const Color(0xFF86AEC6), inkColor: ink, inkWidth: 1.8);
      c.shape(_poly('158,79 200,82 204,69 160,66'), fillColor: const Color(0xFF9BC0D6), inkColor: ink, inkWidth: 1.8);
      c.stroke('M100,27 L96,50 L100,73 M155,21 L150,50 L155,79', ink, 1.4, opacity: 0.5);
      c.stroke('M92,38 L100,38 M147,32 L155,32 M92,62 L100,62 M147,68 L155,68', ink, 1.3, opacity: 0.4);
      c.stroke('M28,42 L38,38 M28,58 L38,62 M32,50 L42,50', ink, 1.2, opacity: 0.4);
      c.shape(_poly('120,47 123,50 120,53 117,50'), fillColor: light, inkColor: ink, inkWidth: 1);
      c.shape(_poly('160,47 163,50 160,53 157,50'), fillColor: light, inkColor: ink, inkWidth: 1);
      c.shape(_poly('190,47 193,50 190,53 187,50'), fillColor: light, inkColor: ink, inkWidth: 1);
      c.shape('M46,50 L28,36 L34,48 L18,42 L30,52 L14,50 L30,58 L18,64 L34,58 L28,70 L46,56 Z', fillColor: const Color(0xFFC6DEEB), inkColor: ink, inkWidth: 1.8);
      c.shape(_poly('44,44 28,50 44,56'), fillColor: const Color(0xFF86AEC6), inkColor: ink, inkWidth: 1.8);
      break;
    case ShipKind.submarine:
      c.shape('M22,50 L46,22 L200,16 L254,30 L290,50 L254,70 L200,84 L46,78 Z', fillColor: const Color(0xFF7FA6BE), inkColor: ink, inkWidth: 2.8, join: StrokeJoin.miter);
      c.fill('M34,50 L52,28 L198,23 L248,35 L276,50 L248,65 L198,77 L52,72 Z', const Color(0xFFA9C9DC));
      c.shape(_poly('254,30 290,50 254,70 242,50'), fillColor: light, inkColor: ink, inkWidth: 2.4, join: StrokeJoin.miter);
      c.stroke('M232,36 L242,36 L238,42 L248,42 L244,48 L252,48 L246,54 L252,60 L244,60 L248,66 L238,66 L242,58', ink, 1.8);
      c.shape(_poly('56,30 104,25 108,37 58,40'), fillColor: const Color(0xFF9BC0D6), inkColor: ink, inkWidth: 1.8);
      c.shape(_poly('108,24 156,20 160,33 110,37'), fillColor: const Color(0xFF86AEC6), inkColor: ink, inkWidth: 1.8);
      c.shape(_poly('158,20 200,16 204,29 162,33'), fillColor: const Color(0xFF9BC0D6), inkColor: ink, inkWidth: 1.8);
      c.shape(_poly('56,70 104,75 108,63 58,60'), fillColor: const Color(0xFF9BC0D6), inkColor: ink, inkWidth: 1.8);
      c.shape(_poly('108,76 156,80 160,67 110,63'), fillColor: const Color(0xFF86AEC6), inkColor: ink, inkWidth: 1.8);
      c.shape(_poly('158,80 200,84 204,71 162,67'), fillColor: const Color(0xFF9BC0D6), inkColor: ink, inkWidth: 1.8);
      c.stroke('M104,25 L100,50 L104,75 M156,20 L152,50 L156,80', ink, 1.4, opacity: 0.5);
      c.stroke('M96,38 L104,38 M148,32 L156,32 M96,62 L104,62 M148,68 L156,68', ink, 1.3, opacity: 0.4);
      c.stroke('M30,42 L40,38 M30,58 L40,62 M34,50 L44,50', ink, 1.2, opacity: 0.4);
      c.shape(_poly('120,47 123,50 120,53 117,50'), fillColor: light, inkColor: ink, inkWidth: 1);
      c.shape(_poly('170,47 173,50 170,53 167,50'), fillColor: light, inkColor: ink, inkWidth: 1);
      c.shape(_poly('200,47 203,50 200,53 197,50'), fillColor: light, inkColor: ink, inkWidth: 1);
      c.shape('M42,50 L22,36 L30,48 L12,42 L26,52 L8,50 L26,58 L12,64 L30,58 L22,70 L42,56 Z', fillColor: const Color(0xFFC6DEEB), inkColor: ink, inkWidth: 1.8);
      c.shape(_poly('38,44 20,50 38,56'), fillColor: const Color(0xFF86AEC6), inkColor: ink, inkWidth: 1.8);
      break;
    case ShipKind.destroyer:
      c.shape('M74,50 L102,24 L214,20 L258,34 L294,50 L258,66 L214,80 L102,76 Z', fillColor: const Color(0xFF7FA6BE), inkColor: ink, inkWidth: 2.8, join: StrokeJoin.miter);
      c.fill('M86,50 L108,30 L212,27 L252,39 L280,50 L252,61 L212,73 L108,70 Z', const Color(0xFFA9C9DC));
      c.shape(_poly('258,34 294,50 258,66 246,50'), fillColor: light, inkColor: ink, inkWidth: 2.4, join: StrokeJoin.miter);
      c.stroke('M222,38 L232,38 L228,44 L238,44 L234,50 L238,56 L228,56 L232,62 L222,62', ink, 1.8);
      c.shape(_poly('108,32 150,29 154,40 110,42'), fillColor: const Color(0xFF9BC0D6), inkColor: ink, inkWidth: 1.8);
      c.shape(_poly('152,28 192,25 196,37 156,40'), fillColor: const Color(0xFF86AEC6), inkColor: ink, inkWidth: 1.8);
      c.shape(_poly('192,25 214,20 218,32 196,37'), fillColor: const Color(0xFF9BC0D6), inkColor: ink, inkWidth: 1.8);
      c.shape(_poly('108,68 150,71 154,60 110,58'), fillColor: const Color(0xFF9BC0D6), inkColor: ink, inkWidth: 1.8);
      c.shape(_poly('152,72 192,75 196,63 156,60'), fillColor: const Color(0xFF86AEC6), inkColor: ink, inkWidth: 1.8);
      c.shape(_poly('192,75 214,80 218,68 196,63'), fillColor: const Color(0xFF9BC0D6), inkColor: ink, inkWidth: 1.8);
      c.stroke('M150,29 L146,50 L150,71 M192,25 L188,50 L192,75', ink, 1.4, opacity: 0.5);
      c.stroke('M142,40 L150,40 M184,34 L192,34 M142,60 L150,60 M184,66 L192,66', ink, 1.3, opacity: 0.4);
      c.stroke('M80,42 L90,38 M80,58 L90,62 M84,50 L94,50', ink, 1.2, opacity: 0.4);
      c.shape(_poly('120,47 123,50 120,53 117,50'), fillColor: light, inkColor: ink, inkWidth: 1);
      c.shape(_poly('165,47 168,50 165,53 162,50'), fillColor: light, inkColor: ink, inkWidth: 1);
      c.shape(_poly('200,47 203,50 200,53 197,50'), fillColor: light, inkColor: ink, inkWidth: 1);
      c.shape('M100,50 L82,36 L88,48 L72,42 L84,52 L68,50 L84,58 L72,64 L88,58 L82,70 L100,56 Z', fillColor: const Color(0xFFC6DEEB), inkColor: ink, inkWidth: 1.8);
      c.shape(_poly('92,44 74,50 92,56'), fillColor: const Color(0xFF86AEC6), inkColor: ink, inkWidth: 1.8);
      break;
  }
}

// ================================================================ CORAL ===
// Reef accretion over a stolen hull — a knobby oval fringed with rings of
// polyp bumps, growth lumps breaking the rim all round.

void _coral(FamilyCanvas c, ShipKind k) {
  const ink = Color(0xFF3A1710);
  void polyp(double cx, double cy, {double r = 12, double innerR = 15}) {
    c.circle(cx, cy, r, fillColor: const Color(0xFF93382A), inkColor: ink, inkWidth: 2.4);
    c.circle(cx, cy, innerR, inkColor: ink, inkWidth: 1, inkOpacity: 0.5);
    c.circle(cx, cy, innerR + 3, inkColor: ink, inkWidth: 0.8, inkOpacity: 0.32);
  }

  switch (k) {
    case ShipKind.carrier:
      c.shape('M20,50 C20,26 58,14 136,12 C206,10 264,26 292,50 C264,74 206,90 136,88 C58,86 20,74 20,50 Z', fillColor: const Color(0xFF93382A), inkColor: ink, inkWidth: 3);
      polyp(66, 20, r: 12, innerR: 15);
      polyp(118, 14, r: 14, innerR: 17);
      polyp(180, 16, r: 12, innerR: 15);
      polyp(66, 80, r: 12, innerR: 15);
      polyp(118, 86, r: 14, innerR: 17);
      polyp(180, 84, r: 12, innerR: 15);
      c.shape('M32,50 C32,32 64,22 136,20 C202,18 254,32 278,50 C254,68 202,82 136,80 C64,78 32,68 32,50 Z', fillColor: const Color(0xFFC1543F), inkColor: ink, inkWidth: 2.4);
      c.fill('M42,50 C42,38 72,30 136,28 C196,26 242,38 264,50 C242,62 196,74 136,72 C72,70 42,62 42,50 Z', const Color(0xFFA34432));
      c.shape('M48,50 C110,42 210,42 260,50 C210,58 110,58 48,50 Z', fillColor: const Color(0xFFE0715A), inkColor: ink, inkWidth: 2);
      c.circle(86, 50, 13, fillColor: const Color(0xFFE0715A), inkColor: ink, inkWidth: 2.4);
      c.circle(80, 42, 7, fillColor: const Color(0xFFE0715A), inkColor: ink, inkWidth: 2);
      c.circle(94, 60, 6, fillColor: const Color(0xFFE0715A), inkColor: ink, inkWidth: 2);
      c.circle(86, 50, 5, fillColor: const Color(0xFFFFD2BE));
      c.circle(86, 50, 8, inkColor: ink, inkWidth: 1, inkOpacity: 0.5);
      c.circle(86, 50, 11, inkColor: ink, inkWidth: 0.8, inkOpacity: 0.32);
      c.circle(146, 50, 13, fillColor: const Color(0xFFE0715A), inkColor: ink, inkWidth: 2.4);
      c.circle(140, 60, 7, fillColor: const Color(0xFFE0715A), inkColor: ink, inkWidth: 2);
      c.circle(154, 41, 6, fillColor: const Color(0xFFE0715A), inkColor: ink, inkWidth: 2);
      c.circle(146, 50, 5, fillColor: const Color(0xFFFFD2BE));
      c.circle(146, 50, 8, inkColor: ink, inkWidth: 1, inkOpacity: 0.5);
      c.circle(146, 50, 11, inkColor: ink, inkWidth: 0.8, inkOpacity: 0.32);
      c.circle(206, 50, 12, fillColor: const Color(0xFFE0715A), inkColor: ink, inkWidth: 2.4);
      c.circle(200, 41, 6, fillColor: const Color(0xFFE0715A), inkColor: ink, inkWidth: 2);
      c.circle(212, 59, 5.4, fillColor: const Color(0xFFE0715A), inkColor: ink, inkWidth: 2);
      c.circle(206, 50, 4.6, fillColor: const Color(0xFFFFD2BE));
      c.circle(206, 50, 7.6, inkColor: ink, inkWidth: 1, inkOpacity: 0.5);
      c.circle(206, 50, 10.6, inkColor: ink, inkWidth: 0.8, inkOpacity: 0.32);
      c.shape('M52,32 C60,20 76,14 92,16 C82,26 68,32 52,32 Z', fillColor: const Color(0xFFFF9E7A), inkColor: ink, inkWidth: 2.2);
      c.shape('M52,68 C60,80 76,86 92,84 C82,74 68,68 52,68 Z', fillColor: const Color(0xFFFF9E7A), inkColor: ink, inkWidth: 2.2);
      c.shape('M264,50 C276,42 290,44 296,50 C290,56 276,58 264,50 Z', fillColor: const Color(0xFFFF9E7A), inkColor: ink, inkWidth: 2.2);
      c.ellipse(240, 50, 14, 11, fillColor: const Color(0xFFA34432), inkColor: ink, inkWidth: 2.4);
      c.circle(240, 50, 5, fillColor: const Color(0xFFFF9E7A));
      break;
    case ShipKind.battleship:
      c.shape('M16,50 C16,22 54,8 134,6 C208,4 268,22 296,50 C268,78 208,96 134,94 C54,92 16,78 16,50 Z', fillColor: const Color(0xFF93382A), inkColor: ink, inkWidth: 3);
      polyp(60, 18, r: 13, innerR: 16);
      polyp(118, 10, r: 15, innerR: 18);
      polyp(186, 14, r: 13, innerR: 16);
      polyp(60, 82, r: 13, innerR: 16);
      polyp(118, 90, r: 15, innerR: 18);
      polyp(186, 86, r: 13, innerR: 16);
      c.shape('M28,50 C28,28 60,16 134,14 C204,12 258,28 284,50 C258,72 204,88 134,86 C60,84 28,72 28,50 Z', fillColor: const Color(0xFFC1543F), inkColor: ink, inkWidth: 2.4);
      c.fill('M40,50 C40,34 68,24 134,22 C198,20 246,34 268,50 C246,66 198,80 134,78 C68,76 40,66 40,50 Z', const Color(0xFFA34432));
      c.fill('M248,44 C266,40 284,44 294,50 C282,56 266,58 248,56 Z', ink);
      c.circle(228, 50, 20, fillColor: const Color(0xFFE0715A), inkColor: ink, inkWidth: 2.8);
      c.circle(216, 34, 11, fillColor: const Color(0xFFE0715A), inkColor: ink, inkWidth: 2.4);
      c.circle(216, 66, 11, fillColor: const Color(0xFFE0715A), inkColor: ink, inkWidth: 2.4);
      c.circle(228, 50, 8, fillColor: const Color(0xFFFFD2BE));
      c.circle(228, 50, 11, inkColor: ink, inkWidth: 1, inkOpacity: 0.5);
      c.circle(228, 50, 14, inkColor: ink, inkWidth: 0.8, inkOpacity: 0.32);
      c.fill('M180,42 C194,38 206,40 214,44 C204,48 192,48 180,48 Z', ink);
      c.circle(166, 44, 14, fillColor: const Color(0xFFE0715A), inkColor: ink, inkWidth: 2.6);
      c.circle(156, 32, 8, fillColor: const Color(0xFFE0715A), inkColor: ink, inkWidth: 2.2);
      c.circle(166, 44, 5.4, fillColor: const Color(0xFFFFD2BE));
      c.circle(166, 44, 8.4, inkColor: ink, inkWidth: 1, inkOpacity: 0.5);
      c.circle(166, 44, 11.4, inkColor: ink, inkWidth: 0.8, inkOpacity: 0.32);
      c.fill('M180,58 C194,62 206,60 214,56 C204,52 192,52 180,52 Z', ink);
      c.circle(166, 56, 14, fillColor: const Color(0xFFE0715A), inkColor: ink, inkWidth: 2.6);
      c.circle(156, 68, 8, fillColor: const Color(0xFFE0715A), inkColor: ink, inkWidth: 2.2);
      c.circle(166, 56, 5.4, fillColor: const Color(0xFFFFD2BE));
      c.circle(166, 56, 8.4, inkColor: ink, inkWidth: 1, inkOpacity: 0.5);
      c.circle(166, 56, 11.4, inkColor: ink, inkWidth: 0.8, inkOpacity: 0.32);
      c.fill('M92,44 C104,42 114,44 120,48 C110,52 100,52 92,50 Z', ink);
      c.circle(78, 50, 16, fillColor: const Color(0xFFE0715A), inkColor: ink, inkWidth: 2.6);
      c.circle(66, 38, 9, fillColor: const Color(0xFFE0715A), inkColor: ink, inkWidth: 2.2);
      c.circle(70, 63, 8, fillColor: const Color(0xFFE0715A), inkColor: ink, inkWidth: 2.2);
      c.circle(78, 50, 6, fillColor: const Color(0xFFFFD2BE));
      c.circle(78, 50, 9, inkColor: ink, inkWidth: 1, inkOpacity: 0.5);
      c.circle(78, 50, 12, inkColor: ink, inkWidth: 0.8, inkOpacity: 0.32);
      c.ellipse(122, 50, 22, 17, fillColor: const Color(0xFFA34432), inkColor: ink, inkWidth: 2.6);
      c.shape('M104,44 C112,38 132,38 140,44 C132,48 112,48 104,44 Z', fillColor: const Color(0xFFFF9E7A));
      c.circle(122, 54, 6, fillColor: const Color(0xFFFFD2BE), inkColor: ink, inkWidth: 1.8);
      c.circle(122, 54, 9, inkColor: ink, inkWidth: 1, inkOpacity: 0.5);
      c.circle(122, 54, 12, inkColor: ink, inkWidth: 0.8, inkOpacity: 0.32);
      c.shape('M268,50 C280,42 292,44 298,50 C292,56 280,58 268,50 Z', fillColor: const Color(0xFFFF9E7A), inkColor: ink, inkWidth: 2.2);
      break;
    case ShipKind.cruiser:
      c.shape('M26,50 C26,30 60,18 128,16 C176,14 206,26 224,40 C240,34 264,36 278,44 C258,48 242,50 224,50 C242,50 258,52 278,56 C264,64 240,66 224,60 C206,74 176,86 128,84 C60,82 26,70 26,50 Z', fillColor: const Color(0xFF93382A), inkColor: ink, inkWidth: 2.8);
      c.fill('M38,50 C38,34 66,24 128,23 C172,22 200,32 216,44 C230,40 250,42 262,46 C246,48 232,50 216,50 C232,50 246,52 262,54 C250,58 230,60 216,56 C200,68 172,78 128,77 C66,76 38,66 38,50 Z', const Color(0xFFC1543F));
      polyp(70, 24, r: 10, innerR: 13);
      polyp(120, 18, r: 12, innerR: 15);
      polyp(70, 76, r: 10, innerR: 13);
      polyp(120, 82, r: 12, innerR: 15);
      c.stroke('M226,40 C244,32 264,32 280,40', const Color(0xFFFF9E7A), 2.6);
      c.stroke('M226,60 C244,68 264,68 280,60', const Color(0xFFFF9E7A), 2.6);
      c.circle(280, 40, 5, fillColor: const Color(0xFFFF9E7A), inkColor: ink, inkWidth: 1.8);
      c.circle(280, 60, 5, fillColor: const Color(0xFFFF9E7A), inkColor: ink, inkWidth: 1.8);
      c.shape('M60,44 C120,38 190,40 240,48 C190,52 120,54 60,56 Z', fillColor: const Color(0xFFA34432), inkColor: ink, inkWidth: 2);
      c.fill('M196,48 C214,46 228,48 236,50 C226,54 212,54 196,52 Z', ink);
      c.circle(184, 50, 15, fillColor: const Color(0xFFE0715A), inkColor: ink, inkWidth: 2.6);
      c.circle(174, 38, 8, fillColor: const Color(0xFFE0715A), inkColor: ink, inkWidth: 2.2);
      c.circle(184, 50, 5.4, fillColor: const Color(0xFFFFD2BE));
      c.circle(184, 50, 8.4, inkColor: ink, inkWidth: 1, inkOpacity: 0.5);
      c.circle(184, 50, 11.4, inkColor: ink, inkWidth: 0.8, inkOpacity: 0.32);
      c.ellipse(106, 50, 20, 15, fillColor: const Color(0xFFA34432), inkColor: ink, inkWidth: 2.6);
      c.shape('M90,45 C98,40 116,40 122,45 C114,49 98,49 90,45 Z', fillColor: const Color(0xFFFF9E7A));
      c.circle(106, 54, 5.4, fillColor: const Color(0xFFFFD2BE), inkColor: ink, inkWidth: 1.6);
      c.circle(106, 54, 8.4, inkColor: ink, inkWidth: 1, inkOpacity: 0.5);
      c.circle(106, 54, 11.4, inkColor: ink, inkWidth: 0.8, inkOpacity: 0.32);
      c.circle(60, 50, 11, fillColor: const Color(0xFFE0715A), inkColor: ink, inkWidth: 2.2);
      c.circle(52, 42, 6, fillColor: const Color(0xFFE0715A), inkColor: ink, inkWidth: 1.8);
      c.circle(60, 50, 4, fillColor: const Color(0xFFFFD2BE));
      c.circle(60, 50, 7, inkColor: ink, inkWidth: 1, inkOpacity: 0.5);
      c.circle(60, 50, 10, inkColor: ink, inkWidth: 0.8, inkOpacity: 0.32);
      break;
    case ShipKind.submarine:
      c.shape('M30,50 C30,28 62,14 118,12 C176,10 226,22 262,36 C280,42 292,46 296,50 C292,54 280,58 262,64 C226,78 176,90 118,88 C62,86 30,72 30,50 Z', fillColor: const Color(0xFF93382A), inkColor: ink, inkWidth: 3);
      c.fill('M42,50 C42,34 68,22 120,20 C174,18 220,30 254,42 C266,46 274,48 278,50 C274,52 266,54 254,58 C220,70 174,82 120,80 C68,78 42,66 42,50 Z', const Color(0xFFC1543F));
      polyp(74, 24, r: 12, innerR: 15);
      polyp(74, 76, r: 12, innerR: 15);
      polyp(140, 18, r: 11, innerR: 14);
      polyp(140, 82, r: 11, innerR: 14);
      c.shape('M62,50 C62,36 86,26 122,26 C160,26 190,38 210,50 C190,62 160,74 122,74 C86,74 62,64 62,50 Z', fillColor: const Color(0xFFA34432), inkColor: ink, inkWidth: 2.4);
      c.shape('M78,50 C78,40 96,34 122,34 C150,34 172,42 188,50 C172,58 150,66 122,66 C96,66 78,60 78,50 Z', fillColor: const Color(0xFFC1543F), inkColor: ink, inkWidth: 2);
      c.shape('M96,50 C96,44 108,40 124,40 C142,40 156,45 166,50 C156,55 142,60 124,60 C108,60 96,56 96,50 Z', fillColor: const Color(0xFFE0715A), inkColor: ink, inkWidth: 1.8);
      c.circle(126, 50, 7, fillColor: const Color(0xFFFFD2BE), inkColor: ink, inkWidth: 1.8);
      c.circle(126, 50, 10, inkColor: ink, inkWidth: 1, inkOpacity: 0.5);
      c.circle(126, 50, 13, inkColor: ink, inkWidth: 0.8, inkOpacity: 0.32);
      c.shape('M212,36 C230,30 250,32 264,38 C248,42 230,42 212,42 Z', fillColor: const Color(0xFFFF9E7A), inkColor: ink, inkWidth: 2.2);
      c.shape('M212,64 C230,70 250,68 264,62 C248,58 230,58 212,58 Z', fillColor: const Color(0xFFFF9E7A), inkColor: ink, inkWidth: 2.2);
      c.shape('M30,50 C18,42 8,44 6,50 C10,56 18,58 30,50 Z', fillColor: const Color(0xFFA34432), inkColor: ink, inkWidth: 2.2);
      c.circle(230, 50, 5.4, fillColor: ink, fillOpacity: 0.55);
      c.circle(252, 50, 4.4, fillColor: ink, fillOpacity: 0.45);
      break;
    case ShipKind.destroyer:
      c.shape('M138,50 C138,26 168,12 208,14 C250,16 282,30 294,50 C282,70 250,84 208,86 C168,88 138,74 138,50 Z', fillColor: const Color(0xFF93382A), inkColor: ink, inkWidth: 2.8);
      c.fill('M148,50 C148,32 174,20 208,22 C246,24 272,34 282,50 C272,66 246,78 208,78 C174,80 148,68 148,50 Z', const Color(0xFFC1543F));
      c.shape(_poly('138,42 112,32 136,48'), fillColor: const Color(0xFF93382A), inkColor: ink, inkWidth: 2.2);
      c.shape(_poly('138,58 112,68 136,52'), fillColor: const Color(0xFF93382A), inkColor: ink, inkWidth: 2.2);
      c.shape(_poly('144,30 124,14 142,38'), fillColor: const Color(0xFF93382A), inkColor: ink, inkWidth: 2);
      c.shape(_poly('144,70 124,86 142,62'), fillColor: const Color(0xFF93382A), inkColor: ink, inkWidth: 2);
      c.shape(_poly('170,20 164,4 178,24'), fillColor: const Color(0xFFC1543F), inkColor: ink, inkWidth: 2);
      c.shape(_poly('170,80 164,96 178,76'), fillColor: const Color(0xFFC1543F), inkColor: ink, inkWidth: 2);
      polyp(180, 26, r: 9, innerR: 12);
      polyp(180, 74, r: 9, innerR: 12);
      c.ellipse(200, 50, 26, 19, fillColor: const Color(0xFFA34432), inkColor: ink, inkWidth: 2.6);
      c.shape('M178,42 C190,36 214,36 222,42 C212,47 190,47 178,42 Z', fillColor: const Color(0xFFFF9E7A));
      c.circle(200, 55, 6.4, fillColor: const Color(0xFFFFD2BE), inkColor: ink, inkWidth: 1.8);
      c.circle(200, 55, 9.4, inkColor: ink, inkWidth: 1, inkOpacity: 0.5);
      c.circle(200, 55, 12.4, inkColor: ink, inkWidth: 0.8, inkOpacity: 0.32);
      c.fill('M256,46 C272,44 286,46 294,50 C284,54 270,55 256,54 Z', ink);
      c.circle(248, 50, 15, fillColor: const Color(0xFFE0715A), inkColor: ink, inkWidth: 2.6);
      c.circle(240, 38, 8, fillColor: const Color(0xFFE0715A), inkColor: ink, inkWidth: 2.2);
      c.circle(240, 62, 7, fillColor: const Color(0xFFE0715A), inkColor: ink, inkWidth: 2.2);
      c.circle(248, 50, 5.4, fillColor: const Color(0xFFFFD2BE));
      c.circle(248, 50, 8.4, inkColor: ink, inkWidth: 1, inkOpacity: 0.5);
      c.circle(248, 50, 11.4, inkColor: ink, inkWidth: 0.8, inkOpacity: 0.32);
      c.circle(164, 50, 8, fillColor: const Color(0xFFE0715A), inkColor: ink, inkWidth: 2.2);
      c.circle(164, 50, 3, fillColor: const Color(0xFFFFD2BE));
      c.circle(164, 50, 6, inkColor: ink, inkWidth: 1, inkOpacity: 0.5);
      c.circle(164, 50, 9, inkColor: ink, inkWidth: 0.8, inkOpacity: 0.32);
      break;
  }
}

// ============================================================ MIDNIGHT ===
// Low, canted, radar-quiet stealth facets — nothing sticks out that
// doesn't have to.

void _midnight(FamilyCanvas c, ShipKind k) {
  const ink = Color(0xFF0A0E15);
  const accent = Color(0xFF4B72A8);
  switch (k) {
    case ShipKind.carrier:
      c.shape('M22,50 L52,22 L214,18 L296,50 L214,82 L52,78 Z', fillColor: const Color(0xFF151B26), inkColor: ink, inkWidth: 3, join: StrokeJoin.miter);
      c.fill('M34,50 L58,28 L212,24 L282,50 L212,76 L58,72 Z', const Color(0xFF232B3A));
      c.shape('M44,50 L64,32 L210,29 L270,50 L210,71 L64,68 Z', fillColor: const Color(0xFF1B2230), inkColor: accent, inkWidth: 2, join: StrokeJoin.miter);
      c.strokeDashed('M52,50 L268,50', accent, 2.6, [18, 14], opacity: 0.85);
      c.stroke('M78,34 L78,66 M132,31 L132,69 M186,30 L186,70', ink, 1.8, opacity: 0.5);
      c.rect(88, 38, 26, 10, fillColor: const Color(0xBF0A0E15));
      c.rect(88, 52, 26, 10, fillColor: const Color(0xBF0A0E15));
      c.shape(_poly('142,42 162,50 142,58 148,50'), fillColor: const Color(0xFF33405A), inkColor: ink, inkWidth: 1.6);
      c.shape(_poly('188,42 208,50 188,58 194,50'), fillColor: const Color(0xFF33405A), inkColor: ink, inkWidth: 1.6);
      c.shape(_poly('228,44 248,50 228,56 234,50'), fillColor: const Color(0xFF33405A), inkColor: ink, inkWidth: 1.4);
      c.shape(_poly('52,36 74,32 74,44 52,44'), fillColor: const Color(0xFF33405A), inkColor: ink, inkWidth: 2);
      c.shape(_poly('52,64 74,68 74,56 52,56'), fillColor: const Color(0xFF33405A), inkColor: ink, inkWidth: 2);
      c.line(56, 40, 70, 39, accent, 2);
      c.line(56, 60, 70, 61, accent, 2);
      c.shape(_poly('252,44 268,50 252,56'), fillColor: accent, inkColor: ink, inkWidth: 1.8);
      break;
    case ShipKind.battleship:
      c.shape('M16,50 L48,16 L208,12 L298,50 L208,88 L48,84 Z', fillColor: const Color(0xFF151B26), inkColor: ink, inkWidth: 3, join: StrokeJoin.miter);
      c.fill('M28,50 L54,22 L206,18 L284,50 L206,82 L54,78 Z', const Color(0xFF232B3A));
      c.shape('M38,50 L60,28 L204,24 L270,50 L204,76 L60,72 Z', fillColor: const Color(0xFF1B2230), inkColor: accent, inkWidth: 2, join: StrokeJoin.miter);
      c.rect(230, 40, 62, 7, fillColor: ink);
      c.rect(230, 53, 62, 7, fillColor: ink);
      c.shape(_poly('196,26 236,38 244,50 236,62 196,74 182,50'), fillColor: const Color(0xFF33405A), inkColor: ink, inkWidth: 3, join: StrokeJoin.miter);
      c.fill(_poly('196,26 236,38 234,48 194,38'), accent);
      c.circle(210, 50, 7, fillColor: const Color(0xFF151B26), inkColor: ink, inkWidth: 2);
      c.rect(72, 30, 44, 18, fillColor: const Color(0xFF151B26), inkColor: ink, inkWidth: 2.4);
      c.rect(76, 33, 9, 5, fillColor: accent);
      c.rect(89, 33, 9, 5, fillColor: accent);
      c.rect(102, 33, 9, 5, fillColor: accent);
      c.rect(76, 40, 9, 5, fillColor: accent);
      c.rect(89, 40, 9, 5, fillColor: accent);
      c.rect(102, 40, 9, 5, fillColor: accent);
      c.rect(72, 52, 44, 18, fillColor: const Color(0xFF151B26), inkColor: ink, inkWidth: 2.4);
      c.rect(76, 55, 9, 5, fillColor: accent);
      c.rect(89, 55, 9, 5, fillColor: accent);
      c.rect(102, 55, 9, 5, fillColor: accent);
      c.rect(76, 62, 9, 5, fillColor: accent);
      c.rect(89, 62, 9, 5, fillColor: accent);
      c.rect(102, 62, 9, 5, fillColor: accent);
      c.shape(_poly('130,34 172,30 182,50 172,70 130,66 122,50'), fillColor: const Color(0xFF1B2230), inkColor: ink, inkWidth: 2.6, join: StrokeJoin.miter);
      c.fill(_poly('130,34 172,30 174,42 128,45'), const Color(0xFF33405A));
      c.line(132, 50, 176, 50, accent, 2.6);
      c.shape(_poly('48,42 66,38 66,50 48,50'), fillColor: const Color(0xFF33405A), inkColor: ink, inkWidth: 2);
      c.shape(_poly('48,58 66,62 66,50 48,50'), fillColor: const Color(0xFF33405A), inkColor: ink, inkWidth: 2);
      break;
    case ShipKind.cruiser:
      c.shape('M26,50 L56,26 L204,20 L296,50 L204,80 L56,74 Z', fillColor: const Color(0xFF151B26), inkColor: ink, inkWidth: 2.8, join: StrokeJoin.miter);
      c.fill('M38,50 L62,32 L202,26 L280,50 L202,74 L62,68 Z', const Color(0xFF232B3A));
      c.shape('M48,50 L68,36 L200,31 L266,50 L200,69 L68,64 Z', fillColor: const Color(0xFF1B2230), inkColor: accent, inkWidth: 1.8, join: StrokeJoin.miter);
      c.shape(_poly('118,36 164,32 174,50 164,68 118,64 110,50'), fillColor: const Color(0xFF33405A), inkColor: ink, inkWidth: 2.6, join: StrokeJoin.miter);
      c.fill(_poly('118,36 164,32 166,42 116,46'), accent);
      c.shape(_poly('134,44 154,44 158,50 154,56 134,56 130,50'), fillColor: const Color(0xFF151B26), inkColor: ink, inkWidth: 1.8);
      c.rect(216, 47, 52, 6, fillColor: ink);
      c.shape(_poly('192,36 220,44 226,50 220,56 192,64 182,50'), fillColor: const Color(0xFF33405A), inkColor: ink, inkWidth: 2.6, join: StrokeJoin.miter);
      c.circle(202, 50, 5.4, fillColor: const Color(0xFF151B26), inkColor: ink, inkWidth: 1.8);
      c.rect(76, 38, 24, 9, fillColor: const Color(0xBF0A0E15));
      c.rect(76, 53, 24, 9, fillColor: const Color(0xBF0A0E15));
      c.shape(_poly('56,42 74,38 74,50 56,50'), fillColor: const Color(0xFF33405A), inkColor: ink, inkWidth: 1.8);
      c.shape(_poly('56,58 74,62 74,50 56,50'), fillColor: const Color(0xFF33405A), inkColor: ink, inkWidth: 1.8);
      c.line(182, 30, 196, 34, accent, 2);
      c.line(182, 70, 196, 66, accent, 2);
      break;
    case ShipKind.submarine:
      c.shape('M28,50 C28,38 58,30 108,29 L214,29 L288,50 L214,71 L108,71 C58,70 28,62 28,50 Z', fillColor: const Color(0xFF151B26), inkColor: ink, inkWidth: 2.8, join: StrokeJoin.miter);
      c.fill('M40,50 C40,42 64,35 110,34 L212,34 L272,50 L212,66 L110,66 C64,65 40,58 40,50 Z', const Color(0xFF232B3A));
      c.shape('M52,50 C52,44 72,39 112,38 L208,38 L256,50 L208,62 L112,62 C72,61 52,56 52,50 Z', fillColor: const Color(0xFF1B2230), inkColor: accent, inkWidth: 1.8, join: StrokeJoin.miter);
      c.ellipse(146, 50, 30, 14, fillColor: const Color(0xFF33405A), inkColor: ink, inkWidth: 2.6);
      c.ellipse(142, 45, 19, 5.4, fillColor: accent);
      c.line(120, 50, 172, 50, ink, 2.2, opacity: 0.8);
      c.shape(_poly('112,29 92,12 84,14 104,31'), fillColor: const Color(0xFF33405A), inkColor: ink, inkWidth: 2.2, join: StrokeJoin.miter);
      c.shape(_poly('112,71 92,88 84,86 104,69'), fillColor: const Color(0xFF33405A), inkColor: ink, inkWidth: 2.2, join: StrokeJoin.miter);
      c.shape(_poly('196,32 214,18 222,22 204,36'), fillColor: const Color(0xFF33405A), inkColor: ink, inkWidth: 2, join: StrokeJoin.miter);
      c.shape(_poly('196,68 214,82 222,78 204,64'), fillColor: const Color(0xFF33405A), inkColor: ink, inkWidth: 2, join: StrokeJoin.miter);
      c.rect(66, 44, 18, 6, fillColor: const Color(0xB30A0E15));
      c.rect(66, 52, 18, 6, fillColor: const Color(0xB30A0E15));
      c.shape(_poly('256,46 274,50 256,54'), fillColor: accent, inkColor: ink, inkWidth: 1.6);
      c.shape('M28,50 L14,42 L20,50 L14,58 Z', fillColor: const Color(0xFF1B2230), inkColor: ink, inkWidth: 2);
      break;
    case ShipKind.destroyer:
      c.shape('M84,50 L112,26 L212,22 L296,50 L212,78 L112,74 Z', fillColor: const Color(0xFF151B26), inkColor: ink, inkWidth: 2.8, join: StrokeJoin.miter);
      c.fill('M96,50 L118,32 L210,28 L280,50 L210,72 L118,68 Z', const Color(0xFF232B3A));
      c.shape('M106,50 L124,37 L208,33 L266,50 L208,67 L124,63 Z', fillColor: const Color(0xFF1B2230), inkColor: accent, inkWidth: 1.8, join: StrokeJoin.miter);
      c.shape(_poly('126,26 168,32 158,44 118,38'), fillColor: const Color(0xFF33405A), inkColor: ink, inkWidth: 2.4, join: StrokeJoin.miter);
      c.shape(_poly('126,74 168,68 158,56 118,62'), fillColor: const Color(0xFF33405A), inkColor: ink, inkWidth: 2.4, join: StrokeJoin.miter);
      c.line(128, 31, 160, 35, accent, 1.8);
      c.line(128, 69, 160, 65, accent, 1.8);
      c.shape(_poly('170,38 198,34 208,50 198,66 170,62 162,50'), fillColor: const Color(0xFF1B2230), inkColor: ink, inkWidth: 2.6, join: StrokeJoin.miter);
      c.fill(_poly('170,38 198,34 200,44 168,47'), const Color(0xFF33405A));
      c.line(172, 50, 202, 50, accent, 2.4);
      c.rect(232, 47, 46, 6, fillColor: ink);
      c.shape(_poly('212,38 236,44 242,50 236,56 212,62 204,50'), fillColor: const Color(0xFF33405A), inkColor: ink, inkWidth: 2.6, join: StrokeJoin.miter);
      c.circle(222, 50, 5, fillColor: const Color(0xFF151B26), inkColor: ink, inkWidth: 1.8);
      c.shape(_poly('112,44 128,42 128,50 112,50'), fillColor: const Color(0xFF33405A), inkColor: ink, inkWidth: 1.8);
      c.shape(_poly('112,56 128,58 128,50 112,50'), fillColor: const Color(0xFF33405A), inkColor: ink, inkWidth: 1.8);
      break;
  }
}

// =============================================================== TOXIC ===
// Welded from three other ships and still leaking — three mismatched
// segments with visible weld steps.

void _toxic(FamilyCanvas c, ShipKind k) {
  const ink = Color(0xFF1C210A);
  const accent = Color(0xFFA3E635);
  switch (k) {
    case ShipKind.carrier:
      c.shape('M20,50 L38,22 L118,18 L124,26 L206,14 L262,30 L294,50 L258,74 L204,86 L126,76 L118,82 L38,78 Z', fillColor: const Color(0xFF4C551D), inkColor: ink, inkWidth: 3, join: StrokeJoin.miter);
      c.fill('M32,50 L46,28 L120,24 L126,32 L204,21 L254,35 L280,50 L250,69 L202,80 L128,71 L120,76 L46,72 Z', const Color(0xFF6E7A2E));
      c.stroke('M62,26 L62,74 M124,24 L126,76 M196,18 L200,82', ink, 2.2, opacity: 0.6);
      c.shape(_poly('42,34 118,30 120,68 44,64'), fillColor: const Color(0xFF575F22), inkColor: ink, inkWidth: 2.6, join: StrokeJoin.miter);
      c.rotated(-2, 165, 48, () {
        c.shape(_poly('126,26 200,22 204,74 128,70'), fillColor: const Color(0xFF575F22), inkColor: ink, inkWidth: 2.6, join: StrokeJoin.miter);
      });
      c.shape(_poly('208,28 258,38 256,64 206,70'), fillColor: const Color(0xFF575F22), inkColor: ink, inkWidth: 2.6, join: StrokeJoin.miter);
      c.strokeDashed('M48,50 L250,50', accent, 3, [12, 9], opacity: 0.85);
      c.shape(_poly('86,42 106,50 86,58 92,50'), fillColor: const Color(0xFFD9F99D), inkColor: ink, inkWidth: 1.6);
      c.shape(_poly('150,42 170,50 150,58 156,50'), fillColor: const Color(0xFFD9F99D), inkColor: ink, inkWidth: 1.6);
      c.rotated(-5, 87, 43, () {
        c.rect(66, 34, 42, 18, r: 1, fillColor: const Color(0xFF8A9A38), inkColor: ink, inkWidth: 2.2);
      });
      c.circle(70, 38, 2, fillColor: ink);
      c.circle(102, 35, 2, fillColor: ink);
      c.circle(70, 49, 2, fillColor: ink);
      c.rect(212, 40, 34, 8, r: 2, fillColor: const Color(0xFF8A9A38), inkColor: ink, inkWidth: 2);
      c.circle(248, 44, 5, fillColor: const Color(0xFF575F22), inkColor: ink, inkWidth: 2);
      c.circle(42, 40, 7, fillColor: const Color(0xFF575F22), inkColor: ink, inkWidth: 2.2);
      c.circle(42, 60, 7, fillColor: const Color(0xFF575F22), inkColor: ink, inkWidth: 2.2);
      c.circle(42, 40, 2.6, fillColor: accent);
      c.stroke('M118,82 Q112,90 118,96', accent, 2.4, opacity: 0.85);
      c.circle(119, 97, 2.4, fillColor: accent, fillOpacity: 0.8);
      break;
    case ShipKind.battleship:
      c.shape('M16,50 L34,18 L112,14 L120,24 L204,10 L258,26 L298,50 L256,76 L202,90 L122,78 L112,86 L34,82 Z', fillColor: const Color(0xFF4C551D), inkColor: ink, inkWidth: 3, join: StrokeJoin.miter);
      c.fill('M28,50 L42,24 L114,20 L122,30 L202,17 L250,31 L282,50 L248,71 L200,84 L124,73 L114,80 L42,76 Z', const Color(0xFF6E7A2E));
      c.stroke('M58,24 L58,76 M120,22 L124,78 M194,14 L198,86', ink, 2.2, opacity: 0.6);
      c.rotated(3, 158, 50, () {
        c.rect(130, 34, 56, 32, r: 1, fillColor: const Color(0xFF8A9A38), inkColor: ink, inkWidth: 2.4);
      });
      c.circle(136, 40, 2.2, fillColor: ink);
      c.circle(180, 42, 2.2, fillColor: ink);
      c.circle(136, 60, 2.2, fillColor: ink);
      c.circle(180, 62, 2.2, fillColor: ink);
      c.rect(236, 40, 58, 7, fillColor: ink);
      c.rect(236, 52, 48, 7, fillColor: ink);
      c.rect(204, 30, 40, 40, r: 3, fillColor: const Color(0xFF8A9A38), inkColor: ink, inkWidth: 2.8);
      c.rect(204, 30, 40, 10, r: 3, fillColor: accent);
      c.circle(224, 55, 6, fillColor: const Color(0xFF575F22), inkColor: ink, inkWidth: 2);
      c.rect(94, 44, 42, 6, fillColor: ink);
      c.rect(94, 53, 34, 6, fillColor: ink);
      c.rect(62, 34, 34, 34, r: 8, fillColor: const Color(0xFF8A9A38), inkColor: ink, inkWidth: 2.6);
      c.rect(62, 34, 34, 9, r: 8, fillColor: accent);
      c.circle(79, 56, 5, fillColor: const Color(0xFF575F22), inkColor: ink, inkWidth: 1.8);
      c.rect(122, 20, 10, 26, r: 3, fillColor: const Color(0xFF575F22), inkColor: ink, inkWidth: 2);
      c.rect(122, 56, 10, 26, r: 3, fillColor: const Color(0xFF575F22), inkColor: ink, inkWidth: 2);
      c.shape(_poly('188,24 214,20 216,26 190,30'), fillColor: const Color(0xFF575F22), inkColor: ink, inkWidth: 2);
      c.circle(42, 38, 7, fillColor: const Color(0xFF575F22), inkColor: ink, inkWidth: 2.2);
      c.circle(42, 62, 7, fillColor: const Color(0xFF575F22), inkColor: ink, inkWidth: 2.2);
      c.stroke('M112,86 Q106,94 112,99', accent, 2.4, opacity: 0.85);
      break;
    case ShipKind.cruiser:
      c.shape('M26,50 L44,26 L114,22 L120,30 L202,18 L252,32 L292,50 L250,70 L200,82 L122,72 L114,78 L44,74 Z', fillColor: const Color(0xFF4C551D), inkColor: ink, inkWidth: 2.8, join: StrokeJoin.miter);
      c.fill('M38,50 L52,32 L116,28 L122,36 L200,25 L244,37 L278,50 L242,65 L198,76 L124,67 L116,72 L52,68 Z', const Color(0xFF6E7A2E));
      c.stroke('M64,30 L64,70 M122,28 L124,72 M194,22 L198,78', ink, 2, opacity: 0.55);
      c.shape(_poly('252,32 292,50 250,70 254,50'), fillColor: const Color(0xFF575F22), inkColor: ink, inkWidth: 2.4, join: StrokeJoin.miter);
      c.fill(_poly('252,36 282,50 252,64 256,50'), const Color(0xFF8A9A38));
      c.rotated(-3, 151, 50, () {
        c.rect(128, 34, 46, 32, r: 1, fillColor: const Color(0xFF8A9A38), inkColor: ink, inkWidth: 2.4);
      });
      c.circle(134, 40, 2, fillColor: ink);
      c.circle(168, 38, 2, fillColor: ink);
      c.circle(134, 60, 2, fillColor: ink);
      c.rect(204, 46, 44, 6, fillColor: ink);
      c.rect(184, 36, 32, 28, r: 3, fillColor: const Color(0xFF8A9A38), inkColor: ink, inkWidth: 2.6);
      c.rect(184, 36, 32, 8, r: 3, fillColor: accent);
      c.circle(80, 38, 8, fillColor: const Color(0xFF575F22), inkColor: ink, inkWidth: 2.2);
      c.circle(80, 62, 8, fillColor: const Color(0xFF575F22), inkColor: ink, inkWidth: 2.2);
      c.circle(102, 38, 8, fillColor: const Color(0xFF575F22), inkColor: ink, inkWidth: 2.2);
      c.circle(102, 62, 8, fillColor: const Color(0xFF575F22), inkColor: ink, inkWidth: 2.2);
      c.circle(80, 38, 3, fillColor: accent);
      c.circle(102, 62, 3, fillColor: accent);
      c.rect(48, 44, 16, 12, r: 2, fillColor: const Color(0xFF575F22), inkColor: ink, inkWidth: 2);
      c.stroke('M114,78 Q108,86 114,92', accent, 2.2, opacity: 0.8);
      break;
    case ShipKind.submarine:
      c.shape('M24,50 L44,32 L96,28 L102,34 L166,28 L172,36 L232,32 L266,42 L288,50 L264,60 L230,70 L172,66 L166,74 L102,68 L96,74 L44,70 Z', fillColor: const Color(0xFF4C551D), inkColor: ink, inkWidth: 2.8, join: StrokeJoin.miter);
      c.fill('M36,50 L52,37 L98,34 L104,40 L164,34 L170,42 L230,38 L258,45 L274,50 L256,57 L228,64 L170,60 L164,66 L104,62 L98,68 L52,65 Z', const Color(0xFF6E7A2E));
      c.stroke('M100,32 L100,70 M168,30 L170,70 L168,30 M230,34 L230,68', ink, 2.4, opacity: 0.6);
      c.rect(112, 36, 48, 28, r: 4, fillColor: const Color(0xFF8A9A38), inkColor: ink, inkWidth: 2.6);
      c.rect(112, 36, 48, 8, r: 4, fillColor: accent);
      c.circle(150, 50, 6, fillColor: const Color(0xFF575F22), inkColor: ink, inkWidth: 2);
      c.circle(120, 58, 2.4, fillColor: ink);
      c.circle(120, 41, 2.4, fillColor: ink);
      c.shape('M96,28 L78,12 L70,14 L86,30 Z', fillColor: const Color(0xFF8A9A38), inkColor: ink, inkWidth: 2.2, join: StrokeJoin.miter);
      c.shape('M96,74 L78,90 L70,88 L86,72 Z', fillColor: const Color(0xFF8A9A38), inkColor: ink, inkWidth: 2.2, join: StrokeJoin.miter);
      c.rect(188, 40, 34, 8, r: 2, fillColor: const Color(0xFF575F22), inkColor: ink, inkWidth: 2);
      c.rect(188, 52, 26, 8, r: 2, fillColor: const Color(0xFF575F22), inkColor: ink, inkWidth: 2);
      c.circle(60, 50, 8, fillColor: const Color(0xFF575F22), inkColor: ink, inkWidth: 2.2);
      c.circle(60, 50, 3, fillColor: accent);
      c.stroke('M166,74 Q160,82 166,88', accent, 2.4, opacity: 0.85);
      c.circle(167, 89, 2.4, fillColor: accent, fillOpacity: 0.8);
      c.shape(_poly('288,50 300,44 296,50 300,56'), fillColor: const Color(0xFF575F22), inkColor: ink, inkWidth: 2);
      break;
    case ShipKind.destroyer:
      c.shape('M108,50 L128,26 L196,22 L202,30 L246,26 L292,50 L244,74 L202,70 L196,78 L128,74 Z', fillColor: const Color(0xFF4C551D), inkColor: ink, inkWidth: 2.8, join: StrokeJoin.miter);
      c.fill('M120,50 L136,32 L198,28 L204,36 L242,33 L276,50 L240,67 L204,64 L198,72 L136,68 Z', const Color(0xFF6E7A2E));
      c.stroke('M144,30 L144,70 M200,26 L204,74', ink, 2.2, opacity: 0.55);
      c.shape(_poly('108,42 82,32 106,48'), fillColor: const Color(0xFF575F22), inkColor: ink, inkWidth: 2.2);
      c.shape(_poly('108,58 82,68 106,52'), fillColor: const Color(0xFF575F22), inkColor: ink, inkWidth: 2.2);
      c.rotated(2, 171, 50, () {
        c.rect(150, 34, 42, 32, r: 1, fillColor: const Color(0xFF8A9A38), inkColor: ink, inkWidth: 2.4);
      });
      c.circle(156, 40, 2, fillColor: ink);
      c.circle(186, 42, 2, fillColor: ink);
      c.circle(156, 60, 2, fillColor: ink);
      c.rect(242, 40, 46, 7, fillColor: ink);
      c.rect(242, 53, 38, 7, fillColor: ink);
      c.rect(212, 34, 34, 32, r: 3, fillColor: const Color(0xFF8A9A38), inkColor: ink, inkWidth: 2.6);
      c.rect(212, 34, 34, 9, r: 3, fillColor: accent);
      c.circle(229, 57, 5, fillColor: const Color(0xFF575F22), inkColor: ink, inkWidth: 1.8);
      c.circle(132, 40, 7, fillColor: const Color(0xFF575F22), inkColor: ink, inkWidth: 2.2);
      c.circle(132, 60, 7, fillColor: const Color(0xFF575F22), inkColor: ink, inkWidth: 2.2);
      c.circle(132, 40, 2.6, fillColor: accent);
      c.stroke('M196,78 Q190,86 196,92', accent, 2.2, opacity: 0.8);
      break;
  }
}
