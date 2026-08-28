// THE DODGE — MANOEUVRE, BLITZ and GHOST FLEET.
//
// The three modes a fleet can still move in advertise a real dodge: a
// shell is in the air for `kShellFlight`, and a hull dragged clear
// inside that window is not there when it lands. That was a lie until
// now. The defending device scored an incoming `'fire'` the instant the
// MESSAGE arrived — a whole flight before the shell was drawn landing —
// so the hit was already on the books no matter what the player did with
// the hull, and the shell visibly splashed into empty water while the
// damage registered anyway.
//
// `GameController._armIncomingShell` splits those two moments apart:
// arrival puts a shell in the air (and nothing else), and
// `_resolveIncomingFire` scores it `kShellFlight` later against the board
// as it stands THEN. These tests pin both halves — that nothing is
// decided early, and that the move actually changes the outcome — plus
// the modes that must keep resolving on arrival, since a fleet that
// cannot move has nothing to gain from the delay and everything to lose
// from it.
import 'dart:math';

import 'package:battleship_blitz/models/game_models.dart';
import 'package:battleship_blitz/services/ai_brain.dart';
import 'package:battleship_blitz/services/game_controller.dart';
import 'package:battleship_blitz/services/network_service.dart';
import 'package:battleship_blitz/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<GameController> _newController(
  LanBattleMode mode, {
  bool host = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  final profile = ProfileStore();
  await profile.load();
  final net = NetworkService();
  net.setMatchHost(host);
  final c = GameController(profile: profile, network: net);
  c.mode = GameMode.hotspot;
  c.lanBattleMode = mode;
  return c;
}

/// A harmless, out-of-the-way enemy fleet — see `ghost_mode_test.dart`'s
/// identical helper for why an empty `Board()` is a trap for `allSunk`.
Board _harmlessEnemyBoard() => Board()..place(kFleet.first, 9, 5, true);

/// Puts a destroyer (2 cells) at (0,0)-(0,1) on this device's own board
/// and drops into battle with the network listener attached.
Future<GameController> _defending(LanBattleMode mode) async {
  final c = await _newController(mode);
  c.attachNetwork();
  c.beginBattle(enemyBoard: _harmlessEnemyBoard());
  c.boards[0] = Board()..place(kFleet.last, 0, 0, true);
  return c;
}

Future<void> _incomingFire(GameController c, int r, int col, {int? seq}) async {
  c.network.handleIncomingForTest({
    'type': 'fire',
    'r': r,
    'c': col,
    if (seq != null) 'seq': seq,
  });
  await pumpEventQueue();
}

