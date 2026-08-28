// GHOST FLEET — the mode where the water keeps no record.
//
// The design in one sentence: `Board.receiveShot`, `canRelocate` and
// `canRelocateTo` still work exactly as every other mode's — this mode
// just calls them with three flags flipped (`allowRefire`, `ignoreDamage`,
// `ignoreShotHistory`) rather than teaching the model a new rule set. So
// most of what needs pinning down here is that those flags do precisely
// what they say and nothing more, plus the one piece of real complexity
// GHOST FLEET introduces on top: allowing a cell to be fired at twice
// reopens a network-replay bug the OTHER modes are protected from for
// free (see `GameController._lastPeerFireSeq`), and that protection needs
// its own coverage.
import 'package:battleship_blitz/models/game_models.dart';
import 'package:battleship_blitz/services/game_controller.dart';
import 'package:battleship_blitz/services/network_service.dart';
import 'package:battleship_blitz/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<GameController> _newGhostController({bool host = true}) async {
  SharedPreferences.setMockInitialValues({});
  final profile = ProfileStore();
  await profile.load();
  final net = NetworkService();
  net.setMatchHost(host);
  final c = GameController(profile: profile, network: net);
  c.mode = GameMode.hotspot;
  c.lanBattleMode = LanBattleMode.ghost;
  return c;
}

/// Feeds a raw incoming 'fire' message to [c] and lets it actually be
/// processed before returning.
///
/// `NetworkService.messages` is a broadcast `Stream`, and
/// `GameController.attachNetwork` subscribes to it with an ordinary
/// `.listen()` — so `_onNetMessage` runs on the NEXT microtask, not
/// synchronously inside `handleIncomingForTest`'s `.add()` call. Every
/// assertion in this file that reads state `_onNetMessage` is
/// responsible for goes through this helper rather than the raw method,
/// so a test can never race its own event.
/// Delivers one incoming shot AND lets its shell land.
///
/// GHOST FLEET is a mode a fleet can move in, so an arriving `'fire'` no
/// longer scores anything by itself — it arms a shell that is scored
/// `kShellFlight` later against wherever the hulls sit by then (see
/// `GameController._armIncomingShell`). Every test in this file is about
/// what the shot RESOLVES to, so they land it immediately; the dodge
/// window itself is exercised in `dodge_test.dart`.
Future<void> _incomingFire(GameController c, int r, int col, int seq) async {
  c.network
      .handleIncomingForTest({'type': 'fire', 'r': r, 'c': col, 'seq': seq});
  await pumpEventQueue();
  c.landIncomingShellsForTest();
  await pumpEventQueue();
}

