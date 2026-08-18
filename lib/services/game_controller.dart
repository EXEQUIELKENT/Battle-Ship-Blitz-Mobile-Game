import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/game_models.dart';
import 'network_service.dart';
import 'sound_service.dart';
import 'storage_service.dart';

enum GameMode { vsAI, local, hotspot, online }
enum BattlePhase { idle, placing, battling, finished }

class CombatEvent {
  final int row;
  final int col;
  final ShotResult result;
  final bool byPlayer;
  final String? sunkShipName;
  final DateTime time;
  DateTime? impactAt;

  CombatEvent({
    required this.row,
    required this.col,
    required this.result,
    required this.byPlayer,
    this.sunkShipName,
  }) : time = DateTime.now();
}

class GameController extends ChangeNotifier {
  GameController({required this.profile, required this.network});

  final ProfileStore profile;
  final NetworkService network;

  GameMode mode = GameMode.vsAI;
  AIDifficulty difficulty = AIDifficulty.normal;
  BattlePhase phase = BattlePhase.idle;
  final List<Board> boards = [Board(), Board()];
  final List<List<int>> myShots =
      List.generate(kBoardSize, (_) => List.filled(kBoardSize, 0));
  final List<List<int>> p2Shots =
      List.generate(kBoardSize, (_) => List.filled(kBoardSize, 0));

  double cooldown1 = 0;
  double cooldown2 = 0;
  double cooldownMax1 = kCooldownSeconds.toDouble();
  double cooldownMax2 = kCooldownSeconds.toDouble();

  bool iWon = false;
  bool p2Won = false;
  bool suddenTimeout = false;
  String endReason = '';
  int rpDelta = 0;
  bool rpAwarded = false;

  // ----- Deferred end-game transition -----
  // BUGFIX (result screen loading before the winning cannonball lands):
  // `_checkVictory` used to call `_finish()` synchronously, the instant a
  // shot was REGISTERED (tap time / AI decision time / network-result
  // time) — well before BattleScreen had even started that shot's
  // projectile animation. That flipped `phase` to `finished` immediately,
  // which battle_screen.dart reads to reveal both full fleets and show the
  // game-over bar, and played the victory/defeat sound, all before the
  // cannonball had visibly traveled anywhere. Fixed by splitting "the
  // match is over" into two steps: `_checkVictory` now only ARMS a pending
  // finish tied to the exact CombatEvent that decided it; the actual
  // `_finish()` (phase flip, sound, RP) only runs once BattleScreen calls
  // [resolvePendingFinishFor] with that same event — i.e. the instant its
  // projectile has visually landed and its hit/sunk marker has been
  // applied. Tying this to the specific event object (not just "some
  // impact resolved") keeps it correct even if another shot's impact
  // resolves around the same time (e.g. hotspot/online's own-shot result
  // arriving asynchronously while a different event is mid-flight).
  CombatEvent? _pendingFinishEvent;
  bool _pendingP1Win = false;
  String _pendingReason = '';

  /// True once a shot has been registered that will end the match, but its
  /// projectile hasn't been confirmed to have visually landed yet. Exposed
  /// mainly for tests/diagnostics — UI code should just fire shots and let
  /// [resolvePendingFinishFor] do the right thing once each impact lands.
  bool get hasPendingFinish => _pendingFinishEvent != null;

  final List<CombatEvent> events = [];
  /// Battle log (oldest-first order via add/removeAt(0) for O(1) appends).
  final List<String> combatLog = [];
  int revision = 0;

  Timer? _ticker;
  StreamSubscription? _netSub;
  final Random _rng = Random();

  final List<List<int>> _aiShots =
      List.generate(kBoardSize, (_) => List.filled(kBoardSize, 0));
  final List<List<int>> _aiQueue = [];
  bool aiTurnToFire = false;

  // Prevents the AI from selecting another target while its current shot
  // is waiting for the visible cannon to fire.
  bool _aiShotPending = false;
  static const Duration _aiVisualFireDelay =
      Duration(milliseconds: 900);

  bool get battling => phase == BattlePhase.battling;

  double get cooldownFraction1 => cooldownMax1 == 0
      ? 1
      : (1 - cooldown1 / cooldownMax1).clamp(0.0, 1.0);

  double get cooldownFraction2 => cooldownMax2 == 0
      ? 1
      : (1 - cooldown2 / cooldownMax2).clamp(0.0, 1.0);

