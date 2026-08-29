import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/game_models.dart';
import '../models/power_up.dart';
import 'network_service.dart';
import 'sound_service.dart';
import 'storage_service.dart';

// `vsAiLan` is its own value rather than reusing `hotspot` so the compiler
// finds every place that needs to know about it: adding a case here turns
// any exhaustive `switch (GameMode ...)` with no `default` into a compile
// error at every site that needs a decision, instead of relying on a
// grep to have caught them all. It runs the full hotspot/online match
// PROTOCOL (mode rules, power-up resolution, turn passing) against a
// hidden AI opponent over a `LoopbackLink` — see `usesMatchProtocol` —
// but has no actual remote human on the other end, so anything about a
// REAL peer (chat, the reconnect grace window, RP sync) reads
// `hasRemotePeer` instead.
enum GameMode { vsAI, local, hotspot, online, vsAiLan }
enum BattlePhase { idle, placing, battling, finished }

class CombatEvent {
  final int row;
  final int col;
  final ShotResult result;
  final bool byPlayer;
  final String? sunkShipName;
  final DateTime time;
  DateTime? impactAt;

  /// POWER PLAY only: this shot is one of several fired as a single
  /// power-up action (or a DOUBLE TAP / COUNTER BATTERY bonus), and must
  /// never itself hand the turn over regardless of its own result — see
  /// `BattleScreen._maybePassTurn`.
  final bool hold;

  /// POWER PLAY only: MINEFIELD / TRAP LINE triggered on this shot — the
  /// turn passes to whoever's board this landed on, i.e. AWAY from
  /// [byPlayer], regardless of hit or miss.
  final bool forcePass;

  CombatEvent({
    required this.row,
    required this.col,
    required this.result,
    required this.byPlayer,
    this.sunkShipName,
    this.hold = false,
    this.forcePass = false,
  }) : time = DateTime.now();
}

/// An enemy shell already on its way to this device's own water, in the
/// modes where a hull still has time to get out from under it.
///
/// Only exists between the `'fire'` message landing and [kShellFlight]
/// later, when `GameController._resolveIncomingFire` decides what it
/// actually hit — see `GameController._armIncomingShell` for why those
/// two moments are no longer the same one. The defending screen reads
/// these to fly the incoming cannonball; nothing else about the shot is
/// known yet, and deliberately so.
class IncomingShell {
  IncomingShell({
    required this.row,
    required this.col,
    required this.hold,
    this.seq,
  }) : launchedAt = DateTime.now();

  final int row;
  final int col;
  final bool hold;

  /// GHOST FLEET's rising fire counter, carried so a redelivery arriving
  /// while this one is still airborne can be recognised as the same shot.
  final int? seq;

  final DateTime launchedAt;
  Timer? timer;
}

class GameController extends ChangeNotifier {
  GameController({required this.profile, required this.network});

  final ProfileStore profile;
  final NetworkService network;

  GameMode mode = GameMode.vsAI;

  /// True for the hidden `GameController` a `vsAiLan` match creates to
  /// stand in for the AI opponent — it runs the real match protocol
  /// against the player's controller (see `usesMatchProtocol`) but has no
  /// screen of its own. Gates the two things in `_finish` that only make
  /// sense for a controller a human is actually looking at: the
  /// victory/defeat SOUND (without this, the AI's `_finish` running at
  /// the same instant as the player's would play the opposite cue right
  /// on top of it) and the ranked RP award (the AI's `ProfileStore` is a
  /// throwaway never backed by `SharedPreferences`, so awarding into it is
  /// harmless either way — this just keeps its intent honest).
  bool headless = false;

  /// Which rules a hotspot/online match runs under — decided by both
  /// players in the pre-match vote (see `LanModeScreen`). Ignored in
  /// vs-AI and local pass-and-play, which are always turn-based UNLESS
  /// [localPhantom] is set (see its own doc) — that one exception is a
  /// standalone flag rather than a value stored here because local play
  /// never runs the vote this field exists to record.
  LanBattleMode lanBattleMode = LanBattleMode.turns;

  /// LOCAL PASS-AND-PLAY only: PHANTOM's rules — no persistent hit/miss
  /// marks, a cell may be re-targeted, the combat log never names a
  /// coordinate — applied to the shared-screen match instead of the
  /// always-turn-based default. Set by whichever screen starts a local
  /// match (see `LocalModeScreen`), the same way `lanBattleMode` is set
  /// by the LAN vote; meaningless — and never read — outside
  /// `mode == GameMode.local`. See [isGhostBattle], which folds this in
  /// alongside GHOST FLEET/PHANTOM themselves rather than exposing it as
  /// a second, parallel flag every downstream check would also need.
  ///
  /// PHANTOM rather than GHOST FLEET specifically: local pass-and-play
  /// never lets a fleet rearrange in the first place (`isManoeuvreBattle`
  /// requires [usesMatchProtocol], which local play never sets), so
  /// GHOST FLEET's one difference from PHANTOM — a damaged hull's escape
  /// window — would be pure dead code here. PHANTOM is the record-free
  /// mode local play can actually offer in full.
  bool localPhantom = false;

  /// True when both fleets fire simultaneously with no turn order.
  /// CHAOS and BLITZ; the two differ only in whether hulls can move.
  bool get isChaosBattle => usesMatchProtocol && !lanBattleMode.hasTurns;

  /// True when ships may be repositioned mid-battle. MANOEUVRE, BLITZ and
  /// GHOST FLEET; the three differ in whether there are turns and in
  /// whether a damaged hull may still move (see [isGhostBattle]).
  bool get isManoeuvreBattle =>
      usesMatchProtocol && lanBattleMode.canRearrange;

  /// True when no hit, miss or wreck is ever recorded — GHOST FLEET and
  /// PHANTOM, the two record-free modes (see
  /// `LanBattleMode.recordsShots`), OR local pass-and-play with
  /// [localPhantom] switched on. Nothing is marked for the shooter, a
  /// fired cell may be fired at again fresh, and (in GHOST FLEET) a
  /// damaged hull's freedom to move is governed by
  /// [damageIgnorableFor] rather than pinned outright. Everything
  /// downstream that cares reads this rather than the mode directly, the
  /// same pattern [isChaosBattle] and [isManoeuvreBattle] use.
  ///
  /// Local pass-and-play is folded in here rather than getting its own
  /// parallel getter because every one of those downstream reads is
  /// EXACTLY what PHANTOM already wants — no persistent marks, an
  /// immediate splash with nothing left behind, a coordinate-less log —
  /// and local matches never set [usesMatchProtocol], so the two halves
  /// of this OR can never both fire for the same match.
  bool get isGhostBattle =>
      (usesMatchProtocol && !lanBattleMode.recordsShots) ||
      (mode == GameMode.local && localPhantom);

  /// True only for PHANTOM — over the wire (hotspot/online/vsAiLan) or on
  /// one shared screen ([localPhantom]), since the mode's rules are the
  /// same either way and every read below is about the RULES.
  ///
  /// On top of keeping no record (so it is also covered by
  /// [isGhostBattle]), the fleet is FIXED — it never rearranges and there
  /// is no dodge window — and a shell that lands on a hull cell already
  /// holed scores nothing at all, leaving that cell a miss for the rest
  /// of the match (`Board.receiveShot`'s `repeatHitMisses`). That last
  /// rule is the one thing PHANTOM does differently from GHOST FLEET,
  /// which instead redirects such a shell onto fresh plating. See
  /// [isGhostFleetBattle] for the non-manoeuvring record-free mode.
  bool get isPhantomBattle =>
      (usesMatchProtocol && lanBattleMode == LanBattleMode.phantom) ||
      (mode == GameMode.local && localPhantom);

  /// True only for GHOST FLEET proper (not PHANTOM): the record-free mode
  /// whose fleet may still run, and whose sunk hulls are freed and fades
  /// away so survivors can sail back onto that water (see [clearSunkShip]
  /// and `PlacedShip.sunkCleared`).
  bool get isGhostFleetBattle =>
      usesMatchProtocol && lanBattleMode == LanBattleMode.ghost;

  /// True only for POWER PLAY.
  bool get isPowerUpBattle => usesMatchProtocol && lanBattleMode.hasPowerUps;

  /// True whenever the match runs under the hotspot/online wire protocol
  /// — mode rules, turn order, power-up resolution — whether the other
  /// end is a real device (`hotspot`/`online`) or a hidden AI opponent
  /// joined over a `LoopbackLink` (`vsAiLan`). Everything above that
  /// decides HOW the match plays reads this.
  bool get usesMatchProtocol =>
      mode == GameMode.hotspot || mode == GameMode.online || mode == GameMode.vsAiLan;

