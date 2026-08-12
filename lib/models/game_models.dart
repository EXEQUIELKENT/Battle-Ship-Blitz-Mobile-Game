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

  PlacedShip({
    required this.spec,
    required this.row,
    required this.col,
    required this.horizontal,
    Set<int>? hitIndices,
  }) : hitIndices = hitIndices ?? <int>{};

  List<List<int>> get cells {
    return List.generate(
      spec.size,
      (i) => horizontal ? [row, col + i] : [row + i, col],
    );
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
      };

  static PlacedShip fromJson(Map<String, dynamic> json) => PlacedShip(
        spec: kFleet.firstWhere((s) => s.kind.index == json['k']),
        row: json['r'] as int,
        col: json['c'] as int,
        horizontal: json['h'] as bool,
      );
}

/// Result of one fired shot.
enum ShotResult { miss, hit, sunk, duplicate, cooldown, invalid }

/// A player's defensive board.
class Board {
  final List<PlacedShip> ships = [];
  final Set<String> _shots = {}; // "r,c" already fired at

  bool containsShipAt(int r, int c) =>
      ships.any((s) => s.cells.any((cell) => cell[0] == r && cell[1] == c));

  PlacedShip? shipAt(int r, int c) {
    for (final s in ships) {
      final cells = s.cells;
      for (var i = 0; i < cells.length; i++) {
        if (cells[i][0] == r && cells[i][1] == c) return s;
      }
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

    final cells = ship.cells;
    for (var i = 0; i < cells.length; i++) {
      if (cells[i][0] == r && cells[i][1] == c) {
        ship.hitIndices.add(i);
        break;
      }
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

  Map<String, dynamic> toJson() => {'ships': ships.map((s) => s.toJson()).toList()};

  static Board fromJson(Map<String, dynamic> json) {
    final b = Board();
    for (final s in (json['ships'] as List)) {
      b.ships.add(PlacedShip.fromJson(Map<String, dynamic>.from(s as Map)));
    }
    return b;
  }

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

/// Difficulty of the AI captain.
enum AIDifficulty { easy, normal, hard }

extension AIDifficultyX on AIDifficulty {
  String get label => switch (this) {
        AIDifficulty.easy => 'ROOKIE',
        AIDifficulty.normal => 'VETERAN',
        AIDifficulty.hard => 'ADMIRAL',
      };
}