  int get mySunk => boards[1].sunkCount;
  int get enemySunk => boards[0].sunkCount;

  void startPlacement({Board? preset}) {
    _teardown();
    boards[0] = preset ?? Board();
    boards[1] = Board();
    phase = BattlePhase.placing;
    notifyListeners();
  }

  void beginBattle({Board? enemyBoard}) {
    boards[1] = enemyBoard ?? Board.random(rng: _rng);
    phase = BattlePhase.battling;
    revision++;
    cooldownMax1 =
        kCooldownSeconds * profile.cannonSkin.cooldownFactor;
    cooldownMax2 = mode == GameMode.local
        ? cooldownMax1
        : kCooldownSeconds.toDouble();
    cooldown1 = 0;
    cooldown2 = 0;
    aiTurnToFire = false;
    _aiShotPending = false;
    events.clear();
    combatLog.clear();
    _aiQueue.clear();
    _pendingFinishEvent = null;
    _pendingP1Win = false;
    _pendingReason = '';

    for (var r = 0; r < kBoardSize; r++) {
      for (var c = 0; c < kBoardSize; c++) {
        myShots[r][c] = 0;
        p2Shots[r][c] = 0;
        _aiShots[r][c] = 0;
      }
    }

    _ticker?.cancel();
    _ticker = Timer.periodic(
      const Duration(milliseconds: 100),
      _onTick,
    );
    _log('⚔️ Battle stations! Fire when ready!');
    notifyListeners();
  }

  void _teardown() {
    _ticker?.cancel();
    _ticker = null;
    _netSub?.cancel();
    _netSub = null;
    _aiShotPending = false;
  }

  void attachNetwork() {
    _netSub?.cancel();
    _netSub = network.messages.listen(_onNetMessage);
  }

  ShotResult fireAt(int r, int c) {
    if (!battling) return ShotResult.invalid;

    if (mode == GameMode.vsAI && aiTurnToFire) {
      SoundService.instance.denied();
      return ShotResult.cooldown;
    }

    if (cooldown1 > 0) {
      SoundService.instance.denied();
      return ShotResult.cooldown;
    }

    if (myShots[r][c] != 0) {
      SoundService.instance.denied();
      return ShotResult.duplicate;
    }

    cooldown1 = cooldownMax1;

    if (mode == GameMode.hotspot || mode == GameMode.online) {
      network.sendFire(r, c);
      notifyListeners();
      return ShotResult.hit;
    }

    final (result, sunk) = boards[1].receiveShot(r, c);
    _registerShot(
      shooterIsP1: true,
      r: r,
      c: c,
      result: result,
      sunk: sunk,
    );

    if (mode == GameMode.vsAI && result == ShotResult.miss) {
      aiTurnToFire = true;
    }

    return result;
  }

  ShotResult p2FireAt(int r, int c) {
    if (!battling || mode != GameMode.local) {
      return ShotResult.invalid;
    }

    if (cooldown2 > 0) {
      SoundService.instance.denied();
      return ShotResult.cooldown;
    }

    if (p2Shots[r][c] != 0) {
      SoundService.instance.denied();
      return ShotResult.duplicate;
    }

    cooldown2 = cooldownMax2;

    final (result, sunk) = boards[0].receiveShot(r, c);
    _registerShot(
      shooterIsP1: false,
      r: r,
      c: c,
      result: result,
      sunk: sunk,
    );
    return result;
  }

  void _registerShot({
    required bool shooterIsP1,
    required int r,
    required int c,
    required ShotResult result,
    PlacedShip? sunk,
  }) {
    final hit =
        result == ShotResult.hit || result == ShotResult.sunk;

    if (shooterIsP1) {
      myShots[r][c] = hit ? 2 : 1;
    } else {
      p2Shots[r][c] = hit ? 2 : 1;
    }

    events.add(
      CombatEvent(
        row: r,
        col: c,
        result: result,
        byPlayer: shooterIsP1,
        sunkShipName: sunk?.spec.name,
      ),
    );
    revision++;

    final shooter =
        shooterIsP1 ? profile.playerName : _opponentName();
    final coord =
        '${String.fromCharCode(65 + r)}${c + 1}';

    if (result == ShotResult.sunk) {
      _log(
        '💥 $shooter SANK the ${sunk!.spec.name} at $coord!',
      );
    } else if (result == ShotResult.hit) {
      _log('🔥 $shooter scored a HIT at $coord');
    } else {
      _log('🌊 $shooter missed at $coord');
    }

    if (hit) {
      _checkVictory();
    }
    notifyListeners();
  }