ShotResult _lastResultSent(GameController c) => ShotResult
    .values[c.network.sentForTest.lastWhere((m) => m['type'] == 'result')['res']
        as int];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The three modes the dodge rule applies to, and the three it must
  /// not: a fleet that cannot move gains nothing from a delayed
  /// resolution, and every extra moving part is a fresh way for a match
  /// to go wrong.
  const dodgeModes = [
    LanBattleMode.rearrange,
    LanBattleMode.blitz,
    LanBattleMode.ghost,
  ];
  const fixedModes = [
    LanBattleMode.turns,
    LanBattleMode.chaos,
    LanBattleMode.powerPlay,
  ];

  group('which modes defer', () {
    for (final mode in dodgeModes) {
      test('${mode.label} puts the shell in the air first', () async {
        final c = await _defending(mode);
        await _incomingFire(c, 0, 0, seq: 0);

        expect(c.incomingShells, hasLength(1));
        expect(c.incomingShells.single.row, 0);
        expect(c.incomingShells.single.col, 0);
        expect(c.events, isEmpty, reason: 'nothing has been scored yet');
        expect(c.network.sentForTest.where((m) => m['type'] == 'result'),
            isEmpty,
            reason: 'and the shooter has been told nothing yet');
        expect(c.boards[0].ships.single.hitIndices, isEmpty,
            reason: 'the hull is untouched while the shell is still up');
      });
    }

    for (final mode in fixedModes) {
      test('${mode.label} still resolves the moment the message lands',
          () async {
        final c = await _defending(mode);
        await _incomingFire(c, 0, 0);

        expect(c.incomingShells, isEmpty);
        expect(c.events, hasLength(1));
        expect(_lastResultSent(c), ShotResult.hit);
      });
    }
  });

  group('the dodge itself', () {
    for (final mode in dodgeModes) {
      test('${mode.label}: a hull that moves in time is missed', () async {
        final c = await _defending(mode);
        await _incomingFire(c, 0, 0, seq: 0);

        // The whole point: this happens WHILE the shell is in the air.
        expect(c.relocateOwnShip(ShipKind.destroyer, 5, 5, true), isTrue);
        c.landIncomingShellsForTest();
        await pumpEventQueue();

        expect(_lastResultSent(c), ShotResult.miss,
            reason: 'the shell landed on the water the hull just left');
        expect(c.boards[0].ships.single.hitIndices, isEmpty);
        expect(c.incomingShells, isEmpty);
      });

      test('${mode.label}: a hull that stays put is hit', () async {
        final c = await _defending(mode);
        await _incomingFire(c, 0, 0, seq: 0);
        c.landIncomingShellsForTest();
        await pumpEventQueue();

        expect(_lastResultSent(c), ShotResult.hit);
        expect(c.boards[0].ships.single.hitIndices, isNotEmpty);
      });

      test('${mode.label}: rotating out from under it counts too', () async {
        final c = await _defending(mode);
        // Aimed at the destroyer's second cell, (0,1). Pivoting the hull
        // to vertical at (0,0) leaves (0,1) empty without the ship going
        // anywhere at all.
        await _incomingFire(c, 0, 1, seq: 0);
        expect(c.relocateOwnShip(ShipKind.destroyer, 0, 0, false), isTrue);
        c.landIncomingShellsForTest();
        await pumpEventQueue();

        expect(_lastResultSent(c), ShotResult.miss);
        expect(c.boards[0].ships.single.hitIndices, isEmpty);
      });

      test('${mode.label}: too late is still a hit', () async {
        final c = await _defending(mode);
        await _incomingFire(c, 0, 0, seq: 0);
        c.landIncomingShellsForTest();
        await pumpEventQueue();
        // Running now changes nothing — the shell already landed.
        c.relocateOwnShip(ShipKind.destroyer, 5, 5, true);

        expect(_lastResultSent(c), ShotResult.hit);
      });
    }

    test('MANOEUVRE: dodging into the shell is still a hit', () async {
      final c = await _defending(LanBattleMode.rearrange);
      c.boards[0] = Board()..place(kFleet.last, 7, 7, true);
      await _incomingFire(c, 0, 0);

      // (0,0) was open water when the shell was armed; the hull runs
      // straight into it. Nothing protects a player from their own move.
      expect(c.relocateOwnShip(ShipKind.destroyer, 0, 0, true), isTrue);
      c.landIncomingShellsForTest();
      await pumpEventQueue();

      expect(_lastResultSent(c), ShotResult.hit);
    });
  });

  group('the real flight timer', () {
    // Everything above lands the shell by hand so the dodge window is the
    // test's to control. This one lets production's own `Timer` do it, so
    // the wiring is proven end to end rather than only through the test
    // hook.
    test('a shell lands on its own after kShellFlight', () async {
      final c = await _defending(LanBattleMode.rearrange);
      await _incomingFire(c, 0, 0);
      expect(c.incomingShells, hasLength(1));

      await Future<void>.delayed(kShellFlight + const Duration(milliseconds: 250));
      await pumpEventQueue();

      expect(c.incomingShells, isEmpty);
      expect(_lastResultSent(c), ShotResult.hit);
    });

    test('a shell still in the air is dropped when the match ends', () async {
      final c = await _defending(LanBattleMode.rearrange);
      await _incomingFire(c, 0, 0);
      expect(c.incomingShells, hasLength(1));

      c.surrender();
      expect(c.incomingShells, isEmpty);

      // And its timer can never fire late into a finished match.
      await Future<void>.delayed(kShellFlight + const Duration(milliseconds: 250));
      await pumpEventQueue();
      expect(c.events, isEmpty);
    });
  });

  group('GHOST FLEET redelivery while the shell is up', () {
    test('a repeat of the same seq does not arm a second shell', () async {
      final c = await _defending(LanBattleMode.ghost);
      await _incomingFire(c, 0, 0, seq: 4);
      await _incomingFire(c, 0, 0, seq: 4);

      // The seq guard in the 'fire' case only catches a repeat of a shot
      // ALREADY resolved — mid-flight, this device has not committed the
      // seq yet, so the pending shell itself has to recognise its own
      // redelivery.
      expect(c.incomingShells, hasLength(1));

      c.landIncomingShellsForTest();
      await pumpEventQueue();
      expect(c.events, hasLength(1),
          reason: 'one shot fired, one shot scored');
    });

    test('a genuinely later shot at the same cell arms its own shell',
        () async {
      final c = await _defending(LanBattleMode.ghost);
      await _incomingFire(c, 0, 0, seq: 4);
      await _incomingFire(c, 0, 0, seq: 5);
      expect(c.incomingShells, hasLength(2));
    });
  });

  group('the AI opponent uses it too', () {
    test('a hull under an inbound shell is moved clear', () async {
      final c = await _defending(LanBattleMode.blitz);
      // HARD dodges most often; a fixed seed makes the roll deterministic.
      final brain = AiBrain(
        controller: c,
        rng: Random(3),
        difficulty: AIDifficulty.hard,
      );
      await _incomingFire(c, 0, 0);

      final before = c.boards[0].ships.single;
      final where = '${before.row},${before.col},${before.horizontal}';
      // Several ticks, exactly as `VsAiSession`'s timer would deliver
      // them across the shell's flight.
      for (var i = 0; i < 5; i++) {
        brain.tick();
      }

      final after = c.boards[0].ships.single;
      expect('${after.row},${after.col},${after.horizontal}', isNot(where),
          reason: 'the AI must take the same dodge a player can');

      c.landIncomingShellsForTest();
      await pumpEventQueue();
      expect(_lastResultSent(c), ShotResult.miss);
    });

    test('it never dodges into another shell already in the air', () async {
      final c = await _defending(LanBattleMode.blitz);
      final brain = AiBrain(
        controller: c,
        rng: Random(3),
        difficulty: AIDifficulty.hard,
      );
      // Two shells up at once — BLITZ's normal state of affairs.
      await _incomingFire(c, 0, 0);
      await _incomingFire(c, 4, 4);
      for (var i = 0; i < 5; i++) {
        brain.tick();
      }

      final cells = c.boards[0].ships.single.cells
          .map((cell) => '${cell[0]},${cell[1]}')
          .toSet();
      expect(cells.contains('4,4'), isFalse,
          reason: 'running under the OTHER shell is worse than standing still');
    });
  });
}
