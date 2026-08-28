import 'dart:math';

import '../models/game_models.dart';
import '../models/power_up.dart';
import 'ai_targeting.dart';
import 'game_controller.dart';

/// Drives the AI's own hidden [GameController] through a vsAiLan match.
///
/// The controller has no screen watching it, so this does the two things
/// `BattleScreen` normally does that plain game logic does not:
///
///  * **Ends the match.** `_checkVictory` only ARMS a pending finish tied
///    to the deciding [CombatEvent] — the actual phase flip happens in
///    `resolvePendingFinishFor`, which the human's battle screen calls
///    once that shot's cannonball has visually landed. There is no ball
///    animation here, so [tick] calls it the instant the event appears.
///  * **Passes the turn.** `peerHasTurn` is a pure UI-maintained mirror
///    (see `BattleScreen._passTurn`) — nothing in `GameController` itself
///    ever flips it. [tick] applies the exact same hit-keeps-firing,
///    miss-passes formula off the AI's own `events` list.
///
/// Everything else — resolving an incoming shot, answering a SONAR/
/// SPOTTER/RECON SWEEP ask, mirroring a MANOEUVRE move — already happens
/// automatically inside `GameController._onNetMessage`, because the AI's
/// controller is a real one wired to a real (loopback) `NetworkService`.
/// This class only has to decide what the AI does on ITS OWN turn.
///
/// ## Pacing
///
/// The AI's controller learns a shot's outcome the moment the loopback
/// link delivers it — microseconds after the human tapped, and a long
/// way ahead of the human's own SCREEN, which is still flying a
/// cannonball across the board and has not begun sliding the cannons
/// over. Acting on that head start is what made the AI look broken:
///
///  * it opened fire during the human's 3-2-1 countdown, before that
///    screen would let its own player shoot at all (see [release]);
///  * its shells landed while the human's shell was still in the air,
///    which reads exactly like both sides firing at once;
///  * its whole turn came and went inside the ~1.25s the human's screen
///    needs to hand the turn over, so the cannon that slid out to mark
///    "their turn" was already sliding home again — the reported "the
///    cannons go to the middle of the grid and come straight back".
///
/// So every action this class takes is scheduled against a wall clock
/// rather than fired the instant it becomes legal: [kHandoffDelay]
/// covers the opponent screen's flight-plus-handoff animation,
/// [kFlightDelay] covers one of the AI's own shells finishing its arc,
/// and [_thinkDelay] on top of either is the deliberate "captain is
/// thinking" beat plain vs-AI already has (`GameController._aiThink`).
class AiBrain {
  AiBrain({
    required GameController controller,
    Random? rng,
    this.difficulty = AIDifficulty.normal,
    bool holdUntilReleased = false,
    DateTime Function()? clock,
  })  : _c = controller,
        _released = !holdUntilReleased,
        _now = clock ?? DateTime.now,
        _rng = rng ?? Random();

  final GameController _c;
  final Random _rng;
  final AIDifficulty difficulty;

  /// Injectable so tests can drive a whole match's worth of pacing
  /// without waiting out real seconds — see the class doc on why the
  /// pacing itself is not something a test should skip.
  final DateTime Function() _now;

  /// `BattleScreen` flies a cannonball for `_projDuration` (750ms) and
  /// then waits another 500ms before actually passing the turn, so from
  /// the moment a miss RESOLVES on this side, the human's screen is
  /// another ~1.25s away from showing them the handoff. Firing inside
  /// that window is what made the two fleets look like they were
  /// shooting simultaneously.
  static const Duration kHandoffDelay = Duration(milliseconds: 1350);

  /// One of the AI's OWN shells needs to finish its arc on the human's
  /// screen before the next one sensibly goes up. Matters most in
  /// CHAOS/BLITZ, where there is no turn to wait for and a miss leaves
  /// the gun instantly ready — the AI used to empty its magazine as fast
  /// as the loopback could carry it.
  static const Duration kFlightDelay = Duration(milliseconds: 800);

