import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:battleship_blitz/models/game_models.dart';
import 'package:battleship_blitz/models/power_up.dart';
import 'package:battleship_blitz/services/ai_brain.dart';
import 'package:battleship_blitz/services/game_controller.dart';
import 'package:battleship_blitz/services/network_service.dart';
import 'package:battleship_blitz/services/storage_service.dart';
import 'package:battleship_blitz/services/vs_ai_session.dart';

/// The AI opponent's PACING and its two mode-specific behaviours
/// (manoeuvring, power-up choice), all of which are about WHEN it acts
/// rather than what the rules allow — see `AiBrain`'s "Pacing" doc.
///
/// Every test here drives a real vsAiLan match (a real `LoopbackLink`
/// between two real `GameController`s) off an injected clock, so a whole
/// match's worth of deliberate delay costs no real time while still
/// running the actual scheduling code rather than a bypassed version of
/// it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A hand-cranked stand-in for `DateTime.now`.
  final clock = _TestClock();

  setUp(() => clock.reset());

  Future<_Rig> newRig(
    LanBattleMode mode, {
    int seed = 7,
    AIDifficulty difficulty = AIDifficulty.normal,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final profile = ProfileStore();
    await profile.load();
    final player = GameController(profile: profile, network: NetworkService());
    final session = VsAiSession();
    addTearDown(() {
      session.end();
      player.dispose();
      unawaited(player.network.stop());
    });

    await session.start(
      player: player,
      lanBattleMode: mode,
      playerName: 'Tester',
      playerShipSkinId: 'steel',
      playerShipChosen: true,
      playerCannonSkinId: 'mk1',
      playerThemeId: 'mk1',
      difficulty: difficulty,
      rng: Random(seed),
      clockForTest: clock.now,
    );

    player.startPlacement(preset: Board.random(rng: Random(seed + 1)));
    await pumpEventQueue();
    final aiBoardMsg = player.network.takePeerBoard()!;
    player.network.sendBoard(player.boards[0]);
    player.attachNetwork();
    player.beginBattle(
      enemyBoard:
          Board.fromJson(Map<String, dynamic>.from(aiBoardMsg['b'] as Map)),
    );
    await pumpEventQueue();

    return _Rig(
      player: player,
      session: session,
      ai: session.aiControllerForTest!,
      brain: session.brainForTest!,
    );
  }

  group('the start-of-battle countdown', () {
    test('the AI holds fire until the player screen reports in', () async {
      // CHAOS is the mode where this was most visible: nothing there
      // waits on a turn, so the AI simply opened up the instant its own
      // controller entered battle — while the player was still watching
      // 3-2-1 and having their own taps refused.
      final rig = await newRig(LanBattleMode.chaos);

      // Well past any think delay, but still un-released.
      await rig.run(clock, const Duration(seconds: 10));
      expect(rig.aiShotsSent, 0,
          reason: 'the AI must not fire during the player\'s countdown');

      rig.session.playerReady();
      await rig.run(clock, const Duration(seconds: 3));
      expect(rig.aiShotsSent, greaterThan(0),
          reason: 'and must start firing once the countdown is over');
    });
  });

  group('firing cadence', () {
    test('CHAOS: a shell lands before the next one goes up', () async {
      final rig = await newRig(LanBattleMode.chaos, seed: 11);
      rig.session.playerReady();

      await rig.run(clock, const Duration(seconds: 20));

      // CHAOS has no turn to wait on and a miss leaves the gun instantly
      // ready, so this spacing is the ONLY thing between the AI and
      // emptying the board as fast as the loopback can carry it.
      expect(rig.shotTimes.length, greaterThan(2),
          reason: 'the AI still has to actually play');
      for (var i = 1; i < rig.shotTimes.length; i++) {
        final gap = rig.shotTimes[i].difference(rig.shotTimes[i - 1]);
        expect(gap, greaterThanOrEqualTo(AiBrain.kFlightDelay),
            reason: 'shot $i went up ${gap.inMilliseconds}ms after the last');
      }
    });

    test('TURN BASED: the AI waits out the player screen\'s handoff',
        () async {
      final rig = await newRig(LanBattleMode.turns, seed: 23);
      rig.session.playerReady();

      // The player (host) has the opening shot; make it a miss so the
      // turn comes to the AI.
      final missedAt = clock.now();
      await rig.playerMisses();
      expect(rig.ai.peerHasTurn, isFalse,
          reason: 'the AI knows the turn is its own straight away');
      expect(rig.shotTimes, isEmpty);

      // ...but the player's own SCREEN is still flying that shell and
      // has not begun sliding the cannons over. Firing inside that
      // window is what looked like both fleets shooting at once — and
      // what made the cannon that slid out to mark "their turn" slide
      // straight back again.
      await rig.run(clock, const Duration(seconds: 10));

      expect(rig.shotTimes, isNotEmpty);
      expect(rig.shotTimes.first.difference(missedAt),
          greaterThanOrEqualTo(AiBrain.kHandoffDelay),
          reason: 'the AI must not fire while the player\'s shell is airborne');
    });
  });

  group('a result that never comes', () {
    test('the awaiting-result latch releases itself', () async {
      final rig = await newRig(LanBattleMode.chaos, seed: 31);

      // Strand every AI shot: `startPlacement` tears the player
      // controller's `_onNetMessage` listener down (see
      // `GameController._teardown`) while leaving the link itself open,
      // so a 'fire' reaches a `NetworkService` nobody is listening to
      // and no 'result' ever comes back. The real causes are subtler — a
      // `ShotResult.duplicate` echo the 'result' handler deliberately
      // drops, or a power-up batch that ends up sending nothing — but
      // they wedge the latch shut in exactly this way.
      rig.player.startPlacement();
      rig.session.playerReady();

      await rig.run(clock, const Duration(seconds: 20));

      expect(rig.shotTimes.length, greaterThan(1),
          reason: 'a match must never wedge on a result that is not coming');
      for (var i = 1; i < rig.shotTimes.length; i++) {
        expect(rig.shotTimes[i].difference(rig.shotTimes[i - 1]),
            greaterThanOrEqualTo(AiBrain.kResultWatchdog),
            reason: 'the latch must still hold while a result could land');
      }
    });
  });

  group('manoeuvring', () {
    test('BLITZ: the AI actually moves its fleet', () async {
      final rig = await newRig(LanBattleMode.blitz, seed: 5);
      rig.session.playerReady();
      final before = rig.fleetLayout();

      await rig.run(clock, const Duration(seconds: 30));

      expect(rig.fleetLayout(), isNot(equals(before)),
          reason: 'a mode whose premise is a fleet that runs needs the '
              'opponent to visibly run');
    });

    test('BLITZ: the move is mirrored to the player', () async {
      final rig = await newRig(LanBattleMode.blitz, seed: 5);
      rig.session.playerReady();
      await rig.run(clock, const Duration(seconds: 30));

      // The player's copy of the AI's fleet is what resolves the
      // player's own shots; if the two drifted apart the same shot would
      // hit on one device and miss on the other.
      for (final ship in rig.ai.boards[0].ships) {
        final mirrored = rig.player.boards[1].shipOfKind(ship.spec.kind)!;
        expect(mirrored.row, ship.row);
        expect(mirrored.col, ship.col);
        expect(mirrored.horizontal, ship.horizontal);
      }
    });

    test('GHOST FLEET: a damaged hull can still run', () async {
      final rig = await newRig(LanBattleMode.ghost, seed: 41);
      rig.session.playerReady();

      // Damage one of the AI's hulls, then hand it the turn.
      final victim = rig.ai.boards[0].ships.first;
      await rig.playerFiresAt(victim.cells.first[0], victim.cells.first[1]);
      expect(victim.hitIndices, isNotEmpty);
      await rig.playerMisses();

      final before = rig.fleetLayout();
      await rig.run(clock, const Duration(seconds: 40));
      expect(rig.fleetLayout(), isNot(equals(before)),
          reason: 'GHOST FLEET is the one mode a hit hull is not pinned in');
    });

    test('MANOEUVRE: the AI manoeuvres on the player\'s turn too', () async {
      // The player (host) opens, so the turn never comes to the AI here
      // at all. It must still be able to run its fleet: a human may drag
      // a hull at any moment in these modes — see `BattleScreen`'s
      // `manoeuvring` flag and the dodge rule it documents.
      final rig = await newRig(LanBattleMode.rearrange, seed: 71);
      rig.session.playerReady();
      expect(rig.ai.peerHasTurn, isTrue, reason: 'the player opens');

      final before = rig.fleetLayout();
      await rig.run(clock, const Duration(seconds: 30));

      expect(rig.shotTimes, isEmpty, reason: 'and it never gets a shot');
      expect(rig.fleetLayout(), isNot(equals(before)));
    });

    test('MANOEUVRE: a hull never lands on water already fired at',
        () async {
      final rig = await newRig(LanBattleMode.rearrange, seed: 17);
      rig.session.playerReady();

      for (var i = 0; i < 6; i++) {
        await rig.playerMisses();
        await rig.run(clock, const Duration(seconds: 6));
      }

      for (final ship in rig.ai.boards[0].ships) {
        for (final cell in ship.cells) {
          expect(rig.ai.p2Shots[cell[0]][cell[1]], 0,
              reason: '${ship.spec.kind} is sitting on known-struck water');
        }
      }
    });
  });

  group('POWER PLAY card choice', () {
    test('an unusable card is held, and the turn\'s shot still goes out',
        () async {
      final rig = await newRig(LanBattleMode.powerPlay, seed: 53);
      rig.session.playerReady();
      await rig.playerMisses();

      // REPAIR with nothing damaged: `usePowerUp` would refuse it and
      // keep it either way, but the AI used to spend every single turn
      // rediscovering that — and, holding a card, never drew another one
      // for the rest of the match.
      rig.ai.myPowerUp = PowerUpCard.repair;
      expect(rig.ai.boards[0].ships.every((s) => s.hitIndices.isEmpty), isTrue);

      final before = rig.aiShotsSent;
      await rig.run(clock, const Duration(seconds: 5));

      expect(rig.ai.myPowerUp, PowerUpCard.repair,
          reason: 'nothing to repair yet — hold it until there is');
      expect(rig.aiShotsSent, greaterThan(before),
          reason: 'holding a card must never cost the AI its shot');
    });

    test('a shaped card whose shape is used up never wedges the match',
        () async {
      final rig = await newRig(LanBattleMode.powerPlay, seed: 61);
      rig.session.playerReady();
      await rig.playerMisses();

      // CROSS FIRE aimed at the corner really fires the plus centred on
      // (1,1) — `PowerUpShapes._clamp` slides it back on-board — so the
      // fresh cell the AI picked need not be in the shape at all. With
      // the whole slid shape already fired at, the batch sent nothing
      // while the card reported success, and the brain then waited out
      // the rest of the match for a result that was never coming.
      for (final cell in const [(1, 1), (0, 1), (2, 1), (1, 0), (1, 2)]) {
        rig.ai.myShots[cell.$1][cell.$2] = 1;
      }
      rig.ai.myPowerUp = PowerUpCard.crossFire;

      await rig.run(clock, const Duration(seconds: 6));
      // A CROSS FIRE that reaches the wire puts several cells on it at
      // once. Left unfixed the card is spent on an empty batch, nothing
      // is sent at all, and the only thing that eventually frees the
      // brain is the four-second watchdog — one lone ordinary shot.
      expect(rig.aiShotsSent, greaterThanOrEqualTo(2),
          reason: 'the card has to actually reach the wire');
    });

    test('a card that can act is spent', () async {
      final rig = await newRig(LanBattleMode.powerPlay, seed: 59);
      rig.session.playerReady();
      await rig.playerMisses();

      rig.ai.myPowerUp = PowerUpCard.sonar;
      await rig.run(clock, const Duration(seconds: 5));

      expect(rig.ai.myPowerUp, isNot(PowerUpCard.sonar),
          reason: 'SONAR always has somewhere to look');
    });
  });

  group('GHOST FLEET vs the AI: the same-cell redirect reaches this path '
      'too', () {
    // `Board.receiveShot`'s redirect fix (see its own doc) lives one
    // layer below `AiBrain`/`VsAiSession` entirely, but a vsAiLan match
    // is real `GameController`s talking over a real (loopback)
    // `NetworkService` — worth pinning end to end so a future change to
    // either side can't quietly reopen the "shooter keeps re-hitting the
    // same reported cell and the hull never sinks" deadlock for the one
    // opponent most players actually spend time against.
    test('the player re-hitting the AI\'s ship on the same cell still '
        'sinks it', () async {
      final rig = await newRig(LanBattleMode.ghost, seed: 83);
      rig.session.playerReady();

      final ship = rig.ai.boards[0].ships
          .reduce((a, b) => a.spec.size <= b.spec.size ? a : b);
      final cell = ship.cells.first;

      await rig.playerFiresAt(cell[0], cell[1]);
      expect(ship.isSunk, isFalse);

      await rig.playerFiresAt(cell[0], cell[1]); // same reported cell again
      expect(ship.isSunk, isTrue,
          reason: 'the second hit must redirect onto the hull\'s other '
              'cell(s), not vanish as a no-op');
    });

    test('the AI re-hitting the player\'s ship on the same cell still '
        'sinks it', () async {
      final rig = await newRig(LanBattleMode.ghost, seed: 89);
      rig.session.playerReady();

      final ship = rig.player.boards[0].ships
          .reduce((a, b) => a.spec.size <= b.spec.size ? a : b);
      final cell = ship.cells.first;

      // Simulates the AI's own controller sending consecutive 'fire's at
      // the same cell — exactly what a fallible-memory shooter with no
      // marks (see `AiBrain._memory`) can legitimately do.
      rig.player.network.handleIncomingForTest(
          {'type': 'fire', 'r': cell[0], 'c': cell[1], 'seq': 0});
      await pumpEventQueue();
      rig.player.landIncomingShellsForTest();
      await pumpEventQueue();
      expect(ship.isSunk, isFalse);

      rig.player.network.handleIncomingForTest(
          {'type': 'fire', 'r': cell[0], 'c': cell[1], 'seq': 1});
      await pumpEventQueue();
      rig.player.landIncomingShellsForTest();
      await pumpEventQueue();
      expect(ship.isSunk, isTrue);
    });

    test('shelling the wreck afterwards is a MISS, not another kill',
        () async {
      // BUGFIX: with no marks to warn them, a shooter goes on firing at a
      // hull they have already destroyed — every time, PHANTOM never frees
      // that water at all, and GHOST FLEET only frees it once the owner's
      // fade animation has run. Each of those shots used to come back
      // `.sunk` with the ship still attached: the kill re-announced, and a
      // "hit" that kept the shooter's streak alive on top of a wreck.
      final rig = await newRig(LanBattleMode.ghost, seed: 83);
      rig.session.playerReady();

      final ship = rig.ai.boards[0].ships
          .reduce((a, b) => a.spec.size <= b.spec.size ? a : b);
      final cell = ship.cells.first;

      await rig.playerFiresAt(cell[0], cell[1]);
      await rig.playerFiresAt(cell[0], cell[1]); // redirects — sinks it
      expect(ship.isSunk, isTrue);
      final kills = rig.player.events
          .where((e) => e.result == ShotResult.sunk)
          .length;

      await rig.playerFiresAt(cell[0], cell[1]);
      expect(rig.player.events.last.result, ShotResult.miss,
          reason: 'there is nothing left there to hit');
      expect(
          rig.player.events.where((e) => e.result == ShotResult.sunk).length,
          kills,
          reason: 'a hull is only ever sunk once');
    });
  });

  group('PHANTOM vs the AI: a repeat on a hole already there is wasted', () {
    // PHANTOM's dead-cell rule, driven through a real vsAiLan match — two
    // `GameController`s talking over a loopback `NetworkService`, which is
    // the same wire path a hotspot/online match takes. Worth pinning here
    // as well as at the model, because this is the opponent most players
    // spend their time against and the rule is the one thing that makes
    // PHANTOM play differently from GHOST FLEET.
    test('the second shell deals no damage and scores a miss', () async {
      final rig = await newRig(LanBattleMode.phantom, seed: 83);
      rig.session.playerReady();

      // A hull with more than one cell, so the shot that lands has
      // somewhere it COULD have been redirected to — the thing PHANTOM
      // deliberately does not do.
      final ship = rig.ai.boards[0].ships
          .reduce((a, b) => a.spec.size >= b.spec.size ? a : b);
      final cell = ship.cells.first;

      await rig.playerFiresAt(cell[0], cell[1]);
      expect(ship.hitIndices, hasLength(1));
      expect(rig.player.events.last.result, ShotResult.hit);

      await rig.playerFiresAt(cell[0], cell[1]); // the same spot again
      expect(ship.hitIndices, hasLength(1),
          reason: 'no damage — and no redirect onto fresh plating either');
      expect(rig.player.events.last.result, ShotResult.miss);

      // And it stays dead however often it is tried.
      await rig.playerFiresAt(cell[0], cell[1]);
      expect(rig.player.events.last.result, ShotResult.miss);
      expect(ship.hitIndices, hasLength(1));

      // The hull is still perfectly sinkable — by shelling the rest of it.
      for (final other in ship.cells.skip(1)) {
        await rig.playerFiresAt(other[0], other[1]);
      }
      expect(ship.isSunk, isTrue);
    });

    test('GHOST FLEET still redirects — the rule is PHANTOM\'s alone',
        () async {
      final rig = await newRig(LanBattleMode.ghost, seed: 83);
      rig.session.playerReady();

      final ship = rig.ai.boards[0].ships
          .reduce((a, b) => a.spec.size >= b.spec.size ? a : b);
      final cell = ship.cells.first;

      await rig.playerFiresAt(cell[0], cell[1]);
      await rig.playerFiresAt(cell[0], cell[1]);
      expect(ship.hitIndices, hasLength(2),
          reason: 'ghost hulls run, so a blind repeat still finds plating');
    });
  });
}

