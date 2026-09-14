import 'package:flutter/material.dart';

import '../art/power_up_icons.dart';
import '../core/theme.dart';
import '../models/power_up.dart';

/// The POWER PLAY reference: every card in the deck, with a picture of
/// what it actually does to the water.
///
/// A card's own one-line description is the source of truth for WHAT it
/// does — it is the same string the game shows on the badge — so this
/// never restates it in different words. What it adds is the part prose is
/// worst at: the SHAPE. "Three shots in a line, centred on the cell you
/// tap" is a sentence you have to build a picture from; the picture is
/// right here instead.
///
/// Every shaped diagram is generated from `PowerUpShapes`, the same code
/// the cards fire through, so a diagram cannot claim a shape the card does
/// not actually cover.
class PowerUpGuide extends StatelessWidget {
  const PowerUpGuide({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: cartoonBox(AppColors.navy, radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.style, color: AppColors.gold, size: 18),
              const SizedBox(width: 8),
              Text('EVERY POWER-UP', style: AppText.heading(size: 14)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'You draw one at the start of each turn and hold it until you '
            'spend it. Blue is the square you tap; red is what it hits; '
            'gold is what it reveals or arms.',
            style: AppText.body(size: 10, color: AppColors.mist),
          ),
          const SizedBox(height: 12),
          for (final rarity in PowerUpRarity.values) ...[
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: powerUpRingColor(rarity),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.outline, width: 2),
                  ),
                ),
                const SizedBox(width: 7),
                Text(rarity.name.toUpperCase(),
                    style: AppText.label(size: 10, color: AppColors.cream)),
                const SizedBox(width: 7),
                Text(_rarityBlurb(rarity),
                    style: AppText.body(size: 9, color: AppColors.mist)),
              ],
            ),
            const SizedBox(height: 8),
            for (final def
                in PowerUps.deck.where((d) => d.rarity == rarity))
              _CardRow(def: def),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  static String _rarityBlurb(PowerUpRarity r) => switch (r) {
        PowerUpRarity.common => 'comes up most often',
        PowerUpRarity.uncommon => 'less often',
        PowerUpRarity.rare => 'rarest of all',
      };
}

class _CardRow extends StatelessWidget {
  final PowerUpDef def;
  const _CardRow({required this.def});

  @override
  Widget build(BuildContext context) {
    final viz = _vizFor(def.card);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: cartoonBox(AppColors.navyDark, radius: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PowerUpIcon(card: def.card, size: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(def.name,
                          style: AppText.label(size: 11),
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 6),
                    if (def.needsTarget)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: def.targetsOwnGrid
                              ? AppColors.hit
                              : AppColors.shipBlue,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          def.targetsOwnGrid ? 'YOUR GRID' : 'AIM IT',
                          style: AppText.label(size: 7),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(def.description,
                    style: AppText.body(size: 10, color: AppColors.cream)),
              ],
            ),
          ),
          if (viz != _Viz.none) ...[
            const SizedBox(width: 10),
            SizedBox(
              width: 62,
              height: 62,
              child: CustomPaint(painter: _VizPainter(viz)),
            ),
          ],
        ],
      ),
    );
  }
}

/// What a card's diagram should show. Cards whose effect has no place on
/// the water at all — a reload buff, a jammed radio — get [none] and no
/// diagram, rather than a picture that would only be decoration.
enum _Viz {
  none,
  line3,
  block2x2,
  plus5,
  twoCells,
  scatter4,
  chain,
  area3x3,
  wholeRow,
  revealOne,
  scout,
  mineOne,
  mineLine,
  hullHeal,
  hullArmour,
  hullMove,
  hullTurn,
  hullBonus,
}

_Viz _vizFor(PowerUpCard card) => switch (card) {
      PowerUpCard.salvo => _Viz.line3,
      PowerUpCard.depthCharge => _Viz.block2x2,
      PowerUpCard.crossFire => _Viz.plus5,
      PowerUpCard.spray => _Viz.twoCells,
      PowerUpCard.barrage => _Viz.scatter4,
      PowerUpCard.chainShot => _Viz.chain,
      PowerUpCard.sonar => _Viz.area3x3,
      PowerUpCard.reconSweep => _Viz.wholeRow,
      PowerUpCard.spotter => _Viz.revealOne,
      PowerUpCard.spyShip => _Viz.scout,
      PowerUpCard.minefield => _Viz.mineOne,
      PowerUpCard.trapLine => _Viz.mineLine,
      PowerUpCard.repair || PowerUpCard.patchCrew => _Viz.hullHeal,
      PowerUpCard.armourPlate => _Viz.hullArmour,
      PowerUpCard.scramble || PowerUpCard.autoDodge => _Viz.hullMove,
      PowerUpCard.hardTurn => _Viz.hullTurn,
      PowerUpCard.hotShot => _Viz.hullBonus,
      // DOUBLE TAP, JAM, RAPID FIRE, COUNTER BATTERY, DECOY: all change
      // the RULES for a turn rather than touching any particular square.
      _ => _Viz.none,
    };

