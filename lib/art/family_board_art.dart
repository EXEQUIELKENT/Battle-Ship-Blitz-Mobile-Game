import 'package:flutter/material.dart';

import 'fleet_family.dart';
import 'svg_path.dart';

/// The six battlefields, ported from `ThemedBoard.dc.html`.
///
/// The design authors each board as a 400×400 field carrying exactly the
/// game's own 10×10 grid at 40 units a cell, so everything here lands on
/// real cell boundaries with no re-derivation. That is the whole
/// constraint the themes work under, in the design's words: "Coordinates,
/// cell count and tap targets do not change — a marker is still one cell,
/// drawn differently."
///
/// Split into three entry points matching how the battle grid already
/// paints: the static field (cached, repaints only on real state change),
/// and the two markers (drawn per marked cell).
const Rect _boardBox = Rect.fromLTWH(0, 0, 400, 400);

/// Design-space size of one cell. The game's `kBoardSize` is 10 and the
/// board is 400 units, so this is fixed by construction.
const double _cellUnits = 40;

/// The design's fixed particle seed — an 18-point scatter used for
/// snowfall (arctic) and rising embers (volcanic). Deliberately a
/// constant rather than a random draw so the field looks identical on
/// both devices in a network match, and so nothing has to tick.
const List<List<double>> _seed = [
  [23, 61, 3], [88, 140, 2.2], [151, 44, 2.6], [212, 118, 3.2],
  [274, 68, 2], [336, 152, 2.8], [47, 205, 2.4], [119, 268, 3],
  [186, 231, 2], [255, 296, 2.6], [318, 244, 2.2], [372, 318, 3],
  [63, 349, 2.4], [141, 378, 2], [228, 356, 2.8], [296, 386, 2.2],
  [364, 26, 2.6], [16, 132, 2],
];

/// Paints the water, texture, gridlines and any fixed props for [family].
void paintFamilyBoard(Canvas canvas, Size size, FleetFamily family) {
  final c = FamilyCanvas.stretch(canvas, size, _boardBox);
  switch (family.id) {
    case FleetFamilyId.pirate:
      _pirateField(c, family);
      break;
    case FleetFamilyId.naval:
      _navalField(c, family);
      break;
    case FleetFamilyId.steam:
      _steamField(c, family);
      break;
    case FleetFamilyId.arctic:
      _arcticField(c, family);
      break;
    case FleetFamilyId.volcanic:
      _volcanicField(c, family);
      break;
    case FleetFamilyId.scifi:
      _scifiField(c, family);
      break;
  }
}

/// Draws the family's gridlines. Split out because several families lay
/// texture *under* the lines and props *over* them.
void _gridlines(
  FamilyCanvas c,
  FleetFamily f, {
  double opacity = 1,
  List<double>? dash,
}) {
  for (var i = 1; i < 10; i++) {
    final p = i * _cellUnits;
    c.line(p, 0, p, 400, f.board.line, f.board.lineWidth,
        opacity: opacity, dash: dash);
    c.line(0, p, 400, p, f.board.line, f.board.lineWidth,
        opacity: opacity, dash: dash);
  }
}

// ------------------------------------------------------------- FIELDS ---

void _pirateField(FamilyCanvas c, FleetFamily f) {
  c.rect(0, 0, 400, 400, fillColor: f.board.field);
  // Mottled brine cells.
  const mottle = Color(0xFF26504F);
  for (final r in const [
    [40.0, 0.0], [120.0, 80.0], [280.0, 40.0],
    [200.0, 200.0], [320.0, 280.0], [80.0, 320.0],
  ]) {
    c.rect(r[0], r[1], 40, 40, fillColor: mottle);
  }
  _gridlines(c, f, opacity: 0.45, dash: const [7, 6]);
  // Drifting swell lines.
  const swell = Color(0xFF1E3A34);
  c.stroke(
      'M0,60 q40,-12 80,0 q40,12 80,0 q40,-12 80,0 q40,12 80,0 q40,-12 80,0',
      swell, 4,
      opacity: 0.35);
  c.stroke(
      'M0,300 q40,12 80,0 q40,-12 80,0 q40,12 80,0 q40,-12 80,0 q40,12 80,0',
      swell, 4,
      opacity: 0.35);
}

