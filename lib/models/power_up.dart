import 'dart:math';

import 'game_models.dart';

/// The twenty cards POWER PLAY draws from. See [PowerUps.deck] for the
/// weights and [GameController]'s "GHOST FLEET"-style block of
/// power-up methods for how each one actually resolves.
///
/// Every card resolves through exactly one of four routes, which is what
/// keeps twenty cards from being twenty bespoke pieces of gameplay code:
///
///  * **local** — fires, cooldown, turn flow. Needs nothing from the wire
///    beyond the `fire`s it already sends.
///  * **local + mirror** — mutates the player's own board, then tells the
///    peer, exactly the way a MANOEUVRE move already does.
///  * **defender answers** — a request the OPPONENT's device evaluates
///    against their own board and answers, because only they have the
///    board to check.
///  * **defender flag** — a one-shot (or few-shot) condition set on the
///    defender's own device, consulted the next time it resolves an
///    incoming `fire`.
enum PowerUpCard {
  // ---- common ----
  sonar,
  spotter,
  reconSweep,
  doubleTap,
  repair,
  jam,
  spray,
  // ---- uncommon ----
  salvo,
  depthCharge,
  chainShot,
  hotShot,
  rapidFire,
  scramble,
  counterBattery,
  // ---- rare ----
  barrage,
  crossFire,
  decoy,
  patchCrew,
  minefield,
  trapLine,
}

enum PowerUpRarity { common, uncommon, rare }

/// Which of the four routes a card resolves through — see [PowerUpCard]'s
/// doc. Purely descriptive (nothing dispatches on it directly); it exists
/// so the deck's own shape can be asserted in one place rather than
/// inferred from which `GameController` method happens to touch a card.
enum PowerUpRoute { local, localMirror, defenderAnswers, defenderFlag }

class PowerUpDef {
  final PowerUpCard card;
  final String name;
  final String description;
  final PowerUpRarity rarity;
  final PowerUpRoute route;

  /// Relative draw weight within the whole deck — see [PowerUps.draw].
  final int weight;

  /// True for a card that needs the player to pick a cell (or several)
  /// before it does anything — the UI puts the grid into a "pick a
  /// target" state for these rather than resolving on tap-to-use alone.
  final bool needsTarget;

  /// True when [needsTarget] points at the player's OWN grid (a mine,
  /// or a scramble destination is picked automatically so this never
  /// applies there) rather than the opponent's.
  final bool targetsOwnGrid;

  const PowerUpDef({
    required this.card,
    required this.name,
    required this.description,
    required this.rarity,
    required this.route,
    required this.weight,
    this.needsTarget = false,
    this.targetsOwnGrid = false,
  });
}

/// The whole POWER PLAY catalogue.
class PowerUps {
  PowerUps._();

