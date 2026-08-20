import 'dart:math';

/// Grid size for every battle.
const int kBoardSize = 10;

/// Shot cooldown between consecutive fires (seconds).
const int kCooldownSeconds = 2;

/// Ship identifiers in the classic fleet.
enum ShipKind { carrier, battleship, cruiser, submarine, destroyer }

class ShipSpec {
  final ShipKind kind;
  final String name;
  final String shortName;
  final int size;

  const ShipSpec(this.kind, this.name, this.shortName, this.size);
}

/// The standard 5-ship fleet.
const List<ShipSpec> kFleet = [
  ShipSpec(ShipKind.carrier, 'Aircraft Carrier', 'CV', 5),
  ShipSpec(ShipKind.battleship, 'Battleship', 'BB', 4),
  ShipSpec(ShipKind.cruiser, 'Cruiser', 'CA', 3),
  ShipSpec(ShipKind.submarine, 'Submarine', 'SS', 3),
  ShipSpec(ShipKind.destroyer, 'Destroyer', 'DD', 2),
];

/// A single placed ship.
class PlacedShip {
  final ShipSpec spec;
  final int row;
  final int col;
  final bool horizontal;
  final Set<int> hitIndices; // indices within cells list that were hit

  late final List<List<int>> cells = List.generate(
    spec.size,
    (i) => horizontal ? [row, col + i] : [row + i, col],
  );

  PlacedShip({
    required this.spec,
    required this.row,
    required this.col,
    required this.horizontal,
    Set<int>? hitIndices,
  }) : hitIndices = hitIndices ?? <int>{};

  /// O(1) cell-membership check without allocating a cells list.
  bool containsCell(int r, int c) {
    if (horizontal) {
      if (r != row) return false;
      final i = c - col;
      return i >= 0 && i < spec.size;
    } else {
      if (c != col) return false;
      final i = r - row;
      return i >= 0 && i < spec.size;
    }
  }

  /// Returns the local cell index for (r, c) or null if not on this ship.
  int? cellIndexAt(int r, int c) {
    if (horizontal) {
      if (r != row) return null;
      final i = c - col;
      return (i >= 0 && i < spec.size) ? i : null;
    } else {
      if (c != col) return null;
      final i = r - row;
      return (i >= 0 && i < spec.size) ? i : null;
    }
  }

  bool get isSunk => hitIndices.length >= spec.size;

  PlacedShip copy() => PlacedShip(
        spec: spec,
        row: row,
        col: col,
        horizontal: horizontal,
        hitIndices: Set<int>.from(hitIndices),
      );

  Map<String, dynamic> toJson() => {
        'k': spec.kind.index,
        'r': row,
        'c': col,
        'h': horizontal,
        // Damage travels with the ship so a mid-match board can be
        // restored exactly — see `Board.toJson`. Omitted from the initial
        // placement exchange only in the sense that it is empty there.
        'x': hitIndices.toList(),
      };

  static PlacedShip fromJson(Map<String, dynamic> json) => PlacedShip(
        spec: kFleet.firstWhere((s) => s.kind.index == json['k']),
        row: json['r'] as int,
        col: json['c'] as int,
        horizontal: json['h'] as bool,
        hitIndices: (json['x'] as List?)?.map((e) => e as int).toSet(),
      );
}

/// Result of one fired shot.
enum ShotResult { miss, hit, sunk, duplicate, cooldown, invalid }

/// A player's defensive board.
class Board {
  final List<PlacedShip> ships = [];
  final Set<String> _shots = {}; // "r,c" already fired at

  bool containsShipAt(int r, int c) =>
      ships.any((s) => s.containsCell(r, c));

  PlacedShip? shipAt(int r, int c) {
    for (final s in ships) {
      if (s.containsCell(r, c)) return s;
    }
    return null;
  }

  bool canPlace(ShipSpec spec, int row, int col, bool horizontal) {
    if (horizontal) {
      if (col + spec.size > kBoardSize) return false;
    } else {
      if (row + spec.size > kBoardSize) return false;
    }
    for (var i = 0; i < spec.size; i++) {
      final r = horizontal ? row : row + i;
      final c = horizontal ? col + i : col;
      if (containsShipAt(r, c)) return false;
    }
    return true;
  }