void _navalField(FamilyCanvas c, FleetFamily f) {
  c.rect(0, 0, 400, 400, fillColor: f.board.field);
  // Three range rings.
  for (final r in const [70.0, 140.0, 200.0]) {
    c.circle(200, 200, r,
        inkColor: const Color(0xFF7FB2CC), inkWidth: 2, inkOpacity: 0.22);
  }
  _gridlines(c, f, opacity: 0.4);
  // Row ticks down the left edge.
  for (var i = 0; i < 10; i++) {
    final y = i * _cellUnits + _cellUnits / 2;
    c.line(0, y, 10, y, const Color(0xFFCFE0EA), 2.4, opacity: 0.5);
  }
}

void _steamField(FamilyCanvas c, FleetFamily f) {
  c.rect(0, 0, 400, 400, fillColor: f.board.field);
  // Riveted quarter-plates with visible seams.
  //
  // Brass, not steel. These were originally a blue-grey plate, which put
  // Brass Works and Fleet Command within a few points of each other —
  // near-identical at store-card size and hard to tell apart even at full
  // board size. Two of six battlefields reading as the same battlefield
  // is precisely the failure the "structural, not chromatic" rule exists
  // to catch, and here it was the colour doing the damage rather than the
  // structure: the plates, seams and bolt grid were always right.
  const plate = Color(0xFF6E5638);
  c.rect(0, 0, 200, 200, fillColor: plate);
  c.rect(200, 200, 200, 200, fillColor: plate);
  _gridlines(c, f, opacity: 0.5);
  // A bolt at every second intersection.
  for (var r = 1; r < 6; r++) {
    for (var col = 1; col < 6; col++) {
      c.circle(col * 80, r * 80, 3.4,
          fillColor: const Color(0xFF2E2317), fillOpacity: 0.8);
    }
  }
}

void _arcticField(FamilyCanvas c, FleetFamily f) {
  c.rect(0, 0, 400, 400, fillColor: f.board.field);
  // Irregular floes over open water.
  const floe = Color(0xFF5C94B2);
  const crack = Color(0xFFDFF4FC);
  for (final d in const [
    'M10,20 L90,6 L140,50 L96,96 L20,80 Z',
    'M210,30 L300,20 L340,70 L280,110 L216,88 Z',
    'M40,190 L130,180 L170,240 L100,290 L36,254 Z',
    'M250,200 L360,210 L380,290 L290,320 L236,266 Z',
    'M110,320 L200,330 L210,390 L120,394 Z',
  ]) {
    c.shape(d,
        fillColor: floe, inkColor: crack, inkWidth: 2.5, inkOpacity: 0.45);
  }
  _gridlines(c, f, opacity: 0.42);
  // Falling snow.
  for (final s in _seed) {
    c.circle(s[0], s[1], s[2], fillColor: Colors.white, fillOpacity: 0.55);
  }
}

void _volcanicField(FamilyCanvas c, FleetFamily f) {
  c.rect(0, 0, 400, 400, fillColor: f.board.field);
  // Basalt slabs.
  const slab = Color(0xFF2A1F22);
  c.fill('M0,0 L120,0 L90,60 L0,80 Z', slab);
  c.fill('M280,120 L400,90 L400,220 L300,200 Z', slab);
  c.fill('M60,240 L180,260 L140,340 L40,320 Z', slab);
  // Molten seams crossing three cells at a time.
  c.stroke('M0,120 L60,150 L40,210 L110,250', f.board.accent, 3,
      opacity: 0.55, cap: StrokeCap.round);
  c.stroke('M200,0 L230,70 L190,120 L240,180', f.board.accent, 3,
      opacity: 0.55, cap: StrokeCap.round);
  c.stroke('M400,300 L330,320 L300,390', f.board.accent, 3,
      opacity: 0.55, cap: StrokeCap.round);
  _gridlines(c, f, opacity: 0.45);
  // Rising embers.
  for (final s in _seed) {
    c.circle(s[0], s[1], s[2],
        fillColor: const Color(0xFFFF9A5A), fillOpacity: 0.6);
  }
}

