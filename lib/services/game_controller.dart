import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/game_models.dart';
import 'network_service.dart';
import 'sound_service.dart';
import 'storage_service.dart';

/// How a battle is played.
enum GameMode { vsAI, local, hotspot, online }

/// Battle lifecycle.
enum BattlePhase { idle, placing, battling, finished }

/// Visual combat event (for animations & the combat log).
class CombatEvent {
  final int row;
  final int col;
  final ShotResult result;
  final bool byPlayer; // true = the local human fired this shot
  final String? sunkShipName;
  final DateTime time;

  /// When the projectile actually landed (set by the battle screen after the
  /// cannonball flight animation completes). Null until impact.
  DateTime? impactAt;

  CombatEvent({
    required this.row,
    required this.col,
    required this.result,
    required this.byPlayer,
    this.sunkShipName,
  }) : time = DateTime.now();
}

/// Central game state machine. Supports:
///  - vs AI (easy / normal / hard)
///  - local pass-and-play (simultaneous, shared screen)
///  - hotspot / online (socket-based)
class GameController extends ChangeNotifier {
  GameController({
    required this.profile,
    required this.network,
  });

  final ProfileStore profile;
  final NetworkService network;

  // ----- Configuration -----
  GameMode mode = GameMode.vsAI;
  AIDifficulty difficulty = AIDifficulty.normal;

  // ----- State -----
  BattlePhase phase = BattlePhase.idle;

  // Board indexes: 0 = "player 1" (local human), 1 = opponent (AI / P2 / remote)
  final List<Board> boards = [Board(), Board()];

  /// Tracking grid of MY shots at the enemy: 0 = unknown, 1 = miss, 2 = hit.
  final List<List<int>> myShots = List.generate(kBoardSize, (_) => List.filled(kBoardSize, 0));

  /// Tracking grid of P2's shots (local mode only).
  final List<List<int>> p2Shots = List.generate(kBoardSize, (_) => List.filled(kBoardSize, 0));

  // Cooldowns (0 = ready)
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

  final List<CombatEvent> events = [];
  final List<String> combatLog = [];

  Timer? _ticker;
  StreamSubscription? _netSub;
  final Random _rng = Random();

  // AI state
  final List<List<int>> _aiShots = List.generate(kBoardSize, (_) => List.filled(kBoardSize, 0));
  final List<List<int>> _aiQueue = [];

  /// Whether it's currently the AI's turn to fire. The battle starts on the
  /// HUMAN's turn; a miss hands the turn over, a hit keeps it. This makes
  /// vs-AI obey the same "hit keeps turn / miss passes turn" rule as local.
  bool aiTurnToFire = false;

  bool get battling => phase == BattlePhase.battling;

  double get cooldownFraction1 =>
      cooldownMax1 == 0 ? 1 : (1 - cooldown1 / cooldownMax1).clamp(0.0, 1.0);

  double get cooldownFraction2 =>
      cooldownMax2 == 0 ? 1 : (1 - cooldown2 / cooldownMax2).clamp(0.0, 1.0);

  int get mySunk => boards[1].sunkCount; // enemy ships I sank
  int get enemySunk => boards[0].sunkCount; // my ships enemy sank

  // ------------------------------------------------------------ LIFECYCLE ---

  void startPlacement({Board? preset}) {
    _teardown();
    boards[0] = preset ?? Board();
    boards[1] = Board();
    phase = BattlePhase.placing;
    notifyListeners();
  }

