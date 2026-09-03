import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/game_models.dart';
import 'ai_brain.dart';
import 'game_controller.dart';
import 'loopback_link.dart';
import 'network_service.dart';
import 'storage_service.dart';

/// Owns the hidden half of a vsAiLan match — the AI's own
/// `GameController`/`NetworkService` pair, joined to the player's real
/// ones over a `LoopbackLink`, plus the [AiBrain] that drives it.
///
/// A single long-lived instance, provided the same way `NetworkService`
/// and `GameController` are (see `main.dart`) rather than constructed per
/// match — [start] tears down and replaces whatever was there before, so
/// a rematch always gets a fresh AI opponent and a fresh board.
class VsAiSession {
  NetworkService? _aiNetwork;
  GameController? _aiController;
  AiBrain? _brain;
  Timer? _timer;
  Timer? _readyFallback;
  StreamSubscription<Map<String, dynamic>>? _aiBoardSub;

  /// Exposed for tests — production code has no reason to reach past
  /// [start]/[end].
  GameController? get aiControllerForTest => _aiController;
  AiBrain? get brainForTest => _brain;

  /// Sets up a brand-new vsAiLan match: builds the AI's hidden
  /// controller, joins it to [player] over a fresh `LoopbackLink`, and
  /// walks the AI through its own placement — all before this returns.
  /// The caller (the mode-picker screen) still needs to send the PLAYER
  /// through `PlacementScreen` exactly as a real hotspot/online match
  /// does; nothing here touches `player`'s own board.
  Future<void> start({
    required GameController player,
    required LanBattleMode lanBattleMode,
    required String playerName,
    required String playerShipSkinId,
    required bool playerShipChosen,
    required String playerCannonSkinId,
    required String playerThemeId,
    AIDifficulty difficulty = AIDifficulty.normal,
    Random? rng,
    @visibleForTesting DateTime Function()? clockForTest,
  }) async {
    end(); // a rematch must not inherit the previous match's AI/state.
    final rand = rng ?? Random();

    final aiProfile = ProfileStore(); // never `load()`ed — see its doc.
    final aiNetwork = NetworkService();
    final aiController = GameController(profile: aiProfile, network: aiNetwork)
      ..headless = true;
    _aiNetwork = aiNetwork;
    _aiController = aiController;
    _brain = AiBrain(
      controller: aiController,
      rng: rand,
      difficulty: difficulty,
      // The player's `BattleScreen` runs a 3-2-1 countdown they cannot
      // fire during; the AI waits it out too. See [playerReady].
      holdUntilReleased: true,
      clock: clockForTest,
    );

    final (playerLink, aiLink) = LoopbackLink.pair();
    // Both ends' listeners must be attached before either announces
    // itself — see `LoopbackLink`'s own doc on why a message sent first
    // is still safe either way, and do this anyway for clarity.
    await player.network.startLoopbackMatch(
      link: playerLink,
      asHost: true, // the human is always host in a vsAiLan match — they
      // fire first in every turn-based mode, and get the RED fleet on
      // the placement screen, matching a plain vsAI/local match's
      // existing "you are always the first side" feel.
      playerName: playerName,
    );
    await aiNetwork.startLoopbackMatch(
      link: aiLink,
      asHost: false,
      playerName: _aiName(difficulty),
    );

    player.network.announceLoadout(
      shipSkinId: playerShipSkinId,
      cannonSkinId: playerCannonSkinId,
      themeId: playerThemeId,
      shipChosen: playerShipChosen,
    );
    // The AI's own hull/gun/board — drawn at random from whatever the
    // real human (`player.profile`) has actually unlocked, so a rematch
    // doesn't always face the same plain starter loadout. `aiProfile`
    // above is a fresh, unloaded store and has nothing worth sampling.
    final aiLoadout = Loadout.randomOwned(player.profile, rng: rand);
    aiNetwork.announceLoadout(
      shipSkinId: aiLoadout.shipSkinId,
      cannonSkinId: aiLoadout.cannonSkinId,
      themeId: aiLoadout.themeId,
      shipChosen: aiLoadout.shipChosen,
    );

    player.mode = GameMode.vsAiLan;
    player.lanBattleMode = lanBattleMode;
    player.difficulty = difficulty;
    aiController.mode = GameMode.vsAiLan;
    aiController.lanBattleMode = lanBattleMode;

    // `startPlacement` tears down (and `attachNetwork` would otherwise be
    // torn down BY it) — see the doc on `GameController._teardown`. This
    // order is the one that survives into battle; `LanModeScreen`'s own
    // call site has it backwards, but gets away with it only because
    // nothing needs the AI's `_onNetMessage` listener during placement.
    aiController.startPlacement(preset: Board.random(rng: rand));
    aiController.attachNetwork();
    aiNetwork.sendBoard(aiController.boards[0]);

    // The player's board may already be here (unlikely — placing a fleet
    // takes real human time — but `takePeerBoard` costs nothing to check
    // first) or may not arrive for a while; either way this must not
    // block `start()` itself, since the caller still has to push the
    // player through their own placement screen.
    final already = aiNetwork.takePeerBoard();
    if (already != null) {
      _beginAiBattle(already);
    } else {
      _aiBoardSub = aiNetwork.messages.listen((msg) {
        if (msg['type'] != 'board') return;
        _aiBoardSub?.cancel();
        _aiBoardSub = null;
        aiNetwork.takePeerBoard();
        _beginAiBattle(msg);
      });
    }
  }

  void _beginAiBattle(Map<String, dynamic> msg) {
    final controller = _aiController;
    final brain = _brain;
    if (controller == null || brain == null) return; // torn down mid-flight
    final board =
        Board.fromJson(Map<String, dynamic>.from(msg['b'] as Map));
    controller.beginBattle(enemyBoard: board);
    _timer?.cancel();
    // Fine-grained enough that `AiBrain`'s own wall-clock schedule is what
    // decides when it acts, rather than this interval quantising it.
    _timer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      brain.tick();
    });
    // The AI is held until the player's battle screen says its countdown
    // is done (see [playerReady]) — but that screen is under no
    // obligation to exist. If it never reports in, start anyway rather
    // than leaving an opponent that never fires a shot.
    _readyFallback?.cancel();
    _readyFallback = Timer(const Duration(seconds: 8), playerReady);
  }

  /// Called by `BattleScreen` the moment its start-of-battle 3-2-1
  /// countdown finishes. Until then the human cannot fire — the screen
  /// refuses their taps — so neither may the AI, which otherwise opened
  /// up during the count in CHAOS and BLITZ (nothing there waits on a
  /// turn) and had a free head start in every other mode. Idempotent and
  /// safe to call from a non-AI match, where there is simply no brain to
  /// release.
  void playerReady() {
    _readyFallback?.cancel();
    _readyFallback = null;
    _brain?.release();
  }

  String _aiName(AIDifficulty difficulty) => 'AI ${difficulty.label}';

  /// Tears down the AI's own controller/network/timer. Idempotent — safe
  /// to call whether or not a match is actually running, since it is
  /// wired to fire on every `NetworkService.mode` transition away from
  /// `NetMode.loopback` (see `main.dart`), not only a deliberate one.
  void end() {
    _timer?.cancel();
    _timer = null;
    _readyFallback?.cancel();
    _readyFallback = null;
    _aiBoardSub?.cancel();
    _aiBoardSub = null;
    _aiController?.dispose();
    _aiController = null;
    _brain = null;
    unawaited(_aiNetwork?.stop());
    _aiNetwork = null;
  }
}