  static const List<PowerUpDef> deck = [
    // -------------------------------------------------------- common (7)
    PowerUpDef(
      card: PowerUpCard.sonar,
      name: 'SONAR',
      description: 'How many ships sit in a 3×3 you pick — the count, '
          'not the positions.',
      rarity: PowerUpRarity.common,
      route: PowerUpRoute.defenderAnswers,
      weight: 7,
      needsTarget: true,
    ),
    PowerUpDef(
      card: PowerUpCard.spotter,
      name: 'SPOTTER',
      description: 'Reveals one random cell an enemy hull occupies. '
          'Marks it; does not fire.',
      rarity: PowerUpRarity.common,
      route: PowerUpRoute.defenderAnswers,
      weight: 7,
    ),
    PowerUpDef(
      card: PowerUpCard.reconSweep,
      name: 'RECON SWEEP',
      description: 'Tap a row: does it hold any ship at all?',
      rarity: PowerUpRarity.common,
      route: PowerUpRoute.defenderAnswers,
      weight: 7,
      needsTarget: true,
    ),
    PowerUpDef(
      card: PowerUpCard.doubleTap,
      name: 'DOUBLE TAP',
      description: 'A miss does not end your turn.',
      rarity: PowerUpRarity.common,
      route: PowerUpRoute.local,
      weight: 7,
    ),
    PowerUpDef(
      card: PowerUpCard.repair,
      name: 'REPAIR',
      description: 'Undo one hit on your most-damaged hull.',
      rarity: PowerUpRarity.common,
      route: PowerUpRoute.localMirror,
      weight: 7,
    ),
    PowerUpDef(
      card: PowerUpCard.jam,
      name: 'JAM',
      description: 'Your opponent draws no power-up next turn.',
      rarity: PowerUpRarity.common,
      route: PowerUpRoute.defenderFlag,
      weight: 7,
    ),
    PowerUpDef(
      card: PowerUpCard.spray,
      name: 'SPRAY',
      description: 'Two shots, at two cells you pick.',
      rarity: PowerUpRarity.common,
      route: PowerUpRoute.local,
      weight: 7,
      needsTarget: true,
    ),

    // ----------------------------------------------------- uncommon (7)
    PowerUpDef(
      card: PowerUpCard.salvo,
      name: 'SALVO',
      description: 'Three shots in a line, centred on the cell you tap.',
      rarity: PowerUpRarity.uncommon,
      route: PowerUpRoute.local,
      weight: 5,
      needsTarget: true,
    ),
    PowerUpDef(
      card: PowerUpCard.depthCharge,
      name: 'DEPTH CHARGE',
      description: 'A 2×2 block from the cell you tap.',
      rarity: PowerUpRarity.uncommon,
      route: PowerUpRoute.local,
      weight: 5,
      needsTarget: true,
    ),
    PowerUpDef(
      card: PowerUpCard.chainShot,
      name: 'CHAIN SHOT',
      description: 'A hit fires once more at a random adjacent unfired '
          'cell.',
      rarity: PowerUpRarity.uncommon,
      route: PowerUpRoute.local,
      weight: 5,
      needsTarget: true,
    ),
    PowerUpDef(
      card: PowerUpCard.hotShot,
      name: 'HOT SHOT',
      description: 'Your next hit also damages the nearest unhit cell '
          'of that same hull.',
      rarity: PowerUpRarity.uncommon,
      route: PowerUpRoute.defenderFlag,
      weight: 5,
    ),
    PowerUpDef(
      card: PowerUpCard.rapidFire,
      name: 'RAPID FIRE',
      description: 'Cooldown halved for your next three shots.',
      rarity: PowerUpRarity.uncommon,
      route: PowerUpRoute.local,
      weight: 5,
    ),
    PowerUpDef(
      card: PowerUpCard.scramble,
      name: 'SCRAMBLE',
      description: 'One of your undamaged hulls jumps to a random '
          'legal spot.',
      rarity: PowerUpRarity.uncommon,
      route: PowerUpRoute.localMirror,
      weight: 5,
    ),
    PowerUpDef(
      card: PowerUpCard.counterBattery,
      name: 'COUNTER BATTERY',
      description: 'The next hit on you earns you an extra shot on your '
          'next turn.',
      rarity: PowerUpRarity.uncommon,
      route: PowerUpRoute.defenderFlag,
      weight: 5,
    ),

    // ----------------------------------------------------------- rare (6)
    PowerUpDef(
      card: PowerUpCard.barrage,
      name: 'BARRAGE',
      description: 'Four random shots into unfired water.',
      rarity: PowerUpRarity.rare,
      route: PowerUpRoute.local,
      weight: 3,
    ),
    PowerUpDef(
      card: PowerUpCard.crossFire,
      name: 'CROSS FIRE',
      description: 'Five shots in a plus, centred on the cell you tap.',
      rarity: PowerUpRarity.rare,
      route: PowerUpRoute.local,
      weight: 3,
      needsTarget: true,
    ),
    PowerUpDef(
      card: PowerUpCard.decoy,
      name: 'DECOY',
      description: 'The next hit on you is reported as a miss, and '
          'takes no damage.',
      rarity: PowerUpRarity.rare,
      route: PowerUpRoute.defenderFlag,
      weight: 3,
    ),
    PowerUpDef(
      card: PowerUpCard.patchCrew,
      name: 'PATCH CREW',
      description: 'Undo one hit on EVERY damaged hull.',
      rarity: PowerUpRarity.rare,
      route: PowerUpRoute.localMirror,
      weight: 3,
    ),
    PowerUpDef(
      card: PowerUpCard.minefield,
      name: 'MINEFIELD',
      description: 'Mine one of your own cells; if they fire there it '
          'costs them their next turn.',
      rarity: PowerUpRarity.rare,
      route: PowerUpRoute.defenderFlag,
      weight: 3,
      needsTarget: true,
      targetsOwnGrid: true,
    ),
    PowerUpDef(
      card: PowerUpCard.trapLine,
      name: 'TRAP LINE',
      description: 'Mine three of your own cells in a row or column; '
          'the first one they hit costs them their next turn.',
      rarity: PowerUpRarity.rare,
      route: PowerUpRoute.defenderFlag,
      weight: 3,
      needsTarget: true,
      targetsOwnGrid: true,
    ),
  ];