  /// Begins the battle once both boards are ready.
  void beginBattle({Board? enemyBoard}) {
    boards[1] = enemyBoard ?? Board.random(rng: _rng);
    phase = BattlePhase.battling;
    cooldownMax1 = kCooldownSeconds * profile.cannonSkin.cooldownFactor;
    cooldownMax2 = mode == GameMode.local ? cooldownMax1 : kCooldownSeconds.toDouble();
    cooldown1 = 0;
    cooldown2 = 0;
    aiTurnToFire = false; // battle always opens on the human's turn
    events.clear();
    combatLog.clear();
    _aiQueue.clear();
    for (var r = 0; r < kBoardSize; r++) {
      for (var c = 0; c < kBoardSize; c++) {
        myShots[r][c] = 0;
        p2Shots[r][c] = 0;
        _aiShots[r][c] = 0;
      }
    }
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), _onTick);
    _log('⚔️ Battle stations! Fire when ready!');
    notifyListeners();
  }

  void _teardown() {
    _ticker?.cancel();
    _ticker = null;
    _netSub?.cancel();
    _netSub = null;
  }

  /// Attach to an established network session.
  void attachNetwork() {
    _netSub?.cancel();
    _netSub = network.messages.listen(_onNetMessage);
  }

  // -------------------------------------------------------------- FIRING ---

  /// Local human fires at the enemy grid.
  ShotResult fireAt(int r, int c) {
    if (!battling) return ShotResult.invalid;
    if (cooldown1 > 0) {
      SoundService.instance.denied();
      return ShotResult.cooldown;
    }
    if (myShots[r][c] != 0) {
      SoundService.instance.denied();
      return ShotResult.duplicate;
    }

    cooldown1 = cooldownMax1;
    SoundService.instance.fire();

    if (mode == GameMode.hotspot || mode == GameMode.online) {
      // Ask the remote peer to resolve the shot.
      network.sendFire(r, c);
      notifyListeners();
      return ShotResult.hit; // optimistic; real result arrives async
    }

    final (result, sunk) = boards[1].receiveShot(r, c);
    _registerShot(shooterIsP1: true, r: r, c: c, result: result, sunk: sunk);
    // A hit keeps the human's turn (fire again); only a miss hands the
    // turn to the AI. Same rule as local pass-and-play.
    if (mode == GameMode.vsAI && result == ShotResult.miss) {
      aiTurnToFire = true;
    }
    return result;
  }

  /// Player 2 fires (local mode).
  ShotResult p2FireAt(int r, int c) {
    if (!battling || mode != GameMode.local) return ShotResult.invalid;
    if (cooldown2 > 0) {
      SoundService.instance.denied();
      return ShotResult.cooldown;
    }
    if (p2Shots[r][c] != 0) {
      SoundService.instance.denied();
      return ShotResult.duplicate;
    }
    cooldown2 = cooldownMax2;
    SoundService.instance.fire();
    final (result, sunk) = boards[0].receiveShot(r, c);
    _registerShot(shooterIsP1: false, r: r, c: c, result: result, sunk: sunk);
    return result;
  }

  void _registerShot({
    required bool shooterIsP1,
    required int r,
    required int c,
    required ShotResult result,
    PlacedShip? sunk,
  }) {
    final hit = result == ShotResult.hit || result == ShotResult.sunk;
    if (shooterIsP1) {
      myShots[r][c] = hit ? 2 : 1;
    } else {
      p2Shots[r][c] = hit ? 2 : 1;
    }

    final evt = CombatEvent(
      row: r,
      col: c,
      result: result,
      byPlayer: shooterIsP1,
      sunkShipName: sunk?.spec.name,
    );
    events.add(evt);

    final shooter = shooterIsP1 ? profile.playerName : _opponentName();
    final coord = '${String.fromCharCode(65 + r)}${c + 1}';
    if (result == ShotResult.sunk) {
      SoundService.instance.sunk();
      _log('💥 $shooter SANK the ${sunk!.spec.name} at $coord!');
    } else if (result == ShotResult.hit) {
      SoundService.instance.hit();
      _log('🔥 $shooter scored a HIT at $coord');
    } else {
      SoundService.instance.miss();
      _log('🌊 $shooter missed at $coord');
    }

    _checkVictory();
    notifyListeners();
  }

  String _opponentName() {
    return switch (mode) {
      GameMode.vsAI => 'Enemy AI',
      GameMode.local => 'Player 2',
      _ => network.peerName,
    };
  }

  void _checkVictory() {
    if (!battling) return;
    if (boards[1].allSunk) {
      _finish(p1Win: true, reason: 'All enemy ships destroyed!');
    } else if (boards[0].allSunk) {
      _finish(p1Win: false, reason: 'Your fleet was destroyed!');
    }
  }

  void surrender() {
    if (!battling) return;
    if (mode == GameMode.hotspot || mode == GameMode.online) {
      network.sendSurrender();
    }
    _finish(p1Win: false, reason: 'You surrendered the battle.');
  }

  void _finish({required bool p1Win, required String reason}) {
    if (phase == BattlePhase.finished) return;
    phase = BattlePhase.finished;
    _ticker?.cancel();
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
    if (cooldown1 > 0) cooldown1 = max(0, cooldown1 - 0.1);
    if (cooldown2 > 0) cooldown2 = max(0, cooldown2 - 0.1);
    if (mode == GameMode.vsAI && aiTurnToFire) _aiThink();
    notifyListeners();
  }

  // ------------------------------------------------------------------- AI ---

  double _aiThinkAccumulator = 0;

  void _aiThink() {
    if (cooldown2 > 0) return;
    _aiThinkAccumulator += 0.1;
    // Difficulty = reaction delay
    final delay = switch (difficulty) {
      AIDifficulty.easy => 1.6,
      AIDifficulty.normal => 0.9,
      AIDifficulty.hard => 0.4,
    };
    if (_aiThinkAccumulator < delay) return;
    _aiThinkAccumulator = 0;

    final target = _aiPickTarget();
    if (target == null) return;
    final int r = target[0];
    final int c = target[1];

    cooldown2 = cooldownMax2;
    final (result, sunk) = boards[0].receiveShot(r, c);
    _aiShots[r][c] = (result == ShotResult.hit || result == ShotResult.sunk) ? 2 : 1;

    if (result == ShotResult.hit || result == ShotResult.sunk) {
      // Queue neighbors for hunt mode (except easy which stays random)
      if (difficulty != AIDifficulty.easy) {
        for (final offset in [[-1, 0], [1, 0], [0, -1], [0, 1]]) {
          final int nr = r + offset[0];
          final int nc = c + offset[1];
          if (nr >= 0 && nr < kBoardSize && nc >= 0 && nc < kBoardSize && _aiShots[nr][nc] == 0) {
            _aiQueue.add([nr, nc]);
          }
        }
      }
      if (result == ShotResult.sunk) _aiQueue.clear();
      // A hit keeps the AI's turn (it fires again); only a miss passes it.
    } else {
      // Miss → hand the turn back to the human.
      aiTurnToFire = false;
    }

    _registerShot(shooterIsP1: false, r: r, c: c, result: result, sunk: sunk);
  }

  List<int>? _aiPickTarget() {
    // Returns [row, col] of the next AI shot.
    // 1. Hunt queue first
    while (_aiQueue.isNotEmpty) {
      final t = _aiQueue.removeAt(0);
      if (_aiShots[t[0]][t[1]] == 0) return t;
    }
    // 2. Random with parity on hard mode
    final candidates = <List<int>>[];
    for (var r = 0; r < kBoardSize; r++) {
      for (var c = 0; c < kBoardSize; c++) {
        if (_aiShots[r][c] != 0) continue;
        if (difficulty == AIDifficulty.hard && (r + c) % 2 != 0) continue;
        candidates.add([r, c]);
      }
    }
    if (candidates.isEmpty) {
      for (var r = 0; r < kBoardSize; r++) {
        for (var c = 0; c < kBoardSize; c++) {
          if (_aiShots[r][c] == 0) candidates.add([r, c]);
        }
      }
    }
    if (candidates.isEmpty) return null;
    return candidates[_rng.nextInt(candidates.length)];
  }

  // -------------------------------------------------------------- NETWORK ---

  void _onNetMessage(Map<String, dynamic> msg) {
    switch (msg['type']) {
      case 'fire':
        // Remote fired at us — resolve and reply.
        final r = msg['r'] as int;
        final c = msg['c'] as int;
        final (result, sunk) = boards[0].receiveShot(r, c);
        network.sendResult(r, c, result, sunkShip: sunk?.spec.name);
        _registerShot(shooterIsP1: false, r: r, c: c, result: result, sunk: sunk);
        break;
      case 'result':
        // Resolution of one of our shots.
        final r = msg['r'] as int;
        final c = msg['c'] as int;
        final result = ShotResult.values[msg['res'] as int];
        PlacedShip? sunk;
        final sunkName = msg['sunk'] as String?;
        if (result == ShotResult.sunk && sunkName != null) {
          // Mark the ship on our tracking board as sunk via the enemy board
          final enemyBoard = boards[1];
          for (final ship in enemyBoard.ships) {
            if (ship.spec.name == sunkName) {
              ship.hitIndices.addAll(List.generate(ship.spec.size, (i) => i));
              sunk = ship;
            }
          }
        }
        _registerShot(shooterIsP1: true, r: r, c: c, result: result, sunk: sunk);
        break;
      case 'surrender':
        _finish(p1Win: true, reason: '${network.peerName} surrendered!');
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
    notifyListeners();
  }

  void _log(String msg) {
    combatLog.insert(0, msg);
    if (combatLog.length > 30) combatLog.removeLast();
  }

  /// Forces a rebuild without changing logical state (used after mutating
  /// event metadata like [CombatEvent.impactAt] from the battle screen).
  void touch() => notifyListeners();

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }
}
