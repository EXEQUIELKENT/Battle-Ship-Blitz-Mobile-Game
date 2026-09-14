import 'package:flutter/material.dart';

import '../models/power_up.dart';
import 'svg_replay.dart';

/// POWER PLAY's twenty power-up icons, imported from the design's
/// `PowerUpIcon.dc.html` / `Power Play Redesign.dc.html`.
///
/// FEEDBACK ("add all of the power play designs, icons, effects,
/// randomizer"): the mode shipped with its power-up shown as a text chip
/// — the card's NAME plus "TAP TO AIM" — floating over the deck. Every
/// one of the twenty read identically at a glance, so the only way to
/// know what you were holding was to stop and read it.
///
/// The design gives each card a bespoke painted badge instead, and puts
/// three things in it:
///
///  * a **per-card background colour**, grouped by what the card DOES —
///    recon blues, damage reds, buff ambers, defensive slates, repair
///    greens, trap navies — so a family reads before the glyph does;
///  * a **bespoke glyph**, drawn verbatim from the design's SVG;
///  * a **rarity ring** whose SHAPE carries the rarity — solid for
///    common, dashed for uncommon, thin-with-six-studs for rare — not
///    colour alone, so it still reads for colourblind players. The ring
///    colour (steel / blue / gold) is the same shorthand the old text
///    chip used, kept as reinforcement rather than as the only signal.
///
/// The glyph markup is replayed through [paintSvgFragmentCached] rather
/// than hand-transcribed into Canvas calls, for the same reason the
/// legacy cannons and boards are: the fragments stay byte-faithful to
/// what was authored, and each one is recorded to a `ui.Picture` once and
/// replayed as a display list on every frame after.

/// The badge's fill, keyed by what the card does rather than by rarity —
/// see the class doc. Straight from the design's `BG` table.
const Map<PowerUpCard, Color> _bg = {
  // Recon — steel blue.
  PowerUpCard.sonar: Color(0xFF4A789A),
  PowerUpCard.spotter: Color(0xFF4A789A),
  PowerUpCard.reconSweep: Color(0xFF4A789A),
  // Buffs on your own gunnery — amber, with HOT SHOT hotter still.
  PowerUpCard.doubleTap: Color(0xFFF7B32B),
  PowerUpCard.hotShot: Color(0xFFF77F3F),
  PowerUpCard.rapidFire: Color(0xFFF7B32B),
  // Defensive/denial — dark slate.
  PowerUpCard.jam: Color(0xFF3D5468),
  PowerUpCard.counterBattery: Color(0xFF3D5468),
  PowerUpCard.decoy: Color(0xFF3D5468),
  // Repair — green.
  PowerUpCard.repair: Color(0xFF5BB381),
  PowerUpCard.patchCrew: Color(0xFF5BB381),
  // Traps laid on your own water — near-black navy.
  PowerUpCard.minefield: Color(0xFF243646),
  PowerUpCard.trapLine: Color(0xFF243646),
  // Repositioning — bright blue.
  PowerUpCard.scramble: Color(0xFF35A3D6),
  PowerUpCard.hardTurn: Color(0xFF2E8BC0),
  PowerUpCard.autoDodge: Color(0xFF4FC3C7),
  // Protection — a steel green-grey, next to the repair greens without
  // being mistaken for them: armour stops damage, it does not undo it.
  PowerUpCard.armourPlate: Color(0xFF6E8E7B),
  // Recon, but the covert end of it — darker than SONAR's open pinging.
  PowerUpCard.spyShip: Color(0xFF35506B),
  // Direct damage — reds, deeper for the heavier shapes.
  PowerUpCard.spray: Color(0xFFF25F5C),
  PowerUpCard.salvo: Color(0xFFF25F5C),
  PowerUpCard.depthCharge: Color(0xFFD64545),
  PowerUpCard.chainShot: Color(0xFFF25F5C),
  PowerUpCard.barrage: Color(0xFFD64545),
  PowerUpCard.crossFire: Color(0xFFF25F5C),
};

/// The badge fill for [card].
Color powerUpBg(PowerUpCard card) => _bg[card] ?? const Color(0xFF4A789A);

