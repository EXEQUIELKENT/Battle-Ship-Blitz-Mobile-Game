import 'package:flutter/material.dart';

/// The six thematic families from the "Skin system architecture" design.
///
/// The design's central claim is that a family is **structural, not
/// chromatic**: each one owns its own cannon silhouette, its own shell,
/// its own five hull classes and its own board treatment, and stays
/// readable with the colour stripped out. So a family here is a bundle of
/// palettes plus a set of painters — never just a pair of tint colours,
/// which is all the original nine skins ever were.
///
/// Nothing in this file knows about the board, the turn order or the
/// network. Painters take a size and a paint set and draw; that is what
/// lets six new fleets ship without `GameController`, `Board`, the AI or
/// the LAN protocol changing at all.
enum FleetFamilyId { pirate, naval, steam, arctic, volcanic, scifi }

/// Colours a family's ships are drawn from.
class ShipPalette {
  final Color hull, trim, deck, sail, ink, glow;
  final double inkW;

  const ShipPalette({
    required this.hull,
    required this.trim,
    required this.deck,
    required this.sail,
    required this.ink,
    required this.glow,
    required this.inkW,
  });
}

/// Colours a family's cannon is drawn from. Deliberately separate from
/// [ShipPalette] — the design gives the guns their own values (arctic's
/// mount is a colder trim than its hulls, sci-fi inverts hull and deck).
class GunPalette {
  final Color hull, trim, deck, ink, glow;
  final double inkW;

  const GunPalette({
    required this.hull,
    required this.trim,
    required this.deck,
    required this.ink,
    required this.glow,
    required this.inkW,
  });
}

/// Colours a family's projectile is drawn from.
class ShellPalette {
  final Color hull, trim, ink, glow;
  final double inkW;

  const ShellPalette({
    required this.hull,
    required this.trim,
    required this.ink,
    required this.glow,
    required this.inkW,
  });
}

/// Everything the battlefield needs from a family: the water, the grid,
/// the deck behind it and the marker colours.
class BoardPalette {
  /// Deck behind the grid — the half's background.
  final Color deck;

  /// Base water/field colour of the grid itself.
  final Color field;

  /// Gridline colour and weight.
  final Color line;
  final double lineWidth;

  /// Accent used for chrome (badges, ready glow, turn scrim).
  final Color accent;

  /// The colour a miss reads as, for anything that needs one flat value.
  final Color miss;

  const BoardPalette({
    required this.deck,
    required this.field,
    required this.line,
    required this.lineWidth,
    required this.accent,
    required this.miss,
  });
}

/// One complete family.
class FleetFamily {
  final FleetFamilyId id;

  /// Stable string id, shared with the catalogue and the network
  /// handshake. Prefixed per asset type at the catalogue level so a hull
  /// and a cannon from the same family never collide.
  final String key;

  final String fleetName; // 'Blackpowder Fleet'
  final String cannonName; // 'Bell-Mouth Broadside'
  final String shellName; // 'Round Shot'
  final String boardName; // 'Pirate Seas'

  final String tagline;
  final String cannonNote;
  final String boardNote;

  final Color accent;
  final ShipPalette ship;
  final GunPalette gun;
  final ShellPalette shell;
  final BoardPalette board;

  /// Geometry tokens — the design's own table. [muzzleFrac] is the one
  /// the battle screen reads to spawn the cannonball, so a long-barrelled
  /// gun genuinely fires from further out than a stubby mortar.
  final double barrelFrac;
  final double muzzleFrac;
  final double shellRadius;

  /// Prices, in RP.
  final int hullCost;
  final int cannonCost;
  final int boardCost;

  const FleetFamily({
    required this.id,
    required this.key,
    required this.fleetName,
    required this.cannonName,
    required this.shellName,
    required this.boardName,
    required this.tagline,
    required this.cannonNote,
    required this.boardNote,
    required this.accent,
    required this.ship,
    required this.gun,
    required this.shell,
    required this.board,
    required this.barrelFrac,
    required this.muzzleFrac,
    required this.shellRadius,
    required this.hullCost,
    required this.cannonCost,
    required this.boardCost,
  });

  /// What the whole family costs bought piecemeal.
  int get fullPrice => hullCost + cannonCost + boardCost;

