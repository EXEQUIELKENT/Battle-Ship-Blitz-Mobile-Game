import 'dart:math';

/// Grid size for every battle.
const int kBoardSize = 10;

/// Shot cooldown between consecutive fires (seconds).
const int kCooldownSeconds = 2;

/// How long a cannonball spends in the air.
///
/// Shared rather than a screen-local animation duration, because in the
/// modes a fleet can still move in it is a RULE, not decoration: the
/// defending device gives an incoming shell exactly this long to arrive
/// before scoring it against the board (see
/// `GameController._armIncomingShell`), which is the window a hull has to
/// dodge out from under it. The shooter's flight animation and the
/// defender's dodge window have to be the same number or one of the two
/// is lying to its player.
const Duration kShellFlight = Duration(milliseconds: 750);

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

  /// GHOST FLEET only: whether this hull is permanently in the water.
  ///
  /// When a hull is destroyed in GHOST FLEET, its owner watches a sinking
  /// animation play and fade — and the moment it does, the water goes
  /// BLANK: the cells it used are freed again, so a surviving hull can be
  /// relocated onto them (the whole point of saying "you may run" in a mode
  /// where nothing is ever recorded). That "gone for good" state is this
  /// flag. It is set once, via `GameController.clearSunkShip` / the
  /// mirrored `'ship_cleared'` message, and never reverted. Meaningless in
  /// every other mode — they keep a hull pinned/visible until game over.
  bool sunkCleared;

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
    this.sunkCleared = false,
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
        sunkCleared: sunkCleared,
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
        // GHOST FLEET's sunk-and-freed pin — see [sunkCleared]. Always
        // false outside that mode, so serializing it unconditionally is
        // harmless there.
        'f': sunkCleared,
      };

  static PlacedShip fromJson(Map<String, dynamic> json) => PlacedShip(
        spec: kFleet.firstWhere((s) => s.kind.index == json['k']),
        row: json['r'] as int,
        col: json['c'] as int,
        horizontal: json['h'] as bool,
        hitIndices: (json['x'] as List?)?.map((e) => e as int).toSet(),
        sunkCleared: json['f'] as bool? ?? false,
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

  /// The ship actually occupying a cell RIGHT NOW for gameplay purposes —
  /// i.e. excluding hulls whose GHOST FLEET sank-and-freed state
  /// ([PlacedShip.sunkCleared]) has freed their water.
  ///
  /// Everything that decides whether a shot hits or a relocation is legal
  /// reads this rather than [shipAt], so a hull the owner watched sink and
  /// fade away no longer occupies its old cells: re-firing there is a fresh
  /// miss, and a surviving hull may be dragged onto it. Display/status
  /// (which still want to see a sunk hull until game over) keep reading
  /// [shipAt] / [ships].
  PlacedShip? activeShipAt(int r, int c) {
    for (final s in ships) {
      if (!s.sunkCleared && s.containsCell(r, c)) return s;
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

  /// Moves an already-placed ship to a new row/col/orientation IN PLACE —
  /// i.e. at the same index in [ships] it already occupied — instead of
  /// the remove-then-append pattern `removeShip` + `place` produces.
  ///
  /// `ships` paints in list order (see `BattleGrid._shipWidgets`), so
  /// removing an entry and re-appending it silently moves it to the END
  /// of that order. Every OTHER caller that repositions a ship this way
  /// (manual tap-to-rotate, manual drag-to-move, Manoeuvre-mode relocate)
  /// was doing exactly that — reordering paint order on every single
  /// reposition — which is the same root cause `PlacementScreen
  ///._runRandomize` had to work around locally for the RANDOM button's
  /// reshuffle: whenever a ship's `AnimatedPositioned` box briefly
  /// overlaps a neighbour's mid-slide, a z-order flip during that overlap
  /// reads as a little shift/pop right as the ship arrives. Centralizing
  /// the fix here (rather than leaving it duplicated ad hoc at each call
  /// site) means EVERY path that moves a ship — not just RANDOM — keeps
  /// stable paint order. Returns false and touches nothing if [kind]
  /// isn't currently on the board.
  bool reposition(ShipKind kind, int row, int col, bool horizontal) {
    final idx = ships.indexWhere((s) => s.spec.kind == kind);
    if (idx == -1) return false;
    final old = ships[idx];
    ships[idx] = PlacedShip(
      spec: old.spec,
      row: row,
      col: col,
      horizontal: horizontal,
      hitIndices: Set<int>.from(old.hitIndices),
      // A cleared hull is never moved again, but carrying the flag is
      // harmless and keeps the model honest.
      sunkCleared: old.sunkCleared,
    );
    return true;
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
  ///
  /// [ignoreDamage] lifts that pin — GHOST FLEET's own rule, where a
  /// damaged hull can still run because nothing recorded where it was
  /// hit in the first place. See [LanBattleMode.movesWhenDamaged].
  bool canRelocate(PlacedShip ship, {bool ignoreDamage = false}) =>
      ignoreDamage || ship.hitIndices.isEmpty;

  /// Whether [ship] could legally sit at (row, col, horizontal): fully
  /// on-grid, clear of every OTHER ship, and — the rule specific to this
  /// mode — clear of every cell the enemy has already fired at. Water
  /// that has been shot at is public knowledge, so a ship can never be
  /// tucked into it to make a known miss retroactively wrong.
  ///
  /// [ignoreDamage] and [ignoreShotHistory] are GHOST FLEET's two
  /// relaxations of that — see [canRelocate] and
  /// [LanBattleMode.recordsShots]. Every other mode leaves both false and
  /// gets the rules exactly as documented above.
  bool canRelocateTo(
    PlacedShip ship,
    int row,
    int col,
    bool horizontal, {
    bool ignoreDamage = false,
    bool ignoreShotHistory = false,
  }) {
    if (!canRelocate(ship, ignoreDamage: ignoreDamage)) return false;
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
      if (!ignoreShotHistory && alreadyShot(r, c)) return false;
      // `activeShipAt`, not `shipAt`: a GHOST FLEET hull that sank and was
      // freed ([PlacedShip.sunkCleared]) no longer blocks — the water it
      // left is free for a surviving hull to move back onto.
      final occupant = activeShipAt(r, c);
      if (occupant != null && occupant.spec.kind != ship.spec.kind) return false;
    }
    return true;
  }

  /// Moves a ship. Returns false and changes nothing if the destination
  /// is illegal, so callers can use the return value directly as "did
  /// this manoeuvre happen". See [canRelocateTo] for [ignoreDamage] and
  /// [ignoreShotHistory].
  bool relocate(
    ShipKind kind,
    int row,
    int col,
    bool horizontal, {
    bool ignoreDamage = false,
    bool ignoreShotHistory = false,
  }) {
    final ship = shipOfKind(kind);
    if (ship == null) return false;
    if (!canRelocateTo(
      ship,
      row,
      col,
      horizontal,
      ignoreDamage: ignoreDamage,
      ignoreShotHistory: ignoreShotHistory,
    )) {
      return false;
    }
    // Outside GHOST FLEET, `canRelocate` already required
    // `hitIndices.isEmpty` above, so `reposition`'s carry-over of the old
    // hit set is a no-op — but going through it anyway keeps every mode
    // on one path (see `reposition`'s doc comment) instead of
    // reintroducing the same remove-then-append z-order bug locally. In
    // GHOST FLEET a damaged hull genuinely does carry its existing
    // `hitIndices` to the new spot: moving doesn't heal it, it just stops
    // the enemy's last-known information from being right any more.
    return reposition(kind, row, col, horizontal);
  }

  /// Receives an incoming shot. Returns the outcome and (if sunk) the ship.
  ///
  /// [allowRefire] is GHOST FLEET's (and PHANTOM's) rule: nothing is
  /// recorded, so a cell already fired at is evaluated completely fresh
  /// rather than being bounced as a duplicate — which matters precisely
  /// because a ship may have since moved into it. Every other mode leaves
  /// this false and keeps a fired cell fired for good, which is also what
  /// protects those modes from a redelivered network message being
  /// applied twice (see `GameController._lastPeerFireSeq` for how these
  /// two modes replace that protection, since they are the one place it
  /// is deliberately given up).
  (ShotResult, PlacedShip?) receiveShot(int r, int c, {bool allowRefire = false}) {
    if (r < 0 || r >= kBoardSize || c < 0 || c >= kBoardSize) {
      return (ShotResult.invalid, null);
    }
    final key = '$r,$c';
    if (!allowRefire && _shots.contains(key)) {
      return (ShotResult.duplicate, null);
    }
    _shots.add(key);

    final ship = activeShipAt(r, c);
    if (ship == null) return (ShotResult.miss, null);

    // BUGFIX (a destroyed hull kept answering as a fresh HIT/SUNK): a sunk
    // ship is a wreck — there is nothing left there to damage, so a shell
    // landing on one of its cells is water. Two ways in, both of them
    // essentially only in the record-free modes: firing again at a cell the
    // shooter has no mark to warn them about (PHANTOM, which never frees a
    // wreck's water at all, and GHOST FLEET in the window before the owner's
    // fade animation frees it via [PlacedShip.sunkCleared]), or firing for
    // the FIRST time at a cell whose hull was already finished off through
    // the redirect below without that particular cell ever being aimed at.
    // Falling through re-reported `.sunk` with the ship attached every time
    // — re-announcing the kill in the log, replaying the sinking beat, and
    // crediting the shooter with a hit that keeps their streak alive on
    // water that holds nothing but debris.
    if (ship.isSunk) return (ShotResult.miss, null);

    final idx = ship.cellIndexAt(r, c);
    if (idx != null) {
      // `!ship.isSunk` is guaranteed by the wreck check above, which is
      // also what guarantees `open` below is never empty.
      if (allowRefire && ship.hitIndices.contains(idx)) {
        // BUGFIX (permanently unsinkable AND, in GHOST FLEET, permanently
        // un-movable hull): [allowRefire] means the shooter has no marks
        // to tell them this cell already carries a hit, so landing on it
        // again is the mode working exactly as designed, not a mistake to
        // punish with a wasted shot. Left as a plain `Set.add` (a no-op
        // for an index already present), a hull could take any number of
        // shots on the one cell and never gain a SECOND point of real
        // damage — never sinking no matter how long the match ran, which
        // left the attacker with no way to finish it and the owner with a
        // hull they could not stop being shot at. Redirect the hit to
        // the nearest cell of the same hull that has not been hit yet
        // instead: the shooter still scores a genuine hit, sinking a hull
        // is always eventually reachable, and the defender sees real,
        // additional damage appear on their own ship art rather than a
        // shot that visibly landed but changed nothing.
        final open = [
          for (var i = 0; i < ship.spec.size; i++) i,
        ].where((i) => !ship.hitIndices.contains(i)).toList()
          ..sort((a, b) => (a - idx).abs().compareTo((b - idx).abs()));
        ship.hitIndices.add(open.first);
      } else {
        ship.hitIndices.add(idx);
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

  /// Undoes [markShot] — see `GameController._healOne`'s doc for why a
  /// REPAIR/PATCH CREW heal needs this: it frees the cell to be
  /// legitimately re-targeted once the shooter's own `myShots` mark for
  /// it is cleared too (over the wire — this side alone isn't enough).
  void unmarkShot(int r, int c) => _shots.remove('$r,$c');

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

/// Finds the closest legal top-left anchor for a hull of [size] cells in
/// the given [horizontal] orientation, searching outward from
/// ([anchorRow], [anchorCol]) — the spot a flip was actually attempted at.
///
/// Used to improve turning a ship in place (deployment's tap-to-rotate,
/// and Manoeuvre/Blitz's in-battle version): the straightforward approach
/// only ever tries the ship's own current anchor, nudged back on-grid if
/// the new orientation would run off an edge, and simply refuses the turn
/// if THAT one spot happens to be blocked (by another hull during
/// deployment, or additionally by a cell the enemy has already shot at
/// mid-battle) — even when the new orientation would fit perfectly fine a
/// couple of cells over. This searches every remaining legal anchor for
/// the requested orientation and returns whichever is nearest (by simple
/// row+column distance) to where the flip was tried, so a blocked turn
/// still finds somewhere to land instead of just failing outright.
///
/// [canPlaceAt] supplies the actual legality check for a candidate
/// top-left anchor, so the same search serves both a fresh deployment
/// (backed by [Board.canPlace]) and an in-battle manoeuvre (backed by
/// [Board.canRelocateTo]) without this needing to know which rule set is
/// in play. Returns null only when literally no anchor anywhere on the
/// board can legally hold this orientation.
({int row, int col})? findNearestRotationAnchor({
  required int size,
  required bool horizontal,
  required int anchorRow,
  required int anchorCol,
  required bool Function(int row, int col) canPlaceAt,
}) {
  final maxRow = horizontal ? kBoardSize - 1 : kBoardSize - size;
  final maxCol = horizontal ? kBoardSize - size : kBoardSize - 1;
  if (maxRow < 0 || maxCol < 0) return null;

  int? bestRow;
  int? bestCol;
  var bestDist = 1 << 30;
  for (var r = 0; r <= maxRow; r++) {
    for (var c = 0; c <= maxCol; c++) {
      if (!canPlaceAt(r, c)) continue;
      final dist = (r - anchorRow).abs() + (c - anchorCol).abs();
      if (dist < bestDist) {
        bestDist = dist;
        bestRow = r;
        bestCol = c;
        if (dist == 0) break;
      }
    }
    if (bestDist == 0) break;
  }
  if (bestRow == null || bestCol == null) return null;
  return (row: bestRow, col: bestCol);
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

  /// Turn-based, plus a fleet that can still manoeuvre: at any point —
  /// including while an enemy shell is in the air at one of them, which
  /// is what makes a dodge a real dodge (see `kShellFlight`) — you may
  /// drag your own ships to new water. Only ships that are still
  /// completely undamaged can move (one hit and that hull is pinned for
  /// the rest of the match), and they can never be moved onto a cell the
  /// enemy has already fired at — you cannot un-discover water.
  rearrange,

  /// Both of the above at once: no turns AND a fleet that can still run.
  /// Cannons stay parked at the back of their own waters and fire the
  /// moment they reload, exactly as in [chaos], while undamaged hulls can
  /// be dragged to fresh water at any time, exactly as in [rearrange].
  ///
  /// Appended rather than slotted in beside its two parents on purpose:
  /// [index] is what goes over the wire in the vote and in a resume
  /// snapshot, so inserting anywhere else would silently reinterpret an
  /// in-flight match on a device running the older build.
  blitz,

  /// Turn-based, like [rearrange] — but the water keeps no record of
  /// anything. No hit, no miss and no wreck is ever marked on either
  /// grid: every hull, damaged or not, can run to any cell at any time,
  /// including one that has already been fired at, and a sunk ship sinks
  /// away rather than leaving a marker behind. The only thing either
  /// captain can still trust is memory and the ships-left counter.
  ///
  /// Also appended, for the same reason [blitz] was.
  ghost,

  /// Turn-based, like [turns] — but every turn you may be holding one
  /// random power-up, drawn the moment your empty-handed turn begins and
  /// kept (never more than one at a time) until you choose to spend it.
  /// See `lib/models/power_up.dart` for the twenty-card deck.
  ///
  /// Also appended, for the same reason [blitz] and [ghost] were.
  powerPlay,

  /// Turn-based, with Ghost Fleet's total silence and a fleet that can
  /// NEVER move once deployed. Nothing is recorded and nothing is
  /// announced: a shot never tells the shooter whether it hit or missed —
  /// no mark, no wreck, not even the splash-against-explosion difference
  /// Ghost Fleet still shows in the moment. The only progress report
  /// either captain gets is the ships-left counter (and a sinking's own
  /// coordinate-less announcement); the owner of a sinking hull still
  /// watches it go down on their own water.
  ///
  /// Also appended, for the same reason [blitz], [ghost] and [powerPlay]
  /// were.
  phantom,
}

extension LanBattleModeX on LanBattleMode {
  String get label => switch (this) {
        LanBattleMode.chaos => 'CHAOS',
        LanBattleMode.turns => 'TURN BASED',
        LanBattleMode.rearrange => 'MANOEUVRE',
        LanBattleMode.blitz => 'BLITZ',
        LanBattleMode.ghost => 'GHOST FLEET',
        LanBattleMode.powerPlay => 'POWER PLAY',
        LanBattleMode.phantom => 'PHANTOM',
      };

  String get tagline => switch (this) {
        LanBattleMode.chaos => 'Fire at will — no turns',
        LanBattleMode.turns => 'Take turns — hit to keep firing',
        LanBattleMode.rearrange => 'Take turns — and keep moving',
        LanBattleMode.blitz => 'No turns, and keep moving',
        LanBattleMode.ghost => 'Take turns — nothing leaves a mark',
        LanBattleMode.powerPlay => 'Take turns — with a power-up in hand',
        LanBattleMode.phantom => 'Take turns — you never know if you hit',
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
          'Turn-based, but your fleet can run. Drag any ship that is still '
              'undamaged to fresh water — even with a shell already in the '
              'air, so a hull moved in time dodges the shot outright. A '
              'hull that has been hit is pinned, and nowhere already fired '
              'on is safe to hide.',
        LanBattleMode.blitz =>
          'Everything at once. No turn order, no waiting — both fleets '
              'fire on their own reload timers, and any hull that has not '
              'been hit yet can run for fresh water while the shells are '
              'still in the air. Move it in time and the shell lands on '
              'nothing.',
        LanBattleMode.ghost =>
          'Turn-based, but the water keeps no record. Shots land, yet '
              'nothing is marked — every hull can run, damaged or not, and '
              'a sunk ship sinks away rather than leaving a wreck. All you '
              'can trust is your memory and the ships-left counter.',
        LanBattleMode.powerPlay =>
          'One shot at a time, same as Turn Based — plus a random '
              'power-up waiting in your hand every turn you don\'t already '
              'have one. Spend it whenever you like: a sweep of intel, an '
              'extra shot, a repair, a trap laid in your own water.',
        LanBattleMode.phantom =>
          'Ghost Fleet\'s silence, with a fleet that can never move. '
              'Turn-based, fixed positions, and your guns tell you '
              'nothing: no hit, no miss, no mark, no wreck — not even the '
              'splash of the moment. Only the ships-left counter reveals '
              'your progress.',
      };

  /// True for the modes that alternate turns.
  bool get hasTurns => this != LanBattleMode.chaos && this != LanBattleMode.blitz;

  /// True only for POWER PLAY — see the mode's own doc.
  bool get hasPowerUps => this == LanBattleMode.powerPlay;

  /// True for the modes where an undamaged hull can still be moved.
  ///
  /// Ghost Fleet included: it relaxes WHERE a hull may move (see
  /// [recordsShots]) but not WHETHER manoeuvring happens at all — it is
  /// still a mode a ship can be dragged and rotated in, same as
  /// Manoeuvre and Blitz.
  bool get canRearrange =>
      this == LanBattleMode.rearrange ||
      this == LanBattleMode.blitz ||
      this == LanBattleMode.ghost;

  /// False for Ghost Fleet AND Phantom — the two modes that keep no
  /// record. Every other mode marks a fired-at cell with a hit/miss
  /// marker, remembers it as struck water for the duplicate-shot and
  /// can't-hide-here rules, and reveals a sunk hull's wreck. The record
  /// -free two do none of that — see the docs on [LanBattleMode.ghost]
  /// and [LanBattleMode.phantom] for what "no record" means in full.
  bool get recordsShots =>
      this != LanBattleMode.ghost && this != LanBattleMode.phantom;

  /// True only for Ghost Fleet: the one mode where a hull already hit can
  /// still be dragged to new water, for as long as it stays afloat (see
  /// `GameController.damageIgnorableFor`). Every other rearranging mode
  /// pins a damaged hull in place for the rest of the match.
  bool get movesWhenDamaged => this == LanBattleMode.ghost;

  // NB: there is deliberately no "hides the impact" axis anymore. Ghost
  // Fleet and Phantom both keep the just-landed hit's explosion and screen
  // shake — a hit moment reads dramatically on the shooter's screen too
  // (see `BattleScreen._refreshDerivedCache` / `_resolveImpact`). What they
  // hide is only the RECORD ([recordsShots]): no persistent marker, no
  // wreck left on the attacker's board, no cell remembered as fired.
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