  /// True only when the other end is an actual remote device — chat, the
  /// reconnect grace window, and online RP sync all read this instead of
  /// [usesMatchProtocol], since none of them mean anything against an AI
  /// that lives in this same process.
  bool get hasRemotePeer => mode == GameMode.hotspot || mode == GameMode.online;

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

  // ---------------------------------------------------- GHOST FLEET ---
  //
  // Every other mode gets network-replay protection on a 'fire' message
  // for free: `Board.receiveShot` already refuses to hit the same cell
  // twice, so a redelivered 'fire' (`RelayLink._flush` retries a batch
  // whose HTTP acknowledgement was lost even though the server had
  // already inserted it — see that method's doc) comes back as
  // `ShotResult.duplicate` and is echoed rather than re-applied. GHOST
  // FLEET deliberately turns that cell-based check OFF — a ship may
  // genuinely have moved into an already-fired cell since, and refiring
  // it has to be evaluated fresh — so it needs its own, separate
  // per-shot identifier to still catch a literal redelivery of the same
  // message. Scoped to this one mode because the other four already have
  // a working, tested guard that this would otherwise duplicate for no
  // reason.

  /// Rising counter tagging every 'fire' THIS device sends in GHOST
  /// FLEET, so a genuine retry of the same tap (identical seq) can be
  /// told apart from a fresh, later fire at the same cell (a higher
  /// seq).
  int _fireSeq = 0;

  /// The seq of the most recent 'fire' actually applied FROM the peer.
  /// A redelivered copy carries the same value again and is answered
  /// with [_lastPeerFireResult] rather than run through
  /// `Board.receiveShot` a second time. Turn-based play means at most
  /// one of the peer's fires is ever outstanding, so remembering only
  /// the latest is enough — there is nothing earlier left to redeliver.
  int? _lastPeerFireSeq;
  ShotResult? _lastPeerFireResult;
  String? _lastPeerFireSunkName;

  // ---------------------------------------------------- POWER PLAY ----
  //
  // See `lib/models/power_up.dart` for the twenty-card deck and the four
  // routes every card resolves through. Every field below is meaningless
  // outside `isPowerUpBattle`, and every method in this block returns
  // early (or is simply never called) when it's false.

  /// The card currently in this player's hand, or null when empty. Never
  /// more than one at a time — see `LanBattleMode.powerPlay`'s doc.
  /// Hidden from the opponent until spent.
  PowerUpCard? myPowerUp;

  /// Cells this device's SONAR/SPOTTER has revealed on the ENEMY board —
  /// "row * kBoardSize + col" keys. Purely additive display state.
  final Set<int> spottedEnemyCells = {};

  /// JAM: set by an incoming `pw_flag`; consumed by the very next
  /// [onMyTurnStart] draw check, which then skips that turn's draw.
  bool _jammed = false;

  /// DECOY: armed by using the card on THIS board; consumed the next time
  /// an incoming shot would otherwise hit it — the hit is swallowed
  /// (reported as a miss, no damage taken) rather than resolved normally.
  bool _decoyArmed = false;

  /// COUNTER BATTERY: armed by using the card; the next incoming hit
  /// this board takes converts it into one queued entry in [_bonusShots]
  /// instead of firing immediately, since the card reads "your NEXT
  /// turn", not "immediately".
  bool _counterBatteryArmed = false;
  int _bonusShots = 0;

  /// HOT SHOT: armed on THIS device by an incoming `pw_flag` from the
  /// peer (they used the card on themselves — "your next hit"). The
  /// very next hit this board takes also damages one more adjacent,
  /// unhit cell of the same hull.
  bool _hotShotArmedAgainstMe = false;

  /// RAPID FIRE: shots left with halved cooldown after a hit.
  int _rapidFireShotsLeft = 0;

  /// DOUBLE TAP: arms the very next [fireAt] so a miss there doesn't pass
  /// the turn. Consumed on that call regardless of its result (a hit
  /// never passed the turn anyway).
  bool _doubleTapArmed = false;

  /// CHAIN SHOT: set the instant the card's single target shot is fired;
  /// consulted once — and only once — that shot's result lands.
  bool _chainShotArmed = false;

  /// MINEFIELD / TRAP LINE mined on THIS player's own board. Each entry
  /// is one trap (MINEFIELD: 1 cell, TRAP LINE: 3) — a hit on ANY cell in
  /// a trap consumes the whole entry, so the other cells (if any) go
  /// inert with it rather than staying armed. Cell keys are
  /// "row * kBoardSize + col".
  final List<Set<int>> _myTraps = [];

  /// True while [myPowerUp] is a card that still needs the player to pick
  /// a cell (or two, for SPRAY) before it does anything.
  bool get powerUpNeedsTarget =>
      myPowerUp != null && PowerUps.of(myPowerUp!).needsTarget;

  /// Whether that target should come from the player's OWN grid
  /// (MINEFIELD / TRAP LINE) rather than the enemy's.
  bool get powerUpTargetsOwnGrid =>
      myPowerUp != null && PowerUps.of(myPowerUp!).targetsOwnGrid;

  /// How many cells the held card's target needs — every targeted card
  /// resolves on a single tap except SPRAY, which picks two.
  int get powerUpTapsNeeded => myPowerUp == PowerUpCard.spray ? 2 : 1;

  /// Called once whenever this device's own turn begins. POWER PLAY:
  /// draws a fresh card if the hand is empty — unless the opponent JAMmed
  /// this turn, in which case that one draw is skipped and the jam is
  /// spent.
  void onMyTurnStart() {
    if (!isPowerUpBattle || !battling) return;
    if (_jammed) {
      _jammed = false;
      _log('📡 Signal jammed — no card this turn.');
      notifyListeners();
      return;
    }
    if (myPowerUp != null) return;
    myPowerUp = PowerUps.draw(_rng);
    _log('🃏 Drew ${PowerUps.of(myPowerUp!).name}.');
    notifyListeners();
  }

  /// GHOST FLEET: whether [ship]'s existing damage does NOT pin it.
  ///
  /// A hull that is still afloat may always be moved, however badly it is
  /// burning — the whole promise of the mode is that nothing recorded
  /// where you were hit, so damage never costs you the right to run. A
  /// SUNK hull is the one exception: it is a wreck, not a ship, and the
  /// only thing that ever happens to it is [clearSunkShip] freeing its
  /// water.
  ///
  /// BUGFIX (a hull stuck where it sat for the rest of the match): this
  /// used to also require [peerHasTurn] and an un-closed per-hull escape
  /// window — "you may only run while the attacker is mid-streak, and the
  /// first miss pins you for good". In practice that meant a single hit
  /// followed by the attacker's very next miss (which is what hands the
  /// turn over, and so what opened the owner's own turn) froze the hull
  /// permanently while it was still perfectly alive — reported as ships
  /// getting stuck, and it made the mode's headline "your fleet can run"
  /// true for roughly one turn. Undamaged hulls were never affected, and
  /// every non-ghost mode still pins a damaged hull outright (this stays
  /// false for them).
  bool damageIgnorableFor(PlacedShip ship) => isGhostBattle && !ship.isSunk;

  /// GHOST FLEET: frees a destroyed hull's water — the "it sank and faded
  /// away" moment. Marks our own board's hull [PlacedShip.sunkCleared]
  /// (so surviving hulls may be moved back onto those cells, and a fresh
  /// shot there is a clean miss) and mirrors the same flag to the
  /// opponent's copy of OUR fleet, keeping the two in step — exactly like
  /// [relocateOwnShip], where our copy is the authority and theirs follows.
  ///
  /// Only meaningful in GHOST FLEET. Every other mode keeps a sunk hull's
  /// water occupied (pinned / shown as a wreck) and this is a no-op.
  void clearSunkShip(ShipKind kind) {
    if (!isGhostBattle || lanBattleMode != LanBattleMode.ghost || !battling) {
      return;
    }
    final ship = boards[0].shipOfKind(kind);
    if (ship == null || !ship.isSunk || ship.sunkCleared) return;
    ship.sunkCleared = true;
    network.sendShipCleared(kind);
    revision++;
    stateSeq++;
    notifyListeners();
  }