  /// The design's one-tap "matched set": the family for less than the sum
  /// of its parts, because the point of a family is wearing all of it.
  int get setPrice => (fullPrice * 0.8).round();

  int get setSaving => fullPrice - setPrice;
}

/// Registry. Order matches the design's FAMILY 01…06.
class FleetFamilies {
  FleetFamilies._();

  static const pirate = FleetFamily(
    id: FleetFamilyId.pirate,
    key: 'pirate',
    fleetName: 'Blackpowder Fleet',
    cannonName: 'Bell-Mouth Broadside',
    shellName: 'Round Shot',
    boardName: 'Pirate Seas',
    tagline: 'Wood, rope and bronze. Everything is built, not machined — '
        'nothing on this fleet is straight.',
    cannonNote: 'Timber carriage, bronze bell muzzle. Round shot.',
    boardNote: 'Brine cells, rope grid, wrecks on the deck.',
    accent: Color(0xFFF2B24C),
    ship: ShipPalette(
      hull: Color(0xFF8A5A2B),
      trim: Color(0xFFC98A3E),
      deck: Color(0xFF6B4423),
      sail: Color(0xFFEFE2C6),
      ink: Color(0xFF2A1B0F),
      glow: Color(0xFFF2B24C),
      inkW: 4,
    ),
    gun: GunPalette(
      hull: Color(0xFF8A5A2B),
      trim: Color(0xFFC98A3E),
      deck: Color(0xFF6B4423),
      ink: Color(0xFF2A1B0F),
      glow: Color(0xFFF2B24C),
      inkW: 4,
    ),
    shell: ShellPalette(
      hull: Color(0xFF4A4038),
      trim: Color(0xFF8A5A2B),
      ink: Color(0xFF1A130C),
      glow: Color(0xFFF2B24C),
      inkW: 4,
    ),
    board: BoardPalette(
      deck: Color(0xFF1F3B3C),
      field: Color(0xFF2C5A5C),
      line: Color(0xFF8FAE8A),
      lineWidth: 2.4,
      accent: Color(0xFFC98A3E),
      miss: Color(0xFFBEE3D8),
    ),
    barrelFrac: 0.48,
    muzzleFrac: 0.44,
    shellRadius: 0.42,
    hullCost: 650,
    cannonCost: 600,
    boardCost: 800,
  );

  static const naval = FleetFamily(
    id: FleetFamilyId.naval,
    key: 'naval',
    fleetName: 'Iron Pact',
    cannonName: 'MK-IV Autoloader',
    shellName: 'Sabot Shell',
    boardName: 'Fleet Command',
    tagline: 'Modern steel. Faceted, bolted, symmetrical — a shape drawn '
        'with a set square.',
    cannonNote: 'Long barrel, muzzle brake. Finned sabot shell.',
    boardNote: 'Steel cells, range rings and row ticks down the edge.',
    accent: Color(0xFFCFE0EA),
    ship: ShipPalette(
      hull: Color(0xFF5A6B78),
      trim: Color(0xFF8CA0AD),
      deck: Color(0xFF3E4A54),
      sail: Color(0xFFB9C8D2),
      ink: Color(0xFF1B252D),
      glow: Color(0xFFCFE0EA),
      inkW: 2,
    ),
    gun: GunPalette(
      hull: Color(0xFF5A6B78),
      trim: Color(0xFF93A7B4),
      deck: Color(0xFF3E4A54),
      ink: Color(0xFF1B252D),
      glow: Color(0xFFCFE0EA),
      inkW: 2,
    ),
    shell: ShellPalette(
      hull: Color(0xFF6B7A87),
      trim: Color(0xFF404E59),
      ink: Color(0xFF1B252D),
      glow: Color(0xFFFFD166),
      inkW: 2,
    ),
    board: BoardPalette(
      deck: Color(0xFF2A3843),
      field: Color(0xFF305064),
      line: Color(0xFF7FB2CC),
      lineWidth: 1.6,
      accent: Color(0xFFCFE0EA),
      miss: Color(0xFF9FB6C4),
    ),
    barrelFrac: 0.78,
    muzzleFrac: 0.72,
    shellRadius: 0.34,
    hullCost: 800,
    cannonCost: 700,
    boardCost: 950,
  );