/// The rarity ring's colour. Reinforces the ring's SHAPE (see
/// [_paintRarityRing]), which is what actually carries the rarity.
Color powerUpRingColor(PowerUpRarity rarity) => switch (rarity) {
      PowerUpRarity.common => const Color(0xFF7C93A8),
      PowerUpRarity.uncommon => const Color(0xFF2E8BC0),
      PowerUpRarity.rare => const Color(0xFFF7B32B),
    };

/// The ring colour for whatever [card] is, or the "empty hand" red the
/// design uses on the badge when there is no card at all.
Color powerUpAccent(PowerUpCard? card) => card == null
    ? const Color(0xFFF25F5C)
    : powerUpRingColor(PowerUps.of(card).rarity);

/// Every glyph, verbatim from the design's `PowerUpIcon.dc.html`, in its
/// own 100×100 viewBox. Drawn on top of the badge disc and rarity ring.
///
/// Two deviations from the source, both mechanical:
///  * PATCH CREW's two rotated `<rect>`s are wrapped in a `<g>` carrying
///    the rotation, because the replay applies `transform` at group level
///    (a leaf `transform` is ignored). Same geometry, same result.
///  * DECOY's centre disc is `none`-filled here rather than filled with
///    the badge colour: the source punches it out with the background
///    colour, which only works because the icon knows its own `bg` — an
///    unfilled hole reads the same over any badge and needs no colour
///    substitution into the markup.
const Map<PowerUpCard, String> _glyph = {
  PowerUpCard.sonar: '''
<circle cx="50" cy="50" r="10" fill="none" stroke="#FFF4EC" stroke-width="3"></circle>
<circle cx="50" cy="50" r="18" fill="none" stroke="#FFF4EC" stroke-width="3" opacity="0.65"></circle>
<circle cx="50" cy="50" r="26" fill="none" stroke="#FFF4EC" stroke-width="3" opacity="0.35"></circle>
<line x1="50" y1="50" x2="70" y2="32" stroke="#FFF4EC" stroke-width="4" stroke-linecap="round"></line>
<circle cx="50" cy="50" r="4.5" fill="#F7B32B"></circle>''',
  PowerUpCard.spotter: '''
<rect x="27" y="42" width="18" height="24" rx="9" fill="#FFF4EC" stroke="#1E2A36" stroke-width="3"></rect>
<rect x="55" y="42" width="18" height="24" rx="9" fill="#FFF4EC" stroke="#1E2A36" stroke-width="3"></rect>
<rect x="42" y="37" width="16" height="11" rx="4" fill="#FFF4EC" stroke="#1E2A36" stroke-width="3"></rect>
<circle cx="36" cy="54" r="5" fill="#4A789A"></circle>
<circle cx="64" cy="54" r="5" fill="#4A789A"></circle>''',
  PowerUpCard.reconSweep: '''
<polygon points="30,28 70,28 50,60" fill="#FFF4EC" opacity="0.9" stroke="#1E2A36" stroke-width="2.5"></polygon>
<circle cx="50" cy="24" r="4" fill="#FFF4EC" stroke="#1E2A36" stroke-width="2"></circle>
<circle cx="36" cy="70" r="4" fill="#1E2A36"></circle>
<circle cx="50" cy="70" r="4" fill="#1E2A36"></circle>
<circle cx="64" cy="70" r="4" fill="#1E2A36"></circle>''',
  PowerUpCard.doubleTap: '''
<polyline points="30,36 50,52 70,36" fill="none" stroke="#FFF4EC" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"></polyline>
<polyline points="30,54 50,70 70,54" fill="none" stroke="#FFF4EC" stroke-width="7" stroke-linecap="round" stroke-linejoin="round" opacity="0.55"></polyline>''',
  PowerUpCard.repair: '''
<rect x="44" y="27" width="12" height="46" rx="4" fill="#FFF4EC" stroke="#1E2A36" stroke-width="3"></rect>
<rect x="27" y="44" width="46" height="12" rx="4" fill="#FFF4EC" stroke="#1E2A36" stroke-width="3"></rect>
<circle cx="50" cy="50" r="6.5" fill="#5BB381" stroke="#1E2A36" stroke-width="2"></circle>''',
  PowerUpCard.jam: '''
<line x1="50" y1="74" x2="50" y2="46" stroke="#FFF4EC" stroke-width="4" stroke-linecap="round"></line>
<circle cx="50" cy="41" r="4" fill="#FFF4EC"></circle>
<path d="M 36 46 A 17 17 0 0 1 50 29" stroke="#FFF4EC" stroke-width="3" fill="none" stroke-linecap="round"></path>
<path d="M 64 46 A 17 17 0 0 0 50 29" stroke="#FFF4EC" stroke-width="3" fill="none" stroke-linecap="round"></path>
<line x1="29" y1="66" x2="71" y2="30" stroke="#E63946" stroke-width="6" stroke-linecap="round"></line>''',
  PowerUpCard.spray: '''
<circle cx="37" cy="56" r="12" fill="#FFF4EC" stroke="#1E2A36" stroke-width="3"></circle>
<polygon points="37,38 32,47 42,47" fill="#FFF4EC" stroke="#1E2A36" stroke-width="2"></polygon>
<circle cx="65" cy="48" r="9" fill="#FFF4EC" stroke="#1E2A36" stroke-width="3"></circle>
<polygon points="65,34 61,42 69,42" fill="#FFF4EC" stroke="#1E2A36" stroke-width="2"></polygon>''',
  PowerUpCard.salvo: '''
<circle cx="32" cy="54" r="7" fill="#1E2A36"></circle>
<circle cx="50" cy="54" r="7" fill="#1E2A36"></circle>
<circle cx="68" cy="54" r="7" fill="#1E2A36"></circle>
<line x1="18" y1="54" x2="24" y2="54" stroke="#FFF4EC" stroke-width="3" stroke-linecap="round"></line>
<line x1="18" y1="46" x2="26" y2="46" stroke="#FFF4EC" stroke-width="2.5" stroke-linecap="round" opacity="0.6"></line>''',
  PowerUpCard.depthCharge: '''
<rect x="37" y="32" width="26" height="32" rx="6" fill="#FFF4EC" stroke="#1E2A36" stroke-width="3"></rect>
<line x1="37" y1="43" x2="63" y2="43" stroke="#1E2A36" stroke-width="2.5"></line>
<line x1="37" y1="54" x2="63" y2="54" stroke="#1E2A36" stroke-width="2.5"></line>
<polygon points="37,64 28,73 37,70" fill="#FFF4EC" stroke="#1E2A36" stroke-width="2"></polygon>
<polygon points="63,64 72,73 63,70" fill="#FFF4EC" stroke="#1E2A36" stroke-width="2"></polygon>
<circle cx="28" cy="28" r="2.5" fill="#FFF4EC"></circle>
<circle cx="71" cy="24" r="2" fill="#FFF4EC"></circle>''',
  PowerUpCard.chainShot: '''
<circle cx="31" cy="50" r="10" fill="#1E2A36"></circle>
<circle cx="69" cy="50" r="10" fill="#1E2A36"></circle>
<rect x="37" y="45" width="26" height="10" rx="5" fill="#FFF4EC" stroke="#1E2A36" stroke-width="2.5"></rect>''',
  PowerUpCard.hotShot: '''
<circle cx="50" cy="60" r="14" fill="#1E2A36"></circle>
<path d="M50 18 C42 29 40 37 46 43 C44 35 50 33 50 29 C54 35 60 39 56 47 C65 40 63 28 50 18 Z" fill="#F77F3F" stroke="#1E2A36" stroke-width="2"></path>''',
  PowerUpCard.rapidFire: '''
<circle cx="34" cy="68" r="6" fill="#1E2A36"></circle>
<circle cx="50" cy="50" r="6" fill="#1E2A36"></circle>
<circle cx="66" cy="32" r="6" fill="#1E2A36"></circle>
<line x1="23" y1="79" x2="29" y2="73" stroke="#F7B32B" stroke-width="3" stroke-linecap="round"></line>
<line x1="39" y1="61" x2="45" y2="55" stroke="#F7B32B" stroke-width="3" stroke-linecap="round" opacity="0.75"></line>
<line x1="55" y1="43" x2="61" y2="37" stroke="#F7B32B" stroke-width="3" stroke-linecap="round" opacity="0.5"></line>''',
  PowerUpCard.scramble: '''
<path d="M32 60 L68 60 L60 70 L40 70 Z" fill="#FFF4EC" stroke="#1E2A36" stroke-width="3"></path>
<line x1="50" y1="60" x2="50" y2="42" stroke="#1E2A36" stroke-width="3"></line>
<path d="M 25 42 A 23 23 0 1 1 38 68" fill="none" stroke="#1E2A36" stroke-width="4.5" stroke-linecap="round" stroke-dasharray="1 8"></path>
<polygon points="38,68 47,66 41,75" fill="#1E2A36"></polygon>''',
  PowerUpCard.counterBattery: '''
<path d="M50 27 L68 33 V53 C68 65 60 73 50 77 C40 73 32 65 32 53 V33 Z" fill="#FFF4EC" stroke="#1E2A36" stroke-width="3"></path>
<rect x="45" y="16" width="10" height="22" rx="3" fill="#1E2A36"></rect>''',
  PowerUpCard.barrage: '''
<circle cx="34" cy="34" r="6.5" fill="#1E2A36"></circle>
<circle cx="66" cy="34" r="6.5" fill="#1E2A36"></circle>
<circle cx="34" cy="66" r="6.5" fill="#1E2A36"></circle>
<circle cx="66" cy="66" r="6.5" fill="#1E2A36"></circle>
<polygon points="50,42 54,50 50,58 46,50" fill="#F7B32B" stroke="#1E2A36" stroke-width="1.5"></polygon>''',
  PowerUpCard.crossFire: '''
<line x1="50" y1="24" x2="50" y2="76" stroke="#FFF4EC" stroke-width="3"></line>
<line x1="24" y1="50" x2="76" y2="50" stroke="#FFF4EC" stroke-width="3"></line>
<circle cx="50" cy="50" r="4.5" fill="#1E2A36"></circle>
<circle cx="50" cy="28" r="4.5" fill="#1E2A36"></circle>
<circle cx="50" cy="72" r="4.5" fill="#1E2A36"></circle>
<circle cx="28" cy="50" r="4.5" fill="#1E2A36"></circle>
<circle cx="72" cy="50" r="4.5" fill="#1E2A36"></circle>''',
  PowerUpCard.decoy: '''
<path d="M34 66 L66 66 L58 74 L42 74 Z" fill="none" stroke="#FFF4EC" stroke-width="2" stroke-dasharray="3 3" opacity="0.7"></path>
<circle cx="50" cy="42" r="16" fill="none" stroke="#FFF4EC" stroke-width="9"></circle>
<rect x="47" y="24" width="6" height="9" fill="#E63946"></rect>
<rect x="47" y="51" width="6" height="9" fill="#E63946"></rect>
<rect x="29" y="39" width="9" height="6" fill="#E63946"></rect>
<rect x="62" y="39" width="9" height="6" fill="#E63946"></rect>
<circle cx="50" cy="42" r="7" fill="none" stroke="#1E2A36" stroke-width="2"></circle>''',
  PowerUpCard.patchCrew: '''
<path d="M28 56 L72 56 L62 70 L38 70 Z" fill="#FFF4EC" stroke="#1E2A36" stroke-width="3"></path>
<g transform="rotate(-5 50 62)">
<rect x="26" y="58" width="48" height="9" fill="#5BB381" stroke="#1E2A36" stroke-width="2"></rect>
<rect x="46" y="58" width="8" height="8" fill="#FFF4EC" stroke="none"></rect>
</g>''',
  PowerUpCard.minefield: '''
<line x1="50" y1="52" x2="50" y2="28" stroke="#1E2A36" stroke-width="4" stroke-linecap="round"></line>
<line x1="50" y1="52" x2="50" y2="76" stroke="#1E2A36" stroke-width="4" stroke-linecap="round"></line>
<line x1="50" y1="52" x2="26" y2="52" stroke="#1E2A36" stroke-width="4" stroke-linecap="round"></line>
<line x1="50" y1="52" x2="74" y2="52" stroke="#1E2A36" stroke-width="4" stroke-linecap="round"></line>
<line x1="50" y1="52" x2="33" y2="35" stroke="#1E2A36" stroke-width="4" stroke-linecap="round"></line>
<line x1="50" y1="52" x2="67" y2="35" stroke="#1E2A36" stroke-width="4" stroke-linecap="round"></line>
<line x1="50" y1="52" x2="33" y2="69" stroke="#1E2A36" stroke-width="4" stroke-linecap="round"></line>
<line x1="50" y1="52" x2="67" y2="69" stroke="#1E2A36" stroke-width="4" stroke-linecap="round"></line>
<circle cx="50" cy="52" r="16" fill="#1E2A36"></circle>
<circle cx="45" cy="47" r="3.5" fill="#FFF4EC" opacity="0.5"></circle>''',
  // ---- Added after the design import, drawn in its vocabulary ----
  // Same 100×100 box, same cream/ink palette, same chunky 3px strokes as
  // the twenty above, so the set still reads as one family.
  //
  // HARD TURN — a hull swinging through a quarter circle, with the arc it
  // turns along and a tick showing the orientation it started from.
  PowerUpCard.hardTurn: '''
<path d="M 26 30 A 30 30 0 0 1 70 26" fill="none" stroke="#FFF4EC" stroke-width="3.5" stroke-linecap="round" stroke-dasharray="5 5"></path>
<polygon points="70,26 60,20 62,33" fill="#FFF4EC"></polygon>
<line x1="30" y1="70" x2="30" y2="46" stroke="#1E2A36" stroke-width="3.5" stroke-linecap="round" opacity="0.55"></line>
<path d="M34 58 L74 58 L66 72 L42 72 Z" fill="#FFF4EC" stroke="#1E2A36" stroke-width="3"></path>
<circle cx="54" cy="65" r="3.5" fill="#1E2A36"></circle>''',
  // AUTO DODGE — a hull sliding clear, its old position left as a dashed
  // ghost and the shot that missed it streaking past.
  PowerUpCard.autoDodge: '''
<path d="M22 40 L58 40 L50 54 L30 54 Z" fill="none" stroke="#FFF4EC" stroke-width="2.5" stroke-dasharray="4 4" opacity="0.75"></path>
<path d="M40 58 L78 58 L70 72 L48 72 Z" fill="#FFF4EC" stroke="#1E2A36" stroke-width="3"></path>
<line x1="20" y1="24" x2="72" y2="24" stroke="#E63946" stroke-width="5" stroke-linecap="round"></line>
<polygon points="78,24 66,18 66,30" fill="#E63946"></polygon>
<path d="M 30 46 A 14 14 0 0 0 42 60" fill="none" stroke="#FFF4EC" stroke-width="3" stroke-linecap="round"></path>''',
  // ARMOUR PLATE — a hull under bolted plating, the two plates the card
  // grants drawn as the two bands across it.
  PowerUpCard.armourPlate: '''
<path d="M28 62 L72 62 L63 75 L37 75 Z" fill="#FFF4EC" stroke="#1E2A36" stroke-width="3"></path>
<path d="M50 20 L72 28 V46 C72 56 62 63 50 67 C38 63 28 56 28 46 V28 Z" fill="#FFF4EC" stroke="#1E2A36" stroke-width="3"></path>
<line x1="30" y1="38" x2="70" y2="38" stroke="#1E2A36" stroke-width="3"></line>
<line x1="31" y1="51" x2="69" y2="51" stroke="#1E2A36" stroke-width="3"></line>
<circle cx="36" cy="31" r="2.6" fill="#1E2A36"></circle>
<circle cx="64" cy="31" r="2.6" fill="#1E2A36"></circle>
<circle cx="50" cy="58" r="2.6" fill="#1E2A36"></circle>''',
  // SPY SHIP — a little scout hull under a periscope, with the sweep it
  // reports back along.
  PowerUpCard.spyShip: '''
<circle cx="50" cy="50" r="27" fill="none" stroke="#FFF4EC" stroke-width="2" stroke-dasharray="4 6" opacity="0.55"></circle>
<line x1="58" y1="56" x2="58" y2="30" stroke="#1E2A36" stroke-width="4" stroke-linecap="round"></line>
<path d="M 58 30 L 70 30" stroke="#1E2A36" stroke-width="4" stroke-linecap="round" fill="none"></path>
<circle cx="72" cy="30" r="4" fill="#F7B32B" stroke="#1E2A36" stroke-width="2"></circle>
<path d="M26 56 L74 56 L65 70 L35 70 Z" fill="#FFF4EC" stroke="#1E2A36" stroke-width="3"></path>
<circle cx="42" cy="63" r="3.2" fill="#1E2A36"></circle>
<circle cx="56" cy="63" r="3.2" fill="#1E2A36"></circle>''',
  PowerUpCard.trapLine: '''
<line x1="28" y1="60" x2="50" y2="50" stroke="#1E2A36" stroke-width="3" stroke-dasharray="3 3"></line>
<line x1="50" y1="50" x2="72" y2="40" stroke="#1E2A36" stroke-width="3" stroke-dasharray="3 3"></line>
<circle cx="28" cy="60" r="8" fill="#1E2A36"></circle>
<circle cx="50" cy="50" r="8" fill="#1E2A36"></circle>
<circle cx="72" cy="40" r="8" fill="#1E2A36"></circle>
<circle cx="28" cy="60" r="2.5" fill="#F7B32B"></circle>
<circle cx="50" cy="50" r="2.5" fill="#F7B32B"></circle>
<circle cx="72" cy="40" r="2.5" fill="#F7B32B"></circle>''',
};