  /// Resolves the currently held power-up. [cells] must have exactly
  /// [powerUpTapsNeeded] entries for a targeted card, or be empty for one
  /// that isn't. Returns false — changing nothing, keeping the card — if
  /// the card can't be used right now: a targeted heal/scramble that
  /// finds nothing eligible to act on, or a firing card whose shots
  /// would every one of them land on water already fired at (see
  /// [_fireShotBatch]).
  bool usePowerUp([List<(int, int)> cells = const []]) {
    final card = myPowerUp;
    if (card == null || !battling || !isPowerUpBattle || peerHasTurn) {
      return false;
    }
    final def = PowerUps.of(card);
    if (def.needsTarget && cells.length != powerUpTapsNeeded) return false;
    if (!def.needsTarget && cells.isNotEmpty) return false;

    switch (card) {
      case PowerUpCard.sonar:
        network.sendPowerUpAsk(card, r: cells[0].$1, c: cells[0].$2);
        break;
      case PowerUpCard.spotter:
        network.sendPowerUpAsk(card);
        break;
      case PowerUpCard.reconSweep:
        network.sendPowerUpAsk(card, r: cells[0].$1);
        break;
      case PowerUpCard.doubleTap:
        _doubleTapArmed = true;
        break;
      case PowerUpCard.repair:
        if (!_healOne(mostDamagedOnly: true)) {
          _log('🛠️ REPAIR — no damaged hull to fix.');
          return false;
        }
        break;
      case PowerUpCard.jam:
        network.sendPowerUpFlag(card);
        break;
      case PowerUpCard.spray:
        if (!_fireShotBatch([cells[0], cells[1]])) return false;
        break;
      case PowerUpCard.salvo:
        if (!_fireShotBatch(PowerUpShapes.salvo(cells[0].$1, cells[0].$2))) {
          return false;
        }
        break;
      case PowerUpCard.depthCharge:
        if (!_fireShotBatch(
            PowerUpShapes.depthCharge(cells[0].$1, cells[0].$2))) {
          return false;
        }
        break;
      case PowerUpCard.chainShot:
        _chainShotArmed = true;
        if (!_fireShotBatch([cells[0]])) {
          _chainShotArmed = false; // never fired, so nothing to chain off
          return false;
        }
        break;
      case PowerUpCard.hotShot:
        network.sendPowerUpFlag(card);
        break;
      case PowerUpCard.rapidFire:
        _rapidFireShotsLeft = 3;
        break;
      case PowerUpCard.scramble:
        if (!_scrambleOneShip()) {
          _log('🎲 SCRAMBLE — no undamaged hull free to move.');
          return false;
        }
        break;
      case PowerUpCard.counterBattery:
        _counterBatteryArmed = true;
        break;
      case PowerUpCard.barrage:
        final avoid = <(int, int)>{
          for (var r = 0; r < kBoardSize; r++)
            for (var c = 0; c < kBoardSize; c++)
              if (myShots[r][c] != 0) (r, c),
        };
        if (!_fireShotBatch(PowerUpShapes.barrage(_rng, avoid))) return false;
        break;
      case PowerUpCard.crossFire:
        if (!_fireShotBatch(
            PowerUpShapes.crossFire(cells[0].$1, cells[0].$2))) {
          return false;
        }
        break;
      case PowerUpCard.decoy:
        _decoyArmed = true;
        break;
      case PowerUpCard.patchCrew:
        if (!_healOne(mostDamagedOnly: false)) {
          _log('🩹 PATCH CREW — nothing damaged to patch.');
          return false;
        }
        break;
      case PowerUpCard.minefield:
        _myTraps.add({cells[0].$1 * kBoardSize + cells[0].$2});
        break;
      case PowerUpCard.trapLine:
        final shape = PowerUpShapes.salvo(cells[0].$1, cells[0].$2);
        _myTraps.add({for (final (r, c) in shape) r * kBoardSize + c});
        break;
    }

    network.sendPowerUpUsed(card);
    _log('🎴 You used ${def.name}.');
    myPowerUp = null;
    notifyListeners();
    return true;
  }

  /// Fires every cell in [cells] as one power-up action — all but the
  /// last are tagged [CombatEvent.hold] so a miss among them doesn't hand
  /// the turn over early; the last follows the ordinary hit-keeps-firing,
  /// miss-passes-the-turn rule. A cell already fired at is skipped for
  /// free: `fireAt` refuses those before anything reaches the wire, so
  /// there is no result to wait for and nothing to hold open for it.
  /// Returns whether anything actually reached the wire.
  ///
  /// BUGFIX (a shaped card spent on nothing at all): the shaped cards do
  /// not fire around the cell they were given — `PowerUpShapes._clamp`
  /// SLIDES a shape that would hang off the board back on, so CROSS FIRE
  /// aimed at the corner (0,0) really fires the plus centred on (1,1),
  /// which need not include the cell that was picked at all. With every
  /// cell of the slid shape already fired at, `fresh` came out empty,
  /// nothing was sent — and [usePowerUp] still reported success and
  /// consumed the card. Callers now use this to keep the card instead,
  /// which is also what stops `AiBrain` latching its awaiting-result
  /// flag onto a shot that was never taken.
  bool _fireShotBatch(List<(int, int)> cells) {
    final fresh = [
      for (final (r, c) in cells)
        if (myShots[r][c] == 0) (r, c),
    ];
    var fired = false;
    for (var i = 0; i < fresh.length; i++) {
      final result =
          fireAt(fresh[i].$1, fresh[i].$2, hold: i < fresh.length - 1);
      if (result != ShotResult.invalid &&
          result != ShotResult.cooldown &&
          result != ShotResult.duplicate) {
        fired = true;
      }
    }
    return fired;
  }

  /// REPAIR ([mostDamagedOnly]) / PATCH CREW (every damaged hull): undoes
  /// one hit on each eligible hull — damaged, but not sunk, since a sunk
  /// hull must never come back. Returns false, touching nothing, if there
  /// was nothing eligible.
  ///
  /// The board itself (`boards[1]` on the peer's device) genuinely needs
  /// no update: it never tracks a hull's damage cell by cell in the first
  /// place — see the `'result'` handler below, which only ever fills a
  /// ship's `hitIndices` all at once, the instant it is reported SUNK.
  ///
  /// BUGFIX (permanently unsinkable hull): but the PEER'S `myShots` mark
  /// for the healed cell is a completely separate piece of state, and it
  /// still says "confirmed hit" — which is exactly what stops `fireAt`'s
  /// duplicate guard from ever letting them re-target it. Heal the cell
  /// without telling them and that cell can never legally be fired at
  /// again by anyone: not the peer (their own client refuses the
  /// "duplicate"), and not this board's `_shots`, which still remembers
  /// it as fired too. A hull healed enough times could end up with no
  /// cell either side could ever complete it through — a permanent
  /// stand-off requiring a surrender to end. `sendPowerUpHeal` mirrors
  /// the healed cells over the wire (the peer already knows a hull sits
  /// there — they hit it — so this reveals nothing new) so both sides'
  /// bookkeeping agrees the cell is open again.
  bool _healOne({required bool mostDamagedOnly}) {
    final damaged =
        boards[0].ships.where((s) => s.hitIndices.isNotEmpty && !s.isSunk).toList();
    if (damaged.isEmpty) return false;
    final healedCells = <(int, int)>[];
    void healOneCellOf(PlacedShip s) {
      final idx = s.hitIndices.reduce(min);
      s.hitIndices.remove(idx);
      final cell = s.cells[idx];
      boards[0].unmarkShot(cell[0], cell[1]);
      healedCells.add((cell[0], cell[1]));
    }

    if (mostDamagedOnly) {
      damaged.sort((a, b) => b.hitIndices.length.compareTo(a.hitIndices.length));
      healOneCellOf(damaged.first);
    } else {
      for (final s in damaged) {
        healOneCellOf(s);
      }
    }
    network.sendPowerUpHeal(healedCells);
    revision++;
    stateSeq++;
    return true;
  }

  /// Safety net for a hull that has become permanently unreachable: every
  /// one of its remaining un-hit cells is already marked fired in
  /// `boards[0]`'s own `_shots`, so no future shot at any of them would
  /// even reach `receiveShot` — the peer's own `myShots` duplicate guard
  /// refuses to let them re-target a cell they already got a result for.
  ///
  /// The DECOY branch above only refuses to swallow a hit that would
  /// STRAND the hull AT THAT INSTANT — checked against the hull's state
  /// right then. It can't see into the future: DECOY swallowing one cell
  /// while a hull still has OTHER open cells is completely legitimate at
  /// the time, but if every one of those other cells is later hit
  /// normally (no DECOY involved), the earlier swallow becomes exactly
  /// the same dead end in hindsight. Called after every incoming shot in
  /// POWER PLAY (cheap — at most 5 ships, each checked once) rather than
  /// trying to predict this in advance, which would mean refusing DECOY
  /// far more often than the rare cases that actually end up stranded.
  ///
  /// Reopens exactly one phantom cell per stuck hull — same wire message
  /// REPAIR/PATCH CREW use for the identical purpose (see `_healOne`),
  /// since "the peer's `myShots` mark for this cell is stale, drop it"
  /// is exactly what's needed regardless of which card caused it.
  void _rescueStrandedHulls() {
    for (final ship in boards[0].ships) {
      if (ship.isSunk) continue;
      final openCells = <(int, int)>[];
      var allPhantom = true;
      for (var i = 0; i < ship.spec.size; i++) {
        if (ship.hitIndices.contains(i)) continue;
        final cell = ship.cells[i];
        if (!boards[0].alreadyShot(cell[0], cell[1])) {
          allPhantom = false;
          break;
        }
        openCells.add((cell[0], cell[1]));
      }
      if (allPhantom && openCells.isNotEmpty) {
        final cell = openCells.first;
        boards[0].unmarkShot(cell.$1, cell.$2);
        network.sendPowerUpHeal([cell]);
      }
    }
  }