/// A harmless, out-of-the-way enemy fleet for tests that don't care about
/// the enemy board's own contents. `beginBattle(enemyBoard: Board())`
/// with a truly EMPTY board is a trap: `Board.allSunk` is
/// `ships.every(...)`, which is vacuously true over an empty list, so an
/// empty enemy board reads as "already fully sunk" the instant any hit
/// anywhere triggers `_checkVictory`. A single ship far from anything
/// these tests actually fire at avoids that without the test needing to
/// care about it.
Board _harmlessEnemyBoard() => Board()..place(kFleet.first, 9, 5, true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LanBattleMode.ghost — the rules it turns on', () {
    test('turn-based and rearranging, like Manoeuvre', () {
      expect(LanBattleMode.ghost.hasTurns, isTrue);
      expect(LanBattleMode.ghost.canRearrange, isTrue);
    });

    test('the axes only Ghost Fleet and Phantom flip', () {
      expect(LanBattleMode.ghost.recordsShots, isFalse);
      expect(LanBattleMode.phantom.recordsShots, isFalse);
      expect(LanBattleMode.ghost.movesWhenDamaged, isTrue);
      expect(LanBattleMode.ghost.canRearrange, isTrue);
      // PHANTOM is Ghost Fleet's silence with a FIXED fleet: it never
      // rearranges, so no hull of its — damaged or not — ever moves.
      expect(LanBattleMode.phantom.movesWhenDamaged, isFalse);
      expect(LanBattleMode.phantom.canRearrange, isFalse);
      for (final m in LanBattleMode.values) {
        if (m == LanBattleMode.ghost || m == LanBattleMode.phantom) {
          continue;
        }
        expect(m.recordsShots, isTrue, reason: '$m must still record shots');
        expect(m.movesWhenDamaged, isFalse,
            reason: '$m must still pin a damaged hull');
      }
    });

    test('Ghost and Phantom both keep the moment yet hide the record', () {
      // Neither GHOST FLEET nor PHANTOM records anything ([recordsShots]
      // feeds `isGhostBattle`, which keeps the grid's persistent marks off
      // and disables the duplicate-shot rule). But the just-landed impact —
      // the transient explosion and screen shake — is still shown; what
      // those modes deny is only that anything is remembered, not that the
      // hit moment happens at all (see `BattleScreen._refreshDerivedCache` /
      // `_resolveImpact`).
      expect(LanBattleMode.ghost.recordsShots, isFalse);
      expect(LanBattleMode.phantom.recordsShots, isFalse);
      expect(LanBattleMode.ghost.movesWhenDamaged, isTrue);
      expect(LanBattleMode.phantom.movesWhenDamaged, isFalse,
          reason: "Phantom is Ghost's silence with a fleet that can't move");
    });

    test('label, tagline and blurb are distinct from every other mode',
        () {
      final labels = LanBattleMode.values.map((m) => m.label).toSet();
      final taglines = LanBattleMode.values.map((m) => m.tagline).toSet();
      final blurbs = LanBattleMode.values.map((m) => m.blurb).toSet();
      expect(labels.length, LanBattleMode.values.length);
      expect(taglines.length, LanBattleMode.values.length);
      expect(blurbs.length, LanBattleMode.values.length);
    });

    test('appended, not inserted — its index is what goes over the wire',
        () {
      // chaos=0, turns=1, rearrange=2, blitz=3, ghost=4, powerPlay=5,
      // phantom=6. Pinned so an accidental reorder (which would silently
      // reinterpret an in-flight match against an older build — see the
      // enum's own doc) fails a test instead of shipping quietly.
      expect(LanBattleMode.chaos.index, 0);
      expect(LanBattleMode.turns.index, 1);
      expect(LanBattleMode.rearrange.index, 2);
      expect(LanBattleMode.blitz.index, 3);
      expect(LanBattleMode.ghost.index, 4);
      expect(LanBattleMode.powerPlay.index, 5);
      expect(LanBattleMode.phantom.index, 6);
      expect(LanBattleMode.values.length, 7);
    });
  });

  group('GameController.isGhostBattle', () {
    test('true only for an actual network match voted into Ghost Fleet',
        () async {
      final c = await _newGhostController();
      expect(c.isGhostBattle, isTrue);
    });

    test('false outside a network match, even with a stale ghost pick',
        () async {
      // `lanBattleMode` is meaningless outside hotspot/online and can be
      // left over from a previous match's vote — every mode-derived flag
      // on the controller has to gate on `isNetworkBattle` for exactly
      // this reason, not just read the mode.
      final c = await _newGhostController();
      c.mode = GameMode.vsAI;
      expect(c.isGhostBattle, isFalse);
      c.mode = GameMode.local;
      expect(c.isGhostBattle, isFalse);
    });

    test('false for every mode that keeps records', () async {
      final c = await _newGhostController();
      for (final m in LanBattleMode.values) {
        // PHANTOM shares Ghost Fleet's record-free rules — the seq replay
        // guard, the refire allowance and the silent log all key off this
        // getter, so it reads TRUE there by design.
        if (m == LanBattleMode.ghost || m == LanBattleMode.phantom) continue;
        c.lanBattleMode = m;
        expect(c.isGhostBattle, isFalse, reason: '$m keeps records');
      }
    });
  });

  group('Board — the three relaxations, in isolation', () {
    test('allowRefire: the same cell can be shot twice, fresh each time',
        () {
      final b = Board(); // empty water at (0,0)
      final first = b.receiveShot(0, 0, allowRefire: true);
      expect(first.$1, ShotResult.miss);
      final second = b.receiveShot(0, 0, allowRefire: true);
      expect(second.$1, ShotResult.miss,
          reason: 'still a miss — nothing moved there in between');
    });

    test('allowRefire: a re-fire sees whatever is ACTUALLY there now', () {
      // The mechanic Ghost Fleet is built for: a miss can stop being a
      // miss if a hull moves into that water afterward.
      final b = Board()..place(kFleet[4], 5, 5, true); // destroyer
      expect(b.receiveShot(0, 0, allowRefire: true).$1, ShotResult.miss);
      expect(
          b.relocate(ShipKind.destroyer, 0, 0, true,
              ignoreDamage: true, ignoreShotHistory: true),
          isTrue);
      final refire = b.receiveShot(0, 0, allowRefire: true);
      expect(refire.$1, ShotResult.hit,
          reason: 'the destroyer is sitting there now');
    });

    test('without allowRefire, the ordinary duplicate rule is untouched',
        () {
      final b = Board();
      expect(b.receiveShot(3, 3).$1, ShotResult.miss);
      expect(b.receiveShot(3, 3).$1, ShotResult.duplicate);
    });

    test('ignoreDamage: a hit hull can still be relocated', () {
      final b = Board()..place(kFleet[4], 0, 0, true);
      b.receiveShot(0, 0); // one hit — pinned in every other mode
      final ship = b.shipOfKind(ShipKind.destroyer)!;
      expect(b.canRelocate(ship), isFalse);
      expect(b.canRelocate(ship, ignoreDamage: true), isTrue);
      expect(b.relocate(ShipKind.destroyer, 5, 5, true, ignoreDamage: true),
          isTrue);
      // The move does not heal it — see `Board.relocate`'s doc.
      expect(b.shipOfKind(ShipKind.destroyer)!.hitIndices, isNotEmpty);
    });

    test('ignoreShotHistory: a hull can hide in water already fired at',
        () {
      final b = Board()..place(kFleet[4], 0, 0, true);
      b.receiveShot(5, 6); // known miss at what will become the new spot
      expect(b.relocate(ShipKind.destroyer, 5, 5, true), isFalse,
          reason: 'ordinary rule: still covers the known-empty (5,6)');
      expect(
          b.relocate(ShipKind.destroyer, 5, 5, true,
              ignoreShotHistory: true),
          isTrue,
          reason: 'Ghost Fleet: shot-up water is no longer off-limits');
    });

    test('the three flags are independent of each other', () {
      // ignoreDamage alone does not also waive shot history, and vice
      // versa — Ghost Fleet happens to pass both together, but nothing
      // stops a caller from asking for just one.
      final b = Board()..place(kFleet[4], 0, 0, true);
      b.receiveShot(0, 0); // damages the ship
      b.receiveShot(5, 6); // and marks the destination's neighbour cell
      final ship = b.shipOfKind(ShipKind.destroyer)!;
      expect(
          b.canRelocateTo(ship, 5, 5, true, ignoreDamage: true), isFalse,
          reason: 'damage waived, but (5,6) is still shot-up water');
      expect(
          b.canRelocateTo(ship, 5, 5, true, ignoreShotHistory: true),
          isFalse,
          reason: 'shot history waived, but the hull is still pinned');
      expect(
          b.canRelocateTo(ship, 5, 5, true,
              ignoreDamage: true, ignoreShotHistory: true),
          isTrue);
    });
  });

  group('allowRefire: a repeat hit on the same cell redirects, not wastes',
      () {
    // BUGFIX (permanently unsinkable, and in GHOST FLEET permanently
    // un-movable, hull): the shooter has no marks to tell them a cell is
    // already hit, so landing on it again is expected, not a mistake — but
    // a plain `Set.add` of an index already present is a no-op, so a hull
    // could take any number of shots on the one cell and never gain a
    // second point of real damage. See `Board.receiveShot`.
    test('a second hit on the same cell lands on the nearest fresh one',
        () {
      final b = Board()..place(kFleet[2], 0, 0, true); // cruiser, 3 cells
      final ship = b.shipOfKind(ShipKind.cruiser)!;

      expect(b.receiveShot(0, 1, allowRefire: true).$1, ShotResult.hit);
      expect(ship.hitIndices, {1});

      // Same cell again — must not be a no-op.
      final second = b.receiveShot(0, 1, allowRefire: true);
      expect(second.$1, ShotResult.hit,
          reason: 'still a genuine hit, just not on index 1 again');
      expect(ship.hitIndices, hasLength(2),
          reason: 'real, additional damage — not a wasted shot');
      // The nearest still-open cell to index 1 is picked — index 0 and 2
      // are equidistant, and the lower one wins ties.
      expect(ship.hitIndices, {1, 0});
    });

    test('repeated fire at the same cell can still sink the hull', () {
      final b = Board()..place(kFleet[4], 0, 0, true); // destroyer, 2 cells
      final ship = b.shipOfKind(ShipKind.destroyer)!;

      expect(b.receiveShot(0, 0, allowRefire: true).$1, ShotResult.hit);
      expect(ship.isSunk, isFalse);

      // A shooter with no marks who keeps guessing the SAME reported
      // spot must still be able to finish the kill.
      final again = b.receiveShot(0, 0, allowRefire: true);
      expect(again.$1, ShotResult.sunk,
          reason: 'the second hit redirects onto the last open cell');
      expect(ship.isSunk, isTrue);
      expect(ship.hitIndices, {0, 1});
    });

    test('an already-sunk hull is a wreck — firing into it is a MISS', () {
      final b = Board()..place(kFleet[4], 0, 0, true); // destroyer
      b.receiveShot(0, 0, allowRefire: true);
      b.receiveShot(0, 1, allowRefire: true); // sunk
      final ship = b.shipOfKind(ShipKind.destroyer)!;
      expect(ship.isSunk, isTrue);

      // `activeShipAt` still finds a sunk-but-not-`sunkCleared` hull — the
      // window before GHOST FLEET's fade animation frees the water, and in
      // PHANTOM (which never frees it) every shot for the rest of the
      // match. There is nothing left there to damage, so it reads as
      // water: no second kill announcement, and no hit to keep the
      // shooter's streak alive on top of a wreck.
      final stray = b.receiveShot(0, 0, allowRefire: true);
      expect(stray.$1, ShotResult.miss);
      expect(stray.$2, isNull, reason: 'a kill is announced exactly once');
      expect(ship.hitIndices, {0, 1}, reason: 'unchanged — nothing to add');
    });

    test('a cell of a sunk hull never aimed at before is also a MISS', () {
      // Reachable only because of the redirect: two shells on cell 0 sink
      // a destroyer without cell 1 ever being fired at, so the "you must
      // have already fired here" reasoning does not cover it.
      final b = Board()..place(kFleet[4], 0, 0, true); // destroyer
      b.receiveShot(0, 0, allowRefire: true);
      b.receiveShot(0, 0, allowRefire: true); // redirects — sunk
      expect(b.shipOfKind(ShipKind.destroyer)!.isSunk, isTrue);

      expect(b.receiveShot(0, 1, allowRefire: true).$1, ShotResult.miss);
    });

    test('without allowRefire, a repeat is still the ordinary duplicate',
        () {
      // The redirect is scoped to GHOST FLEET/PHANTOM's own relaxation —
      // every other mode keeps its existing "you cannot re-target a cell
      // you've already fired at" rule untouched.
      final b = Board()..place(kFleet[2], 0, 0, true);
      expect(b.receiveShot(0, 1).$1, ShotResult.hit);
      expect(b.receiveShot(0, 1).$1, ShotResult.duplicate);
      expect(b.shipOfKind(ShipKind.cruiser)!.hitIndices, {1});
    });

    test(
        'GHOST FLEET end to end: the deadlock this fixes — stuck neither '
        'sinking nor movable', () async {
      final c = await _newGhostController(host: true);
      c.boards[0] = Board()..place(kFleet.last, 0, 0, true); // destroyer
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();

      // The attacker holds the turn and, with no marks to go by, fires
      // twice at the exact same reported cell.
      c.peerHasTurn = true;
      await _incomingFire(c, 0, 0, 0);
      await _incomingFire(c, 0, 0, 1);

      final ship = c.boards[0].shipOfKind(ShipKind.destroyer)!;
      expect(ship.isSunk, isTrue,
          reason: 'two shots on a two-cell hull must be able to finish it '
              '— not stall forever on one cell');
    });
  });

  group('GameController — combat log carries no coordinates', () {
    test(
        'a miss and a hit are silent; the killing blow is announced '
        'without one', () async {
      final c = await _newGhostController(host: true);
      c.boards[0] = Board()..place(kFleet.last, 0, 0, true); // destroyer
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.combatLog.clear();

      // A miss from the peer.
      await _incomingFire(c, 5, 5, 0);
      expect(c.combatLog, isEmpty, reason: 'a miss must not be logged');

      // A hit that does not yet sink the destroyer.
      await _incomingFire(c, 0, 0, 1);
      expect(c.combatLog, isEmpty, reason: 'nor a hit');

      // The killing blow.
      await _incomingFire(c, 0, 1, 2);
      expect(c.combatLog, hasLength(1));
      expect(c.combatLog.single, contains('SANK'));
      expect(c.combatLog.single, isNot(contains('A2')),
          reason: 'the sinking is narrated, but not at a named coordinate '
              '— (0,1) would print as A2');
    });

    test('a non-ghost match still logs coordinates as before', () async {
      final c = await _newGhostController(host: true);
      c.lanBattleMode = LanBattleMode.turns;
      c.mode = GameMode.local;
      c.boards[0] = Board()..place(kFleet.last, 0, 0, true);
      c.beginBattle(enemyBoard: Board()..place(kFleet.last, 9, 9, true));
      c.combatLog.clear();

      c.fireAt(9, 9); // local mode resolves immediately, a genuine hit
      expect(c.combatLog.any((l) => l.contains('J10')), isTrue);
    });
  });

  group('a damaged hull runs for as long as it stays afloat', () {
    // BUGFIX (ships getting stuck): a damaged hull used to be movable only
    // while the attacker held the turn AND its per-hull "escape window"
    // was still open — and that window closed permanently the first time
    // the owner's own turn began. Since the thing that hands the turn over
    // IS the attacker's miss, one hit plus one miss froze a perfectly
    // healthy ship for the rest of the match. Ghost Fleet's promise is
    // that nothing recorded where you were hit, so damage never costs you
    // the right to run: the only hull that stops moving is one that has
    // sunk.
    test('a hit hull still relocates after the turn has passed back',
        () async {
      final c = await _newGhostController(host: true);
      c.boards[0] = Board()..place(kFleet.last, 0, 0, true); // destroyer
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();

      // The attacker holds the turn and lands a hit.
      c.peerHasTurn = true;
      await _incomingFire(c, 0, 0, 0);
      final ship = c.boards[0].shipOfKind(ShipKind.destroyer)!;
      expect(ship.hitIndices, isNotEmpty, reason: 'the shot landed');
      expect(c.damageIgnorableFor(ship), isTrue,
          reason: 'under fire: the damaged hull may still run');

      expect(c.relocateOwnShip(ShipKind.destroyer, 5, 5, true), isTrue,
          reason: 'the dodge goes through, damage carried along');
      expect(c.boards[0].shipOfKind(ShipKind.destroyer)!.hitIndices,
          isNotEmpty, reason: 'moving does not heal the hull');

      // The attacker misses; the turn passes to this side — exactly the
      // moment the old escape window slammed shut for good.
      c.peerHasTurn = false;
      c.onMyTurnStart(); // what BattleScreen._passTurn invokes

      // NB: re-fetch — the relocation replaced the PlacedShip in the
      // board (see `Board.reposition`), so the old reference is stale.
      final moved = c.boards[0].shipOfKind(ShipKind.destroyer)!;
      expect(moved.hitIndices, isNotEmpty,
          reason: 'the dodge carried the damage along');
      expect(c.damageIgnorableFor(moved), isTrue,
          reason: 'still afloat, so still free to run');
      expect(c.relocateOwnShip(ShipKind.destroyer, 7, 7, true), isTrue,
          reason: 'movable on our own turn too');

      // And it keeps that freedom through any number of later turns.
      c.peerHasTurn = true;
      expect(c.relocateOwnShip(ShipKind.destroyer, 8, 8, true), isTrue);
      c.peerHasTurn = false;
      c.onMyTurnStart();
      expect(c.relocateOwnShip(ShipKind.destroyer, 2, 2, true), isTrue);
    });

    test('taking a SECOND hit on the same reported cell does not pin it',
        () async {
      // The exact flow reported: hit the middle of a hull, hit that same
      // spot again (which `Board.receiveShot` redirects onto a fresh
      // cell), then miss. The hull is damaged but very much alive.
      final c = await _newGhostController(host: true);
      c.boards[0] = Board()..place(kFleet.first, 0, 0, true); // carrier, 5
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();

      c.peerHasTurn = true;
      await _incomingFire(c, 0, 2, 0); // the middle of the hull
      await _incomingFire(c, 0, 2, 1); // the same spot again — redirected
      await _incomingFire(c, 9, 9, 2); // a miss, handing the turn over
      c.peerHasTurn = false;
      c.onMyTurnStart();

      final ship = c.boards[0].shipOfKind(kFleet.first.kind)!;
      expect(ship.hitIndices, hasLength(2),
          reason: 'the repeat shot did real, additional damage');
      expect(ship.isSunk, isFalse);
      expect(c.canRelocate(ship), isTrue);
      expect(c.relocateOwnShip(kFleet.first.kind, 4, 0, true), isTrue,
          reason: 'alive and not destroyed — it must still be able to run');
    });

    test('a SUNK hull is the one thing that stops moving', () async {
      final c = await _newGhostController(host: true);
      c.boards[0] = Board()..place(kFleet.last, 0, 0, true); // destroyer
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();

      c.peerHasTurn = true;
      await _incomingFire(c, 0, 0, 0);
      await _incomingFire(c, 0, 1, 1);

      final ship = c.boards[0].shipOfKind(ShipKind.destroyer)!;
      expect(ship.isSunk, isTrue);
      expect(c.damageIgnorableFor(ship), isFalse,
          reason: 'a wreck is not a ship');
      expect(c.relocateOwnShip(ShipKind.destroyer, 5, 5, true), isFalse);
    });

    test('an undamaged hull is unaffected by the turn state', () async {
      final c = await _newGhostController(host: true);
      c.boards[0] = Board()..place(kFleet.last, 0, 0, true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();

      c.peerHasTurn = false;
      c.onMyTurnStart();
      final ship = c.boards[0].shipOfKind(ShipKind.destroyer)!;
      expect(ship.hitIndices, isEmpty);
      expect(c.relocateOwnShip(ShipKind.destroyer, 5, 5, true), isTrue,
          reason: 'ghost rule: an intact hull may run at any time');
    });

    test('damage rides through a move and a board round-trip', () async {
      final b = Board()..place(kFleet.last, 0, 0, true);
      b.shipOfKind(ShipKind.destroyer)!.hitIndices.add(0);

      expect(b.relocate(ShipKind.destroyer, 4, 4, true,
          ignoreDamage: true, ignoreShotHistory: true), isTrue);
      expect(b.shipOfKind(ShipKind.destroyer)!.hitIndices, {0},
          reason: 'moving does not heal the hull');

      final restored = Board.fromJson({
        'ships': [b.shipOfKind(ShipKind.destroyer)!.toJson()],
        'shots': <String>[],
      });
      expect(restored.shipOfKind(ShipKind.destroyer)!.hitIndices, {0},
          reason: 'the damage survives a resume snapshot');
    });
  });

  group('the network-replay guard Ghost Fleet needs on its own', () {
    // `Board.receiveShot`'s cell-based duplicate check is what protects
    // every OTHER mode from a redelivered 'fire' message being applied
    // twice (see the bugfix comment above the 'fire' case in
    // `_onNetMessage`). Ghost Fleet turns that check off on purpose, so
    // it needs the seq-based guard instead — this is what would have
    // caught the original bug in a mode where cell-based dedup can't be
    // reused.
    test('a fresh fire from the peer is applied normally', () async {
      final c = await _newGhostController(host: true);
      c.boards[0] = Board(); // this device's own fleet — empty water
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();

      await _incomingFire(c, 2, 2, 0);
      expect(c.p2Shots[2][2], 1, reason: "the peer's shot landed as a miss");
    });

    test('an identical redelivery of that fire is answered but not '
        're-applied', () async {
      final c = await _newGhostController(host: true);
      c.boards[0] = Board()..place(kFleet.last, 2, 2, true); // destroyer
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();

      await _incomingFire(c, 2, 2, 0);
      expect(c.p2Shots[2][2], 2, reason: 'first delivery: a real hit');
      final eventsAfterFirst = c.events.length;

      // The SAME message, redelivered — same seq, as a genuine retry
      // would be (see `RelayLink._flush`'s doc for why this happens).
      await _incomingFire(c, 2, 2, 0);
      expect(c.events.length, eventsAfterFirst,
          reason:
              'a replay must not append a second combat event for one shot');
    });

    test(
        'a genuinely later fire from the peer at the same cell IS applied '
        '— that is the whole point of the mode', () async {
      final c = await _newGhostController(host: true);
      c.boards[0] = Board(); // (2,2) starts empty
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();

      await _incomingFire(c, 2, 2, 0);
      expect(c.p2Shots[2][2], 1, reason: 'first fire: a miss');

      // A ship of ours moves into (2,2) between the two shots — allowed
      // in Ghost Fleet regardless of whether (2,2) was fired at before.
      c.boards[0].place(kFleet.last, 2, 2, true);

      // A NEW fire from the peer at the same cell — a higher seq, so it
      // is not mistaken for a replay of the first one.
      await _incomingFire(c, 2, 2, 1);
      expect(c.p2Shots[2][2], 2,
          reason: 'this is a fresh shot and must see the ship that moved in');
    });
  });

  group('reconnect: the seq counter survives a cold restart', () {
    // BUGFIX: a returning player's `_fireSeq` used to reset to 0 on a
    // fresh `GameController` (a real app restart, not just a dropped
    // socket) while the SURVIVOR's `_lastPeerFireSeq` — untouched, since
    // the survivor never went anywhere — stayed at whatever it last saw.
    // The returner's very first shot after reconnecting then looked
    // exactly like a stray redelivery of their very first shot of the
    // whole match, and the survivor answered it with a stale cached
    // result instead of actually resolving it. See the doc on
    // `buildResumeSnapshot`'s `yourFireSeq`/`yourLastPeerFireSeq` fields.
    test('a returner restored from a snapshot fires seq 3 against a '
        'survivor sitting at _lastPeerFireSeq 2 — and it is resolved, '
        'not echoed', () async {
      final survivor = await _newGhostController(host: true);
      survivor.boards[0] = Board(); // empty water — every incoming shot misses
      survivor.beginBattle(enemyBoard: _harmlessEnemyBoard());
      survivor.attachNetwork();
      await _incomingFire(survivor, 0, 0, 0);
      await _incomingFire(survivor, 0, 1, 1);
      await _incomingFire(survivor, 0, 2, 2); // survivor's _lastPeerFireSeq == 2

      final snapshot = survivor.buildResumeSnapshot();

      // A BRAND NEW controller — simulating the app having fully
      // restarted, not merely reconnected a socket.
      final returner = await _newGhostController(host: false);
      returner.restoreFromSnapshot(snapshot);
      returner.peerHasTurn = false; // isolate the seq behaviour from turn order
      returner.cooldown1 = 0;

      returner.fireAt(5, 5);
      final sent =
          returner.network.sentForTest.lastWhere((m) => m['type'] == 'fire');
      expect(sent['seq'], 3,
          reason: 'must continue the sequence, not restart it at 0');

      await _incomingFire(survivor, 5, 5, 3);
      expect(survivor.p2Shots[5][5], isNot(0),
          reason: "the returner's first shot after reconnecting must be "
              'resolved for real, not treated as a stale replay');
    });
  });
}