  static const steam = FleetFamily(
    id: FleetFamilyId.steam,
    key: 'steam',
    fleetName: 'Brass Consortium',
    cannonName: 'Pressure Battery',
    shellName: 'Governor Sphere',
    boardName: 'Brass Works',
    tagline: 'Pressure, not powder. Boilers, gears and external plumbing '
        'on every hull.',
    cannonNote: 'Three boiler drums and a bypass pipe. Gear sphere.',
    boardNote: 'Riveted quarter-plates with bolts at the intersections.',
    accent: Color(0xFFE8A33D),
    ship: ShipPalette(
      hull: Color(0xFF7A5A34),
      trim: Color(0xFFC99A3F),
      deck: Color(0xFF4E3A22),
      sail: Color(0xFFE0C089),
      ink: Color(0xFF241A10),
      glow: Color(0xFFE8A33D),
      inkW: 3,
    ),
    gun: GunPalette(
      hull: Color(0xFF7A5A34),
      trim: Color(0xFFC99A3F),
      deck: Color(0xFF4E3A22),
      ink: Color(0xFF241A10),
      glow: Color(0xFFE8A33D),
      inkW: 3,
    ),
    shell: ShellPalette(
      hull: Color(0xFF7A5A34),
      trim: Color(0xFFC99A3F),
      ink: Color(0xFF241A10),
      glow: Color(0xFFFFC24A),
      inkW: 3,
    ),
    board: BoardPalette(
      deck: Color(0xFF4A3927),
      field: Color(0xFF4E6474),
      line: Color(0xFF8FA6B4),
      lineWidth: 2,
      accent: Color(0xFFC99A3F),
      miss: Color(0xFFC99A3F),
    ),
    barrelFrac: 0.66,
    muzzleFrac: 0.62,
    shellRadius: 0.46,
    hullCost: 1200,
    cannonCost: 900,
    boardCost: 1150,
  );

  static const arctic = FleetFamily(
    id: FleetFamilyId.arctic,
    key: 'arctic',
    fleetName: 'Rime Wardens',
    cannonName: 'Icebreaker Mortar',
    shellName: 'Rime Shard',
    boardName: 'Rime Field',
    tagline: 'Icebreakers. Blunt ram bows, sealed superstructures, '
        'accreted ice on every windward edge.',
    cannonNote: 'Stubby two-stage barrel behind a collar of crystal shards.',
    boardNote: 'Floes over open water. Snowfall, aurora band.',
    accent: Color(0xFFBDF1FF),
    ship: ShipPalette(
      hull: Color(0xFFC8DCE6),
      trim: Color(0xFF8FC3D8),
      deck: Color(0xFF5E8A9E),
      sail: Color(0xFFEAF7FC),
      ink: Color(0xFF2C3D4A),
      glow: Color(0xFFBDF1FF),
      inkW: 3,
    ),
    gun: GunPalette(
      hull: Color(0xFFC8DCE6),
      trim: Color(0xFF7FB6CE),
      deck: Color(0xFF8FA9B8),
      ink: Color(0xFF2C3D4A),
      glow: Color(0xFFB8F0FF),
      inkW: 3,
    ),
    shell: ShellPalette(
      hull: Color(0xFFBBDCEA),
      trim: Color(0xFF7FB6CE),
      ink: Color(0xFF2C3D4A),
      glow: Color(0xFFEAFBFF),
      inkW: 3,
    ),
    board: BoardPalette(
      deck: Color(0xFFCFE6EE),
      field: Color(0xFF4E86A6),
      line: Color(0xFFDFF4FC),
      lineWidth: 1.8,
      accent: Color(0xFFBDF1FF),
      miss: Color(0xFFEAFBFF),
    ),
    barrelFrac: 0.50,
    muzzleFrac: 0.46,
    shellRadius: 0.44,
    hullCost: 900,
    cannonCost: 1000,
    boardCost: 1100,
  );