  /// Backstop for [_awaitingResult], which is cleared by a result
  /// landing — and a result can legitimately never land. A `'fire'` the
  /// defender answers as `ShotResult.duplicate` is echoed back and then
  /// deliberately DROPPED by the `'result'` handler without registering
  /// an event, and a power-up batch whose cells were all already fired
  /// at sends nothing at all. Either would otherwise wedge the latch shut
  /// for the rest of the match — the reported "the game mode will not
  /// continue". The specific causes are headed off in [_usePowerUp]; this
  /// is what keeps any remaining one from being fatal.
  static const Duration kResultWatchdog = Duration(seconds: 4);

  /// Cells left in the current PHANTOM blind sweep — see
  /// [_pickBlindSweepTarget].
  final List<(int, int)> _sweepQueue = [];

  /// Cells worth trying next because they neighbour a hit that hasn't
  /// been finished off yet. See `AiTargeting.pickTarget`.
  final List<(int, int)> _huntQueue = [];

  /// GHOST FLEET only: the AI's OWN fallible memory of what it has fired
  /// at against the player, kept separate from `GameController.myShots`.
  ///
  /// `myShots` records every shot in every mode regardless of
  /// `recordsShots` — it has to, `_registerShot` is what feeds the
  /// duplicate-shot guard everywhere else — so reading it directly here
  /// would hand the AI a perfect, permanent memory in the one mode where
  /// a HUMAN player is explicitly given none (nothing is drawn on the
  /// grid). [_forgetPass] periodically drops entries from this copy so
  /// the AI's targeting has the same kind of fallibility a person
  /// relying on memory alone actually has.
  List<List<int>>? _memory;

  /// How many of `_c.events` this brain has already walked for impact
  /// resolution / turn-passing — see [_processNewEvents]. Events before
  /// this index have already had their effects applied.
  int _processedEvents = 0;

  /// Set the instant the AI fires (plain shot or a firing power-up) and
  /// cleared once that shot's result comes back. Not optional: `cooldown1`
  /// is only ever set once a `'result'` message lands (see
  /// `GameController._onNetMessage`'s `'result'` case), so without this
  /// latch nothing stops [tick] from calling `fireAt` again before the
  /// first shot has even reached the wire. See [kResultWatchdog] for what
  /// happens when the result never comes.
  bool _awaitingResult = false;
  DateTime? _awaitingSince;

  /// False until the human's battle screen says it is actually showing
  /// the match — see [release].
  bool _released;

  /// Earliest wall-clock moment the AI may take its next shot. Null
  /// means "now".
  DateTime? _nextActionAt;

  /// Earliest moment it may next consider relocating a hull — on its own
  /// independent cadence, since manoeuvring is not a turn-taking action
  /// for either side. See [_maybeRelocate].
  DateTime? _nextMoveAt;

  /// How long between two of the AI's manoeuvring opportunities. Paired
  /// with [_moveChance] this works out to a hull running roughly every
  /// three to five seconds — a captain making decisions, rather than the
  /// old code's roll on every single 300ms tick.
  Duration get _moveInterval => kFlightDelay + _thinkDelay;

  /// Incoming shells this brain has already had its one chance to dodge.
  /// Pruned against the controller's own list, so it can never outlive
  /// the shells — see `GameController.incomingShells`.
  final Set<IncomingShell> _consideredShells = <IncomingShell>{};

  /// True in the modes where the defender waits out [kShellFlight] before
  /// scoring an incoming shot (see `GameController._armIncomingShell`).
  ///
  /// Worth knowing because it changes what this brain still has to wait
  /// for. Everywhere else, a result comes back the instant the peer's
  /// device sees the 'fire', so the shell's own flight across the
  /// player's screen is still ahead of it. In these modes that flight has
  /// ALREADY happened by the time the result lands, and waiting it out a
  /// second time only makes the AI sluggish.
  bool get _resolutionIsDeferred => _c.isManoeuvreBattle;

  Duration get _flightLead =>
      _resolutionIsDeferred ? Duration.zero : kFlightDelay;

  Duration get _handoffLead =>
      _resolutionIsDeferred ? kHandoffDelay - kShellFlight : kHandoffDelay;

  /// Chance the AI gets a hull out from under a shell aimed at it.
  ///
  /// Not 1.0 on purpose. A human with their eyes on the board can dodge
  /// every single time — but they have to notice and act inside the
  /// shell's flight, and an opponent that never once got caught would be
  /// a wall rather than a captain.
  double get _dodgeChance => switch (difficulty) {
        AIDifficulty.easy => 0.20,
        AIDifficulty.normal => 0.35,
        AIDifficulty.hard => 0.55,
      };

