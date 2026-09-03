import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:battleship_blitz/models/game_models.dart';
import 'package:battleship_blitz/services/ai_brain.dart';
import 'package:battleship_blitz/services/game_controller.dart';
import 'package:battleship_blitz/services/network_service.dart';
import 'package:battleship_blitz/services/storage_service.dart';
import 'package:battleship_blitz/services/vs_ai_session.dart';

/// Full-match, headless coverage of the vsAiLan loopback opponent — one
/// smoke test per [LanBattleMode], the highest-value tests in this
/// feature because they exercise the ENTIRE real match protocol (mode
/// rules, turn passing, power-up resolution, MANOEUVRE moves) end to
/// end, exactly the same code both a real hotspot match and a human vs
/// this AI actually run.
///
/// There is no `BattleScreen` here to do the two things it normally does
/// (resolve a pending finish, pass the turn) for the PLAYER side, so the
/// "player" is stood in for by a second [AiBrain] wrapping its
/// controller — [AiBrain] doesn't know or care whether the controller it
/// drives belongs to a screen or not, so this genuinely exercises an
/// AI-vs-AI match over the same loopback link a human's match would use.
///
/// Real-time cannon reload is bypassed by forcing `cooldown1` to 0 every
/// iteration: `GameController.beginBattle` starts its own 100ms ticker
/// independent of any UI, so it works fine left alone too, but waiting
/// out ~2 real seconds per shot across two full fleets would make this
/// suite glacially slow for no correctness benefit — see the matching
/// `cooldown1 = 0` shortcut already used in `game_controller_test.dart`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<GameController> newPlayerController() async {
    SharedPreferences.setMockInitialValues({});
    final profile = ProfileStore();
    await profile.load();
    return GameController(profile: profile, network: NetworkService());
  }

  /// Every ship on [mine] must sit at the same (kind, row, col,
  /// horizontal) as its counterpart on [peerCopy] — the peer's mirror of
  /// this exact fleet. `hitIndices` is checked only for a fully SUNK
  /// ship: `GameController`'s own 'result' handling only ever fills in
  /// the peer's copy of an enemy hull's damage all at once, the instant
  /// it's reported sunk (see the doc on `_healOne`), so a merely-damaged
  /// hull legitimately shows no damage on the peer's copy until then —
  /// that is the real, intentional data model, not a bug this test
  /// should flag.
  void expectFleetsAgree(Board mine, Board peerCopy) {
    for (final ship in mine.ships) {
      final theirs = peerCopy.shipOfKind(ship.spec.kind);
      expect(theirs, isNotNull,
          reason: '${ship.spec.kind} missing from the peer\'s copy');
      expect(theirs!.row, ship.row, reason: '${ship.spec.kind} row drifted');
      expect(theirs.col, ship.col, reason: '${ship.spec.kind} col drifted');
      expect(theirs.horizontal, ship.horizontal,
          reason: '${ship.spec.kind} orientation drifted');
      if (ship.isSunk) {
        expect(theirs.isSunk, isTrue,
            reason: '${ship.spec.kind} sunk on one side but not the peer\'s copy');
      }
    }
  }

  Future<void> playFullMatch(LanBattleMode mode, int seed) async {
    final player = await newPlayerController();
    final session = VsAiSession();
    // `AiBrain` deliberately paces itself against a wall clock (see its
    // "Pacing" doc) — hand both brains a hand-cranked one so a whole
    // match's worth of that costs no real time, while still running the
    // real scheduling code rather than a bypassed version of it.
    var now = DateTime.utc(2026, 1, 1);
    DateTime clock() => now;
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
      rng: Random(seed + 1),
      clockForTest: clock,
    );

    player.startPlacement(preset: Board.random(rng: Random(seed + 2)));
    // Lets the AI's already-sent board (buffered by `LoopbackLink` if it
    // beat this listener into existence) actually land.
    await Future<void>.delayed(Duration.zero);
    final aiBoardMsg = player.network.takePeerBoard();
    expect(aiBoardMsg, isNotNull,
        reason: 'the AI must have sent its board during session.start()');

    player.network.sendBoard(player.boards[0]);
    player.attachNetwork();
    player.beginBattle(
      enemyBoard:
          Board.fromJson(Map<String, dynamic>.from(aiBoardMsg!['b'] as Map)),
    );

    final playerBrain =
        AiBrain(controller: player, rng: Random(seed + 3), clock: clock);
    final aiBrain = session.brainForTest!;
    final aiController = session.aiControllerForTest!;
    // Stands in for `BattleScreen` reporting its 3-2-1 countdown done —
    // without it the AI never fires a shot at all, by design.
    session.playerReady();

    final playerShells = _ShellLander();
    final aiShells = _ShellLander();

    var iterations = 0;
    const maxIterations = 80000;
    while (player.phase == BattlePhase.battling && iterations < maxIterations) {
      playerBrain.tick();
      aiBrain.tick();
      // Flushes the microtasks the `LoopbackLink` round-trip needs (the
      // 'fire' → defender resolves → 'result' chain) between decisions.
      await Future<void>.delayed(Duration.zero);
      playerShells.step(player);
      aiShells.step(aiController);
      await Future<void>.delayed(Duration.zero);
      player.cooldown1 = 0;
      aiController.cooldown1 = 0;
      // One production tick's worth of virtual time — `VsAiSession`
      // drives the real brain on exactly this interval.
      now = now.add(const Duration(milliseconds: 150));
      iterations++;
    }

    expect(iterations, lessThan(maxIterations),
        reason: 'the match must actually terminate, not stall forever');
    expect(player.phase, BattlePhase.finished);
    expect(aiController.phase, BattlePhase.finished);
    expect(player.iWon, isNot(equals(aiController.iWon)),
        reason: 'exactly one side won');

    expectFleetsAgree(player.boards[0], aiController.boards[1]);
    expectFleetsAgree(aiController.boards[0], player.boards[1]);

    // RP isolation (see `GameController.headless`): the PLAYER'S ranked
    // record moves exactly as it would after any other decided match,
    // while the AI's own controller — wired to a throwaway `ProfileStore`
    // that is never `load()`ed, so `_save()` no-ops on a null `_prefs`
    // regardless — must never award itself RP or flip `rpAwarded` at all.
    expect(player.rpAwarded, isTrue,
        reason: 'a decided vsAiLan match must be ranked, same as vs-AI');
    expect(player.profile.wins + player.profile.losses, 1,
        reason: "the player's own win/loss record must move by exactly one");
    expect(aiController.headless, isTrue);
    expect(aiController.rpAwarded, isFalse,
        reason: "the AI's own controller must never award itself RP");
  }

  group('vsAiLan — full headless match, one per mode', () {
    for (final mode in LanBattleMode.values) {
      test(mode.label, () async {
        await playFullMatch(mode, mode.index * 97 + 13);
      });
    }
  });
}

/// Keeps the shells in the air aloft for as long as `kShellFlight`, which
/// at this loop's 150ms-per-iteration clock is five iterations.
///
/// In a mode its fleet can move in, the defender no longer scores an
/// incoming shot when the message arrives: the shell flies first and is
/// only then scored against wherever the hulls ended up (see
/// `GameController._armIncomingShell`). Landing them instantly here would
/// skip the dodge window altogether — and a dodging opponent is exactly
/// the thing a full match most needs to survive, since every dodge is a
/// shot that has to be taken again.
class _ShellLander {
  static const int _flightIterations = 5;
  final Map<IncomingShell, int> _age = {};

  void step(GameController c) {
    if (c.incomingShells.isEmpty) {
      _age.clear();
      return;
    }
    var due = false;
    for (final shell in c.incomingShells) {
      final age = (_age[shell] ?? 0) + 1;
      _age[shell] = age;
      if (age >= _flightIterations) due = true;
    }
    // Shells arrive in order and land in order, so the oldest coming due
    // means anything else up there is within a tick of due itself.
    if (!due) return;
    c.landIncomingShellsForTest();
    _age.clear();
  }
}