void _scifiField(FamilyCanvas c, FleetFamily f) {
  c.rect(0, 0, 400, 400, fillColor: f.board.field);
  _gridlines(c, f, opacity: 0.55);
  // Cyan corner ticks.
  for (var r = 1; r < 6; r++) {
    for (var col = 1; col < 6; col++) {
      final x = col * 80.0, y = r * 80.0;
      c.line(x - 8, y, x + 8, y, f.board.accent, 2.4, opacity: 0.5);
      c.line(x, y - 8, x, y + 8, f.board.accent, 2.4, opacity: 0.5);
    }
  }
  // The scan band.
  c.rect(0, 150, 400, 34, fillColor: f.board.accent, fillOpacity: 0.07);
  // Holo range rings.
  c.circle(80, 320, 34,
      inkColor: f.board.accent, inkWidth: 2, inkOpacity: 0.25);
  c.circle(80, 320, 18,
      inkColor: f.board.accent, inkWidth: 2, inkOpacity: 0.25);
  c.circle(320, 70, 26,
      inkColor: f.board.accent, inkWidth: 2, inkOpacity: 0.25);
}

// ------------------------------------------------------------ MARKERS ---

/// Marker geometry is authored around the origin at roughly ±18 units on
/// a 40-unit cell, so a marker painted into a real cell just needs the
/// cell centre and the cell size.
FamilyCanvas _markerCanvas(Canvas canvas, Offset center, double cellSize) {
  final s = cellSize / _cellUnits;
  final half = _cellUnits / 2;
  canvas.save();
  canvas.translate(center.dx - half * s, center.dy - half * s);
  return FamilyCanvas.stretch(
    canvas,
    Size(cellSize, cellSize),
    const Rect.fromLTWH(0, 0, _cellUnits, _cellUnits),
  );
}

/// Draws this family's MISS marker centred on [center].
void paintFamilyMiss(
  Canvas canvas,
  Offset center,
  double cellSize,
  FleetFamily family,
) {
  final c = _markerCanvas(canvas, center, cellSize);
  const o = _cellUnits / 2; // marker origin inside the cell
  switch (family.id) {
    // Opacities here are deliberately high: a miss is drawn straight onto
    // whichever deck the shot landed on, and since a mark is themed by the
    // SHOOTER's gun, that can be any of the fifteen. See the note on the
    // scrim these sit on in `_StaticGridPainter.paint`.
    case FleetFamilyId.pirate:
      // Foam ring.
      c.circle(o, o, 13,
          inkColor: const Color(0xFFBEE3D8), inkWidth: 3, inkOpacity: 0.95);
      c.circle(o, o, 6,
          fillColor: const Color(0xFFBEE3D8), fillOpacity: 0.50);
      break;
    case FleetFamilyId.naval:
      // Hollow square.
      c.rect(o - 13, o - 13, 26, 26,
          inkColor: const Color(0xFFC3D6E2), inkWidth: 3);
      break;
    case FleetFamilyId.steam:
      // Brass valve.
      c.circle(o, o, 12, inkColor: const Color(0xFFE8BC63), inkWidth: 4);
      c.line(o - 7, o, o + 7, o, const Color(0xFFE8BC63), 4);
      break;
    case FleetFamilyId.arctic:
      // Frost star.
      const ice = Color(0xFFEAFBFF);
      c.line(o - 12, o, o + 12, o, ice, 3.4,
          opacity: 0.95, cap: StrokeCap.round);
      c.line(o - 6, o - 10, o + 6, o + 10, ice, 3.4,
          opacity: 0.95, cap: StrokeCap.round);
      c.line(o + 6, o - 10, o - 6, o + 10, ice, 3.4,
          opacity: 0.95, cap: StrokeCap.round);
      break;
    case FleetFamilyId.volcanic:
      // Ash puff cluster.
      const ash = Color(0xFFBDB2A8);
      c.circle(o - 4, o + 2, 9, fillColor: ash, fillOpacity: 0.90);
      c.circle(o + 6, o - 4, 7, fillColor: ash, fillOpacity: 0.75);
      c.circle(o + 2, o + 8, 5, fillColor: ash, fillOpacity: 0.60);
      break;
    case FleetFamilyId.scifi:
      // Hollow hex.
      c.stroke(
        'M$o,${o - 13} L${o + 11},${o - 6} L${o + 11},${o + 7} '
        'L$o,${o + 14} L${o - 11},${o + 7} L${o - 11},${o - 6} Z',
        const Color(0xFF6FE7FF),
        2.6,
        opacity: 0.95,
      );
      break;
  }
  canvas.restore();
}