  /// The deliberate pause between "the AI could fire" and "the AI fires",
  /// mirroring the delay plain vs-AI already applies in
  /// `GameController._aiThink`.
  Duration get _thinkDelay => switch (difficulty) {
        AIDifficulty.easy => const Duration(milliseconds: 1400),
        AIDifficulty.normal => const Duration(milliseconds: 1000),
        AIDifficulty.hard => const Duration(milliseconds: 700),
      };

  /// Fraction of remembered GHOST FLEET cells kept after each of the
  /// AI's own turns begins — the rest are forgotten. Mirrors the
  /// existing `AIDifficulty` used by plain vs-AI: a sharper opponent
  /// forgets less.
  double get _ghostRetention => switch (difficulty) {
        AIDifficulty.easy => 0.5,
        AIDifficulty.normal => 0.7,
        AIDifficulty.hard => 0.85,
      };

  /// Chance, each action window in a manoeuvring mode, that the AI
  /// spends it relocating a hull as well as firing.
  ///
  /// Deliberately high. These used to be 0.10/0.20/0.30 AND gated behind
  /// "only if something is already under threat", which together meant a
  /// fleet that sat perfectly still through most of a match — the
  /// reported "sometimes they can move their ships, sometimes they
  /// don't". A mode whose entire premise is a fleet that runs needs the
  /// opponent to visibly run.
  double get _moveChance => switch (difficulty) {
        AIDifficulty.easy => 0.30,
        AIDifficulty.normal => 0.45,
        AIDifficulty.hard => 0.60,
      };

  /// Lets the AI start playing. Called by `BattleScreen` once its
  /// start-of-battle 3-2-1 countdown has finished — the human cannot
  /// fire during that (`BattleScreen._fireAtCell` returns early while
  /// `_countingDown`), so neither may the AI. Idempotent.
  void release() {
    if (_released) return;
    _released = true;
    _scheduleAction(Duration.zero);
    _nextMoveAt = _now().add(kHandoffDelay);
  }

  /// One decision cycle. Cheap and idempotent to call repeatedly — safe
  /// to drive from a periodic timer in production or a bounded loop in a
  /// test, and a no-op whenever there is genuinely nothing to do.
  void tick() {
    if (!_c.battling) return;
    _processNewEvents();
    if (!_c.battling) return; // the match may have just ended above
    if (!_released) return;

    final now = _now();
    // Both deliberately ahead of every turn/cooldown gate below: a human
    // may drag a hull at ANY moment in a manoeuvring mode — on their
    // turn, on their opponent's, and above all with a shell already
    // inbound, which is the entire dodge rule. An AI held to its own
    // turn would be manoeuvring at half the tempo of the player it is
    // playing against, and could never dodge at all.
    _maybeDodge(now);
    _maybeRelocate(now);

    if (_awaitingResult) {
      final since = _awaitingSince;
      if (since != null && now.difference(since) < kResultWatchdog) return;
      // See [kResultWatchdog] — a result that is never coming.
      _awaitingResult = false;
      _awaitingSince = null;
    }

    final myTurn = !_c.lanBattleMode.hasTurns || !_c.peerHasTurn;
    if (!myTurn) return;

    if (_c.cooldown1 > 0) return;
    final due = _nextActionAt;
    if (due != null && now.isBefore(due)) return;
    _nextActionAt = null;

    if (_c.isPowerUpBattle && _c.myPowerUp != null) {
      if (_usePowerUp()) return; // a firing card just fired — done this tick
    }

    _fireOrdinaryShot();
  }

  // ------------------------------------------------- EVENTS / TURN FLOW ---