  void place(ShipSpec spec, int row, int col, bool horizontal) {
    ships.add(PlacedShip(spec: spec, row: row, col: col, horizontal: horizontal));
  }

  void removeShip(ShipKind kind) {
    ships.removeWhere((s) => s.spec.kind == kind);
  }

  PlacedShip? shipOfKind(ShipKind kind) {
    for (final s in ships) {
      if (s.spec.kind == kind) return s;
    }
    return null;
  }

  bool get isComplete => ships.length == kFleet.length;

  bool get allSunk => ships.every((s) => s.isSunk);

  int get sunkCount => ships.where((s) => s.isSunk).length;

  bool alreadyShot(int r, int c) => _shots.contains('$r,$c');

  // ------------------------------------------------- MANOEUVRE MODE ---

  /// Whether this hull is still free to move. A single hit pins a ship
  /// where it is for the rest of the match — you only get to run while
  /// the enemy still has no idea where you are.
  bool canRelocate(PlacedShip ship) => ship.hitIndices.isEmpty;

  /// Whether [ship] could legally sit at (row, col, horizontal): fully
  /// on-grid, clear of every OTHER ship, and — the rule specific to this
  /// mode — clear of every cell the enemy has already fired at. Water
  /// that has been shot at is public knowledge, so a ship can never be
  /// tucked into it to make a known miss retroactively wrong.
  bool canRelocateTo(PlacedShip ship, int row, int col, bool horizontal) {
    if (!canRelocate(ship)) return false;
    final size = ship.spec.size;
    if (horizontal) {
      if (col < 0 || row < 0 || row >= kBoardSize || col + size > kBoardSize) {
        return false;
      }
    } else {
      if (col < 0 || row < 0 || col >= kBoardSize || row + size > kBoardSize) {
        return false;
      }
    }
    for (var i = 0; i < size; i++) {
      final r = horizontal ? row : row + i;
      final c = horizontal ? col + i : col;
      if (alreadyShot(r, c)) return false;
      final occupant = shipAt(r, c);
      if (occupant != null && occupant.spec.kind != ship.spec.kind) return false;
    }
    return true;
  }

  /// Moves an undamaged ship. Returns false and changes nothing if the
  /// destination is illegal, so callers can use the return value directly
  /// as "did this manoeuvre happen".
  bool relocate(ShipKind kind, int row, int col, bool horizontal) {
    final ship = shipOfKind(kind);
    if (ship == null) return false;
    if (!canRelocateTo(ship, row, col, horizontal)) return false;
    ships.remove(ship);
    ships.add(PlacedShip(
      spec: ship.spec,
      row: row,
      col: col,
      horizontal: horizontal,
    ));
    return true;
  }

  /// Receives an incoming shot. Returns the outcome and (if sunk) the ship.
  (ShotResult, PlacedShip?) receiveShot(int r, int c) {
    if (r < 0 || r >= kBoardSize || c < 0 || c >= kBoardSize) {
      return (ShotResult.invalid, null);
    }
    final key = '$r,$c';
    if (_shots.contains(key)) return (ShotResult.duplicate, null);
    _shots.add(key);

    final ship = shipAt(r, c);
    if (ship == null) return (ShotResult.miss, null);

    final idx = ship.cellIndexAt(r, c);
    if (idx != null) {
      ship.hitIndices.add(idx);
    }
    return (ship.isSunk ? ShotResult.sunk : ShotResult.hit, ship.isSunk ? ship : null);
  }

  Board copy() {
    final b = Board();
    for (final s in ships) {
      b.ships.add(s.copy());
    }
    b._shots.addAll(_shots);
    return b;
  }

  /// Serializes the whole board — layout, damage AND the set of cells
  /// already fired at. The last two only matter for the mid-match resume
  /// snapshot a reconnecting player is restored from (see
  /// `GameController.restoreFromSnapshot`); at placement time both are
  /// empty, so the fleet exchange is unaffected.
  Map<String, dynamic> toJson() => {
        'ships': ships.map((s) => s.toJson()).toList(),
        'shots': _shots.toList(),
      };

  static Board fromJson(Map<String, dynamic> json) {
    final b = Board();
    for (final s in (json['ships'] as List)) {
      b.ships.add(PlacedShip.fromJson(Map<String, dynamic>.from(s as Map)));
    }
    for (final k in (json['shots'] as List? ?? const [])) {
      b._shots.add(k as String);
    }
    return b;
  }

