// POWER PLAY — turn-based, with one random power-up in hand at a time.
//
// Every card resolves through one of four routes (see the doc on
// `PowerUpCard` in `lib/models/power_up.dart`), which is what keeps this
// file from needing twenty bespoke tests: `local` cards go through
// `fireAt`/`_fireShotBatch` (already covered structurally by
// `power_up_test.dart`'s shape geometry — this file checks they're wired
// up correctly, including which shots get tagged `hold`), `local+mirror`
// cards mutate `boards[0]` directly, and `defenderAnswers`/`defenderFlag`
// cards round-trip through `NetworkService`. The riskiest code in the
// whole feature is the turn-flow plumbing (`CombatEvent.hold`/`forcePass`)
// and the defender-side effects (DECOY, MINEFIELD/TRAP LINE, HOT SHOT,
// COUNTER BATTERY) that only ever run inside `_onNetMessage` — that's
// where most of the coverage below is spent.
import 'package:battleship_blitz/models/game_models.dart';
import 'package:battleship_blitz/models/power_up.dart';
import 'package:battleship_blitz/services/game_controller.dart';
import 'package:battleship_blitz/services/network_service.dart';
import 'package:battleship_blitz/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<GameController> _newPowerUpController({bool host = true}) async {
  SharedPreferences.setMockInitialValues({});
  final profile = ProfileStore();
  await profile.load();
  final net = NetworkService();
  net.setMatchHost(host);
  final c = GameController(profile: profile, network: net);
  c.mode = GameMode.hotspot;
  c.lanBattleMode = LanBattleMode.powerPlay;
  return c;
}

/// Feeds a raw incoming message to [c] and lets it actually be processed
/// before returning — see `ghost_mode_test.dart`'s `_incomingFire` for why
/// this await is necessary (the message stream delivers on the next
/// microtask, not synchronously inside `handleIncomingForTest`).
Future<void> _incoming(GameController c, Map<String, dynamic> msg) async {
  c.network.handleIncomingForTest(msg);
  await pumpEventQueue();
}