  void _processNewEvents() {
    while (_processedEvents < _c.events.length) {
      final e = _c.events[_processedEvents];
      _processedEvents++;

      // Mirrors `BattleScreen._resolveImpact`: arm→finish transition and
      // the sound/RP award it gates are `_c.headless`-suppressed there.
      _c.resolvePendingFinishFor(e);
      if (!_c.battling) return; // finished — nothing left to pass

      if (e.byPlayer) {
        // This shot's result is now known — see the doc on
        // [_awaitingResult] for why that alone (not turn-passing below,
        // which never happens at all in CHAOS/BLITZ) is what frees the
        // brain to act again.
        _awaitingResult = false;
        _awaitingSince = null;
        if (_c.isGhostBattle) _rememberOwnShot(e);
        _updateHuntQueue(e);
        // Whatever happens to the turn below — kept by a hit, held open
        // by a power-up, or not a thing at all in CHAOS/BLITZ — this
        // shell still has to finish its arc on the player's screen
        // before the next one goes up. See [_flightLead] for why that is
        // already paid for in the dodge modes.
        _scheduleAction(_flightLead);
      }

      if (!_c.lanBattleMode.hasTurns) continue; // no turn to pass here

      // Mirrors `BattleScreen._maybePassTurn` exactly — see its own doc
      // for why `forcePass` bypasses the hold/hit checks below and why
      // `e.byPlayer` alone decides the direction either way.
      if (!e.forcePass) {
        if (e.hold) continue;
        if (e.result != ShotResult.miss) continue;
      }
      final wasMyTurn = !_c.peerHasTurn;
      _c.peerHasTurn = e.byPlayer;
      final nowMyTurn = !_c.peerHasTurn;
      if (!wasMyTurn && nowMyTurn) _onOwnTurnStart();
    }
  }

  void _onOwnTurnStart() {
    // The turn is ours HERE, but the human's screen is still ~1.25s from
    // showing them that — see [kHandoffDelay] and [_handoffLead].
    _scheduleAction(_handoffLead);
    // Unconditional on purpose: `onMyTurnStart` gates its own work —
    // POWER PLAY's draw AND GHOST FLEET's escape-window closing (this
    // turn began because the human missed, which is exactly the boundary
    // that pins their previously-dodging hulls — the AI plays the pin
    // rule by the same book the human's device does).
    _c.onMyTurnStart();
    if (_c.isGhostBattle) _forgetPass();
  }

  /// Pushes the next shot out to [lead] plus a think beat, never dragging
  /// an already-later deadline earlier.
  void _scheduleAction(Duration lead) {
    final at = _now().add(lead + _thinkDelay);
    final cur = _nextActionAt;
    if (cur == null || at.isAfter(cur)) _nextActionAt = at;
  }

  void _forgetPass() {
    final mem = _memory;
    if (mem == null) return;
    for (var r = 0; r < kBoardSize; r++) {
      for (var c = 0; c < kBoardSize; c++) {
        if (mem[r][c] != 0 && _rng.nextDouble() > _ghostRetention) {
          mem[r][c] = 0;
        }
      }
    }
  }

  void _rememberOwnShot(CombatEvent e) {
    final mem = _memory ??=
        List.generate(kBoardSize, (_) => List.filled(kBoardSize, 0));
    mem[e.row][e.col] =
        (e.result == ShotResult.hit || e.result == ShotResult.sunk) ? 2 : 1;
  }

  void _updateHuntQueue(CombatEvent e) {
    // PHANTOM: neither captain is told what a shot did — the human's
    // screen shows the same neutral splash for a hit as for a miss (see
    // `LanBattleMode.hidesShotFeedback`). Feeding this queue from the
    // REAL results would hand the AI an information edge its opponent is
    // explicitly denied, so it aims blind there: fallible memory only
    // (`_knownShots` / `_forgetPass`), exactly like Ghost Fleet's grid.
    if (_c.isPhantomBattle) return;
    if (e.result == ShotResult.sunk) {
      // Nothing left to follow up on for that contact.
      _huntQueue.clear();
    } else if (e.result == ShotResult.hit) {
      _huntQueue.addAll(AiTargeting.neighborsOf(e.row, e.col, _rng));
    }
  }

  // ------------------------------------------------------------- FIRING ---

  List<List<int>> get _knownShots => _c.isGhostBattle
      ? (_memory ??=
          List.generate(kBoardSize, (_) => List.filled(kBoardSize, 0)))
      : _c.myShots;