  String _opponentName() => switch (mode) {
    GameMode.vsAI => 'Enemy AI',
    GameMode.local => 'Player 2',
    _ => network.peerName,
  };

  void _checkVictory() {
    if (!battling) return;
    if (_pendingFinishEvent != null) return; // already decided

    if (boards[1].allSunk) {
      _armFinish(
        p1Win: true,
        reason: 'All enemy ships destroyed!',
      );
    } else if (boards[0].allSunk) {
      _armFinish(
        p1Win: false,
        reason: 'Your fleet was destroyed!',
      );
    }
  }

  /// Records that the match is decided, WITHOUT ending it yet — see the
  /// bugfix note above [hasPendingFinish]. `events.last` is the exact shot
  /// [_registerShot] just added right before calling `_checkVictory`, so
  /// this ties the pending finish to precisely the event whose visual
  /// impact must land before the match is allowed to actually end.
  void _armFinish({required bool p1Win, required String reason}) {
    _pendingFinishEvent = events.last;
    _pendingP1Win = p1Win;
    _pendingReason = reason;
  }

  /// Called by the battle screen the instant a shot's impact has been
  /// visually resolved (projectile landed, hit/sunk marker applied). If
  /// [event] is the shot that decided the match, THIS is where the match
  /// actually ends — phase flips to finished, RP is awarded, and the
  /// victory/defeat sound plays. Any other event (the match isn't over, or
  /// this isn't the deciding shot) is a no-op, so it's always safe to call
  /// this after resolving any impact. Idempotent: once armed, only the
  /// first matching call does anything (`_pendingFinishEvent` is cleared
  /// immediately), so duplicate/late-arriving state updates can never
  /// trigger the transition twice.
  void resolvePendingFinishFor(CombatEvent event) {
    if (!identical(_pendingFinishEvent, event)) return;
    final p1Win = _pendingP1Win;
    final reason = _pendingReason;
    _pendingFinishEvent = null;
    _finish(p1Win: p1Win, reason: reason);
  }

  void surrender() {
    if (!battling) return;

    if (mode == GameMode.hotspot ||
        mode == GameMode.online) {
      network.sendSurrender();
    }

    _finish(
      p1Win: false,
      reason: 'You surrendered the battle.',
    );
  }

  void _finish({
    required bool p1Win,
    required String reason,
  }) {
    if (phase == BattlePhase.finished) return;

    phase = BattlePhase.finished;
    _ticker?.cancel();
    _aiShotPending = false;
    iWon = p1Win;
    p2Won = !p1Win;
    endReason = reason;

    if (!rpAwarded) {
      rpAwarded = true;
      rpDelta = profile.recordResult(won: p1Win);
    }

    if (p1Win) {
      SoundService.instance.victory();
      _log('🏆 VICTORY! $reason');
    } else {
      SoundService.instance.defeat();
      _log('☠️ DEFEAT. $reason');
    }

    notifyListeners();
  }

  void _onTick(Timer _) {
    if (!battling) return;

    if (cooldown1 > 0) {
      cooldown1 = max(0, cooldown1 - 0.1);
    }
    if (cooldown2 > 0) {
      cooldown2 = max(0, cooldown2 - 0.1);
    }

    if (mode == GameMode.vsAI && aiTurnToFire) {
      _aiThink();
    }

    notifyListeners();
  }

  double _aiThinkAccumulator = 0;