  /// Marks a cell as already fired at without resolving a shot against it.
  /// Used when rebuilding a board from a resume snapshot, where the
  /// outcome of every past shot is already known.
  void markShot(int r, int c) => _shots.add('$r,$c');

  /// Randomly places the whole fleet.
  static Board random({Random? rng}) {
    final random = rng ?? Random();
    final b = Board();
    for (final spec in kFleet) {
      var placed = false;
      var attempts = 0;
      while (!placed && attempts < 500) {
        attempts++;
        final horizontal = random.nextBool();
        final row = random.nextInt(kBoardSize);
        final col = random.nextInt(kBoardSize);
        if (b.canPlace(spec, row, col, horizontal)) {
          b.place(spec, row, col, horizontal);
          placed = true;
        }
      }
      // Fallback: scan systematically
      if (!placed) {
        for (var r = 0; r < kBoardSize && !placed; r++) {
          for (var c = 0; c < kBoardSize && !placed; c++) {
            for (final h in [true, false]) {
              if (b.canPlace(spec, r, c, h)) {
                b.place(spec, r, c, h);
                placed = true;
                break;
              }
            }
          }
        }
      }
    }
    return b;
  }
}

/// How a LAN (hotspot / online) match plays out. Both players vote for
/// one of these before deploying their fleets — see the vote protocol in
/// `NetworkService` and `LanModeScreen`.
///
/// Lives here rather than next to [GameMode] in `game_controller.dart`
/// because `NetworkService` (which owns the vote) is imported BY the
/// controller, not the other way round — putting it there would create an
/// import cycle.
enum LanBattleMode {
  /// No turns at all. Both fleets fire the moment their own cannon has
  /// reloaded, so shots cross in mid-air — the cooldown is the only
  /// limiter. Both cannons stay parked at the BACK of their own grid
  /// (the far edge of the screen) for the whole match instead of sliding
  /// out to mark a turn, since there are no turns to mark.
  chaos,

  /// Classic alternating turns, identical in flow to local pass-and-play:
  /// a hit lets you fire again, a miss hands the turn to your opponent,
  /// and the active player's cannon slides out to the middle of their own
  /// grid as the "your turn" indicator.
  turns,

  /// Turn-based, plus a fleet that can still manoeuvre: between shots you
  /// may drag your own ships to new water. Only ships that are still
  /// completely undamaged can move (one hit and that hull is pinned for
  /// the rest of the match), and they can never be moved onto a cell the
  /// enemy has already fired at — you cannot un-discover water.
  rearrange,
}

extension LanBattleModeX on LanBattleMode {
  String get label => switch (this) {
        LanBattleMode.chaos => 'CHAOS',
        LanBattleMode.turns => 'TURN BASED',
        LanBattleMode.rearrange => 'MANOEUVRE',
      };

  String get tagline => switch (this) {
        LanBattleMode.chaos => 'Fire at will — no turns',
        LanBattleMode.turns => 'Take turns — hit to keep firing',
        LanBattleMode.rearrange => 'Take turns — and keep moving',
      };

  String get blurb => switch (this) {
        LanBattleMode.chaos =>
          'Both fleets fire at the same time from the back of their own '
              'waters. No waiting, no turn order — only your reload timer '
              'holds you back.',
        LanBattleMode.turns =>
          'One shot at a time. Land a hit and you fire again; miss and the '
              'guns pass to your opponent.',
        LanBattleMode.rearrange =>
          'Turn-based, but your fleet can run. Between shots, drag any '
              'ship that is still undamaged to fresh water — a hull that '
              'has been hit is pinned, and nowhere already fired on is safe '
              'to hide.',
      };

  /// True for the modes that alternate turns (everything but chaos).
  bool get hasTurns => this != LanBattleMode.chaos;
}

/// Difficulty of the AI captain.
enum AIDifficulty { easy, normal, hard }

extension AIDifficultyX on AIDifficulty {
  String get label => switch (this) {
        AIDifficulty.easy => 'ROOKIE',
        AIDifficulty.normal => 'VETERAN',
        AIDifficulty.hard => 'ADMIRAL',
      };
}