  void _fireOrdinaryShot() {
    final target = _c.isPhantomBattle
        ? _pickBlindSweepTarget()
        : AiTargeting.pickTarget(
            shots: _knownShots,
            huntQueue: _huntQueue,
            rng: _rng,
          );
    if (target == null) return; // nowhere left to shoot — shouldn't happen
    final result = _c.fireAt(target.$1, target.$2);
    if (result != ShotResult.invalid &&
        result != ShotResult.cooldown &&
        result != ShotResult.duplicate) {
      _markAwaitingResult();
    }
  }

  /// PHANTOM's targeting: a systematic sweep of the whole board.
  ///
  /// No result ever reaches either captain in this mode, so there is no
  /// hunt to follow and no splash to read — the only sensible blind
  /// policy is the one a blind human falls back to: cover every cell.
  /// This matters for LIVENESS, not just style. The default
  /// [AiTargeting.pickTarget] hunts on the checkerboard parity and only
  /// reaches the odd half of the board once every even cell is tried —
  /// but this mode's fallible memory keeps un-forgetting even cells, so
  /// the parity pool never empties and NO ship would ever take the odd
  /// -half damage it needs to sink. Every fleet would float forever and
  /// the match could never end. Sweeping all 100 cells in a fresh random
  /// order each pass guarantees full coverage, so every match terminates.
  ///
  /// [AiTargeting]'s parity logic stays in every other mode, where real
  /// results come back and the hunt queue finishes what parity finds.
  (int, int)? _pickBlindSweepTarget() {
    final known = _knownShots;
    (int, int)? take() {
      while (_sweepQueue.isNotEmpty) {
        final cell = _sweepQueue.removeLast();
        if (known[cell.$1][cell.$2] == 0) return cell;
      }
      return null;
    }

    var pick = take();
    if (pick != null) return pick;
    // Pass exhausted — deal a fresh random one. Never-fired cells are
    // always unremembered (`_forgetPass` only fades FIRED cells), so the
    // first pass already offers every cell of the board at least once.
    final all = [
      for (var r = 0; r < kBoardSize; r++)
        for (var c = 0; c < kBoardSize; c++) (r, c),
    ];
    all.shuffle(_rng);
    _sweepQueue
      ..clear()
      ..addAll(all);
    return take();
  }

  void _markAwaitingResult() {
    _awaitingResult = true;
    _awaitingSince = _now();
  }

  // --------------------------------------------------------- POWER PLAY ---

  /// Uses the currently-held card. Returns true only when doing so fired
  /// a shot (or shots) of its own, in which case the turn's ordinary
  /// firing step should be skipped — every other card is a free action
  /// alongside the turn's actual shot, exactly as it is for a human.
  ///
  /// A card that can't accomplish anything right now is simply HELD, the
  /// way a human holds one: `GameController.usePowerUp` returns false and
  /// keeps it, and the turn's ordinary shot still goes out. The checks
  /// below exist so the AI doesn't spend its turn discovering that — and,
  /// for the firing cards, so it never latches [_awaitingResult] onto a
  /// batch that ends up sending nothing at all.
  bool _usePowerUp() {
    final card = _c.myPowerUp!;
    switch (card) {
      case PowerUpCard.spray:
      case PowerUpCard.salvo:
      case PowerUpCard.depthCharge:
      case PowerUpCard.chainShot:
      case PowerUpCard.crossFire:
        // Both SPRAY cells (or `usePowerUp` refuses the card outright),
        // and for the shaped cards a centre whose SHAPE still has
        // something to shoot at — see [_shapeHasFreshCell].
        final cells = _firingCellsFor(card);
        if (cells == null) return false;
        if (_c.usePowerUp(cells)) {
          _markAwaitingResult();
          return true;
        }
        return false;
      case PowerUpCard.barrage:
        // `PowerUpShapes.barrage` draws four DISTINCT cells from the
        // ones NOT already fired at, and returns however few it could
        // find — on a nearly-exhausted board that can be none at all,
        // which would spend the card and fire nothing.
        if (_unfiredCellCount() < 4) return false;
        if (_c.usePowerUp()) {
          _markAwaitingResult();
          return true;
        }
        return false;
      case PowerUpCard.sonar:
      case PowerUpCard.reconSweep:
        final cells = _targetCellsFor(card);
        if (cells != null && cells.length == _c.powerUpTapsNeeded) {
          _c.usePowerUp(cells);
        }
        return false;
      case PowerUpCard.minefield:
      case PowerUpCard.trapLine:
        final cells = _ownGridCellsFor(card);
        if (cells != null) _c.usePowerUp(cells);
        return false;
      case PowerUpCard.spotter:
      case PowerUpCard.doubleTap:
      case PowerUpCard.jam:
      case PowerUpCard.hotShot:
      case PowerUpCard.rapidFire:
      case PowerUpCard.counterBattery:
      case PowerUpCard.decoy:
        // No target needed; `usePowerUp` itself no-ops safely if it can't
        // apply right now (e.g. it's not actually this device's turn).
        _c.usePowerUp();
        return false;
      case PowerUpCard.repair:
      case PowerUpCard.patchCrew:
        // Nothing damaged yet — hold it until there is, rather than
        // spending the turn's card slot on a guaranteed refusal.
        if (!_hasDamagedHull()) return false;
        _c.usePowerUp();
        return false;
      case PowerUpCard.scramble:
        if (!_c.boards[0].ships.any((s) => s.hitIndices.isEmpty)) return false;
        _c.usePowerUp();
        return false;
    }
  }