  /// SCRAMBLE: jumps one random undamaged hull to a random legal spot.
  /// Mirrors the move exactly as MANOEUVRE's [relocateOwnShip] does —
  /// deliberately NOT going through that method itself, since it gates on
  /// [isManoeuvreBattle] and POWER PLAY is not a rearranging mode; only
  /// this card may move a ship in it. Returns false if no undamaged hull
  /// could find a legal spot within a bounded number of tries.
  bool _scrambleOneShip() {
    final undamaged = boards[0].ships.where((s) => s.hitIndices.isEmpty).toList();
    if (undamaged.isEmpty) return false;
    final ship = undamaged[_rng.nextInt(undamaged.length)];
    for (var attempt = 0; attempt < 200; attempt++) {
      final horizontal = _rng.nextBool();
      final row = _rng.nextInt(kBoardSize);
      final col = _rng.nextInt(kBoardSize);
      if (boards[0].canRelocateTo(ship, row, col, horizontal) &&
          boards[0].relocate(ship.spec.kind, row, col, horizontal)) {
        network.sendMove(ship.spec.kind, row, col, horizontal);
        revision++;
        stateSeq++;
        return true;
      }
    }
    return false;
  }

  String _coord(int r, int c) => '${String.fromCharCode(65 + r)}${c + 1}';

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

  /// Enemy shells currently in the air toward this device's own board,
  /// not yet scored — see [IncomingShell] and [_armIncomingShell]. Only
  /// ever non-empty in a mode a fleet can move in; every other mode
  /// resolves an incoming shot the instant it arrives and so never has
  /// one of these to show. `BattleScreen` reads it to fly the incoming
  /// cannonball, which in these modes is no longer something an already
  /// registered `CombatEvent` can announce.
  final List<IncomingShell> incomingShells = [];

  /// Battle log (oldest-first order via add/removeAt(0) for O(1) appends).
  final List<String> combatLog = [];
  int revision = 0;

