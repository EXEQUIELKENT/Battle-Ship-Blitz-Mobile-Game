// POWER PLAY — the four cards added after the original twenty: HARD
// TURN, AUTO DODGE, ARMOUR PLATE and SPY SHIP.
//
// Three of them are hull-scoped where every earlier card was board-scoped,
// and SPY SHIP is the first card that leaves a persistent object on the
// OTHER player's board. Both are new shapes for this feature, so the
// coverage here leans on the places that can actually corrupt a match:
// deflections that could strand a hull unsinkable, relocations that could
// land on water already fired at, and the scout's two-device lifecycle.
import 'dart:math';

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

Future<void> _incoming(GameController c, Map<String, dynamic> msg) async {
  c.network.handleIncomingForTest(msg);
  await pumpEventQueue();
}

Board _harmlessEnemyBoard() => Board()..place(kFleet.first, 9, 5, true);

/// An incoming shot from the peer at (r, c).
Future<void> _incomingFire(GameController c, int r, int c0) =>
    _incoming(c, {'type': 'fire', 'r': r, 'c': c0, 'seq': r * 100 + c0});

/// The result this device last echoed back for an incoming shot.
Map<String, dynamic> _lastResult(GameController c) =>
    c.network.sentForTest.lastWhere((m) => m['type'] == 'result');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the deck still holds together', () {
    test('every card has a definition and a sane weight', () {
      expect(PowerUps.deck, hasLength(PowerUpCard.values.length));
      for (final card in PowerUpCard.values) {
        final def = PowerUps.of(card);
        expect(def.weight, greaterThan(0), reason: def.name);
        expect(def.name.trim(), isNotEmpty);
        expect(def.description.trim(), isNotEmpty);
      }
    });

    test('a card that targets its own grid always needs a target', () {
      // `targetsOwnGrid` only means anything while a target is being
      // picked; set without `needsTarget` it would silently do nothing.
      for (final def in PowerUps.deck) {
        if (def.targetsOwnGrid) {
          expect(def.needsTarget, isTrue, reason: def.name);
        }
      }
    });

    test('draw only ever returns a card that is in the deck', () {
      final c = GameController(
        profile: ProfileStore(),
        network: NetworkService(),
      );
      // Not using the controller, just a seeded draw loop.
      c.hashCode;
      final seen = <PowerUpCard>{};
      for (var i = 0; i < 5000; i++) {
        seen.add(PowerUps.draw(_seededRandom(i)));
      }
      expect(seen.difference(PowerUpCard.values.toSet()), isEmpty);
    });
  });

  group('HARD TURN', () {
    test('swings the tapped hull to the opposite orientation', () async {
      final c = await _newPowerUpController();
      c.boards[0] = Board()..place(kFleet[2], 4, 4, true); // cruiser, size 3
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      final before = c.boards[0].shipOfKind(ShipKind.cruiser)!;
      expect(before.horizontal, isTrue);

      c.myPowerUp = PowerUpCard.hardTurn;
      expect(c.usePowerUp([(4, 4)]), isTrue);

      final after = c.boards[0].shipOfKind(ShipKind.cruiser)!;
      expect(after.horizontal, isFalse, reason: 'it must actually turn');
      final move = c.network.sentForTest.lastWhere((m) => m['type'] == 'move');
      expect(move['k'], ShipKind.cruiser.index);
      expect(move['h'], isFalse);
    });

    test('turns a DAMAGED hull too — unlike SCRAMBLE', () async {
      final c = await _newPowerUpController();
      c.boards[0] = Board()..place(kFleet[2], 4, 4, true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.boards[0].shipOfKind(ShipKind.cruiser)!.hitIndices.add(0);

      c.myPowerUp = PowerUpCard.hardTurn;
      expect(c.usePowerUp([(4, 4)]), isTrue);
      expect(c.boards[0].shipOfKind(ShipKind.cruiser)!.horizontal, isFalse);
    });

    test('refuses, keeping the card, when the tap is not on a hull',
        () async {
      final c = await _newPowerUpController();
      c.boards[0] = Board()..place(kFleet[2], 4, 4, true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.myPowerUp = PowerUpCard.hardTurn;
      expect(c.usePowerUp([(0, 0)]), isFalse);
      expect(c.myPowerUp, PowerUpCard.hardTurn);
    });

    test('never lands the hull on water already fired at', () async {
      final c = await _newPowerUpController();
      c.boards[0] = Board()..place(kFleet[2], 4, 4, true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      // Pepper the board so most turns are illegal.
      for (var r = 0; r < kBoardSize; r++) {
        for (var cc = 0; cc < kBoardSize; cc++) {
          if (r >= 3 && r <= 5 && cc >= 3 && cc <= 5) continue;
          c.boards[0].markShot(r, cc);
        }
      }
      c.myPowerUp = PowerUpCard.hardTurn;
      c.usePowerUp([(4, 4)]);
      final ship = c.boards[0].shipOfKind(ShipKind.cruiser)!;
      for (final cell in ship.cells) {
        expect(c.boards[0].alreadyShot(cell[0], cell[1]), isFalse,
            reason: 'a turned hull must never sit on spent water');
      }
    });
  });

  group('ARMOUR PLATE', () {
    Future<GameController> plated() async {
      final c = await _newPowerUpController();
      c.boards[0] = Board()..place(kFleet[0], 0, 0, true); // carrier, size 5
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.myPowerUp = PowerUpCard.armourPlate;
      expect(c.usePowerUp([(0, 0)]), isTrue);
      return c;
    }

    test('turns aside exactly two hits, then lets the third through',
        () async {
      final c = await plated();
      expect(c.armourOn(ShipKind.carrier), PowerUps.armourPlates);

      await _incomingFire(c, 0, 0);
      expect(_lastResult(c)['res'], ShotResult.miss.index,
          reason: 'a deflected shell is reported as a miss');
      expect(c.boards[0].shipOfKind(ShipKind.carrier)!.hitIndices, isEmpty);
      expect(c.armourOn(ShipKind.carrier), 1);

      await _incomingFire(c, 0, 1);
      expect(c.boards[0].shipOfKind(ShipKind.carrier)!.hitIndices, isEmpty);
      expect(c.armourOn(ShipKind.carrier), 0);

      await _incomingFire(c, 0, 2);
      expect(_lastResult(c)['res'], ShotResult.hit.index,
          reason: 'plating is gone — the third shell lands');
      expect(c.boards[0].shipOfKind(ShipKind.carrier)!.hitIndices, isNotEmpty);
    });

    test('only protects the hull it was fitted to', () async {
      final c = await _newPowerUpController();
      c.boards[0] = Board()
        ..place(kFleet[0], 0, 0, true)
        ..place(kFleet[4], 5, 0, true); // destroyer
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.myPowerUp = PowerUpCard.armourPlate;
      expect(c.usePowerUp([(0, 0)]), isTrue);

      await _incomingFire(c, 5, 0);
      expect(_lastResult(c)['res'], ShotResult.hit.index);
      expect(c.armourOn(ShipKind.carrier), PowerUps.armourPlates,
          reason: "another hull's hit must not spend the carrier's plating");
    });

    test('never deflects the shot that was the hull\'s last reachable cell',
        () async {
      // REGRESSION GUARD. A deflection records the cell as spent without
      // damaging the hull. If that cell was the only one still legally
      // fireable, the hull could never be sunk by anybody for the rest of
      // the match. DECOY already guards this; armour shares the guard.
      final c = await _newPowerUpController();
      c.boards[0] = Board()..place(kFleet[4], 0, 0, true); // destroyer, size 2
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.boards[0].shipOfKind(ShipKind.destroyer)!.hitIndices.add(0);
      c.boards[0].markShot(0, 0);
      c.myPowerUp = PowerUpCard.armourPlate;
      expect(c.usePowerUp([(0, 1)]), isTrue);

      await _incomingFire(c, 0, 1);
      expect(_lastResult(c)['res'], isNot(ShotResult.miss.index),
          reason: 'the finishing blow must land, not be plated away');
    });

    test('refuses to plate a sunk hull', () async {
      final c = await _newPowerUpController();
      c.boards[0] = Board()..place(kFleet[4], 0, 0, true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      final d = c.boards[0].shipOfKind(ShipKind.destroyer)!;
      d.hitIndices.addAll([0, 1]);
      c.myPowerUp = PowerUpCard.armourPlate;
      expect(c.usePowerUp([(0, 0)]), isFalse);
      expect(c.myPowerUp, PowerUpCard.armourPlate);
    });
  });

  group('AUTO DODGE', () {
    test('reports a miss and really moves the hull off the shot', () async {
      final c = await _newPowerUpController();
      c.boards[0] = Board()..place(kFleet[2], 4, 4, true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.myPowerUp = PowerUpCard.autoDodge;
      expect(c.usePowerUp([(4, 4)]), isTrue);
      expect(c.dodgeKind, ShipKind.cruiser);

      await _incomingFire(c, 4, 4);

      expect(_lastResult(c)['res'], ShotResult.miss.index);
      final ship = c.boards[0].shipOfKind(ShipKind.cruiser)!;
      expect(ship.hitIndices, isEmpty);
      // The shot cell must genuinely be empty now — that is what makes
      // the reported miss honest rather than a lie.
      expect(c.boards[0].shipAt(4, 4), isNull);
      expect(c.dodgeKind, isNull, reason: 'one-shot');
      final move = c.network.sentForTest.lastWhere((m) => m['type'] == 'move');
      expect(move['k'], ShipKind.cruiser.index);
    });

    test('never dodges onto the very cell it was shot at', () async {
      final c = await _newPowerUpController();
      c.boards[0] = Board()..place(kFleet[4], 4, 4, true); // destroyer, size 2
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.myPowerUp = PowerUpCard.autoDodge;
      c.usePowerUp([(4, 4)]);
      await _incomingFire(c, 4, 4);
      final ship = c.boards[0].shipOfKind(ShipKind.destroyer)!;
      for (final cell in ship.cells) {
        expect(cell[0] == 4 && cell[1] == 4, isFalse);
        expect(c.boards[0].alreadyShot(cell[0], cell[1]), isFalse);
      }
    });

    test('falls back to taking the hit when boxed in', () async {
      final c = await _newPowerUpController();
      c.boards[0] = Board()..place(kFleet[4], 0, 0, true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      // Every cell but the hull's own is spent, so there is nowhere legal
      // to slip to.
      for (var r = 0; r < kBoardSize; r++) {
        for (var cc = 0; cc < kBoardSize; cc++) {
          if (r == 0 && cc <= 1) continue;
          c.boards[0].markShot(r, cc);
        }
      }
      c.myPowerUp = PowerUpCard.autoDodge;
      c.usePowerUp([(0, 0)]);
      await _incomingFire(c, 0, 0);
      expect(_lastResult(c)['res'], isNot(ShotResult.miss.index),
          reason: 'a dodge with nowhere to go must not swallow the shot');
      expect(c.boards[0].shipOfKind(ShipKind.destroyer)!.hitIndices,
          isNotEmpty);
    });

    test('a dodge on one hull does nothing for another', () async {
      final c = await _newPowerUpController();
      c.boards[0] = Board()
        ..place(kFleet[2], 4, 4, true)
        ..place(kFleet[4], 8, 0, true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.myPowerUp = PowerUpCard.autoDodge;
      c.usePowerUp([(4, 4)]);
      await _incomingFire(c, 8, 0);
      expect(_lastResult(c)['res'], ShotResult.hit.index);
      expect(c.dodgeKind, ShipKind.cruiser, reason: 'still armed');
    });
  });

  group('SPY SHIP', () {
    test('plants on enemy water and announces it to the defender', () async {
      final c = await _newPowerUpController();
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.myPowerUp = PowerUpCard.spyShip;
      expect(c.usePowerUp([(3, 3)]), isTrue);
      expect(c.mySpyCell, 3 * kBoardSize + 3);
      final flag = c.network.sentForTest
          .lastWhere((m) => m['type'] == 'pw_flag');
      expect(flag['card'], PowerUpCard.spyShip.index);
      expect(flag['r'], 3);
      expect(flag['c'], 3);
    });

    test('refuses water already fired at, and a second scout', () async {
      final c = await _newPowerUpController();
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.myShots[3][3] = 1;
      c.myPowerUp = PowerUpCard.spyShip;
      expect(c.usePowerUp([(3, 3)]), isFalse);
      expect(c.myPowerUp, PowerUpCard.spyShip);

      expect(c.usePowerUp([(4, 4)]), isTrue);
      c.myPowerUp = PowerUpCard.spyShip;
      expect(c.usePowerUp([(6, 6)]), isFalse,
          reason: 'only one scout out at a time');
    });

    test('the defender records an incoming scout on their own board',
        () async {
      final c = await _newPowerUpController(host: false);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      await _incoming(c, {
        'type': 'pw_flag',
        'card': PowerUpCard.spyShip.index,
        'r': 2,
        'c': 7,
      });
      expect(c.enemySpyCell, 2 * kBoardSize + 7);
    });

    test('the defender answers a reveal with a hull cell beside the scout',
        () async {
      final c = await _newPowerUpController(host: false);
      c.boards[0] = Board()..place(kFleet[2], 2, 6, true); // cruiser 2,6-2,8
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      await _incoming(c, {
        'type': 'pw_flag',
        'card': PowerUpCard.spyShip.index,
        'r': 3,
        'c': 7,
      });
      await _incoming(c, {
        'type': 'pw_ask',
        'card': PowerUpCard.spyShip.index,
        'r': 3,
        'c': 7,
      });
      final answer =
          c.network.sentForTest.lastWhere((m) => m['type'] == 'pw_answer');
      expect(answer['has'], isTrue);
      final r = answer['r'] as int, cc = answer['c'] as int;
      expect(c.boards[0].shipAt(r, cc), isNotNull,
          reason: 'the scout must only ever name a real hull cell');
      expect((r - 3).abs() <= 1 && (cc - 7).abs() <= 1, isTrue,
          reason: 'and only one touching it');
    });

    test('answers "still there, nothing to see" over clear water', () async {
      final c = await _newPowerUpController(host: false);
      c.boards[0] = Board()..place(kFleet[4], 9, 0, true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      await _incoming(c, {
        'type': 'pw_flag',
        'card': PowerUpCard.spyShip.index,
        'r': 3,
        'c': 3,
      });
      await _incoming(c,
          {'type': 'pw_ask', 'card': PowerUpCard.spyShip.index, 'r': 3, 'c': 3});
      final answer =
          c.network.sentForTest.lastWhere((m) => m['type'] == 'pw_answer');
      expect(answer['has'], isTrue, reason: 'the scout is alive...');
      expect(answer['r'], isNull, reason: '...it just has nothing to report');
    });

    test('a reveal marks the cell for the asker exactly once', () async {
      final c = await _newPowerUpController();
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.myPowerUp = PowerUpCard.spyShip;
      c.usePowerUp([(3, 3)]);
      for (var i = 0; i < 3; i++) {
        await _incoming(c, {
          'type': 'pw_answer',
          'card': PowerUpCard.spyShip.index,
          'has': true,
          'r': 2,
          'c': 2,
        });
      }
      expect(c.spottedEnemyCells, contains(2 * kBoardSize + 2));
      expect(c.spottedEnemyCells.length, 1, reason: 'no duplicate marks');
    });

    test('a hull steered over the scout runs it down, both sides agreeing',
        () async {
      final defender = await _newPowerUpController(host: false);
      defender.boards[0] = Board()..place(kFleet[2], 4, 4, true);
      defender.beginBattle(enemyBoard: _harmlessEnemyBoard());
      defender.attachNetwork();
      // The attacker's scout lands right where the cruiser can turn onto.
      await _incoming(defender, {
        'type': 'pw_flag',
        'card': PowerUpCard.spyShip.index,
        'r': 5,
        'c': 4,
      });
      expect(defender.enemySpyCell, 5 * kBoardSize + 4);

      // Turning the cruiser vertical about (4,4) puts it over (5,4). The
      // joiner opens the match on the peer's turn, so hand the guns over
      // first — `usePowerUp` rightly refuses a card out of turn.
      defender.peerHasTurn = false;
      defender.myPowerUp = PowerUpCard.hardTurn;
      expect(defender.usePowerUp([(4, 4)]), isTrue);

      expect(defender.enemySpyCell, isNull, reason: 'crushed');
      final gone = defender.network.sentForTest.lastWhere(
          (m) => m['type'] == 'pw_flag' && m['card'] == PowerUpCard.spyShip.index);
      expect(gone['on'], isFalse,
          reason: 'the owner has to be told their scout is gone');
    });

    test('its owner drops it when told it is gone', () async {
      final c = await _newPowerUpController();
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.myPowerUp = PowerUpCard.spyShip;
      c.usePowerUp([(3, 3)]);
      expect(c.mySpyCell, isNotNull);
      await _incoming(c, {
        'type': 'pw_flag',
        'card': PowerUpCard.spyShip.index,
        'on': false,
      });
      expect(c.mySpyCell, isNull);
    });

    test('a dead scout answers "gone" and its owner stops asking', () async {
      final c = await _newPowerUpController();
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.myPowerUp = PowerUpCard.spyShip;
      c.usePowerUp([(3, 3)]);
      await _incoming(c, {
        'type': 'pw_answer',
        'card': PowerUpCard.spyShip.index,
        'has': false,
      });
      expect(c.mySpyCell, isNull);
    });

    test('asks for a report at the start of every turn it survives',
        () async {
      final c = await _newPowerUpController();
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.myPowerUp = PowerUpCard.spyShip;
      c.usePowerUp([(3, 3)]);
      final before =
          c.network.sentForTest.where((m) => m['type'] == 'pw_ask').length;
      c.onMyTurnStart();
      c.onMyTurnStart();
      final after =
          c.network.sentForTest.where((m) => m['type'] == 'pw_ask').length;
      expect(after - before, 2);
    });

    test('a JAM silences the draw but not the scout', () async {
      // A joiner, so no opening draw of its own to get in the way — but
      // the guns start with the peer, so hand them over before spending a
      // card.
      final c = await _newPowerUpController(host: false);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      c.peerHasTurn = false;
      c.myPowerUp = PowerUpCard.spyShip;
      expect(c.usePowerUp([(3, 3)]), isTrue);
      await _incoming(c, {'type': 'pw_flag', 'card': PowerUpCard.jam.index});
      final before =
          c.network.sentForTest.where((m) => m['type'] == 'pw_ask').length;
      c.onMyTurnStart();
      expect(c.myPowerUp, isNull, reason: 'the draw really was jammed');
      final after =
          c.network.sentForTest.where((m) => m['type'] == 'pw_ask').length;
      expect(after - before, 1,
          reason: 'the boat in their water still reports');
    });
  });
}

/// A tiny deterministic generator so the draw sweep is reproducible.
_SeededRandom _seededRandom(int seed) => _SeededRandom(seed);

class _SeededRandom implements Random {
  final Random _inner;
  _SeededRandom(int seed) : _inner = Random(seed);
  @override
  bool nextBool() => _inner.nextBool();
  @override
  double nextDouble() => _inner.nextDouble();
  @override
  int nextInt(int max) => _inner.nextInt(max);
}