  bool _hasDamagedHull() =>
      _c.boards[0].ships.any((s) => s.hitIndices.isNotEmpty && !s.isSunk);

  int _unfiredCellCount() {
    var n = 0;
    for (var r = 0; r < kBoardSize; r++) {
      for (var c = 0; c < kBoardSize; c++) {
        if (_c.myShots[r][c] == 0) n++;
      }
    }
    return n;
  }

  /// The cells to hand a FIRING card, or null when it can't usefully be
  /// spent right now and should be held instead.
  ///
  /// BUGFIX (POWER PLAY hung on the AI's turn and never resumed): the
  /// shaped cards do NOT simply fire around the cell they are given.
  /// `PowerUpShapes._clamp` SLIDES a shape that would hang off the board
  /// back on — so CROSS FIRE aimed at (0,0) actually fires the plus
  /// centred on (1,1), and the fresh cell that was picked isn't in the
  /// shape at all. `GameController._fireShotBatch` then silently drops
  /// every cell already fired at, and a batch left with nothing sends
  /// nothing — while `usePowerUp` still reports success and spends the
  /// card. The brain latched [_awaitingResult] onto a shot that was
  /// never on the wire and waited for a result that could not come, with
  /// nothing on either device able to move the match forward.
  List<(int, int)>? _firingCellsFor(PowerUpCard card) {
    final picked = _targetCellsFor(card);
    if (picked == null || picked.length != _c.powerUpTapsNeeded) return null;
    // SPRAY fires its two cells verbatim and both came from the
    // already-tried filter, so there is nothing to slide out from under
    // it; likewise CHAIN SHOT's single cell.
    if (card == PowerUpCard.spray || card == PowerUpCard.chainShot) {
      return picked;
    }
    if (_shapeHasFreshCell(card, picked.first)) return picked;
    // The hunt's own pick lands on an edge with nothing left around it.
    // Any other centre whose shape still has water to hit will do.
    final fallback = <(int, int)>[
      for (var r = 0; r < kBoardSize; r++)
        for (var c = 0; c < kBoardSize; c++)
          if (_c.myShots[r][c] == 0) (r, c),
    ]..shuffle(_rng);
    for (final cell in fallback) {
      if (_shapeHasFreshCell(card, cell)) return [cell];
    }
    return null; // hold it — nothing this card could still accomplish
  }

  bool _shapeHasFreshCell(PowerUpCard card, (int, int) centre) {
    final (r, c) = centre;
    final shape = switch (card) {
      PowerUpCard.salvo => PowerUpShapes.salvo(r, c),
      PowerUpCard.depthCharge => PowerUpShapes.depthCharge(r, c),
      PowerUpCard.crossFire => PowerUpShapes.crossFire(r, c),
      _ => [centre],
    };
    return shape.any((p) => _c.myShots[p.$1][p.$2] == 0);
  }