  static const volcanic = FleetFamily(
    id: FleetFamilyId.volcanic,
    key: 'volcanic',
    fleetName: 'Cinder Hold',
    cannonName: 'Magma Bombard',
    shellName: 'Ember Slug',
    boardName: 'Cinder Straits',
    tagline: 'Basalt slabs and heat. Asymmetric, cracked, lit from inside.',
    cannonNote: 'Rock-slab mortar. Ember slug, crater impact.',
    boardNote: 'Basalt slabs with molten seams. Rising embers.',
    accent: Color(0xFFFF6A2B),
    ship: ShipPalette(
      hull: Color(0xFF3A3438),
      trim: Color(0xFF514247),
      deck: Color(0xFF221C1F),
      sail: Color(0xFF6B4A3E),
      ink: Color(0xFF12100F),
      glow: Color(0xFFFF6A2B),
      inkW: 3.5,
    ),
    gun: GunPalette(
      hull: Color(0xFF3A3438),
      trim: Color(0xFF241E22),
      deck: Color(0xFF4A3F42),
      ink: Color(0xFF12100F),
      glow: Color(0xFFFF6A2B),
      inkW: 3.5,
    ),
    shell: ShellPalette(
      hull: Color(0xFF332B2E),
      trim: Color(0xFF4C3A34),
      ink: Color(0xFF100D0C),
      glow: Color(0xFFFF6A2B),
      inkW: 3.5,
    ),
    board: BoardPalette(
      deck: Color(0xFF241B1B),
      field: Color(0xFF33262A),
      line: Color(0xFF7A6A62),
      lineWidth: 1.8,
      accent: Color(0xFFFF6A2B),
      miss: Color(0xFF8A8079),
    ),
    barrelFrac: 0.54,
    muzzleFrac: 0.50,
    shellRadius: 0.48,
    hullCost: 1600,
    cannonCost: 1400,
    boardCost: 1600,
  );

  static const scifi = FleetFamily(
    id: FleetFamilyId.scifi,
    key: 'scifi',
    fleetName: 'Helios Drift',
    cannonName: 'Ion Lance',
    shellName: 'Plasma Bolt',
    boardName: 'Helios Grid',
    tagline: 'Nothing touches anything. Segments float, edges emit, '
        'mass is implied.',
    cannonNote: 'Floating segments, forked emitter. Plasma bolt.',
    boardNote: 'Lattice, corner ticks, travelling scan band.',
    accent: Color(0xFF6FE7FF),
    ship: ShipPalette(
      hull: Color(0xFF1B2138),
      trim: Color(0xFF6E8FD8),
      deck: Color(0xFF2B3550),
      sail: Color(0xFF3A4870),
      ink: Color(0xFF121A2E),
      glow: Color(0xFF6FE7FF),
      inkW: 2.5,
    ),
    gun: GunPalette(
      hull: Color(0xFF2B3550),
      trim: Color(0xFF6E8FD8),
      deck: Color(0xFF1B2138),
      ink: Color(0xFF121A2E),
      glow: Color(0xFF6FE7FF),
      inkW: 2.5,
    ),
    shell: ShellPalette(
      hull: Color(0xFF232B45),
      trim: Color(0xFF6E8FD8),
      ink: Color(0xFF121A2E),
      glow: Color(0xFF6FE7FF),
      inkW: 2.5,
    ),
    board: BoardPalette(
      deck: Color(0xFF0E1428),
      field: Color(0xFF16223E),
      line: Color(0xFF3A5A9E),
      lineWidth: 1.4,
      accent: Color(0xFF6FE7FF),
      miss: Color(0xFF6FE7FF),
    ),
    barrelFrac: 0.72,
    muzzleFrac: 0.68,
    shellRadius: 0.40,
    hullCost: 2800,
    cannonCost: 2600,
    boardCost: 2200,
  );

  static const List<FleetFamily> all = [
    pirate,
    naval,
    steam,
    arctic,
    volcanic,
    scifi,
  ];

  /// Looks a family up by its key, or null for the nine original skins —
  /// which have no family and keep their own flat-tint painters.
  static FleetFamily? byKey(String? key) {
    if (key == null) return null;
    for (final f in all) {
      if (f.key == key) return f;
    }
    return null;
  }
}

/// The neutral ramp the design uses for its silhouette acceptance test:
/// "If a row is unreadable here, that skin is not finished." Exposed so
/// the shipyard can show a family's shape without its colour.
const ShipPalette kMonoShipPalette = ShipPalette(
  hull: Color(0xFF9AA0A6),
  trim: Color(0xFFC6CBCF),
  deck: Color(0xFF71777C),
  sail: Color(0xFFE4E7E9),
  ink: Color(0xFF191C1F),
  glow: Color(0xFFF2F4F6),
  inkW: 3,
);