class _TestClock {
  DateTime _t = DateTime.utc(2026, 1, 1);
  DateTime now() => _t;
  void advance(Duration d) => _t = _t.add(d);
  void reset() => _t = DateTime.utc(2026, 1, 1);
}

class _Rig {
  _Rig({
    required this.player,
    required this.session,
    required this.ai,
    required this.brain,
  });

  final GameController player;
  final VsAiSession session;
  final GameController ai;
  final AiBrain brain;

  /// Counted off the wire rather than off `events`, so a shot still
  /// counts when nothing ever answers it — see the watchdog test.
  int get aiShotsSent =>
      ai.network.sentForTest.where((m) => m['type'] == 'fire').length;

  List<String> fleetLayout() => [
        for (final s in ai.boards[0].ships)
          '${s.spec.kind}@${s.row},${s.col},${s.horizontal}',
      ];

  /// The virtual time of every tick at which the AI put a new shot on
  /// the wire — what the cadence tests actually assert against, since
  /// "how many shots landed inside an arbitrary window" says nothing
  /// about the spacing between them.
  final List<DateTime> shotTimes = [];
  int _seenShots = 0;

  /// Advances the injected clock in production-sized steps, ticking the
  /// brain at each one exactly as `VsAiSession`'s own timer does.
  Future<void> run(_TestClock clock, Duration total) async {
    const step = Duration(milliseconds: 150);
    var elapsed = Duration.zero;
    while (elapsed < total) {
      brain.tick();
      if (aiShotsSent > _seenShots) {
        _seenShots = aiShotsSent;
        shotTimes.add(clock.now());
      }
      await pumpEventQueue();
      _ageIncomingShells();
      await pumpEventQueue();
      // Reload is real-time and irrelevant to what is under test here —
      // the same shortcut `game_controller_test.dart` already uses.
      ai.cooldown1 = 0;
      clock.advance(step);
      elapsed += step;
    }
  }