/// Design-space size of every icon — the SVG's own viewBox.
const double _viewBox = 100.0;

/// Paints [card]'s complete badge — disc, rarity ring and glyph — filling
/// [size] (the shorter side wins; the icon is always square and centred).
void paintPowerUpIcon(Canvas canvas, Size size, PowerUpCard card) {
  final side = size.shortestSide;
  if (side <= 0) return;
  final def = PowerUps.of(card);
  canvas.save();
  canvas.translate((size.width - side) / 2, (size.height - side) / 2);
  canvas.scale(side / _viewBox);

  // The disc.
  canvas.drawCircle(
    const Offset(50, 50),
    46,
    Paint()..color = powerUpBg(card),
  );
  canvas.drawCircle(
    const Offset(50, 50),
    46,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..color = const Color(0xFF1E2A36),
  );

  _paintRarityRing(canvas, def.rarity);
  paintSvgFragmentCached(canvas, _glyph[card]!);
  canvas.restore();
}

/// The rarity ring, in the design's own 100×100 space.
///
/// Rarity is carried by the ring's SHAPE first and its colour second —
/// solid, dashed, or thin-with-six-studs — so it survives being read in
/// greyscale or by a colourblind player, which colour alone would not.
void _paintRarityRing(Canvas canvas, PowerUpRarity rarity) {
  final color = powerUpRingColor(rarity);
  switch (rarity) {
    case PowerUpRarity.common:
      canvas.drawCircle(
        const Offset(50, 50),
        40,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = color,
      );
    case PowerUpRarity.uncommon:
      // 7-on/6-off dashes, walked around the circle by hand: the replay's
      // dash support works on a `Path`, and drawing the arcs directly is
      // cheaper than building and re-measuring a dashed path per frame.
      const dash = 7.0, gap = 6.0, r = 40.0;
      final step = (dash + gap) / r; // radians per dash+gap
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = color;
      final rect = Rect.fromCircle(center: const Offset(50, 50), radius: r);
      for (var a = 0.0; a < 6.28318; a += step) {
        canvas.drawArc(rect, a, dash / r, false, paint);
      }
    case PowerUpRarity.rare:
      canvas.drawCircle(
        const Offset(50, 50),
        41,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color,
      );
      // Six studs at the hexagon points, exactly where the design puts
      // them.
      const studs = [
        Offset(50, 8),
        Offset(86.4, 29),
        Offset(86.4, 71),
        Offset(50, 92),
        Offset(13.6, 71),
        Offset(13.6, 29),
      ];
      final fill = Paint()..color = color;
      for (final s in studs) {
        canvas.drawCircle(s, 2.6, fill);
      }
  }
}

/// One power-up icon at a fixed [size].
class PowerUpIcon extends StatelessWidget {
  final PowerUpCard card;
  final double size;

  const PowerUpIcon({super.key, required this.card, this.size = 44});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _PowerUpIconPainter(card)),
      );
}

class _PowerUpIconPainter extends CustomPainter {
  final PowerUpCard card;
  const _PowerUpIconPainter(this.card);

  @override
  void paint(Canvas canvas, Size size) => paintPowerUpIcon(canvas, size, card);

  @override
  bool shouldRepaint(_PowerUpIconPainter old) => old.card != card;
}