class _VizPainter extends CustomPainter {
  final _Viz viz;
  const _VizPainter(this.viz);

  static const _n = 5;
  static const _aim = (2, 2);

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / _n;
    final fired = <(int, int)>{};
    final revealed = <(int, int)>{};
    final hull = <(int, int)>{};
    final ghost = <(int, int)>{};
    var aim = _aim;

    switch (viz) {
      case _Viz.none:
        return;
      case _Viz.line3:
        fired.addAll(PowerUpShapes.salvo(2, 2));
      case _Viz.block2x2:
        fired.addAll(PowerUpShapes.depthCharge(2, 2));
      case _Viz.plus5:
        fired.addAll(PowerUpShapes.crossFire(2, 2));
      case _Viz.twoCells:
        fired.addAll(const [(1, 1), (3, 3)]);
      case _Viz.scatter4:
        // No aim point at all — BARRAGE picks its own cells.
        aim = (-1, -1);
        fired.addAll(const [(0, 3), (1, 1), (3, 4), (4, 2)]);
      case _Viz.chain:
        fired.add((2, 2));
        fired.add((2, 3)); // the bonus shot, on a random adjacent cell
      case _Viz.area3x3:
        for (var r = 1; r <= 3; r++) {
          for (var c = 1; c <= 3; c++) {
            revealed.add((r, c));
          }
        }
      case _Viz.wholeRow:
        aim = (2, 0);
        for (var c = 0; c < _n; c++) {
          revealed.add((2, c));
        }
      case _Viz.revealOne:
        aim = (-1, -1);
        revealed.add((1, 3));
      case _Viz.scout:
        aim = (-1, -1);
        revealed.add((2, 2));
        for (var dr = -1; dr <= 1; dr++) {
          for (var dc = -1; dc <= 1; dc++) {
            if (dr == 0 && dc == 0) continue;
            ghost.add((2 + dr, 2 + dc));
          }
        }
      case _Viz.mineOne:
        aim = (-1, -1);
        revealed.add((2, 2));
      case _Viz.mineLine:
        aim = (-1, -1);
        revealed.addAll(PowerUpShapes.salvo(2, 2));
      case _Viz.hullHeal:
        aim = (-1, -1);
        hull.addAll(const [(2, 1), (2, 2), (2, 3)]);
        fired.add((2, 1)); // the wound
        revealed.add((2, 1)); // ...being mended
      case _Viz.hullArmour:
        aim = (-1, -1);
        hull.addAll(const [(2, 1), (2, 2), (2, 3)]);
        revealed.addAll(const [(2, 1), (2, 2), (2, 3)]);
      case _Viz.hullMove:
        aim = (-1, -1);
        ghost.addAll(const [(1, 0), (1, 1), (1, 2)]);
        hull.addAll(const [(3, 2), (3, 3), (3, 4)]);
      case _Viz.hullTurn:
        aim = (-1, -1);
        ghost.addAll(const [(2, 1), (2, 2), (2, 3)]);
        hull.addAll(const [(1, 2), (2, 2), (3, 2)]);
      case _Viz.hullBonus:
        aim = (-1, -1);
        hull.addAll(const [(2, 1), (2, 2), (2, 3)]);
        fired.addAll(const [(2, 1), (2, 2)]);
    }

    for (var r = 0; r < _n; r++) {
      for (var c = 0; c < _n; c++) {
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(c * cell + 1, r * cell + 1, cell - 2, cell - 2),
          Radius.circular(cell * 0.22),
        );
        var color = AppColors.steelBlue;
        if (hull.contains((r, c))) color = AppColors.shipRed;
        if (fired.contains((r, c))) color = AppColors.hit;
        canvas.drawRRect(rect, Paint()..color = color);
        if (ghost.contains((r, c))) {
          canvas.drawRRect(
            rect,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.6
              ..color = AppColors.cream.withValues(alpha: 0.55),
          );
        }
        if (revealed.contains((r, c))) {
          canvas.drawRRect(
            rect,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.4
              ..color = AppColors.gold,
          );
        }
        if ((r, c) == aim) {
          canvas.drawRRect(
            rect,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.4
              ..color = AppColors.shipBlue,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_VizPainter old) => old.viz != viz;
}