  void _aiThink() {
    // The AI already has a shot waiting to be visibly fired.
    if (_aiShotPending) return;

    if (cooldown2 > 0) {
      _aiThinkAccumulator = 0;
      return;
    }

    _aiThinkAccumulator += 0.1;

    final delay = switch (difficulty) {
      AIDifficulty.easy => 2.2,
      AIDifficulty.normal => 1.6,
      AIDifficulty.hard => 1.0,
    };

    if (_aiThinkAccumulator < delay) return;
    _aiThinkAccumulator = 0;

    final target = _aiPickTarget();
    if (target == null) return;

    final int r = target[0];
    final int c = target[1];

    // Resolve the target now so the game state is deterministic, but DO NOT
    // start cooldown2 yet. The battle screen waits 900ms before the visible
    // cannon fire; the reload starts at that same point instead.
    _aiShotPending = true;

    final (result, sunk) = boards[0].receiveShot(r, c);
    _aiShots[r][c] =
        (result == ShotResult.hit ||
                result == ShotResult.sunk)
            ? 2
            : 1;

    if (result == ShotResult.hit ||
        result == ShotResult.sunk) {
      if (difficulty != AIDifficulty.easy) {
        for (final offset in [
          [-1, 0],
          [1, 0],
          [0, -1],
          [0, 1],
        ]) {
          final int nr = r + offset[0];
          final int nc = c + offset[1];

          if (nr >= 0 &&
              nr < kBoardSize &&
              nc >= 0 &&
              nc < kBoardSize &&
              _aiShots[nr][nc] == 0) {
            _aiQueue.add([nr, nc]);
          }
        }
      }

      if (result == ShotResult.sunk) {
        _aiQueue.clear();
      }
    } else {
      aiTurnToFire = false;
    }

    _registerShot(
      shooterIsP1: false,
      r: r,
      c: c,
      result: result,
      sunk: sunk,
    );

    // BattleScreen uses the same 900ms visual delay before launching the
    // AI projectile. Starting the cooldown here would make the cannon look
    // like it is reloading before it has fired.
    Future.delayed(_aiVisualFireDelay, () {
      if (!_aiShotPending) return;

      _aiShotPending = false;

      if (phase == BattlePhase.battling) {
        cooldown2 = cooldownMax2;
        notifyListeners();
      }
    });
  }

  List<int>? _aiPickTarget() {
    while (_aiQueue.isNotEmpty) {
      final t = _aiQueue.removeAt(0);
      if (_aiShots[t[0]][t[1]] == 0) return t;
    }

    final candidates = <List<int>>[];

    for (var r = 0; r < kBoardSize; r++) {
      for (var c = 0; c < kBoardSize; c++) {
        if (_aiShots[r][c] != 0) continue;

        if (difficulty == AIDifficulty.hard &&
            (r + c) % 2 != 0) {
          continue;
        }

        candidates.add([r, c]);
      }
    }

    if (candidates.isEmpty) {
      for (var r = 0; r < kBoardSize; r++) {
        for (var c = 0; c < kBoardSize; c++) {
          if (_aiShots[r][c] == 0) {
            candidates.add([r, c]);
          }
        }
      }
    }

    if (candidates.isEmpty) return null;

    return candidates[_rng.nextInt(candidates.length)];
  }

  void _onNetMessage(Map<String, dynamic> msg) {
    switch (msg['type']) {
      case 'fire':
        final r = msg['r'] as int;
        final c = msg['c'] as int;
        final (result, sunk) =
            boards[0].receiveShot(r, c);

        network.sendResult(
          r,
          c,
          result,
          sunkShip: sunk?.spec.name,
        );

        _registerShot(
          shooterIsP1: false,
          r: r,
          c: c,
          result: result,
          sunk: sunk,
        );
        break;

      case 'result':
        final r = msg['r'] as int;
        final c = msg['c'] as int;
        final result =
            ShotResult.values[msg['res'] as int];

        PlacedShip? sunk;
        final sunkName = msg['sunk'] as String?;

        if (result == ShotResult.sunk &&
            sunkName != null) {
          final enemyBoard = boards[1];

          for (final ship in enemyBoard.ships) {
            if (ship.spec.name == sunkName) {
              ship.hitIndices.addAll(
                List.generate(
                  ship.spec.size,
                  (i) => i,
                ),
              );
              sunk = ship;
            }
          }
        }

        _registerShot(
          shooterIsP1: true,
          r: r,
          c: c,
          result: result,
          sunk: sunk,
        );
        break;

      case 'surrender':
        _finish(
          p1Win: true,
          reason:
              '${network.peerName} surrendered!',
        );
        break;
    }
  }

  void reset() {
    _teardown();
    phase = BattlePhase.idle;
    boards[0] = Board();
    boards[1] = Board();
    rpAwarded = false;
    suddenTimeout = false;
    _aiThinkAccumulator = 0;
    _aiShotPending = false;
    _pendingFinishEvent = null;
    _pendingP1Win = false;
    _pendingReason = '';
    notifyListeners();
  }

  void _log(String msg) {
    combatLog.add(msg);
    if (combatLog.length > 30) {
      combatLog.removeAt(0);
    }
  }

  void touch() => notifyListeners();

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }
}