  /// Fires one deliberate miss from the player, so a turn-taking mode
  /// hands the turn to the AI.
  Future<void> playerMisses() async {
    for (var r = 0; r < kBoardSize; r++) {
      for (var c = 0; c < kBoardSize; c++) {
        if (player.myShots[r][c] != 0) continue;
        if (ai.boards[0].shipAt(r, c) != null) continue;
        await playerFiresAt(r, c);
        // The battle screen is what normally passes a turn; there isn't
        // one here, so apply the same rule it does — to the PLAYER'S
        // mirror only. The AI keeps its own, off its own event stream:
        // setting it here would rob the brain of the transition it hangs
        // the handoff delay (and POWER PLAY's draw) off.
        if (player.lanBattleMode.hasTurns) player.peerHasTurn = true;
        brain.tick(); // lets the brain see the handoff and schedule off it
        return;
      }
    }
    fail('no unfired empty water left to miss into');
  }

  Future<void> playerFiresAt(int r, int c) async {
    player.cooldown1 = 0;
    player.peerHasTurn = false;
    player.fireAt(r, c);
    await pumpEventQueue();
    // In a mode the AI's fleet can move in, its board holds an incoming
    // shot in the air rather than scoring it (see
    // `GameController._armIncomingShell`). These tests use the player's
    // fire to SET SOMETHING UP — hand the AI its turn, damage a hull —
    // so the shell lands at once and there is no window to dodge in.
    // The dodge itself is `dodge_test.dart`'s subject.
    ai.landIncomingShellsForTest();
    await pumpEventQueue();
  }

  /// The mirror of the above for shells the AI fires at the PLAYER: aged
  /// across five of [run]'s iterations, which is what `kShellFlight`
  /// works out to at 150ms a tick. Landing them instantly instead would
  /// quietly hand the AI a faster shot loop than it really has.
  final Map<IncomingShell, int> _shellAge = {};

  void _ageIncomingShells() {
    final shells = player.incomingShells;
    if (shells.isEmpty) {
      _shellAge.clear();
      return;
    }
    var due = false;
    for (final shell in shells) {
      final age = (_shellAge[shell] ?? 0) + 1;
      _shellAge[shell] = age;
      if (age >= 5) due = true;
    }
    if (!due) return;
    player.landIncomingShellsForTest();
    _shellAge.clear();
  }
}