  /// One or two cells against the OPPONENT's grid for a card that needs
  /// them, reusing the same hunt logic ordinary firing does — spending a
  /// card's shots on an already-good guess is strictly better than a
  /// fresh random tap. Null only when nowhere legal remains.
  List<(int, int)>? _targetCellsFor(PowerUpCard card) {
    final taps = card == PowerUpCard.spray ? 2 : 1;
    final picked = <(int, int)>[];
    final tried = <(int, int)>{};
    for (var i = 0; i < taps; i++) {
      final queueCopy = [..._huntQueue.where((c) => !tried.contains(c))];
      final cell = AiTargeting.pickTarget(
        shots: _knownShots,
        huntQueue: queueCopy,
        rng: _rng,
      );
      // A repeat means the blind search has only that one cell left to
      // offer, so a two-tap card genuinely cannot be filled.
      if (cell == null || tried.contains(cell)) {
        return picked.isEmpty ? null : picked;
      }
      picked.add(cell);
      tried.add(cell);
    }
    return picked;
  }

  /// One cell on the AI's OWN grid for MINEFIELD/TRAP LINE — anywhere the
  /// opponent hasn't already fired, so the mine has a chance of ever
  /// being stepped on. Null only when the whole board is already fired
  /// on (the match is essentially over at that point regardless).
  List<(int, int)>? _ownGridCellsFor(PowerUpCard card) {
    final candidates = <(int, int)>[
      for (var r = 0; r < kBoardSize; r++)
        for (var c = 0; c < kBoardSize; c++)
          if (_c.p2Shots[r][c] == 0) (r, c),
    ];
    if (candidates.isEmpty) return null;
    return [candidates[_rng.nextInt(candidates.length)]];
  }

  // ----------------------------------------------------------- MOVEMENT ---

  /// Gets a hull out from under an enemy shell that is still in the air.
  ///
  /// The shot is only scored when the shell lands, against the board as
  /// it stands then (see `GameController._armIncomingShell`), so this is
  /// the same window — and the same move — a player gets by dragging the
  /// threatened hull clear. One decision per shell: if the roll goes
  /// against it, the AI wears the hit rather than getting a fresh chance
  /// on every tick of the flight.
  void _maybeDodge(DateTime now) {
    if (!_c.isManoeuvreBattle) return;
    final shells = _c.incomingShells;
    if (shells.isEmpty) {
      _consideredShells.clear();
      return;
    }
    for (final shell in shells.toList()) {
      if (!_consideredShells.add(shell)) continue;
      final ship = _c.boards[0].shipAt(shell.row, shell.col);
      if (ship == null) continue; // aimed at open water already
      if (!_c.canRelocate(ship)) continue; // pinned by damage
      if (_rng.nextDouble() >= _dodgeChance) continue;
      if (_dodgeShip(ship)) {
        // A hull that just ran counts as this window's manoeuvre —
        // otherwise the fleet would shuffle twice in the same beat.
        _nextMoveAt = now.add(_moveInterval);
      }
    }
    _consideredShells.retainAll(shells);
  }

  /// Moves [ship] to the quietest legal water that no shell currently in
  /// the air is aimed at. Dodging INTO another inbound shell would be a
  /// worse move than standing still.
  bool _dodgeShip(PlacedShip ship) {
    final danger = <(int, int)>{
      for (final s in _c.incomingShells) (s.row, s.col),
    };
    final spots = _legalSpotsFor(ship)
        .where((spot) => !_spotCovers(ship, spot, danger))
        .toList();
    if (spots.isEmpty) return false;
    spots.sort(
        (a, b) => _threatAtSpot(ship, a).compareTo(_threatAtSpot(ship, b)));
    final pool = spots.take(max(1, spots.length ~/ 4)).toList();
    final pick = pool[_rng.nextInt(pool.length)];
    return _c.relocateOwnShip(ship.spec.kind, pick.$1, pick.$2, pick.$3);
  }

  bool _spotCovers(
    PlacedShip ship,
    (int, int, bool) spot,
    Set<(int, int)> cells,
  ) {
    final (row, col, horizontal) = spot;
    for (var i = 0; i < ship.spec.size; i++) {
      final r = horizontal ? row : row + i;
      final c = horizontal ? col + i : col;
      if (cells.contains((r, c))) return true;
    }
    return false;
  }

  void _maybeRelocate(DateTime now) {
    if (!_c.isManoeuvreBattle) return;
    final due = _nextMoveAt;
    if (due != null && now.isBefore(due)) return;
    // The interval is spent whether or not the roll goes through — a
    // refused roll must not be retried several times a second until one
    // finally lands.
    _nextMoveAt = now.add(_moveInterval);
    if (_rng.nextDouble() >= _moveChance) return;
    _relocateBestShip();
  }