/// A harmless, out-of-the-way enemy fleet — see `ghost_mode_test.dart`'s
/// identical helper for why an empty `Board()` is a trap for `allSunk`.
Board _harmlessEnemyBoard() => Board()..place(kFleet.first, 9, 5, true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LanBattleMode.powerPlay — the rules it turns on', () {
    test('turn-based, but not a rearranging mode', () {
      expect(LanBattleMode.powerPlay.hasTurns, isTrue);
      expect(LanBattleMode.powerPlay.canRearrange, isFalse);
      expect(LanBattleMode.powerPlay.hasPowerUps, isTrue);
      for (final m in LanBattleMode.values) {
        if (m == LanBattleMode.powerPlay) continue;
        expect(m.hasPowerUps, isFalse, reason: '$m must not carry power-ups');
      }
    });
  });

  group('GameController.isPowerUpBattle', () {
    test('true for an actual network match voted into Power Play', () async {
      final c = await _newPowerUpController(host: true);
      expect(c.isPowerUpBattle, isTrue);
    });

    test('false outside a network match, even with a stale Power Play pick',
        () async {
      final c = await _newPowerUpController(host: true);
      c.mode = GameMode.local;
      expect(c.isPowerUpBattle, isFalse);
    });
  });

  group('the turn-start draw', () {
    test('the host draws for their own opening turn', () async {
      final c = await _newPowerUpController(host: true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      expect(c.myPowerUp, isNotNull);
    });

    test('the joiner does not draw until their turn actually starts',
        () async {
      final c = await _newPowerUpController(host: false);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      expect(c.peerHasTurn, isTrue);
      expect(c.myPowerUp, isNull);
    });

    test('never draws a second card while one is already held', () async {
      final c = await _newPowerUpController(host: true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      final held = c.myPowerUp;
      c.onMyTurnStart();
      expect(c.myPowerUp, held);
    });

    test('an incoming JAM flag skips exactly the next draw', () async {
      final c = await _newPowerUpController(host: false); // no opening draw
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      expect(c.myPowerUp, isNull);
      await _incoming(c, {'type': 'pw_flag', 'card': PowerUpCard.jam.index});
      c.onMyTurnStart();
      expect(c.myPowerUp, isNull, reason: 'the jammed turn draws nothing');
      c.onMyTurnStart();
      expect(c.myPowerUp, isNotNull, reason: 'jam only costs ONE turn');
    });
  });

  group('usePowerUp guard rails', () {
    test('refuses when it is not this player\'s turn', () async {
      final c = await _newPowerUpController(host: false);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      expect(c.peerHasTurn, isTrue);
      c.myPowerUp = PowerUpCard.doubleTap;
      expect(c.usePowerUp(), isFalse);
      expect(c.myPowerUp, PowerUpCard.doubleTap,
          reason: 'nothing should be spent');
    });

    test('refuses a targeted card given the wrong number of cells',
        () async {
      final c = await _newPowerUpController(host: true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.myPowerUp = PowerUpCard.salvo; // needs exactly one
      expect(c.usePowerUp(), isFalse);
      expect(c.usePowerUp([(1, 1), (2, 2)]), isFalse);
      expect(c.myPowerUp, PowerUpCard.salvo);
    });

    test('refuses an un-targeted card given a cell', () async {
      final c = await _newPowerUpController(host: true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.myPowerUp = PowerUpCard.jam;
      expect(c.usePowerUp([(1, 1)]), isFalse);
      expect(c.myPowerUp, PowerUpCard.jam);
    });

    test('refuses when no card is held', () async {
      final c = await _newPowerUpController(host: true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.myPowerUp = null;
      expect(c.usePowerUp(), isFalse);
    });
  });

  group('target-picking getters reflect the held card', () {
    test('vary by card', () async {
      final c = await _newPowerUpController(host: true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();

      c.myPowerUp = PowerUpCard.spray;
      expect(c.powerUpNeedsTarget, isTrue);
      expect(c.powerUpTapsNeeded, 2);
      expect(c.powerUpTargetsOwnGrid, isFalse);

      c.myPowerUp = PowerUpCard.minefield;
      expect(c.powerUpTargetsOwnGrid, isTrue);
      expect(c.powerUpTapsNeeded, 1);

      c.myPowerUp = PowerUpCard.jam;
      expect(c.powerUpNeedsTarget, isFalse);

      c.myPowerUp = null;
      expect(c.powerUpNeedsTarget, isFalse);
    });
  });

  group('DOUBLE TAP', () {
    test('holds exactly the next fire, regardless of its own result',
        () async {
      final c = await _newPowerUpController(host: true);
      c.boards[0] = Board();
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.myPowerUp = PowerUpCard.doubleTap;
      expect(c.usePowerUp(), isTrue);
      expect(c.myPowerUp, isNull);

      c.fireAt(0, 0);
      expect(c.network.sentForTest.last['hold'], isTrue);

      c.fireAt(1, 1);
      expect(c.network.sentForTest.last['hold'], isNot(true),
          reason: 'DOUBLE TAP only ever covers the one shot after it');
    });
  });

  group('REPAIR / PATCH CREW', () {
    test('REPAIR heals only the most-damaged ELIGIBLE hull, never a sunk one',
        () async {
      final c = await _newPowerUpController(host: true);
      c.boards[0] = Board()
        ..place(kFleet[2], 0, 0, true) // cruiser, size 3
        ..place(kFleet[3], 3, 0, true) // submarine, size 3
        ..place(kFleet.last, 6, 0, true); // destroyer, size 2
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.boards[0].shipOfKind(ShipKind.cruiser)!.hitIndices.addAll({0, 1});
      c.boards[0].shipOfKind(ShipKind.submarine)!.hitIndices.add(0);
      c.boards[0].shipOfKind(ShipKind.destroyer)!.hitIndices.addAll({0, 1});
      // The destroyer is fully sunk — must never be touched.

      c.myPowerUp = PowerUpCard.repair;
      expect(c.usePowerUp(), isTrue);

      expect(c.boards[0].shipOfKind(ShipKind.cruiser)!.hitIndices, hasLength(1),
          reason: 'the most-damaged eligible hull (2 hits) is healed by one');
      expect(c.boards[0].shipOfKind(ShipKind.submarine)!.hitIndices,
          hasLength(1),
          reason: 'a less-damaged hull is left alone');
      expect(c.boards[0].shipOfKind(ShipKind.destroyer)!.hitIndices,
          hasLength(2),
          reason: 'a sunk hull must never come back');
    });

    test('REPAIR fails harmlessly, keeping the card, when nothing is hurt',
        () async {
      final c = await _newPowerUpController(host: true);
      c.boards[0] = Board()..place(kFleet.last, 0, 0, true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.myPowerUp = PowerUpCard.repair;
      expect(c.usePowerUp(), isFalse);
      expect(c.myPowerUp, PowerUpCard.repair);
    });

    test('PATCH CREW heals every damaged, non-sunk hull by exactly one',
        () async {
      final c = await _newPowerUpController(host: true);
      c.boards[0] = Board()
        ..place(kFleet.last, 0, 0, true) // destroyer, size 2
        ..place(kFleet[2], 3, 0, true) // cruiser, size 3
        ..place(kFleet[1], 6, 0, true); // battleship, size 4
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.boards[0].shipOfKind(ShipKind.destroyer)!.hitIndices.add(0);
      c.boards[0].shipOfKind(ShipKind.cruiser)!.hitIndices.addAll({0, 1});
      c.boards[0]
          .shipOfKind(ShipKind.battleship)!
          .hitIndices
          .addAll({0, 1, 2, 3}); // sunk

      c.myPowerUp = PowerUpCard.patchCrew;
      expect(c.usePowerUp(), isTrue);

      expect(c.boards[0].shipOfKind(ShipKind.destroyer)!.hitIndices, isEmpty);
      expect(
          c.boards[0].shipOfKind(ShipKind.cruiser)!.hitIndices, hasLength(1));
      expect(c.boards[0].shipOfKind(ShipKind.battleship)!.hitIndices,
          hasLength(4),
          reason: 'the sunk battleship must be left exactly as it was');
    });

    // BUGFIX regression (permanently unsinkable hull): healing a hit used
    // to touch `hitIndices` only, leaving the PEER'S `myShots` mark for
    // that cell as a permanent "confirmed hit" — which is exactly what
    // stops `fireAt`'s own duplicate guard from ever letting them
    // re-target it. See the doc on `GameController._healOne`.
    test('REPAIR reopens the healed cell on our own board and tells the '
        'peer to forget it too', () async {
      final c = await _newPowerUpController(host: true);
      c.boards[0] = Board()..place(kFleet.last, 0, 0, true); // (0,0)-(0,1)
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      await _incoming(c, {'type': 'fire', 'r': 0, 'c': 0}); // a genuine hit
      expect(c.boards[0].alreadyShot(0, 0), isTrue);

      c.myPowerUp = PowerUpCard.repair;
      expect(c.usePowerUp(), isTrue);

      expect(c.boards[0].shipOfKind(ShipKind.destroyer)!.hitIndices, isEmpty);
      expect(c.boards[0].alreadyShot(0, 0), isFalse,
          reason: 'the healed cell must become re-targetable again');
      final healMsg =
          c.network.sentForTest.lastWhere((m) => m['type'] == 'pw_heal');
      expect(healMsg['cells'], [
        [0, 0]
      ]);
    });

    test('pw_heal clears the RECEIVER\'s own myShots mark for that cell',
        () async {
      final c = await _newPowerUpController(host: true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.myShots[3][5] = 2; // this device's own confirmed hit on the peer
      await _incoming(c, {
        'type': 'pw_heal',
        'cells': [
          [3, 5]
        ]
      });
      expect(c.myShots[3][5], 0,
          reason: 'a healed cell must be re-targetable again');
    });
  });

  group('SCRAMBLE', () {
    test('only ever moves an undamaged hull, and mirrors the move',
        () async {
      final c = await _newPowerUpController(host: true);
      c.boards[0] = Board()
        ..place(kFleet.last, 0, 0, true) // destroyer, undamaged
        ..place(kFleet[2], 5, 0, true); // cruiser, will be damaged
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.boards[0].shipOfKind(ShipKind.cruiser)!.hitIndices.add(0);
      final cruiserBefore = c.boards[0].shipOfKind(ShipKind.cruiser)!;
      final beforePos =
          (cruiserBefore.row, cruiserBefore.col, cruiserBefore.horizontal);

      c.myPowerUp = PowerUpCard.scramble;
      expect(c.usePowerUp(), isTrue);

      final cruiserAfter = c.boards[0].shipOfKind(ShipKind.cruiser)!;
      expect((cruiserAfter.row, cruiserAfter.col, cruiserAfter.horizontal),
          beforePos,
          reason: 'the damaged hull must never be the one that moves');
      final moveMsg =
          c.network.sentForTest.lastWhere((m) => m['type'] == 'move');
      expect(moveMsg['k'], ShipKind.destroyer.index);
    });

    test('fails harmlessly, keeping the card, when nothing is undamaged',
        () async {
      final c = await _newPowerUpController(host: true);
      c.boards[0] = Board()..place(kFleet.last, 0, 0, true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.boards[0].shipOfKind(ShipKind.destroyer)!.hitIndices.add(0);
      c.myPowerUp = PowerUpCard.scramble;
      expect(c.usePowerUp(), isFalse);
      expect(c.myPowerUp, PowerUpCard.scramble);
    });
  });

  group('multi-shot power-ups', () {
    test('SALVO fires all three shots; only the last one is not held',
        () async {
      final c = await _newPowerUpController(host: true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.myPowerUp = PowerUpCard.salvo;
      expect(c.usePowerUp([(5, 5)]), isTrue);

      final fires =
          c.network.sentForTest.where((m) => m['type'] == 'fire').toList();
      expect(fires, hasLength(3));
      final shape = PowerUpShapes.salvo(5, 5);
      for (var i = 0; i < 3; i++) {
        expect(fires[i]['r'], shape[i].$1);
        expect(fires[i]['c'], shape[i].$2);
        expect(fires[i]['hold'], i < 2 ? isTrue : isNot(true));
      }
    });

    test('SPRAY fires exactly the two tapped cells', () async {
      final c = await _newPowerUpController(host: true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.myPowerUp = PowerUpCard.spray;
      expect(c.usePowerUp([(0, 0), (9, 9)]), isTrue);

      final fires =
          c.network.sentForTest.where((m) => m['type'] == 'fire').toList();
      expect(fires, hasLength(2));
      expect((fires[0]['r'], fires[0]['c']), (0, 0));
      expect((fires[1]['r'], fires[1]['c']), (9, 9));
      expect(fires[0]['hold'], isTrue);
      expect(fires[1]['hold'], isNot(true));
    });

    test('DEPTH CHARGE fires the full clamped 2x2 in a corner', () async {
      final c = await _newPowerUpController(host: true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.myPowerUp = PowerUpCard.depthCharge;
      expect(c.usePowerUp([(9, 9)]), isTrue);

      final fires =
          c.network.sentForTest.where((m) => m['type'] == 'fire').toList();
      expect(fires.map((m) => (m['r'] as int, m['c'] as int)).toSet(),
          {(8, 8), (8, 9), (9, 8), (9, 9)});
    });

    test('CROSS FIRE fires all five cells of the clamped plus', () async {
      final c = await _newPowerUpController(host: true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.myPowerUp = PowerUpCard.crossFire;
      expect(c.usePowerUp([(0, 0)]), isTrue);

      final fires =
          c.network.sentForTest.where((m) => m['type'] == 'fire').toList();
      expect(fires, hasLength(5));
    });

    test('BARRAGE never lands on a cell already fired at', () async {
      final c = await _newPowerUpController(host: true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      // As above: `myShots` is only actually populated once a `result`
      // lands, not by `fireAt` alone in network mode — poke it directly
      // to mark the whole top row already resolved.
      for (var col = 0; col < kBoardSize; col++) {
        c.myShots[0][col] = 1;
      }
      c.myPowerUp = PowerUpCard.barrage;
      final before = c.network.sentForTest.length;
      expect(c.usePowerUp(), isTrue);

      final fires = c.network.sentForTest
          .skip(before)
          .where((m) => m['type'] == 'fire')
          .toList();
      expect(fires, isNotEmpty);
      expect(fires.any((m) => m['r'] == 0), isFalse,
          reason: 'the whole top row was already fired at');
    });

    test('a cell already fired at is skipped for free inside a shaped batch',
        () async {
      final c = await _newPowerUpController(host: true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      // Mark one of SALVO(5,5)'s three cells as already resolved. A bare
      // `fireAt` alone wouldn't do this in network mode — `myShots` is only
      // actually updated once the matching `result` lands (see `fireAt`'s
      // network branch and `_registerShot`) — so this pokes the exact state
      // `_fireShotBatch`'s dedup filter reads, directly.
      c.myShots[5][4] = 1;
      c.myPowerUp = PowerUpCard.salvo;
      final before = c.network.sentForTest.length;
      expect(c.usePowerUp([(5, 5)]), isTrue);

      final newFires = c.network.sentForTest
          .skip(before)
          .where((m) => m['type'] == 'fire')
          .toList();
      expect(newFires, hasLength(2),
          reason: 'only the two NOT-already-fired cells of the shape go out');
      expect(newFires.map((m) => (m['r'] as int, m['c'] as int)).toSet(),
          {(5, 5), (5, 6)});
    });
  });

  group('CHAIN SHOT', () {
    test('fires one bonus shot at an adjacent, unfired cell — but only on '
        'a hit', () async {
      final c = await _newPowerUpController(host: true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.myPowerUp = PowerUpCard.chainShot;
      expect(c.usePowerUp([(5, 5)]), isTrue);
      // `usePowerUp` sends the shot itself, then a trailing `pw_used`
      // banner message — so the shot is not necessarily the LAST thing
      // sent by the time it returns.
      final initialFire =
          c.network.sentForTest.firstWhere((m) => m['type'] == 'fire');
      expect(initialFire, containsPair('r', 5));

      await _incoming(
          c, {'type': 'result', 'r': 5, 'c': 5, 'res': ShotResult.hit.index});
      final bonus = c.network.sentForTest.last;
      expect(bonus['type'], 'fire');
      const adjacent = [(4, 5), (6, 5), (5, 4), (5, 6)];
      expect(adjacent, contains((bonus['r'] as int, bonus['c'] as int)));
    });

    test('fires no bonus shot on a miss', () async {
      final c = await _newPowerUpController(host: true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.myPowerUp = PowerUpCard.chainShot;
      expect(c.usePowerUp([(5, 5)]), isTrue);
      final afterUse = c.network.sentForTest.length;

      await _incoming(
          c, {'type': 'result', 'r': 5, 'c': 5, 'res': ShotResult.miss.index});
      expect(c.network.sentForTest.length, afterUse,
          reason: 'nothing more should have been sent');
    });
  });

  group('RAPID FIRE', () {
    test('halves cooldown for the next three hits, then reverts', () async {
      final c = await _newPowerUpController(host: true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.myPowerUp = PowerUpCard.rapidFire;
      expect(c.usePowerUp(), isTrue);

      Future<void> hitAt(int r, int col) async {
        c.cooldown1 = 0;
        c.fireAt(r, col);
        await _incoming(c,
            {'type': 'result', 'r': r, 'c': col, 'res': ShotResult.hit.index});
      }

      await hitAt(0, 0);
      expect(c.cooldown1, c.cooldownMax1 / 2);
      await hitAt(0, 1);
      expect(c.cooldown1, c.cooldownMax1 / 2);
      await hitAt(0, 2);
      expect(c.cooldown1, c.cooldownMax1 / 2);
      await hitAt(0, 3);
      expect(c.cooldown1, c.cooldownMax1,
          reason: 'the fourth hit is back to the ordinary cooldown');
    });
  });

  group('COUNTER BATTERY', () {
    test('queues exactly one held bonus shot after the next hit taken',
        () async {
      final c = await _newPowerUpController(host: true);
      c.boards[0] = Board()..place(kFleet.last, 3, 3, true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.myPowerUp = PowerUpCard.counterBattery;
      expect(c.usePowerUp(), isTrue);

      await _incoming(c, {'type': 'fire', 'r': 3, 'c': 3}); // the peer hits us

      c.fireAt(0, 0);
      expect(c.network.sentForTest.last['hold'], isTrue,
          reason: 'the bonus shot must not pass the turn even on a miss');
      c.fireAt(0, 1);
      expect(c.network.sentForTest.last['hold'], isNot(true),
          reason: 'the bonus is spent after one shot');
    });

    test('does nothing if the incoming shot missed', () async {
      final c = await _newPowerUpController(host: true);
      c.boards[0] = Board(); // guaranteed miss anywhere
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.myPowerUp = PowerUpCard.counterBattery;
      expect(c.usePowerUp(), isTrue);

      await _incoming(c, {'type': 'fire', 'r': 0, 'c': 0});
      c.fireAt(5, 5);
      expect(c.network.sentForTest.last['hold'], isNot(true));
    });
  });

  group('DECOY', () {
    test('swallows exactly the next hit — no damage, reported as a miss',
        () async {
      final c = await _newPowerUpController(host: true);
      c.boards[0] = Board()..place(kFleet.last, 4, 4, true); // (4,4)-(4,5)
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.myPowerUp = PowerUpCard.decoy;
      expect(c.usePowerUp(), isTrue);

      await _incoming(c, {'type': 'fire', 'r': 4, 'c': 4});
      final result =
          c.network.sentForTest.lastWhere((m) => m['type'] == 'result');
      expect(result['res'], ShotResult.miss.index);
      expect(c.boards[0].shipOfKind(ShipKind.destroyer)!.hitIndices, isEmpty,
          reason: 'no damage should have landed');
      expect(c.boards[0].alreadyShot(4, 4), isTrue,
          reason: 'the cell still counts as fired for duplicate purposes');

      // Spent — the SAME hull's other cell now resolves as a real hit.
      await _incoming(c, {'type': 'fire', 'r': 4, 'c': 5});
      final second = c.network.sentForTest.last;
      expect(second['res'], isNot(ShotResult.miss.index));
    });

    // BUGFIX regression (permanently unsinkable hull): swallowing a hit
    // marks that cell fired on `boards[0]` AND — the instant the result
    // reaches them — on the shooter's own `myShots`. Neither side can
    // ever legally re-target a cell already marked fired, so a decoy
    // swallowing a hull's LAST remaining cell used to make that hull
    // impossible to finish off for the rest of the match.
    test('does NOT swallow a hit that would strand the hull — its last '
        'open cell always lands for real', () async {
      final c = await _newPowerUpController(host: true);
      c.boards[0] = Board()..place(kFleet.last, 4, 4, true); // (4,4)-(4,5)
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.boards[0].shipOfKind(ShipKind.destroyer)!.hitIndices.add(0); // (4,4)
      c.myPowerUp = PowerUpCard.decoy;
      expect(c.usePowerUp(), isTrue);

      // (4,5) is the destroyer's only remaining cell.
      await _incoming(c, {'type': 'fire', 'r': 4, 'c': 5});
      final result =
          c.network.sentForTest.lastWhere((m) => m['type'] == 'result');
      expect(result['res'], ShotResult.sunk.index,
          reason: 'the finishing blow must land for real, or this hull '
              'could never be sunk again');
      expect(c.boards[0].shipOfKind(ShipKind.destroyer)!.isSunk, isTrue);
    });

    // BUGFIX regression, the harder case: the check above is a
    // point-in-time guard and can't see the future — DECOY swallowing a
    // cell while the hull still has OTHER open cells is completely
    // legitimate at the time. If every one of those other cells is later
    // hit NORMALLY (no further decoy involved), the earlier swallow
    // becomes exactly the same dead end in hindsight. This is what
    // `GameController._rescueStrandedHulls` catches after the fact.
    test('a hull decoyed early and finished off normally later is '
        'rescued, not left stranded', () async {
      final c = await _newPowerUpController(host: true);
      c.boards[0] = Board()..place(kFleet[2], 0, 0, true); // cruiser (0,0)-(0,2)
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();

      c.myPowerUp = PowerUpCard.decoy;
      expect(c.usePowerUp(), isTrue);
      await _incoming(c, {'type': 'fire', 'r': 0, 'c': 0}); // swallowed
      expect(c.boards[0].alreadyShot(0, 0), isTrue);
      expect(c.boards[0].shipOfKind(ShipKind.cruiser)!.hitIndices, isEmpty);

      // The other two cells land normally — no decoy left to spend.
      await _incoming(c, {'type': 'fire', 'r': 0, 'c': 1});
      await _incoming(c, {'type': 'fire', 'r': 0, 'c': 2});

      expect(c.boards[0].shipOfKind(ShipKind.cruiser)!.isSunk, isFalse,
          reason: 'the decoyed cell was never actually hit');
      expect(c.boards[0].alreadyShot(0, 0), isFalse,
          reason: 'the phantom cell must be reopened once every other '
              'cell of the hull is spoken for');
      final healMsg =
          c.network.sentForTest.lastWhere((m) => m['type'] == 'pw_heal');
      expect(healMsg['cells'], [
        [0, 0]
      ]);
    });
  });

  group('MINEFIELD / TRAP LINE', () {
    test('MINEFIELD costs the shooter their turn on that one cell, hit or '
        'miss', () async {
      final c = await _newPowerUpController(host: true);
      c.boards[0] = Board();
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.myPowerUp = PowerUpCard.minefield;
      expect(c.usePowerUp([(6, 6)]), isTrue);

      await _incoming(c, {'type': 'fire', 'r': 6, 'c': 6});
      expect(c.network.sentForTest.last['fp'], isTrue);

      await _incoming(c, {'type': 'fire', 'r': 1, 'c': 1});
      expect(c.network.sentForTest.last['fp'], isNot(true),
          reason: 'an unmined cell must never trigger it');
    });

    test('TRAP LINE mines a three-cell line; the first hit consumes the '
        'WHOLE trap', () async {
      final c = await _newPowerUpController(host: true);
      c.boards[0] = Board();
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.myPowerUp = PowerUpCard.trapLine;
      expect(c.usePowerUp([(5, 5)]), isTrue);
      final shape = PowerUpShapes.salvo(5, 5);

      await _incoming(
          c, {'type': 'fire', 'r': shape[0].$1, 'c': shape[0].$2});
      expect(c.network.sentForTest.last['fp'], isTrue);

      await _incoming(
          c, {'type': 'fire', 'r': shape[1].$1, 'c': shape[1].$2});
      expect(c.network.sentForTest.last['fp'], isNot(true),
          reason: 'the other two mines go inert once the trap is sprung');
    });
  });

  group('HOT SHOT', () {
    test('adds one bonus hit on the nearest unhit cell of the same hull',
        () async {
      final c = await _newPowerUpController(host: true);
      c.boards[0] = Board()..place(kFleet[2], 2, 2, true); // cruiser, size 3
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      await _incoming(
          c, {'type': 'pw_flag', 'card': PowerUpCard.hotShot.index});
      await _incoming(c, {'type': 'fire', 'r': 2, 'c': 2});

      final result = c.network.sentForTest.last;
      expect(result['hotR'], isNotNull);
      expect(c.boards[0].shipOfKind(ShipKind.cruiser)!.hitIndices, {0, 1},
          reason: 'the nearest unhit cell to index 0 is index 1');
    });

    test('can complete the sinking through its own bonus cell', () async {
      final c = await _newPowerUpController(host: true);
      c.boards[0] = Board()..place(kFleet.last, 7, 7, true); // (7,7)-(7,8)
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      await _incoming(
          c, {'type': 'pw_flag', 'card': PowerUpCard.hotShot.index});
      await _incoming(c, {'type': 'fire', 'r': 7, 'c': 7});

      final result = c.network.sentForTest.last;
      expect(result['res'], ShotResult.sunk.index);
      expect(result['sunk'], 'Destroyer');
      expect(c.boards[0].shipOfKind(ShipKind.destroyer)!.isSunk, isTrue);
    });

    test('ignores misses and stays armed for the eventual hit', () async {
      final c = await _newPowerUpController(host: true);
      c.boards[0] = Board()..place(kFleet.last, 2, 2, true); // (2,2)-(2,3)
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      await _incoming(
          c, {'type': 'pw_flag', 'card': PowerUpCard.hotShot.index});

      await _incoming(c, {'type': 'fire', 'r': 8, 'c': 8}); // a clean miss
      expect(c.network.sentForTest.last['hotR'], isNull);

      await _incoming(c, {'type': 'fire', 'r': 2, 'c': 2}); // the real hit
      expect(c.network.sentForTest.last['hotR'], isNotNull);
    });

    test('is spent after its one hit', () async {
      final c = await _newPowerUpController(host: true);
      c.boards[0] = Board()
        ..place(kFleet[2], 2, 2, true)
        ..place(kFleet.last, 5, 5, true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      await _incoming(
          c, {'type': 'pw_flag', 'card': PowerUpCard.hotShot.index});
      await _incoming(c, {'type': 'fire', 'r': 2, 'c': 2});
      expect(c.network.sentForTest.last['hotR'], isNotNull);

      await _incoming(c, {'type': 'fire', 'r': 5, 'c': 5});
      expect(c.network.sentForTest.last['hotR'], isNull);
    });
  });

  group('JAM', () {
    test('sends a flag naming the card', () async {
      final c = await _newPowerUpController(host: true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.myPowerUp = PowerUpCard.jam;
      expect(c.usePowerUp(), isTrue);
      final flag =
          c.network.sentForTest.firstWhere((m) => m['type'] == 'pw_flag');
      expect(flag['card'], PowerUpCard.jam.index);
    });
  });

  group('SONAR', () {
    test('counts DISTINCT ships in the 3x3, not cells', () async {
      final c = await _newPowerUpController(host: true);
      c.boards[0] = Board()
        ..place(kFleet.last, 4, 4, true) // destroyer, fully inside the box
        ..place(kFleet[2], 6, 6, true); // cruiser, one cell inside the box
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();

      await _incoming(
          c, {'type': 'pw_ask', 'card': PowerUpCard.sonar.index, 'r': 5, 'c': 5});
      expect(c.network.sentForTest.last['n'], 2);
    });

    test('ignores a ship entirely outside the box', () async {
      final c = await _newPowerUpController(host: true);
      c.boards[0] = Board()..place(kFleet.last, 9, 9, false);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();

      await _incoming(
          c, {'type': 'pw_ask', 'card': PowerUpCard.sonar.index, 'r': 0, 'c': 0});
      expect(c.network.sentForTest.last['n'], 0);
    });

    test('a SONAR answer is logged for the asker', () async {
      final c = await _newPowerUpController(host: true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      await _incoming(
          c, {'type': 'pw_answer', 'card': PowerUpCard.sonar.index, 'n': 2});
      expect(c.combatLog.any((l) => l.contains('SONAR') && l.contains('2')),
          isTrue);
    });
  });

  group('SPOTTER', () {
    test('reveals a real cell of one of the sender\'s own ships', () async {
      final c = await _newPowerUpController(host: true);
      c.boards[0] = Board()..place(kFleet.last, 0, 0, true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();

      await _incoming(
          c, {'type': 'pw_ask', 'card': PowerUpCard.spotter.index});
      final answer = c.network.sentForTest.last;
      expect(answer['type'], 'pw_answer');
      expect(c.boards[0].shipAt(answer['r'] as int, answer['c'] as int),
          isNotNull);
    });

    test('the answer marks the cell on the enemy grid and is logged',
        () async {
      final c = await _newPowerUpController(host: true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      await _incoming(c, {
        'type': 'pw_answer',
        'card': PowerUpCard.spotter.index,
        'r': 3,
        'c': 4,
      });
      expect(c.spottedEnemyCells, contains(3 * kBoardSize + 4));
      expect(c.combatLog.any((l) => l.contains('SPOTTER')), isTrue);
    });
  });

  group('RECON SWEEP', () {
    test('reports whether the tapped row holds any ship', () async {
      final c = await _newPowerUpController(host: true);
      c.boards[0] = Board()..place(kFleet.last, 3, 0, true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();

      await _incoming(c,
          {'type': 'pw_ask', 'card': PowerUpCard.reconSweep.index, 'r': 3});
      expect(c.network.sentForTest.last['has'], isTrue);

      await _incoming(c,
          {'type': 'pw_ask', 'card': PowerUpCard.reconSweep.index, 'r': 9});
      expect(c.network.sentForTest.last['has'], isFalse);
    });

    test('a RECON SWEEP answer is logged for the asker', () async {
      final c = await _newPowerUpController(host: true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      await _incoming(c, {
        'type': 'pw_answer',
        'card': PowerUpCard.reconSweep.index,
        'r': 2,
        'has': true,
      });
      expect(c.combatLog.any((l) => l.contains('RECON')), isTrue);
    });
  });

  group('restoreFromOwnSnapshot', () {
    // BUGFIX regression: Power Play's hand/armed-flags are private to
    // whoever holds them — never sent over the wire — so a snapshot from
    // a real PEER genuinely cannot restore them (see the doc on
    // `restoreFromSnapshot`). `restoreFromOwnSnapshot` is the one path
    // that can, because there the "peer" who supposedly built the
    // snapshot and the device restoring it are the same device — this
    // is what `MatchStore`'s self-persistence path relies on.
    test('round-trips boards, shots, turn, a held card and both armed '
        'defensive effects', () async {
      final c = await _newPowerUpController(host: true);
      c.boards[0] = Board()..place(kFleet.last, 0, 0, true); // destroyer
      c.beginBattle(
          enemyBoard: Board()..place(kFleet[2], 5, 5, true)); // cruiser
      c.attachNetwork();
      c.myShots[1][1] = 2;
      c.p2Shots[2][2] = 1;

      // Arm real Power Play state through the public API — DECOY (an
      // armed defensive flag) and MINEFIELD (own-grid trap state) — both
      // need `!peerHasTurn`, true by default for the host right after
      // `beginBattle`.
      c.myPowerUp = PowerUpCard.decoy;
      expect(c.usePowerUp(), isTrue);
      c.myPowerUp = PowerUpCard.minefield;
      expect(c.usePowerUp([(3, 3)]), isTrue);
      c.myPowerUp = PowerUpCard.sonar; // a card still in hand, unspent
      c.peerHasTurn = true;

      final ownSnapshot = c.buildResumeSnapshot();

      final restored = await _newPowerUpController(host: true);
      restored.restoreFromOwnSnapshot(ownSnapshot);

      // Boards, shots and turn came back exactly as they were.
      expect(restored.boards[0].shipOfKind(ShipKind.destroyer), isNotNull);
      expect(restored.myShots[1][1], 2);
      expect(restored.p2Shots[2][2], 1);
      expect(restored.peerHasTurn, isTrue);

      // The held card came back.
      expect(restored.myPowerUp, PowerUpCard.sonar);

      // DECOY is still armed — the next hit on the destroyer is swallowed.
      await _incoming(restored, {'type': 'fire', 'r': 0, 'c': 0});
      final decoyResult =
          restored.network.sentForTest.lastWhere((m) => m['type'] == 'result');
      expect(decoyResult['res'], ShotResult.miss.index,
          reason: 'DECOY must still be armed after the round trip');

      // MINEFIELD is still live at (3,3) — costs the shooter their turn.
      await _incoming(restored, {'type': 'fire', 'r': 3, 'c': 3});
      final mineResult =
          restored.network.sentForTest.lastWhere((m) => m['type'] == 'result');
      expect(mineResult['fp'], isTrue,
          reason: 'the MINEFIELD trap must still be live after the round trip');
    });
  });

  group('a shaped card with nothing left to hit', () {
    // `PowerUpShapes._clamp` SLIDES a shape that would hang off the board
    // back on, so a shaped card aimed at the corner does not fire around
    // the cell it was given at all: CROSS FIRE tapped at (0,0) fires the
    // plus centred on (1,1). With every cell of that slid shape already
    // fired at, `_fireShotBatch` had nothing to send — and `usePowerUp`
    // still reported success and ate the card. Against the AI that was
    // worse than a wasted card: the brain latched onto a shot that was
    // never taken and waited out the rest of the match for its result.
    test('CROSS FIRE at a corner is kept, not spent on nothing', () async {
      final c = await _newPowerUpController(host: true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      // The plus centred on (1,1) — where a tap on (0,0) really lands.
      for (final cell in const [(1, 1), (0, 1), (2, 1), (1, 0), (1, 2)]) {
        c.myShots[cell.$1][cell.$2] = 1;
      }
      c.myPowerUp = PowerUpCard.crossFire;
      c.network.sentForTest.clear();

      expect(c.usePowerUp([(0, 0)]), isFalse);
      expect(c.myPowerUp, PowerUpCard.crossFire, reason: 'the card is kept');
      expect(c.network.sentForTest.where((m) => m['type'] == 'fire'), isEmpty);
    });

    test('CHAIN SHOT that cannot fire does not stay armed', () async {
      final c = await _newPowerUpController(host: true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.myShots[4][4] = 1; // already fired at
      c.myPowerUp = PowerUpCard.chainShot;

      expect(c.usePowerUp([(4, 4)]), isFalse);
      expect(c.myPowerUp, PowerUpCard.chainShot);

      // Left armed, the next ORDINARY hit would have spawned a bonus
      // shot the player never paid a card for.
      c.network.sentForTest.clear();
      c.myPowerUp = null;
      c.fireAt(7, 7);
      await _incoming(c, {
        'type': 'result',
        'r': 7,
        'c': 7,
        'res': ShotResult.hit.index,
      });
      expect(c.network.sentForTest.where((m) => m['type'] == 'fire').length, 1,
          reason: 'exactly the one shot that was actually fired');
    });

    test('a shape with even one fresh cell still fires', () async {
      final c = await _newPowerUpController(host: true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      for (final cell in const [(1, 1), (0, 1), (2, 1), (1, 0)]) {
        c.myShots[cell.$1][cell.$2] = 1;
      }
      c.myPowerUp = PowerUpCard.crossFire;
      c.network.sentForTest.clear();

      expect(c.usePowerUp([(0, 0)]), isTrue);
      final fires = c.network.sentForTest.where((m) => m['type'] == 'fire');
      expect(fires.length, 1);
      expect(fires.first['r'], 1);
      expect(fires.first['c'], 2);
    });
  });
}
