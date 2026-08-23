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

  /// Which rules a hotspot/online match runs under — decided by both
  /// players in the pre-match vote (see `LanModeScreen`). Ignored in
  /// vs-AI and local pass-and-play, which are always turn-based.
  LanBattleMode lanBattleMode = LanBattleMode.turns;

  /// True when both fleets fire simultaneously with no turn order.
  /// CHAOS and BLITZ; the two differ only in whether hulls can move.
  bool get isChaosBattle => isNetworkBattle && !lanBattleMode.hasTurns;

  /// True when ships may be repositioned mid-battle. MANOEUVRE and BLITZ;
  /// the two differ only in whether there are turns.
  bool get isManoeuvreBattle =>
      isNetworkBattle && lanBattleMode.canRearrange;

  bool get isNetworkBattle =>
      mode == GameMode.hotspot || mode == GameMode.online;

  /// Mirror of the battle screen's "the opponent is the active side" flag.
  /// The screen owns turn-passing (it has to, since a turn only changes
  /// once a shell has visibly landed), but the value has to live somewhere
  /// the controller can read it: a resume snapshot for a reconnecting
  /// player is worthless if it can't say whose turn it was.
  bool peerHasTurn = false;

  /// Set when a match ended because the opponent walked out rather than
  /// because it was played to a finish. Such a match is void: no win, no
  /// loss, no RP — see [abandonMatch].
  bool matchAbandoned = false;

  /// True when this battle was rebuilt from a resume snapshot rather than
  /// started fresh. The battle screen reads it to skip the opening 3-2-1
  /// countdown: the match is already running on the other device, and
  /// counting one player in while the other is mid-turn would just lock
  /// the returning player out of their own guns for a few seconds.
  bool resumedMidMatch = false;

  /// Per-seat gear for LOCAL pass-and-play: index 0 is Player 1, index 1
  /// is Player 2.
  ///
  /// Two people share one device and therefore one saved profile, but
  /// they still each get to sail the hull, gun and battlefield they
  /// picked — same as a hotspot match, where the two loadouts simply
  /// arrive from two different profiles. Each player chooses theirs on
  /// their own deployment screen (nobody can see the other's yet, which
  /// is the natural moment for it), and both are seeded from the device
  /// owner's equipped gear so a player who changes nothing gets exactly
  /// what they had before.
  ///
  /// Only ever read while [mode] is [GameMode.local].
  List<Loadout> localLoadouts = const [Loadout(), Loadout()];

  /// Points both seats back at the profile's own equipped gear. Called at
  /// the top of every local match so one match's picks can't leak into
  /// the next.
  void resetLocalLoadouts() {
    final mine = Loadout.of(profile);
    localLoadouts = [mine, mine];
  }

  void setLocalLoadout(int seat, Loadout loadout) {
    if (seat < 0 || seat > 1) return;
    localLoadouts = [
      seat == 0 ? loadout : localLoadouts[0],
      seat == 1 ? loadout : localLoadouts[1],
    ];
    notifyListeners();
  }

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

  /// PERF (mobile jank that got worse the longer a match ran): bumped on
  /// every 100ms tick so the cannons' cooldown RINGS can animate smoothly
  /// — WITHOUT going through `notifyListeners()`.
  ///
  /// `_onTick` used to call `notifyListeners()` unconditionally, 10× a
  /// second, purely so those two rings could advance. That rebuilt the
  /// ENTIRE battle screen 10×/sec (both grids, every ship/wreck widget,
  /// both fleet status rows), and — because a couple of the values handed
  /// down to the grid painters were freshly-allocated lists each build —
  /// it also forced both grids to fully REPAINT every accumulated
  /// hit/miss mark 10×/sec. That's why the game degraded specifically as
  /// marks piled up. Only the cannon subtrees actually need a 10Hz
  /// update, so they now listen to this instead, and `notifyListeners()`
  /// fires only when something structural really changed (see `_onTick`).
  final ValueNotifier<int> cooldownTick = ValueNotifier<int>(0);

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
    matchAbandoned = false;
    resumedMidMatch = false;
    // The host fires the opening shot in every turn-taking network mode.
    peerHasTurn = isNetworkBattle &&
        lanBattleMode.hasTurns &&
        !network.isHost;
    if (isNetworkBattle) network.beginMatch();
    revision++;
    // BUGFIX (Player 2 silently inheriting Player 1's cannon reload speed):
    // this used to read `profile.cannonSkin.cooldownFactor` — the ONE
    // shared profile's globally-equipped cannon — for `cooldownMax1`, and
    // then, in local pass-and-play, simply copied that same number
    // straight into `cooldownMax2`. Neither seat's own pick (see
    // `GameController.localLoadouts`) was ever actually read, so a fast
    // reload skin equipped through either player's GEAR dialog silently
    // gave BOTH cannons that exact same reload time — the appearance of
    // each gun stayed correctly per-seat (see `_cannonSkinFor` in
    // battle_screen.dart), only the gameplay timer didn't. Each seat's
    // own equipped cannon now decides its own seat's reload speed.
    final myCannon =
        mode == GameMode.local ? localLoadouts[0].cannonSkin : profile.cannonSkin;
    cooldownMax1 = kCooldownSeconds * myCannon.cooldownFactor;
    cooldownMax2 = mode == GameMode.local
        ? kCooldownSeconds * localLoadouts[1].cannonSkin.cooldownFactor
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

  // ------------------------------------------------ MANOEUVRE MODE ---

  /// Repositions one of the player's OWN ships mid-battle. Returns false
  /// (changing nothing) when the move is illegal — the hull has already
  /// taken a hit, the destination overlaps another ship, or it covers a
  /// cell the enemy has already fired at. See [Board.canRelocateTo].
  ///
  /// A successful move is mirrored to the opponent immediately, because
  /// their copy of this fleet is what resolves their incoming shots; if
  /// the two drifted apart the same shot would hit on one device and miss
  /// on the other.
  bool relocateOwnShip(ShipKind kind, int row, int col, bool horizontal) {
    if (!battling || !isManoeuvreBattle) return false;
    if (!boards[0].relocate(kind, row, col, horizontal)) return false;
    network.sendMove(kind, row, col, horizontal);
    revision++;
    notifyListeners();
    return true;
  }

  /// Whether a ship on the player's own board is still free to move.
  bool canRelocate(PlacedShip ship) =>
      battling && isManoeuvreBattle && boards[0].canRelocate(ship);

  // -------------------------------------------------- RESUME SUPPORT ---

  /// Everything a reconnecting opponent needs to pick the match back up
  /// exactly where they left it.
  ///
  /// Built entirely from THIS device's state, which is sufficient because
  /// each side already holds both fleets: our own board carries our exact
  /// damage, and their board plus our own shot grid reconstructs their
  /// damage precisely (a cell we recorded as a hit is, by definition, one
  /// of their ships). Nothing has to be remembered on their behalf.
  Map<String, dynamic> buildResumeSnapshot() => {
        'mode': lanBattleMode.index,
        // Match roles are fixed for the whole match. Telling them which
        // side they are is what stops a reconnect from swapping fleet
        // colours or turn order around.
        'youAreHost': !network.isHost,
        'yourBoard': boards[1].toJson(),
        'myBoard': boards[0].toJson(),
        'shotsByYou': p2Shots.map((row) => row.toList()).toList(),
        'shotsByMe': myShots.map((row) => row.toList()).toList(),
        'yourTurn': peerHasTurn,
        'log': combatLog.toList(),
      };

  /// Rebuilds a whole in-progress match from the surviving player's
  /// snapshot and drops straight back into battle.
  void restoreFromSnapshot(Map<String, dynamic> s) {
    _teardown();

    lanBattleMode = LanBattleMode.values[
        (s['mode'] as int? ?? LanBattleMode.turns.index)
            .clamp(0, LanBattleMode.values.length - 1)];

    // Our own fleet, and the opponent's, as the survivor knows them.
    final own = Board.fromJson(Map<String, dynamic>.from(s['yourBoard'] as Map));
    final enemy = Board.fromJson(Map<String, dynamic>.from(s['myBoard'] as Map));

    final shotsByMe = _grid(s['shotsByYou']);   // what WE fired
    final shotsByThem = _grid(s['shotsByMe']);  // what THEY fired at us

    // Damage on our own fleet is derived rather than trusted: every cell
    // they recorded as a hit is one of our ship cells, so this
    // reconstructs it exactly and can't disagree with their shot grid.
    for (final ship in own.ships) {
      ship.hitIndices.clear();
    }
    for (var r = 0; r < kBoardSize; r++) {
      for (var c = 0; c < kBoardSize; c++) {
        if (shotsByThem[r][c] == 0) continue;
        own.markShot(r, c);
        if (shotsByThem[r][c] == 2) {
          final ship = own.shipAt(r, c);
          final idx = ship?.cellIndexAt(r, c);
          if (ship != null && idx != null) ship.hitIndices.add(idx);
        }
      }
    }
    for (var r = 0; r < kBoardSize; r++) {
      for (var c = 0; c < kBoardSize; c++) {
        if (shotsByMe[r][c] != 0) enemy.markShot(r, c);
      }
    }

    boards[0] = own;
    boards[1] = enemy;

    for (var r = 0; r < kBoardSize; r++) {
      for (var c = 0; c < kBoardSize; c++) {
        myShots[r][c] = shotsByMe[r][c];
        p2Shots[r][c] = shotsByThem[r][c];
      }
    }

    peerHasTurn = !(s['yourTurn'] as bool? ?? false);

    phase = BattlePhase.battling;
    matchAbandoned = false;
    resumedMidMatch = true;
    iWon = false;
    p2Won = false;
    endReason = '';
    cooldownMax1 = kCooldownSeconds * profile.cannonSkin.cooldownFactor;
    cooldownMax2 = kCooldownSeconds.toDouble();
    cooldown1 = 0;
    cooldown2 = 0;
    aiTurnToFire = false;
    _aiShotPending = false;
    _pendingFinishEvent = null;
    _pendingP1Win = false;
    _pendingReason = '';

    combatLog
      ..clear()
      ..addAll(((s['log'] as List?) ?? const []).map((e) => e.toString()));

    _seedEventsFromShots(shotsByMe: shotsByMe, shotsByThem: shotsByThem);

    revision++;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), _onTick);
    attachNetwork();
    _log('🔄 Reconnected — battle resumed!');
    notifyListeners();
  }

  static List<List<int>> _grid(Object? raw) {
    final out = List.generate(kBoardSize, (_) => List.filled(kBoardSize, 0));
    if (raw is! List) return out;
    for (var r = 0; r < kBoardSize && r < raw.length; r++) {
      final row = raw[r];
      if (row is! List) continue;
      for (var c = 0; c < kBoardSize && c < row.length; c++) {
        out[r][c] = (row[c] as num?)?.toInt() ?? 0;
      }
    }
    return out;
  }

  /// Recreates the combat events every past shot would have produced, all
  /// pre-resolved (`impactAt` set), so the restored board shows its full
  /// history of hit/miss markers and wrecks the instant it comes back up
  /// rather than replaying a match's worth of cannon fire.
  void _seedEventsFromShots({
    required List<List<int>> shotsByMe,
    required List<List<int>> shotsByThem,
  }) {
    events.clear();
    void seed(List<List<int>> grid, bool byPlayer, Board target) {
      for (var r = 0; r < kBoardSize; r++) {
        for (var c = 0; c < kBoardSize; c++) {
          final v = grid[r][c];
          if (v == 0) continue;
          final ship = v == 2 ? target.shipAt(r, c) : null;
          // A sunk ship is reported on its final cell so the wreck and the
          // fleet-status icon reveal, exactly as they would have live.
          final sunk = ship != null &&
              ship.isSunk &&
              ship.cellIndexAt(r, c) == ship.spec.size - 1;
          events.add(
            CombatEvent(
              row: r,
              col: c,
              result: v == 2
                  ? (sunk ? ShotResult.sunk : ShotResult.hit)
                  : ShotResult.miss,
              byPlayer: byPlayer,
              sunkShipName: sunk ? ship.spec.name : null,
            )..impactAt = DateTime.now(),
          );
        }
      }
    }

    seed(shotsByMe, true, boards[1]);
    seed(shotsByThem, false, boards[0]);
  }

  // ----------------------------------------------------- ABANDONMENT ---

  /// Ends a match that was never played to a finish because the opponent
  /// walked out and did not come back.
  ///
  /// Deliberately does NOT call [ProfileStore.recordResult]: a match
  /// nobody lost should not show up in anybody's record, so neither
  /// player takes a win or a loss and no RP changes hands.
  void abandonMatch({String reason = 'Your opponent left the match.'}) {
    if (phase == BattlePhase.finished) return;
    matchAbandoned = true;
    phase = BattlePhase.finished;
    _ticker?.cancel();
    _aiShotPending = false;
    iWon = false;
    p2Won = false;
    rpDelta = 0;
    endReason = reason;
    _log('🚪 $reason No result recorded.');
    notifyListeners();
  }

  /// Clears the last match but keeps the connection and mode so a rematch
  /// can go straight back into the pre-match flow.
  void resetForRematch() {
    _teardown();
    phase = BattlePhase.idle;
    boards[0] = Board();
    boards[1] = Board();
    rpAwarded = false;
    rpDelta = 0;
    iWon = false;
    p2Won = false;
    endReason = '';
    matchAbandoned = false;
    suddenTimeout = false;
    events.clear();
    combatLog.clear();
    _pendingFinishEvent = null;
    _pendingP1Win = false;
    _pendingReason = '';
    network.resetRematch();
    network.resetLanVote();
    notifyListeners();
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

    // Local (same-device) never touches the ranked record at all —
    // same as an abandoned match, no win/loss counted, no RP, no streak
    // change. Both fleets are one person passing the phone back and forth,
    // so no result here represents a ranked outcome the way vs AI or
    // online does.
    final noRpLocal = mode == GameMode.local;

    // An abandoned match is void — see [abandonMatch]. Guarded here as
    // well so a late-arriving result can't sneak a record in afterwards.
    if (!rpAwarded && !matchAbandoned && !noRpLocal) {
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

    // Snapshot everything the UI's STRUCTURE (as opposed to the cannons'
    // cooldown rings) actually depends on, so we can tell a purely
    // cosmetic cooldown advance apart from a real state change. See the
    // doc on [cooldownTick] for why this matters so much on mobile.
    final beforeRevision = revision;
    final beforePhase = phase;
    final beforeAiTurn = aiTurnToFire;
    // Readiness — i.e. "can this side fire right now" — gates grid taps
    // and the ready-pulse, so a cooldown REACHING zero is structural even
    // though the countdown getting there is not.
    final beforeReady1 = cooldown1 <= 0;
    final beforeReady2 = cooldown2 <= 0;

    if (cooldown1 > 0) {
      cooldown1 = max(0, cooldown1 - 0.1);
    }
    if (cooldown2 > 0) {
      cooldown2 = max(0, cooldown2 - 0.1);
    }

    if (mode == GameMode.vsAI && aiTurnToFire) {
      _aiThink();
    }

    // Always advance the rings (cheap: only the two cannon subtrees
    // listen to this).
    cooldownTick.value++;

    // ...but only rebuild the whole screen when something beyond the
    // ring's sweep actually changed.
    if (revision != beforeRevision ||
        phase != beforePhase ||
        aiTurnToFire != beforeAiTurn ||
        (cooldown1 <= 0) != beforeReady1 ||
        (cooldown2 <= 0) != beforeReady2) {
      notifyListeners();
    }
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

        // Mirror the peer's reload on their on-screen cannon. Purely
        // cosmetic — nothing gates on `cooldown2` in a network match (the
        // peer enforces its own) — but without it the opponent's cooldown
        // ring sits permanently full, which reads as "they can fire
        // forever". That's most obvious in chaos mode, where both cannons
        // are visible and firing at once and the ring is the only cue for
        // when the next incoming shot is due.
        cooldown2 = cooldownMax2;

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

      case 'move':
        // MANOEUVRE mode: the opponent repositioned one of their ships.
        // Applied verbatim — they are the authority on their own fleet,
        // and they already validated it against the same rules we would.
        final kind = ShipKind.values[msg['k'] as int];
        final ship = boards[1].shipOfKind(kind);
        if (ship != null) {
          boards[1].ships.remove(ship);
          boards[1].ships.add(PlacedShip(
            spec: ship.spec,
            row: msg['r'] as int,
            col: msg['c'] as int,
            horizontal: msg['h'] as bool,
            hitIndices: Set<int>.from(ship.hitIndices),
          ));
          revision++;
          notifyListeners();
        }
        break;

      case 'resume_request':
        // Our opponent made it back inside the grace window and needs the
        // match handed to them. We are the surviving side, so our state is
        // the authoritative copy.
        if (battling) network.sendResume(buildResumeSnapshot());
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
    cooldownTick.dispose();
    super.dispose();
  }
}