  /// Relocates at most one hull, preferring whichever is nearest the
  /// cells the player has actually been shooting at — the same "am I
  /// about to be found" signal a human reads off their own board — and
  /// landing it on the quietest water available.
  ///
  /// Every legal destination is enumerated rather than sampled. The old
  /// version threw 40 random (row, col, orientation) darts and gave up if
  /// none stuck, which fails more and more often as the board fills with
  /// fired-at water a hull may not be moved onto: another reason the AI's
  /// fleet appeared to move only sometimes.
  void _relocateBestShip() {
    final board = _c.boards[0];
    // GHOST FLEET lets a damaged hull run too — `GameController.canRelocate`
    // already encodes exactly that difference.
    final movable =
        board.ships.where((s) => !s.isSunk && _c.canRelocate(s)).toList();
    if (movable.isEmpty) return;

    movable.sort((a, b) => _threatTo(b).compareTo(_threatTo(a)));
    // Nothing under threat yet (early match): pick at random rather than
    // standing perfectly still — this mode's whole premise is a fleet
    // that keeps moving.
    if (_threatTo(movable.first) == 0) movable.shuffle(_rng);

    for (final ship in movable) {
      final spots = _legalSpotsFor(ship);
      if (spots.isEmpty) continue;
      spots.sort(
          (a, b) => _threatAtSpot(ship, a).compareTo(_threatAtSpot(ship, b)));
      // Choose among the quietest quarter so the AI isn't perfectly
      // predictable about where it runs to.
      final pool = spots.take(max(1, spots.length ~/ 4)).toList();
      final pick = pool[_rng.nextInt(pool.length)];
      if (_c.relocateOwnShip(ship.spec.kind, pick.$1, pick.$2, pick.$3)) {
        return;
      }
    }
  }

  /// How close the player's fire has come to [ship] where it sits now.
  int _threatTo(PlacedShip ship) {
    var score = 0;
    for (final cell in ship.cells) {
      score += _threatAtCell(cell[0], cell[1]);
    }
    return score;
  }

  int _threatAtSpot(PlacedShip ship, (int, int, bool) spot) {
    final (row, col, horizontal) = spot;
    var score = 0;
    for (var i = 0; i < ship.spec.size; i++) {
      final r = horizontal ? row : row + i;
      final c = horizontal ? col + i : col;
      score += _threatAtCell(r, c);
    }
    return score;
  }

  int _threatAtCell(int r, int c) {
    var score = _c.p2Shots[r][c] != 0 ? 2 : 0;
    for (final o in const [(-1, 0), (1, 0), (0, -1), (0, 1)]) {
      final nr = r + o.$1;
      final nc = c + o.$2;
      if (nr < 0 || nr >= kBoardSize || nc < 0 || nc >= kBoardSize) continue;
      if (_c.p2Shots[nr][nc] != 0) score++;
    }
    return score;
  }

  /// Every (row, col, horizontal) [ship] could legally move to, minus
  /// where it already is.
  List<(int, int, bool)> _legalSpotsFor(PlacedShip ship) {
    final board = _c.boards[0];
    final ghost = _c.isGhostBattle;
    // Per-hull, not per-mode: whether damage pins this particular hull is
    // the hull's own business (in GHOST FLEET it stays free to run until
    // it goes down — see `GameController.damageIgnorableFor`), so this
    // must ask about the hull rather than assume the mode's blanket rule,
    // or the AI could go on dragging one the human couldn't.
    final escape = _c.damageIgnorableFor(ship);
    final out = <(int, int, bool)>[];
    for (final horizontal in const [true, false]) {
      for (var r = 0; r < kBoardSize; r++) {
        for (var c = 0; c < kBoardSize; c++) {
          if (r == ship.row && c == ship.col && horizontal == ship.horizontal) {
            continue; // not a move
          }
          if (board.canRelocateTo(ship, r, c, horizontal,
              ignoreDamage: escape, ignoreShotHistory: ghost)) {
            out.add((r, c, horizontal));
          }
        }
      }
    }
    return out;
  }
}