/// Draws this family's HIT marker centred on [center].
void paintFamilyHit(
  Canvas canvas,
  Offset center,
  double cellSize,
  FleetFamily family,
) {
  final c = _markerCanvas(canvas, center, cellSize);
  const o = _cellUnits / 2;
  switch (family.id) {
    case FleetFamilyId.pirate:
      // Splintered black hole with a bronze burst.
      c.circle(o, o, 15, fillColor: const Color(0xFF1B1208));
      c.fill(
        'M$o,${o - 19} L${o + 4},${o - 6} L${o + 17},${o - 9} '
        'L${o + 7},$o L${o + 16},${o + 11} L${o + 3},${o + 7} '
        'L$o,${o + 20} L${o - 4},${o + 7} L${o - 16},${o + 10} '
        'L${o - 7},$o L${o - 17},${o - 10} L${o - 4},${o - 6} Z',
        const Color(0xFFC98A3E),
      );
      break;
    case FleetFamilyId.naval:
      // Red corner bracket with a centre dot.
      c.rect(o - 17, o - 17, 34, 34, fillColor: const Color(0xFF101820));
      const red = Color(0xFFE4483F);
      c.stroke(
        'M${o - 17},${o - 8} L${o - 17},${o - 17} L${o - 8},${o - 17} '
        'M${o + 8},${o - 17} L${o + 17},${o - 17} L${o + 17},${o - 8} '
        'M${o + 17},${o + 8} L${o + 17},${o + 17} L${o + 8},${o + 17} '
        'M${o - 8},${o + 17} L${o - 17},${o + 17} L${o - 17},${o + 8}',
        red,
        4,
      );
      c.circle(o, o, 6, fillColor: red);
      break;
    case FleetFamilyId.steam:
      // Gear collar around a glowing bore.
      c.circle(o, o, 17,
          inkColor: const Color(0xFFC99A3F), inkWidth: 9, dash: const [6, 7]);
      c.circle(o, o, 11, fillColor: const Color(0xFF1A1208));
      c.circle(o, o, 5, fillColor: const Color(0xFFFFC24A));
      break;
    case FleetFamilyId.arctic:
      // Shattered hole with radiating cracks.
      c.fill(
        'M$o,${o - 18} L${o + 14},${o - 11} L${o + 18},${o + 6} '
        'L${o + 6},${o + 18} L${o - 9},${o + 16} L${o - 18},${o + 2} '
        'L${o - 13},${o - 12} Z',
        const Color(0xFF132430),
      );
      const ice = Color(0xFFBDF1FF);
      c.line(o, o, o - 16, o - 12, ice, 3, cap: StrokeCap.round);
      c.line(o, o, o + 15, o - 9, ice, 3, cap: StrokeCap.round);
      c.line(o, o, o + 6, o + 17, ice, 3, cap: StrokeCap.round);
      c.line(o, o, o - 13, o + 12, ice, 3, cap: StrokeCap.round);
      break;
    case FleetFamilyId.volcanic:
      // Magma crater with a white-hot core.
      c.fill(
        'M$o,${o - 18} L${o + 15},${o - 10} L${o + 19},${o + 7} '
        'L${o + 4},${o + 18} L${o - 12},${o + 14} L${o - 18},$o '
        'L${o - 11},${o - 13} Z',
        const Color(0xFFFF6A2B),
      );
      c.fill(
        'M$o,${o - 11} L${o + 9},${o - 6} L${o + 11},${o + 4} '
        'L${o + 2},${o + 11} L${o - 7},${o + 8} L${o - 11},$o '
        'L${o - 7},${o - 8} Z',
        const Color(0xFFFFD08A),
      );
      c.circle(o, o, 4, fillColor: const Color(0xFFFFF6E0));
      break;
    case FleetFamilyId.scifi:
      // Filled hex.
      const hex = Color(0xFF6FE7FF);
      final d = 'M$o,${o - 18} L${o + 16},${o - 9} L${o + 16},${o + 9} '
          'L$o,${o + 18} L${o - 16},${o + 9} L${o - 16},${o - 9} Z';
      c.fill(d, hex, opacity: 0.28);
      c.stroke(d, hex, 3.5);
      c.circle(o, o, 6, fillColor: Colors.white);
      break;
  }
  canvas.restore();
}