  static final Map<PowerUpCard, PowerUpDef> _byCard = {
    for (final d in deck) d.card: d,
  };

  static PowerUpDef of(PowerUpCard card) => _byCard[card]!;

  static int get totalWeight => deck.fold(0, (sum, d) => sum + d.weight);

  /// Draws one card, weighted by [PowerUpDef.weight].
  static PowerUpCard draw(Random rng) {
    var roll = rng.nextInt(totalWeight);
    for (final d in deck) {
      if (roll < d.weight) return d.card;
      roll -= d.weight;
    }
    return deck.last.card; // unreachable; keeps the type non-nullable
  }
}

/// The four multi-shot cards' targeting shapes, as offsets from the
/// tapped cell — pure functions so the shape itself (in particular, that
/// it stays the full size when clamped at an edge rather than losing
/// cells) can be tested without any board or controller involved.
class PowerUpShapes {
  PowerUpShapes._();

  /// Clamps a list of candidate (row, col) offsets so the whole shape
  /// fits on the board, sliding rather than truncating — a shape must
  /// always cost its full number of shots, including flush against an
  /// edge or corner.
  static List<(int, int)> _clamp(
    int centerRow,
    int centerCol,
    List<(int, int)> offsets,
  ) {
    var rows = offsets.map((o) => centerRow + o.$1).toList();
    var cols = offsets.map((o) => centerCol + o.$2).toList();
    final minRow = rows.reduce(min), maxRow = rows.reduce(max);
    final minCol = cols.reduce(min), maxCol = cols.reduce(max);
    var dRow = 0, dCol = 0;
    if (minRow < 0) dRow = -minRow;
    if (maxRow + dRow >= kBoardSize) dRow -= (maxRow + dRow - kBoardSize + 1);
    if (minCol < 0) dCol = -minCol;
    if (maxCol + dCol >= kBoardSize) dCol -= (maxCol + dCol - kBoardSize + 1);
    return [
      for (var i = 0; i < offsets.length; i++) (rows[i] + dRow, cols[i] + dCol),
    ];
  }

  /// SALVO — three in a horizontal line, centred on the tapped cell.
  static List<(int, int)> salvo(int r, int c) =>
      _clamp(r, c, const [(0, -1), (0, 0), (0, 1)]);

  /// SPRAY — the two cells the player picked, verbatim (no shape to
  /// clamp; both taps are already on-board by construction).
  static List<(int, int)> spray((int, int) a, (int, int) b) => [a, b];

  /// DEPTH CHARGE — a 2×2 block with the tapped cell as its top-left.
  static List<(int, int)> depthCharge(int r, int c) =>
      _clamp(r, c, const [(0, 0), (0, 1), (1, 0), (1, 1)]);

  /// CROSS FIRE — a plus, five cells, centred on the tapped cell.
  static List<(int, int)> crossFire(int r, int c) => _clamp(
      r, c, const [(0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)]);

  /// BARRAGE — four DISTINCT random cells, drawn from [avoid] (cells to
  /// skip — pass the shooter's own already-fired cells so a barrage
  /// never wastes one of its four shots on water already tried, and
  /// never wastes one on a duplicate within itself).
  static List<(int, int)> barrage(Random rng, Set<(int, int)> avoid) =>
      _randomDistinct(rng, 4, avoid);

  static List<(int, int)> _randomDistinct(
    Random rng,
    int count,
    Set<(int, int)> avoid,
  ) {
    final out = <(int, int)>{};
    // The board is 100 cells; even with most of it already fired at,
    // this converges fast, and a hard cap keeps it from ever spinning —
    // if genuinely fewer than `count` cells remain, it returns what it
    // could find rather than looping forever.
    for (var attempt = 0; attempt < 500 && out.length < count; attempt++) {
      final cell = (rng.nextInt(kBoardSize), rng.nextInt(kBoardSize));
      if (!avoid.contains(cell)) out.add(cell);
    }
    return out.toList();
  }
}