  /// Like [revision], but MEANT to be compared across processes — carried
  /// in [buildResumeSnapshot] and restored by [restoreFromSnapshot], reset
  /// to 0 at the start of each match by [beginBattle]. `revision` itself
  /// can't serve this purpose: it restarts at 0 on every app relaunch
  /// (it's a plain in-memory field, never persisted), so two devices that
  /// have BOTH gone cold and come back with no live connection between
  /// them (see the both-restarted case `restoreFromOwnSnapshot` exists
  /// for) would each see "0" and have no way to tell whose copy of the
  /// match is actually more advanced. This does — same match, so the
  /// higher count really did see more shots/moves/heals since the match
  /// began.
  int stateSeq = 0;

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
    peerHasTurn = usesMatchProtocol &&
        lanBattleMode.hasTurns &&
        !network.isHost;
    if (usesMatchProtocol) network.beginMatch();
    revision++;
    stateSeq = 0; // a fresh match — see the doc on [stateSeq] itself
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
    _clearIncomingShells();
    combatLog.clear();
    _aiQueue.clear();
    _pendingFinishEvent = null;
    _pendingP1Win = false;
    _pendingReason = '';
    _fireSeq = 0;
    _lastPeerFireSeq = null;
    _lastPeerFireResult = null;
    _lastPeerFireSunkName = null;
    myPowerUp = null;
    spottedEnemyCells.clear();
    _jammed = false;
    _decoyArmed = false;
    _counterBatteryArmed = false;
    _bonusShots = 0;
    _hotShotArmedAgainstMe = false;
    _rapidFireShotsLeft = 0;
    _doubleTapArmed = false;
    _chainShotArmed = false;
    _myTraps.clear();

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
    // Whoever has the opening shot in POWER PLAY draws right away, rather
    // than waiting for a `_passTurn` that never happens for turn one.
    if (isPowerUpBattle && !peerHasTurn) onMyTurnStart();
    notifyListeners();
  }

  void _teardown() {
    _ticker?.cancel();
    _ticker = null;
    _netSub?.cancel();
    _netSub = null;
    _aiShotPending = false;
    _clearIncomingShells();
  }

  void attachNetwork() {
    _netSub?.cancel();
    _netSub = network.messages.listen(_onNetMessage);
  }

  /// [hold] is POWER PLAY only — see `CombatEvent.hold`. Callers outside
  /// [_fireShotBatch] should never need to pass it explicitly; an ordinary
  /// tap-to-fire still gets held for free when [_doubleTapArmed] or a
  /// queued [_bonusShots] applies, below.
  ShotResult fireAt(int r, int c, {bool hold = false}) {
    if (!battling) return ShotResult.invalid;

    if (mode == GameMode.vsAI && aiTurnToFire) {
      SoundService.instance.denied();
      return ShotResult.cooldown;
    }

    if (cooldown1 > 0) {
      SoundService.instance.denied();
      return ShotResult.cooldown;
    }

    // GHOST FLEET records nothing, so `myShots` never has anything in it
    // to catch here — this guard would otherwise silently refuse a tap
    // the player has no way to explain, since the grid gives them no
    // mark to recognise as "already tried". See `isGhostBattle`.
    if (myShots[r][c] != 0 && !isGhostBattle) {
      SoundService.instance.denied();
      return ShotResult.duplicate;
    }

    if (usesMatchProtocol) {
      // BUGFIX (double-fire): belt-and-braces alongside
      // `BattleScreen._shotOutstanding` — that latch closes the ~500ms
      // window between a miss's ball landing and the turn actually
      // passing (see its own doc), but it lives on the UI's `State` and
      // so wouldn't survive that screen being torn down and rebuilt
      // mid-match. `peerHasTurn` is the controller's own mirror of whose
      // turn it is (kept current by `BattleScreen._passTurn`), so this
      // is a second, UI-independent line of defense against the same
      // race. Scoped to `hasTurns` modes only — CHAOS/BLITZ have no turn
      // to protect and `peerHasTurn` is never meaningfully updated
      // there, and this must never block `_fireShotBatch`'s own calls
      // here, which only ever run during MY turn (`usePowerUp` already
      // refuses otherwise).
      if (lanBattleMode.hasTurns && peerHasTurn) {
        SoundService.instance.denied();
        return ShotResult.invalid;
      }
      // Cooldown is only for confirmed hits — starting it now and the
      // real result turns out to be a miss would leave the circle timer
      // spinning for nothing. The 'result' handler will start it if
      // needed once the true outcome is known.
      //
      // GHOST FLEET tags every fire with a rising sequence number —
      // see `_lastPeerFireSeq` for what it protects against, which only
      // matters in this one mode.
      //
      // POWER PLAY: DOUBLE TAP and a queued COUNTER BATTERY bonus both
      // hold THIS shot regardless of what the caller asked for, and are
      // spent the instant they do — each affects exactly the next shot
      // fired, never more.
      var effectiveHold = hold;
      if (isPowerUpBattle) {
        if (_doubleTapArmed) {
          effectiveHold = true;
          _doubleTapArmed = false;
        }
        if (_bonusShots > 0) {
          effectiveHold = true;
          _bonusShots--;
        }
      }
      network.sendFire(r, c,
          seq: isGhostBattle ? _fireSeq++ : null, hold: effectiveHold);
      notifyListeners();
      return ShotResult.hit;
    }

    // LOCAL PHANTOM: same relaxation GHOST FLEET/PHANTOM get over the
    // wire — see [isGhostBattle] and `Board.receiveShot`'s doc on
    // [allowRefire].
    final (result, sunk) =
        boards[1].receiveShot(r, c,
            allowRefire: isGhostBattle, repeatHitMisses: isPhantomBattle);
    // Only a hit/sunk puts the gun into reload; a miss leaves it
    // instantly ready so the circle timer never appears for a miss.
    if (result == ShotResult.hit || result == ShotResult.sunk) {
      cooldown1 = cooldownMax1;
    } else {
      cooldown1 = 0;
    }
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

    // LOCAL PHANTOM: mirrors `fireAt`'s own duplicate-cell relaxation —
    // see [isGhostBattle].
    if (p2Shots[r][c] != 0 && !isGhostBattle) {
      SoundService.instance.denied();
      return ShotResult.duplicate;
    }

    final (result, sunk) =
        boards[0].receiveShot(r, c,
            allowRefire: isGhostBattle, repeatHitMisses: isPhantomBattle);
    if (result == ShotResult.hit || result == ShotResult.sunk) {
      cooldown2 = cooldownMax2;
    } else {
      cooldown2 = 0;
    }
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
  /// taken a hit and this mode pins a damaged hull (see
  /// [damageIgnorableFor]), the destination overlaps another ship, or it
  /// covers a cell the enemy has already fired at. See
  /// [Board.canRelocateTo].
  ///
  /// A successful move is mirrored to the opponent immediately, because
  /// their copy of this fleet is what resolves their incoming shots; if
  /// the two drifted apart the same shot would hit on one device and miss
  /// on the other.
  bool relocateOwnShip(ShipKind kind, int row, int col, bool horizontal) {
    if (!battling || !isManoeuvreBattle) return false;
    final ship = boards[0].shipOfKind(kind);
    if (ship == null) return false;
    if (!boards[0].relocate(
      kind,
      row,
      col,
      horizontal,
      ignoreDamage: damageIgnorableFor(ship),
      ignoreShotHistory: isGhostBattle,
    )) {
      return false;
    }
    network.sendMove(kind, row, col, horizontal);
    revision++;
    stateSeq++;
    notifyListeners();
    return true;
  }

  /// Whether a ship on the player's own board is still free to move.
  bool canRelocate(PlacedShip ship) {
    if (!battling || !isManoeuvreBattle) return false;
    return boards[0]
        .canRelocate(ship, ignoreDamage: damageIgnorableFor(ship));
  }

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
        // Cross-process comparable — see the doc on [stateSeq].
        'stateSeq': stateSeq,
        // BUGFIX (GHOST FLEET redelivery guard broken after a cold
        // reconnect): `_fireSeq`/`_lastPeerFireSeq` are per-device
        // counters that used to reset to their defaults on a fresh
        // `GameController`, while THIS device's matching counters stayed
        // wherever they were — so the returner's very first shot after
        // reconnecting always looked like a stray redelivery of shot #0
        // to whoever they're playing (see the guard in the `'fire'` case
        // below) and got a stale cached result echoed back instead of
        // being resolved. Written here in exactly the shape
        // `restoreFromSnapshot` needs: "yourFireSeq" is what the
        // RECEIVER's own `_fireSeq` should become — one past the last
        // seq we ever accepted FROM them — and "yourLastPeerFireSeq" is
        // what their `_lastPeerFireSeq` should become — the last seq WE
        // ourselves sent.
        'yourFireSeq': _lastPeerFireSeq == null ? 0 : _lastPeerFireSeq! + 1,
        'yourLastPeerFireSeq': _fireSeq == 0 ? null : _fireSeq - 1,
        // BUGFIX (Power Play hand/armed-flags dropped on every
        // reconnect): meaningless to a PEER restoring from this snapshot
        // — none of this is visible to them even in principle, since
        // none of it is ever sent over the wire — so `restoreFromSnapshot`
        // deliberately never reads this block. It exists purely for
        // `restoreFromOwnSnapshot`: the one case where the same device
        // that built this snapshot is the one restoring from it, and so
        // genuinely does own every field in it.
        'pw': {
          'myPowerUp': myPowerUp?.index,
          'jammed': _jammed,
          'decoyArmed': _decoyArmed,
          'counterBatteryArmed': _counterBatteryArmed,
          'bonusShots': _bonusShots,
          'hotShotArmedAgainstMe': _hotShotArmedAgainstMe,
          'rapidFireShotsLeft': _rapidFireShotsLeft,
          'doubleTapArmed': _doubleTapArmed,
          'chainShotArmed': _chainShotArmed,
          'myTraps': _myTraps.map((t) => t.toList()).toList(),
          'spottedEnemyCells': spottedEnemyCells.toList(),
        },
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

    // BUGFIX (GHOST FLEET redelivery guard broken after a cold
    // reconnect) — see the doc on `buildResumeSnapshot`'s `yourFireSeq`/
    // `yourLastPeerFireSeq` fields for the exact failure this prevents.
    _fireSeq = (s['yourFireSeq'] as int?) ?? 0;
    _lastPeerFireSeq = s['yourLastPeerFireSeq'] as int?;
    _lastPeerFireResult = null;
    _lastPeerFireSunkName = null;

    // Power Play hand/armed-flags reset to a clean slate rather than
    // read from `s['pw']` — that block belongs to the SURVIVOR who built
    // this snapshot, not to us, and applying it would hand us their held
    // card. `restoreFromOwnSnapshot` is the one path allowed to read it,
    // because there — and only there — "the survivor" and "us" are the
    // same device. Losing a held card/armed effect on reconnect here is
    // a real, accepted downgrade (there is no way to do better without
    // the peer knowing something it fundamentally can't).
    myPowerUp = null;
    spottedEnemyCells.clear();
    _jammed = false;
    _decoyArmed = false;
    _counterBatteryArmed = false;
    _bonusShots = 0;
    _hotShotArmedAgainstMe = false;
    _rapidFireShotsLeft = 0;
    _doubleTapArmed = false;
    _chainShotArmed = false;
    _myTraps.clear();

    combatLog
      ..clear()
      ..addAll(((s['log'] as List?) ?? const []).map((e) => e.toString()));

    _seedEventsFromShots(shotsByMe: shotsByMe, shotsByThem: shotsByThem);

    revision++;
    // Adopted from the snapshot, not incremented — see the doc on
    // [stateSeq]: this device's own prior count means nothing once it is
    // about to become a mid-match copy of the SURVIVOR's state.
    stateSeq = (s['stateSeq'] as int?) ?? 0;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), _onTick);
    attachNetwork();
    _log('🔄 Reconnected — battle resumed!');
    notifyListeners();
  }

  /// Converts a snapshot from "what MY opponent needs to become" (what
  /// [buildResumeSnapshot] always produces) into "what I MYSELF need to
  /// become" — an involution: flipping twice returns the original. Lets
  /// a device that persisted its own [buildResumeSnapshot] output (there
  /// being no meaningful difference between "a snapshot for my opponent"
  /// and "a snapshot of my own state" beyond which perspective it's
  /// written from) rehydrate its OWN state from it — see
  /// [restoreFromOwnSnapshot].
  Map<String, dynamic> flipSnapshot(Map<String, dynamic> s) {
    final yourFireSeq = s['yourFireSeq'] as int?;
    final yourLastPeerFireSeq = s['yourLastPeerFireSeq'] as int?;
    return {
      ...s,
      'youAreHost': !(s['youAreHost'] as bool? ?? false),
      'yourBoard': s['myBoard'],
      'myBoard': s['yourBoard'],
      'shotsByYou': s['shotsByMe'],
      'shotsByMe': s['shotsByYou'],
      'yourTurn': !(s['yourTurn'] as bool? ?? false),
      // Same "+1 / -1" relationship `buildResumeSnapshot` itself uses,
      // just applied with the two fields swapped — see the worked
      // example in that method's doc if the arithmetic here looks
      // arbitrary in isolation.
      'yourFireSeq':
          yourLastPeerFireSeq == null ? 0 : yourLastPeerFireSeq + 1,
      'yourLastPeerFireSeq': (yourFireSeq == null || yourFireSeq == 0)
          ? null
          : yourFireSeq - 1,
    };
  }

  /// Rebuilds THIS device's own mid-match state from a snapshot it wrote
  /// about itself — the self-persistence path (`MatchStore`) uses when
  /// there is no live opponent left to ask for a fresh one, e.g. both
  /// sides restarted the app with no connection between them to recover
  /// over. [restoreFromSnapshot] alone gets the boards, shots and turn
  /// right (via [flipSnapshot]) but deliberately skips the Power Play
  /// block — here, unlike a snapshot arriving from a real peer, it's
  /// genuinely ours, so it's safe (and necessary) to restore it too.
  void restoreFromOwnSnapshot(Map<String, dynamic> s) {
    restoreFromSnapshot(flipSnapshot(s));
    final pw = s['pw'] as Map?;
    if (pw == null) return;
    final cardIdx = pw['myPowerUp'] as int?;
    myPowerUp = cardIdx == null ? null : PowerUpCard.values[cardIdx];
    _jammed = pw['jammed'] as bool? ?? false;
    _decoyArmed = pw['decoyArmed'] as bool? ?? false;
    _counterBatteryArmed = pw['counterBatteryArmed'] as bool? ?? false;
    _bonusShots = pw['bonusShots'] as int? ?? 0;
    _hotShotArmedAgainstMe = pw['hotShotArmedAgainstMe'] as bool? ?? false;
    _rapidFireShotsLeft = pw['rapidFireShotsLeft'] as int? ?? 0;
    _doubleTapArmed = pw['doubleTapArmed'] as bool? ?? false;
    _chainShotArmed = pw['chainShotArmed'] as bool? ?? false;
    _myTraps
      ..clear()
      ..addAll(((pw['myTraps'] as List?) ?? const [])
          .map((t) => Set<int>.from(t as List)));
    spottedEnemyCells
      ..clear()
      ..addAll(((pw['spottedEnemyCells'] as List?) ?? const [])
          .map((e) => e as int));
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
    bool hold = false,
    bool forcePass = false,
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
        hold: hold,
        forcePass: forcePass,
      ),
    );
    revision++;
    stateSeq++;

    final shooter =
        shooterIsP1 ? profile.playerName : _opponentName();
    final coord =
        '${String.fromCharCode(65 + r)}${c + 1}';

    // GHOST FLEET: the combat log is a written record of exactly the
    // thing the grid refuses to mark, so a coordinate has no business
    // showing up here either — the whole point is that neither captain
    // gets to keep a reliable list of what they have already tried. A
    // sinking still gets its own line, because it is not new positional
    // information: both players already SAW that hull go down (see the
    // doc on `LanBattleMode.ghost`), so naming it without the coordinate
    // is narration, not a leak.
    if (!isGhostBattle) {
      if (result == ShotResult.sunk) {
        _log('💥 $shooter SANK the ${sunk!.spec.name} at $coord!');
      } else if (result == ShotResult.hit) {
        _log('🔥 $shooter scored a HIT at $coord');
      } else {
        _log('🌊 $shooter missed at $coord');
      }
    } else if (result == ShotResult.sunk) {
      _log('💥 $shooter SANK the ${sunk!.spec.name}!');
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

    if (usesMatchProtocol) {
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
    // Whatever was still in the air is moot — the match is decided.
    _clearIncomingShells();
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
    // `headless` (the AI's own hidden controller in a vsAiLan match) is
    // excluded too — see its doc.
    if (!rpAwarded && !matchAbandoned && !noRpLocal && !headless) {
      rpAwarded = true;
      rpDelta = profile.recordResult(won: p1Win);
    }

    if (p1Win) {
      if (!headless) SoundService.instance.victory();
      _log('🏆 VICTORY! $reason');
    } else {
      if (!headless) SoundService.instance.defeat();
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

    // RELOAD COMPLETE — the moment a gun finishes its cooldown, play that
    // seat's equipped cannon's own reload sound. This is the reload cue
    // for actual gameplay: a hit grants an immediate extra shot and BLITZ /
    // chaos guns reload on their own clock with no turn handoff, so until
    // this existed the only "reload" sound ever heard was the one
    // `_passTurn` plays at a turn change — the reload itself finished
    // silently. Fires on the same `beforeReady` edge the structural
    // rebuild below already uses, so it happens exactly once per reload
    // and always on the tick the ring visibly completes.
    //
    // BUGFIX (the reload sound playing TWICE on every shot — hit or miss —
    // in BLITZ/CHAOS over AI and LAN/online play): two compounding echoes.
    //
    // 1. The hidden vsAiLan opponent is its own GameController in THIS
    //    process (`headless = true`), running its own ticker — so its
    //    `_onTick` played the same reload completions the player's
    //    controller was already playing, doubling every one of them.
    //    `headless` exists precisely to keep that controller silent (see
    //    `_finish`'s victory/defeat gating), so the cue is gated on it.
    // 2. Over the match protocol, `cooldown2` is only a MIRROR of the
    //    peer's gun — the peer's own device plays that reload. Playing it
    //    here too put every reload on both devices, heard back-to-back
    //    the moment both guns reloaded (constant in BLITZ/CHAOS, where a
    //    miss now reloads exactly like a hit). Seat 2 therefore only
    //    sounds when it is a REAL local gun — pass-and-play's second
    //    seat, or the classic on-device AI — never a protocol mirror.
    if (!headless) {
      if (!beforeReady1 && cooldown1 <= 0) {
        SoundService.instance.cannonReady(cannonSkinId: _cannonSkinIdFor(true));
      }
      if (!usesMatchProtocol && !beforeReady2 && cooldown2 <= 0) {
        SoundService.instance.cannonReady(cannonSkinId: _cannonSkinIdFor(false));
      }
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

  /// Which cannon skin a seat has equipped — the same gear rule
  /// `_loadoutFor` applies on the battle screen, kept in step with it so a
  /// reload sound and the gun it belongs to can never disagree:
  ///
  ///  * Match-protocol modes (LAN, and the loopback-linked VS AI) — this
  ///    device's captain on seat 1, the handshake's peer gear on seat 2.
  ///    The AI never sends gear, so its peer id stays the default 'mk1',
  ///    exactly like the plain gun its half is drawn with.
  ///  * Local pass-and-play — one equipped cannon per seat.
  ///  * Anything else — the profile's own gun; seat 2 has no gear of its
  ///    own and sails the standard cannon.
  String _cannonSkinIdFor(bool p1) {
    if (usesMatchProtocol) {
      return p1 ? profile.cannonSkinId : network.peerCannonSkinId;
    }
    if (mode == GameMode.local) {
      return localLoadouts[p1 ? 0 : 1].cannonSkinId;
    }
    return p1 ? profile.cannonSkinId : 'mk1';
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
        // Only hits keep the gun in reload; misses leave the circle timer
        // hidden so it matches the removed recoil animation.
        if (result == ShotResult.hit || result == ShotResult.sunk) {
          cooldown2 = cooldownMax2;
        } else {
          cooldown2 = 0;
        }
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

  /// Arms a shell aimed at this device's own water and lets it fly
  /// before deciding what it hit — the whole point of the modes a fleet
  /// can still run in.
  ///
  /// Every other mode resolves an incoming `'fire'` the instant the
  /// message lands, which is what made the advertised dodge a lie: the
  /// shell was already scored against wherever the hull sat when the
  /// message arrived, so a player watching it arc in and dragging the
  /// hull clear still took the hit, on empty water, every time.
  /// [kShellFlight] later, [_resolveIncomingFire] scores it against the
  /// board as it stands THEN — move in time and the shell lands on the
  /// water the hull just left.
  ///
  /// The window runs concurrently with the shooter's own flight
  /// animation rather than after it (both start from the same
  /// `sendFire`), so the result still reaches them as their shell
  /// lands and nothing about the attacking end feels any slower.
  void _armIncomingShell({
    required int r,
    required int c,
    required bool hold,
    int? seq,
  }) {
    // GHOST FLEET tags each fire with a rising seq, but this device
    // does not commit that seq until the shell actually lands — so a
    // redelivery arriving mid-flight slips past the guard in the
    // 'fire' case above and would otherwise arm a second shell for the
    // same shot.
    if (seq != null && incomingShells.any((s) => s.seq == seq)) return;
    // Nothing to dodge with outside a running battle, and no ticker to
    // land the shell either — score it where it stands, exactly as every
    // non-manoeuvring mode does.
    if (!battling) {
      _resolveIncomingFire(r: r, c: c, hold: hold, seq: seq);
      return;
    }
    final shell = IncomingShell(row: r, col: c, hold: hold, seq: seq);
    incomingShells.add(shell);
    shell.timer = Timer(kShellFlight, () {
      if (!incomingShells.remove(shell)) return;
      if (!battling) return;
      _resolveIncomingFire(r: r, c: c, hold: hold, seq: seq);
    });
    // Wakes the defender's screen so it can start the incoming shell's
    // flight now, instead of at the impact that no longer coincides
    // with it — see `BattleScreen._onUpdate`.
    revision++;
    notifyListeners();
  }

  /// Lands every shell currently in the air, now, instead of waiting out
  /// its real [kShellFlight] timer.
  ///
  /// Tests only. It exists so a test can drive the DODGE WINDOW itself —
  /// hand the board a `'fire'`, move a hull (or don't), then land the
  /// shell — rather than having the deferral bypassed for them, which
  /// would leave the very behaviour under test unexercised.
  @visibleForTesting
  void landIncomingShellsForTest() {
    final pending = incomingShells.toList();
    incomingShells.clear();
    for (final shell in pending) {
      shell.timer?.cancel();
      if (!battling) continue;
      _resolveIncomingFire(
        r: shell.row,
        c: shell.col,
        hold: shell.hold,
        seq: shell.seq,
      );
    }
  }

  /// Cancels every shell still in the air. A pending shell owns a live
  /// timer holding a closure over this controller, so anything that ends
  /// or replaces the match has to drop them.
  void _clearIncomingShells() {
    for (final shell in incomingShells) {
      shell.timer?.cancel();
    }
    incomingShells.clear();
  }

  /// Scores one incoming shot against this device's own board and
  /// answers the shooter. Called straight from the `'fire'` handler in
  /// every mode whose fleet stays put, and [kShellFlight] later — from
  /// [_armIncomingShell] — in the ones it can run in.
  void _resolveIncomingFire({
    required int r,
    required int c,
    required bool hold,
    int? seq,
  }) {
    ShotResult result;
    PlacedShip? sunk;

    // DECOY: swallowed before it ever touches the board — no damage,
    // reported as a miss, but the cell still counts as fired so the
    // ordinary duplicate rule still applies to a later repeat of it.
    //
    // BUGFIX (permanently unsinkable hull): reporting a miss marks the
    // cell fired on BOTH sides — this board's `_shots` here, and the
    // shooter's own `myShots` the instant this result reaches them
    // (see `_registerShot`) — and no mode this card exists in ever
    // allows a cell to be re-targeted once fired at. If every OTHER
    // still-un-hit cell of this hull has ALREADY been fired at (most
    // often: this is its one remaining cell outright, but a hull hit
    // by TWO separate decoys over the course of a match — each fine
    // on its own — reaches exactly the same dead end), swallowing
    // this one too would leave the hull with no cell any future shot
    // could legally land on: permanently un-sinkable for the rest of
    // the match, since no player action can undo a `myShots` mark.
    // Decoy still consumes itself against the shot that found it —
    // "the next hit finds you anyway" is the intended cost of running
    // out of hull to hide behind — it just no longer blocks the one
    // shot that was this hull's actual last chance.
    final decoyTarget = boards[0].shipAt(r, c);
    bool decoyWouldStrandHull() {
      if (decoyTarget == null) return false;
      final thisIdx = decoyTarget.cellIndexAt(r, c);
      for (var i = 0; i < decoyTarget.spec.size; i++) {
        if (i == thisIdx || decoyTarget.hitIndices.contains(i)) continue;
        final cell = decoyTarget.cells[i];
        if (!boards[0].alreadyShot(cell[0], cell[1])) {
          return false; // another cell is still legally reachable
        }
      }
      return true;
    }

    if (isPowerUpBattle &&
        _decoyArmed &&
        decoyTarget != null &&
        !decoyWouldStrandHull()) {
      _decoyArmed = false;
      boards[0].markShot(r, c);
      result = ShotResult.miss;
      sunk = null;
    } else {
      if (isPowerUpBattle && _decoyArmed && decoyTarget != null) {
        _decoyArmed = false; // fizzled against the finishing blow
      }
      (result, sunk) =
          boards[0].receiveShot(r, c,
            allowRefire: isGhostBattle, repeatHitMisses: isPhantomBattle);
    }

    // BUGFIX (duplicate-fire turn corruption): a stray repeat of a
    // 'fire' this board already answered — most often
    // `RelayLink._flush` resending a line whose first delivery
    // actually landed but whose ack got lost to a timeout (the relay
    // has no dedup; a resend after a lost ack is a real second INSERT
    // — see `RelayLink`), occasionally a leftover from the same tap
    // race `_fireAtCell` guards against on the sender's side.
    // `Board.receiveShot` already refuses to hit the same cell twice,
    // but without this check the rest of this case would still run
    // for it: `_registerShot` would count the incoming shot a SECOND
    // time, and because `.duplicate` isn't `.miss`, `_maybePassTurn`
    // would read it as a hit and hand the attacker a bogus extra
    // turn — which is exactly the "multiple fire rounds" this fixes.
    // The real result for this cell already went out the first time
    // it was seen, so just echo it again and stop.
    //
    // Not reachable in GHOST FLEET (`allowRefire` above means
    // `receiveShot` never returns `.duplicate` there) — which is
    // exactly why that mode needs the separate seq-based guard above
    // instead of being able to reuse this one.
    if (result == ShotResult.duplicate) {
      network.sendResult(r, c, result);
      return;
    }

    if (isGhostBattle) {
      _lastPeerFireSeq = seq;
      _lastPeerFireResult = result;
      _lastPeerFireSunkName = sunk?.spec.name;
    }

    var forcePass = false;
    int? hotR, hotC;
    if (isPowerUpBattle) {
      final hit = result == ShotResult.hit || result == ShotResult.sunk;

      // MINEFIELD / TRAP LINE: triggers on the CELL regardless of
      // hit or miss — a mine is water rigged to cost a turn, not
      // damage. Consumes the whole trap it belongs to.
      final key = r * kBoardSize + c;
      final trapIdx = _myTraps.indexWhere((t) => t.contains(key));
      if (trapIdx != -1) {
        _myTraps.removeAt(trapIdx);
        forcePass = true;
      }

      // HOT SHOT: one extra, nearest unhit cell of the SAME hull —
      // may itself complete the sinking, in which case the PRIMARY
      // cell's result is upgraded to sunk; the bonus cell is always
      // registered as a plain hit below, so only one SANK line ever
      // gets logged for it.
      if (hit && _hotShotArmedAgainstMe) {
        final ship = boards[0].shipAt(r, c)!;
        final open = [
          for (var i = 0; i < ship.spec.size; i++) i,
        ].where((i) => !ship.hitIndices.contains(i)).toList();
        _hotShotArmedAgainstMe = false;
        if (open.isNotEmpty) {
          final baseIdx = ship.cellIndexAt(r, c)!;
          open.sort(
              (a, b) => (a - baseIdx).abs().compareTo((b - baseIdx).abs()));
          final extraIdx = open.first;
          ship.hitIndices.add(extraIdx);
          final cell = ship.cells[extraIdx];
          hotR = cell[0];
          hotC = cell[1];
          if (ship.isSunk) {
            result = ShotResult.sunk;
            sunk = ship;
          }
        }
      }

      // COUNTER BATTERY: "next turn", not "immediately" — queues a
      // bonus shot rather than firing one now.
      if (hit && _counterBatteryArmed) {
        _counterBatteryArmed = false;
        _bonusShots++;
        _log('⚡ Counter Battery primed — extra shot next turn.');
      }
    }

    // Mirror the peer's reload on their on-screen cannon only for
    // hits — misses leave the gun instantly ready so the circle timer
    // never spins for a miss (matches the removed recoil animation).
    //
    // CHAOS and BLITZ are the exception: with no turns, the cooldown is
    // the ONLY thing pacing the peer's fire, so a miss reloads their gun
    // exactly like a hit does — the reload ring (and its reload-complete
    // sound, see `_onTick`) has to run on a miss too. Turn-based modes
    // keep the instantly-ready miss: the turn passes anyway, and a ring
    // would just spin for nothing while the opponent aims.
    if (result == ShotResult.hit || result == ShotResult.sunk) {
      cooldown2 = cooldownMax2;
    } else if (isChaosBattle) {
      cooldown2 = cooldownMax2;
    } else {
      cooldown2 = 0;
    }

    network.sendResult(
      r,
      c,
      result,
      sunkShip: sunk?.spec.name,
      hold: hold,
      forcePass: forcePass,
      hotR: hotR,
      hotC: hotC,
    );

    _registerShot(
      shooterIsP1: false,
      r: r,
      c: c,
      result: result,
      sunk: sunk,
      hold: hold,
      forcePass: forcePass,
    );
    if (hotR != null) {
      _registerShot(
        shooterIsP1: false,
        r: hotR,
        c: hotC!,
        result: ShotResult.hit,
      );
    }
    if (isPowerUpBattle) _rescueStrandedHulls();
  }

  void _onNetMessage(Map<String, dynamic> msg) {
    switch (msg['type']) {
      case 'fire':
        final r = msg['r'] as int;
        final c = msg['c'] as int;
        // POWER PLAY: see `CombatEvent.hold` — echoed straight back on
        // our `result` below so the shooter's own device agrees.
        final hold = msg['hold'] == true;

        // GHOST FLEET's own redelivery guard — see the doc on
        // `_lastPeerFireSeq`. A redelivered copy of the fire we already
        // answered carries the SAME seq again; re-send the result we
        // already computed rather than asking `receiveShot` to evaluate
        // the cell a second time, which in this one mode could
        // legitimately come back different (a ship may have moved in).
        final seq = msg['seq'] as int?;
        if (isGhostBattle &&
            seq != null &&
            _lastPeerFireSeq != null &&
            seq <= _lastPeerFireSeq!) {
          network.sendResult(
            r,
            c,
            _lastPeerFireResult ?? ShotResult.miss,
            sunkShip: _lastPeerFireSunkName,
          );
          break;
        }

        // MANOEUVRE / BLITZ / GHOST FLEET: this shell gets to finish its
        // arc before anyone decides what it hit, so a hull dragged clear
        // in time genuinely dodges it. See [_armIncomingShell].
        if (isManoeuvreBattle) {
          _armIncomingShell(r: r, c: c, hold: hold, seq: seq);
          break;
        }
        _resolveIncomingFire(r: r, c: c, hold: hold, seq: seq);
        break;

      case 'result':
        final r = msg['r'] as int;
        final c = msg['c'] as int;
        final result =
            ShotResult.values[msg['res'] as int];
        final hold = msg['hold'] == true;
        final forcePass = msg['fp'] == true;

        // The echo for a stray repeat of one of OUR OWN 'fire' messages
        // (see the matching guard in the 'fire' case above) — the real
        // result for this cell already arrived and was applied the first
        // time it came back. Ignore this one: registering it again would
        // stomp `myShots[r][c]`'s already-correct value and, since
        // `.duplicate` isn't `.miss`, be read as a hit that keeps our
        // turn we never actually earned.
        if (result == ShotResult.duplicate) break;

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

        // Apply reload only on hits; misses clear the circle timer.
        // RAPID FIRE spends down its three boosted shots here, in the
        // order results actually land — safe because POWER PLAY only
        // ever has one shot outstanding at a time.
        //
        // CHAOS/BLITZ: a miss reloads too — with no turns the cooldown
        // is the only fire-rate limiter, and the gun's reload ring (and
        // its reload-complete sound) must run after every shot. See the
        // matching rule in `_resolveIncomingFire`.
        if (result == ShotResult.hit || result == ShotResult.sunk) {
          if (isPowerUpBattle && _rapidFireShotsLeft > 0) {
            cooldown1 = cooldownMax1 / 2;
            _rapidFireShotsLeft--;
          } else {
            cooldown1 = cooldownMax1;
          }
        } else if (isChaosBattle) {
          cooldown1 = cooldownMax1;
        } else {
          cooldown1 = 0;
        }
        _registerShot(
          shooterIsP1: true,
          r: r,
          c: c,
          result: result,
          sunk: sunk,
          hold: hold,
          forcePass: forcePass,
        );

        final hotR = msg['hotR'] as int?;
        final hotC = msg['hotC'] as int?;
        if (hotR != null && hotC != null) {
          _registerShot(
            shooterIsP1: true,
            r: hotR,
            c: hotC,
            result: ShotResult.hit,
          );
        }

        // CHAIN SHOT: one bonus shot at a random unfired cell adjacent to
        // the one just fired, only when it landed. Cleared unconditionally
        // right away so it can never linger onto a later, unrelated shot.
        if (isPowerUpBattle && _chainShotArmed) {
          _chainShotArmed = false;
          if (result == ShotResult.hit || result == ShotResult.sunk) {
            final neighbors = [(r - 1, c), (r + 1, c), (r, c - 1), (r, c + 1)]
                .where((p) =>
                    p.$1 >= 0 &&
                    p.$1 < kBoardSize &&
                    p.$2 >= 0 &&
                    p.$2 < kBoardSize)
                .where((p) => myShots[p.$1][p.$2] == 0)
                .toList();
            if (neighbors.isNotEmpty) {
              final pick = neighbors[_rng.nextInt(neighbors.length)];
              // The reload cooldown for the shot that just landed (above,
              // hit/sunk always starts one) would otherwise block this
              // bonus shot outright — CHAIN SHOT's whole point is that it
              // fires WITHOUT waiting on that. `fireAt` overwrites
              // `cooldown1` again from the bonus shot's own eventual
              // result, so this doesn't skip reload entirely — it only
              // waives the one cooldown this bonus shot would otherwise
              // have been blocked by.
              cooldown1 = 0;
              fireAt(pick.$1, pick.$2);
            }
          }
        }
        break;

      case 'pw_ask':
        _handlePowerUpAsk(msg);
        break;

      case 'pw_answer':
        _handlePowerUpAnswer(msg);
        break;

      case 'pw_flag':
        final card = PowerUpCard.values[msg['card'] as int];
        if (card == PowerUpCard.jam) _jammed = true;
        if (card == PowerUpCard.hotShot) _hotShotArmedAgainstMe = true;
        break;

      case 'pw_used':
        final card = PowerUpCard.values[msg['card'] as int];
        _log('🎴 ${network.peerName} used ${PowerUps.of(card).name}!');
        notifyListeners();
        break;

      case 'pw_heal':
        // See `GameController._healOne`'s doc: the peer just undid one of
        // OUR confirmed hits on their hull, so our own record of it has
        // to let go too, or that cell can never legally be fired at
        // again by either side.
        for (final cell in (msg['cells'] as List? ?? const [])) {
          final pair = cell as List;
          final r = pair[0] as int;
          final c = pair[1] as int;
          if (r >= 0 && r < kBoardSize && c >= 0 && c < kBoardSize) {
            myShots[r][c] = 0;
          }
        }
        notifyListeners();
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
          stateSeq++;
          notifyListeners();
        }
        break;

      case 'ship_cleared':
        // GHOST FLEET: the opponent's destroyed hull has sunk and faded
        // out, freeing its watermark on their own board. Mirror the flag
        // onto our copy of THEIR fleet (see `fightFor`), so a fresh shot
        // at those cells is a miss and — for our later relocation rules —
        // their watermark no longer blocks anything relevant to us.
        {
          final k = ShipKind.values[msg['k'] as int];
          final sc = boards[1].shipOfKind(k);
          if (sc != null) {
            sc.sunkCleared = true;
            revision++;
            stateSeq++;
            notifyListeners();
          }
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

  /// POWER PLAY — SONAR / SPOTTER / RECON SWEEP: the peer is asking about
  /// THIS board, since only we have it to check.
  void _handlePowerUpAsk(Map<String, dynamic> msg) {
    final card = PowerUpCard.values[msg['card'] as int];
    switch (card) {
      case PowerUpCard.sonar:
        final r = msg['r'] as int;
        final c = msg['c'] as int;
        final seen = <ShipKind>{};
        for (var dr = -1; dr <= 1; dr++) {
          for (var dc = -1; dc <= 1; dc++) {
            final rr = r + dr, cc = c + dc;
            if (rr < 0 || rr >= kBoardSize || cc < 0 || cc >= kBoardSize) {
              continue;
            }
            final s = boards[0].shipAt(rr, cc);
            if (s != null) seen.add(s.spec.kind);
          }
        }
        network.sendPowerUpAnswer(card, n: seen.length);
        break;
      case PowerUpCard.spotter:
        final candidates = <(int, int)>[
          for (final s in boards[0].ships)
            for (final cell in s.cells) (cell[0], cell[1]),
        ];
        if (candidates.isNotEmpty) {
          final pick = candidates[_rng.nextInt(candidates.length)];
          network.sendPowerUpAnswer(card, r: pick.$1, c: pick.$2);
        }
        break;
      case PowerUpCard.reconSweep:
        final r = msg['r'] as int;
        final has = boards[0].ships.any((s) => s.cells.any((cell) => cell[0] == r));
        network.sendPowerUpAnswer(card, r: r, has: has);
        break;
      default:
        break;
    }
  }

  /// POWER PLAY — the answer to our own [_handlePowerUpAsk]-triggering
  /// use: information about the ENEMY board, purely for display/log.
  void _handlePowerUpAnswer(Map<String, dynamic> msg) {
    final card = PowerUpCard.values[msg['card'] as int];
    switch (card) {
      case PowerUpCard.sonar:
        _log('📡 SONAR: ${msg['n']} ship(s) in that area.');
        break;
      case PowerUpCard.spotter:
        final r = msg['r'] as int?, c = msg['c'] as int?;
        if (r != null && c != null) {
          spottedEnemyCells.add(r * kBoardSize + c);
          _log('👁️ SPOTTER found a hull at ${_coord(r, c)}.');
        }
        break;
      case PowerUpCard.reconSweep:
        final r = msg['r'] as int;
        final has = msg['has'] as bool;
        _log(
            '🔍 RECON: row ${String.fromCharCode(65 + r)} ${has ? "holds a ship" : "is empty"}.');
        break;
      default:
        break;
    }
    notifyListeners();
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
