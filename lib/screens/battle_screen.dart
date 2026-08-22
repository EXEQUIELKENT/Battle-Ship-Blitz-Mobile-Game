import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../art/family_shell_art.dart';
import '../art/fleet_family.dart';
import '../art/legacy_shell_art.dart';
import '../core/fleet_identity.dart';
import '../core/theme.dart';
import '../models/game_models.dart';
import '../services/game_controller.dart';
import '../services/network_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../widgets/battle_grid.dart';
import '../widgets/cannon_widget.dart';
import '../widgets/cartoon_confirm.dart';
import '../widgets/match_chat.dart';
import '../widgets/neon_widgets.dart';
import '../widgets/ship_painter.dart';
import 'result_screen.dart';

/// Battle arena — 1:1 copy of the reference gameplay video:
///  • BOTH player halves are on screen at once and NEVER swap sides:
///    P1's half is always at the bottom (upright), P2's half is always on
///    top rotated 180° (so they face each other across the table).
///  • Each half shows that player's OWN grid + their OWN cannon
///    (red ring = P1, blue ring = P2). You tap the OTHER player's grid to
///    fire at it (it lives on the opposite half).
///  • Middle band: two ship-status rows (top solid / bottom faded),
///    EXIT pill on the edge and the white dots badge.
///  • Battle starts with a giant translucent 3-2-1 countdown mirrored on
///    both halves, then play begins on GO.
///  • Battle grids are EMPTY (ships hidden) — you guess where the enemy
///    fleet is. A HIT lets you fire again; only a MISS passes the turn.
///  • Firing is a SINGLE TAP: tap any untried cell on the opponent's grid
///    to fire at it immediately. During a player's turn their cannon
///    slides to the middle of THEIR grid as a "ready to fire" indicator
///    and reacts (recoil + muzzle flash) on every shot, but the cannon
///    itself isn't a separate tap target — the grid tap is what fires.
///    When the turn passes, the outgoing cannon slides back home near the
///    middle band and the newly-active cannon slides out while flashing
///    "ready".
class BattleScreen extends StatefulWidget {
  const BattleScreen({super.key});

  @override
  State<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends State<BattleScreen>
    with TickerProviderStateMixin {
  /// The theme for chrome that isn't tied to one half (the middle band).
  /// Always this device's own — the band belongs to the player holding
  /// the phone, not to either fleet.
  GameplayTheme get gameplayTheme => context.read<ProfileStore>().gameplayTheme;

  final _cannon1Fire = StreamController<void>.broadcast();
  final _cannon2Fire = StreamController<void>.broadcast();
  final _cannon1Ready = StreamController<void>.broadcast();
  final _cannon2Ready = StreamController<void>.broadcast();

  /// Whose turn it is, in every mode that HAS turns. The bottom half's
  /// owner is the "P1" side and the top half's owner is the "P2" side —
  /// the halves never swap sides, only this flag changes.
  ///
  /// In a LAN match the bottom half is always THIS device's own fleet, so
  /// `_p2Active == false` reads as "my turn" here and as "their turn" on
  /// the opponent's device. Both ends derive it independently from the
  /// same shot outcomes (see `_maybePassTurn`), which is what keeps them
  /// agreeing without a dedicated turn message.
  bool _p2Active = false;

  bool _navigatedToResult = false;

  // ----- Match shape (snapshotted once — none of it changes mid-battle) --

  /// Hotspot/online: exactly ONE human per device, with the opponent on
  /// the other end of a socket. This is the distinction that drives the
  /// perspective fix below — several behaviors that make sense with two
  /// players sharing one screen are actively wrong with two screens.
  late final bool _lan;

  /// LAN chaos rules: no turn order at all, both fleets firing at once,
  /// both cannons parked at the back of their own grid all match.
  late final bool _chaos;

  /// A turn order exists and this screen owns handing it over.
  late final bool _turnTracked;

  /// Whether the TOP half is drawn rotated 180°.
  ///
  /// BUGFIX (LAN perspective): that rotation exists so two players seated
  /// across from ONE device each read their own grid right-side-up — it's
  /// a shared-screen affordance. LAN inherited it wholesale, which meant
  /// the enemy grid you were shooting at appeared upside down: its rows
  /// ran bottom-to-top and its columns right-to-left relative to yours, so
  /// the two devices disagreed visually about where any given cell was
  /// even though the underlying coordinates matched. With one player per
  /// screen there is nobody sitting opposite, so LAN draws both halves
  /// upright and the top half's grid+cannon are simply laid out mirrored
  /// WITHIN the half instead (grid against the middle band, cannon out at
  /// the screen edge) — see `flipLayout` in `_buildHalf`.
  late final bool _mirrorTopHalf;

  /// LAN MANOEUVRE rules: undamaged ships can be repositioned mid-battle.
  late final bool _manoeuvre;

  /// True when this device commands the BLUE fleet — i.e. it joined a LAN
  /// match rather than hosting it. The host always commands red.
  late final bool _iAmBlue;

  // ----- MANOEUVRE mode: live drag preview on your own grid -----
  PlacedShip? _movePreview;
  bool _movePreviewValid = true;

  // ----- Countdown -----
  bool _countingDown = false;
  int _countdownValue = 3;
  bool _countdownGo = false;

  // ----- Cannonball flight + impact -----
  //
  // ONE SLOT PER SHOOTER, rather than one for the whole screen. There
  // used to be a single projectile, so whenever a second shot went up
  // while one was already airborne the newcomer got no flight animation
  // at all — its marker just popped onto the board. That was tolerable
  // while every mode took turns (shots could only overlap in rare
  // network-timing edge cases), but LAN chaos mode makes overlapping the
  // NORMAL case: both fleets fire the moment their own gun reloads, so
  // balls cross in mid-air constantly. Each side now owns its own slot
  // and both balls fly properly at the same time.
  // BUGFIX (shots looked like they teleported instead of arcing over):
  // 430ms was fast enough that a shell crossed the whole board arc —
  // launch, rise, fall, impact — in under half a second, too quick to
  // read as a lobbed projectile rather than a snap-to-target effect.
  // Nothing else times off this exact value (the animation's completion
  // LISTENER is what actually drives impact resolution/turn-passing, not
  // a magic duration — see the `addStatusListener` below), so it's safe
  // to simply slow it down; the accuracy/targeting math is untouched.
  static const Duration _projDuration = Duration(milliseconds: 750);
  late final _Projectile _projP1; // fired by the bottom half's owner
  late final _Projectile _projP2; // fired by the top half's owner

  /// Screen-space geometry of each half, refreshed every layout pass.
  final Map<bool, _HalfGeom> _geom = {}; // key: isTopHalf

  // ----- Cannon slide (active player's cannon moves to its grid center) ---
  late final AnimationController _slideCtrl;

  // ----- Screen shake (impact feedback) -----
  // A short, decaying wobble applied to the ENTIRE battle Stack whenever a
  // cannonball actually lands on a ship (hit or sunk — never on a miss).
  // Triggered from `_resolveImpact()`, i.e. the same moment the ball's
  // flight animation completes and the hit/miss marker appears, so the
  // shake is synced to what the player sees land, not to when the shot
  // was fired. `_shakeMagnitude` is set per-trigger so a sunk ship (kills
  // the whole ship) shakes noticeably harder than a plain hit.
  late final AnimationController _shakeCtrl;
  double _shakeMagnitude = 6;
  static const _shakeHitMagnitude = 6.0;
  static const _shakeSunkMagnitude = 12.0;
  static const _shakeCycles = 3.5;

  /// Decaying sine wobble: full magnitude at t=0, settles back to exactly
  /// zero at t=1 so the board never ends up visibly offset once the shake
  /// finishes.
  Offset _shakeOffset(double t) {
    if (t <= 0 || t >= 1) return Offset.zero;
    final decay = 1 - t;
    final angle = t * _shakeCycles * 2 * math.pi;
    final dx = math.sin(angle) * _shakeMagnitude * decay;
    final dy = math.cos(angle * 1.3) * _shakeMagnitude * 0.5 * decay;
    return Offset(dx, dy);
  }

  void _shake(double magnitude) {
    _shakeMagnitude = magnitude;
    _shakeCtrl.forward(from: 0);
  }

  /// Plays the sound (and matching haptic) for a shot's outcome, right as
  /// that shot's cannonball actually lands — see the call sites in
  /// `_resolveImpact`, `_launchOpponentBall`, and `_onUpdate`. Kept as one
  /// shared helper so every "impact just happened" call site (including
  /// the couple of edge cases with no travel animation to wait for) picks
  /// the sound the exact same way.
  void _playImpactSound(ShotResult result) {
    switch (result) {
      case ShotResult.sunk:
        SoundService.instance.sunk();
        break;
      case ShotResult.hit:
        SoundService.instance.hit();
        break;
      case ShotResult.miss:
        SoundService.instance.miss();
        break;
      default:
        break;
    }
  }

  // ----- PERF: cached derived grid data (see _refreshDerivedCache) -----
  int _cachedRevision = -1;
  final Map<bool, List<List<int>>> _shotsCache = {};
  final Map<bool, List<CombatEventLike>> _eventsCache = {};

  /// Ships whose SINKING shot has visually landed, per half — see the PERF
  /// notes in `_refreshDerivedCache`. Both are cached (rather than rebuilt
  /// per `build()`) so their identity stays stable between real state
  /// changes, which is what lets the grid painters skip repainting.
  final Map<bool, Set<String>> _sunkNamesCache = {};
  final Map<bool, List<PlacedShip>> _destroyedShipsCache = {};

  /// Own-fleet ships as they should be DRAWN, per half — same [PlacedShip]s
  /// as `controller.boards[...].ships` but with `hitIndices` limited to
  /// cells whose shot has actually landed (`impactAt` set), instead of the
  /// raw model set which flips the instant the shot is REGISTERED (tap
  /// time / AI decision time / network-result time). Without this, a
  /// damage crater (and, once every cell is hit, the sunk graphic) could
  /// pop onto a player's own ship well before that shot's cannonball had
  /// actually flown across the screen and struck the grid cell — the same
  /// "logically decided vs visually confirmed" gate `_destroyedShipsCache`
  /// already applies to the enemy-side wreck reveal, just applied to the
  /// live ship art shown on one's OWN board (vsAI / hotspot / online —
  /// see `showOwnFleet`).
  final Map<bool, List<PlacedShip>> _visibleOwnShipsCache = {};

  /// Bumped every time a [CombatEvent.impactAt] is actually set (a ball
  /// visually lands) — see `_resolveImpact` and the overlapping-shot
  /// branch in `_onUpdate`. `controller.revision` does NOT change when
  /// this happens (impact resolution mutates event metadata, not the
  /// controller's own shot-fired state), so this is the signal
  /// `_refreshDerivedCache` needs to know a shot just became visible.
  int _impactResolutions = 0;
  int _cachedImpactResolutions = -1;

  // Prevent the same AI event from being scheduled more than once while
  // the deliberate firing delay is waiting to expire.
  final Set<CombatEvent> _delayedOpponentEvents = <CombatEvent>{};

  @override
  void initState() {
    super.initState();
    SoundService.instance.stopMenuMusic();
    final controller = context.read<GameController>();
    controller.addListener(_onUpdate);

    _lan = controller.mode == GameMode.hotspot ||
        controller.mode == GameMode.online;
    // BLITZ is both at once, so these read the two properties rather
    // than naming modes — otherwise every rule below would need a second
    // clause for a mode that behaves exactly like its two parents.
    _chaos = _lan && !controller.lanBattleMode.hasTurns;
    _manoeuvre = _lan && controller.lanBattleMode.canRearrange;
    _turnTracked = !_chaos &&
        (controller.mode == GameMode.local ||
            controller.mode == GameMode.vsAI ||
            _lan);
    _mirrorTopHalf = !_lan;
    _iAmBlue = _lan && !controller.network.isHost;

    // Whose turn it is at the moment this screen opens. `peerHasTurn` is
    // set by `beginBattle` (host fires first) and by a resume snapshot
    // (whoever's turn it was when the match was interrupted), so a
    // reconnecting player comes back on the correct side of the turn
    // order rather than always as if the match had just started.
    if (_lan && _turnTracked) {
      _p2Active = controller.peerHasTurn;
    }

    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
      // 1 = P1's cannon out at its grid (P2 parked), 0 = the reverse.
      value: _p2Active ? 0.0 : 1.0,
    );

    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );

    _projP1 = _Projectile(byP1: true, vsync: this, duration: _projDuration);
    _projP2 = _Projectile(byP1: false, vsync: this, duration: _projDuration);
    for (final p in [_projP1, _projP2]) {
      p.ctrl.addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) {
          setState(() => p.visible = false);
          _tryResolveImpact(p);
        }
      });
    }

    // Start-of-battle countdown (video: big 3-2-1 over both halves).
    // Skipped when walking back into a match already in progress — see
    // `GameController.resumedMidMatch`.
    if (controller.battling && !controller.resumedMidMatch) {
      _countingDown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _runCountdown());
    }
  }

  Future<void> _runCountdown() async {
    final sfx = SoundService.instance;
    for (var n = 3; n >= 1; n--) {
      if (!mounted) return;
      setState(() => _countdownValue = n);
      sfx.countBeep();
      await Future.delayed(const Duration(milliseconds: 640));
    }
    if (!mounted) return;
    setState(() => _countdownGo = true);
    sfx.countGo();
    await Future.delayed(const Duration(milliseconds: 520));
    if (!mounted) return;
    setState(() {
      _countingDown = false;
      _countdownGo = false;
    });
  }

  void _onUpdate() {
    final controller = context.read<GameController>();
    if (controller.events.isNotEmpty) {
      final e = controller.events.last;
      final age = DateTime.now().difference(e.time).inMilliseconds;
      // Opponent (AI / remote) shots animate from their cannon here; the
      // local player's own ball is launched at tap time. If a ball is
      // already in flight, don't clobber its pending state — just mark
      // the impact so the marker appears (local turn-taking means this
      // only matters for the async AI/remote modes).
      //
      // In local pass-and-play BOTH players are local, so P2's shots also
      // have byPlayer==false (P2 is "the opponent" from P1's POV), but they
      // are NOT async — _fireAtCell already called _launchBall for them.
      // Processing them here as opponent shots causes a double-launch
      // (projectile restart, double cannonFire) and, on the next 100ms
      // cooldown tick, _projCtrl.isAnimating is true so the overlapping-shot
      // branch fires the impact sound + screen shake PREMATURELY (before the
      // ball visibly lands). Excluding GameMode.local prevents this entirely;
      // P2's feedback is handled synchronously by _launchBall just like P1's.
      // `impactAt == null` matters as much as the age check: a match
      // rebuilt from a resume snapshot seeds every past shot as an
      // already-landed event (see `GameController._seedEventsFromShots`),
      // and those are brand new objects. Without this guard the newest of
      // them would be mistaken for an incoming shot and fired again as a
      // phantom cannonball whose impact could never resolve — leaving the
      // opponent's gun permanently jammed.
      if (!e.byPlayer &&
          e.impactAt == null &&
          age < 200 &&
          mounted &&
          controller.mode != GameMode.local) {
        if (!_delayedOpponentEvents.contains(e)) {
          _delayedOpponentEvents.add(e);
          _launchOpponentBall(e);
        }
      }
    }
    // BUGFIX (hotspot/online own-shot race): in hotspot/online mode,
    // firing launches the projectile immediately off a placeholder result
    // (the real one only arrives later over the network — see
    // `GameController.fireAt`), so the ball can finish its fixed-duration
    // flight before the true result message lands. `_tryResolveImpact`
    // already handles "ball landed but the matching event doesn't exist
    // yet" by simply waiting; this call is what wakes it back up the
    // instant that event actually arrives, from wherever in the event
    // list it landed. It's a safe no-op whenever nothing is pending or the
    // ball is still visibly in flight.
    _tryResolveImpact(_projP1);
    _tryResolveImpact(_projP2);
  }

  /// Advances to the result screen — now the ONLY way there once the
  /// match ends (see the game-over bar in build()). Previously this
  /// fired on its own 1.5s after `BattlePhase.finished`, which yanked
  /// players away right as both grids revealed their full fleets,
  /// before there was any real chance to look at where everything was.
  void _goToResult() {
    if (_navigatedToResult) return;
    _navigatedToResult = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ResultScreen()),
    );
  }

  /// AI / remote opponent fired at the BOTTOM player's grid.
  Future<void> _launchOpponentBall(CombatEvent e) async {
    // The AI now pauses before visibly firing so a missed human shot is not
    // followed by an almost-instant cannon blast. Remote multiplayer keeps
    // its previous timing.
    final controller = context.read<GameController>();
    if (controller.mode == GameMode.vsAI) {
      await Future.delayed(const Duration(milliseconds: 900));
    }
    if (!mounted || controller.phase != BattlePhase.battling) return;

    final top = _geom[true];
    final bottom = _geom[false];
    if (top == null || bottom == null || _projP2.visible) {
      // No flight is possible right now — either the halves haven't been
      // laid out yet, or this gun's previous ball is somehow still
      // airborne. Resolve the shot in place rather than dropping it: this
      // used to just `return`, which left the event pending FOREVER,
      // since `_onUpdate` only ever reconsiders events under 200ms old.
      _resolveImpact(e);
      return;
    }
    // The opponent's cannon may be slid out to its grid center (during its
    // turn) or parked at the back — fire from wherever it currently sits,
    // which `_slideFor` reports for every mode including chaos (where it
    // never leaves the back at all).
    final from = _cannonMouth(top, _slideFor(false), false);
    final to = bottom.cellCenterScreen(e.row, e.col) +
        _mouthDir(bottom) * (bottom.cannonSize * 0.25);
    setState(() {
      _projP2
        ..pendingCell = [e.row, e.col]
        ..from = from
        ..to = to
        ..cell = bottom.cell
        ..visible = true;
    });
    SoundService.instance.cannonFire();
    _cannon2Fire.add(null);
    _projP2.ctrl.forward(from: 0);
  }

  /// Resolves the currently pending shot (`_pendingImpact`/`_pendingByP1`)
  /// against `controller.events` — but ONLY once both (a) the projectile
  /// has visibly finished traveling (`_showProjectile == false`) and (b)
  /// the true result is actually known (a matching, not-yet-resolved
  /// `CombatEvent` exists). For a purely local shot both become true at
  /// the same instant the flight animation completes. For the local
  /// player's own shot in hotspot/online mode the true result arrives
  /// asynchronously over the network and can land slightly before OR
  /// after the ball's fixed-duration flight finishes — so this is safe to
  /// call from either trigger (`_projCtrl`'s completion listener, or
  /// `_onUpdate` whenever a new event arrives) and only ever resolves
  /// once, whichever condition is satisfied last. If the ball has landed
  /// but the event doesn't exist yet, it simply leaves `_pendingImpact`
  /// set and returns — the next call (from `_onUpdate`, the instant the
  /// real result arrives) finishes the job.
  void _tryResolveImpact(_Projectile p) {
    if (p.visible) return; // ball still visibly traveling
    final cell = p.pendingCell;
    if (cell == null) return;
    final controller = context.read<GameController>();
    CombatEvent? found;
    for (final e in controller.events.reversed) {
      if (e.row == cell[0] &&
          e.col == cell[1] &&
          e.byPlayer == p.byP1 &&
          e.impactAt == null) {
        found = e;
        break;
      }
    }
    if (found == null) return; // true result not in yet — wait for it

    p.pendingCell = null;
    _resolveImpact(found);
  }

  /// Everything that happens the instant a shot's impact becomes visible:
  /// the marker/wreck reveal is unlocked (`impactAt`), the outcome sound
  /// and screen shake play, the match is allowed to end if this was the
  /// deciding shot, and the turn passes on a miss.
  ///
  /// Shared by the normal path (a ball finished its flight — see
  /// [_tryResolveImpact]) and the fallback path (no flight was possible —
  /// see [_launchOpponentBall]) so a shot lands identically either way.
  /// Idempotent: an already-resolved event is left alone.
  void _resolveImpact(CombatEvent e) {
    if (e.impactAt != null) return;
    final controller = context.read<GameController>();
    e.impactAt = DateTime.now();
    _impactResolutions++;
    controller.touch();
    // Hit/sunk/miss sound, right as the ball actually lands — synced to
    // the same moment as the shake below and the hit/miss/wreckage reveal
    // (see `sunkShips` in `_buildHalf`), instead of firing back at tap
    // time before the ball has visually gone anywhere.
    _playImpactSound(e.result);
    // Screen shake, right as the ball actually lands — never on a miss
    // (there's nothing to "hit"). Sinking a ship shakes harder than a
    // plain hit so a killing blow reads as more impactful.
    if (e.result == ShotResult.sunk) {
      _shake(_shakeSunkMagnitude);
    } else if (e.result == ShotResult.hit) {
      _shake(_shakeHitMagnitude);
    }
    // BUGFIX (end-game timing): the match is only actually allowed to end
    // here, now that this shot's impact has been visually applied — see
    // GameController.hasPendingFinish / resolvePendingFinishFor. A no-op
    // unless `e` happens to be the exact shot that decided the match.
    controller.resolvePendingFinishFor(e);
    _maybePassTurn(e);
  }

  /// 1:1 video rule: a HIT lets the same player keep firing; only a MISS
  /// passes the turn to the other player. Applies to every mode that HAS
  /// turns — local pass-and-play, vs AI, and LAN "turn based" — but never
  /// to LAN chaos, where both fleets fire freely and there is no turn to
  /// hand over (`_turnTracked` is false there).
  ///
  /// In a LAN match both devices run this independently off their own
  /// event streams. That stays consistent because every shot's outcome is
  /// known to BOTH ends (the defender resolves it and echoes the result
  /// back), and each end sees the same shot as the same side: my shots are
  /// always `byPlayer == true` on my device and `byPlayer == false` on
  /// theirs — which is exactly the flip the two `_p2Active` flags need.
  void _maybePassTurn(CombatEvent e) {
    if (!_turnTracked) return;
    if (e.result != ShotResult.miss) return;
    final controller = context.read<GameController>();
    if (controller.phase != BattlePhase.battling) return;
    // P1 missed → P2's turn; P2/AI/remote missed → P1's.
    final passToP2 = e.byPlayer;
    // The handoff is seamless (no popup): the active flag flips, the
    // cannons slide (outgoing → back, incoming → its grid center) and the
    // newly-active cannon flashes "ready".
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted || controller.phase != BattlePhase.battling) return;
      _passTurn(passToP2);
    });
  }

  /// Seamlessly pass the turn: flip the active flag, slide the cannons
  /// (the outgoing player's cannon returns home; the incoming player's
  /// cannon slides out to the middle of its grid) and flash the new
  /// active cannon "ready" — no blocking popup. The halves themselves
  /// NEVER swap sides (P1 stays bottom, P2 stays top).
  void _passTurn(bool toP2) {
    SoundService.instance.whir();
    SoundService.instance.turnPass();
    setState(() => _p2Active = toP2);
    // Keep the controller's mirror current: it's what a resume snapshot
    // reads to tell a reconnecting player whose turn they came back to.
    context.read<GameController>().peerHasTurn = toP2;
    // Animate the slide: value 1 = P1 out (P2 home), 0 = P2 out (P1 home).
    if (toP2) {
      _slideCtrl.reverse();
    } else {
      _slideCtrl.forward();
    }
    // Flash the newly-active cannon once the slide has begun, with a
    // mechanical "locked in" clunk synced to the same moment.
    Future.delayed(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      SoundService.instance.cannonReady();
      (_p2Active ? _cannon2Ready : _cannon1Ready).add(null);
    });
  }

  // ------------------------------------------------------------- FIRING

  /// The active player taps a cell on the OPPONENT's grid → fire
  /// immediately at that cell. Tapping is the ONLY action needed to fire;
  /// there is no separate "now tap your own cannon" step (that extra tap
  /// was the bug: taps on the grid used to only move a crosshair, so
  /// nothing ever actually fired unless you also found and tapped the
  /// tiny cannon icon).
  void _fireAtCell(GameController controller, {required int r, required int c}) {
    if (_countingDown) return;
    // On a LAN device the local player IS the bottom half, always — the
    // top half belongs to the remote opponent and is never fired by this
    // device, whoever's turn it happens to be. Only shared-screen modes
    // use `_p2Active` to pick which of two LOCAL players is shooting.
    final byP1 = _lan ? true : !_p2Active;
    // Block only on THIS gun's own ball still being airborne. Blocking on
    // "any ball anywhere" would make chaos mode unplayable, since the
    // opponent has a ball in the air a good part of the time.
    final proj = byP1 ? _projP1 : _projP2;
    if (proj.visible) return;
    final tracking = byP1 ? controller.myShots : controller.p2Shots;
    if (tracking[r][c] != 0) {
      // No pop-up reminder for this — an already-tried cell simply
      // already shows its hit/miss marker, and the denied-shot sound/
      // haptic below is enough feedback without interrupting the view.
      SoundService.instance.denied();
      return;
    }
    final res = byP1 ? controller.fireAt(r, c) : controller.p2FireAt(r, c);
    if (res == ShotResult.cooldown) {
      // No bottom-of-screen popup for this — the cannon's own cooldown
      // ring already shows reload state, and a denied-shot sound/haptic
      // (below) is enough feedback without interrupting the view.
      SoundService.instance.denied();
      return;
    }
    if (res == ShotResult.duplicate || res == ShotResult.invalid) {
      SoundService.instance.denied();
      return;
    }
    _launchBall(controller, byP1: byP1, r: r, c: c);
  }

  /// Shared ball-launch used by the player's cannon tap. Deliberately does
  /// NOT take the shot's result: in hotspot/online mode the true result of
  /// the LOCAL player's own shot isn't known yet at launch time (it comes
  /// back from the peer asynchronously — see `GameController.fireAt`), so
  /// resolving what actually happened is left entirely to
  /// `_tryResolveImpact`, which looks it up from `controller.events` once
  /// it's actually known instead of trusting a guess made at tap time.
  void _launchBall(
    GameController controller, {
    required bool byP1,
    required int r,
    required int c,
  }) {
    final top = _geom[true];
    final bottom = _geom[false];
    if (top == null || bottom == null) return;
    // The shooter fires from wherever its cannon currently sits (slid out
    // to its grid center during its turn). The ball arcs toward the aimed
    // cell on the OPPONENT's grid.
    final shooterGeom = byP1 ? bottom : top;
    final targetGeom = byP1 ? top : bottom;
    final from = _cannonMouth(shooterGeom, _slideFor(byP1), byP1);
    final to = targetGeom.cellCenterScreen(r, c) +
        _mouthDir(targetGeom) * (targetGeom.cannonSize * 0.25);
    final proj = byP1 ? _projP1 : _projP2;
    setState(() {
      proj
        ..pendingCell = [r, c]
        ..from = from
        ..to = to
        ..cell = targetGeom.cell
        ..visible = true;
    });
    SoundService.instance.cannonFire();
    (byP1 ? _cannon1Fire : _cannon2Fire).add(null);
    proj.ctrl.forward(from: 0);
  }

  // ----------------------------------------------------- CANNON SLIDE ---

  // ------------------------------------------------- PER-PLAYER GEAR ---
  //
  // In a network match each captain sails their OWN purchased loadout,
  // and both devices render it the same way: my half uses what I have
  // equipped, the opponent's half uses what they told us they have
  // equipped in the handshake (see `NetworkService._helloPayload`). Away
  // from network play there is only one profile, so everything falls back
  // to it.

  /// Whose gear paints a given half.
  ///
  ///  * LAN — your own profile on the bottom, and the loadout the
  ///    opponent sent in the handshake on top. Both devices therefore
  ///    draw the same two fleets the same way.
  ///  * LOCAL pass-and-play — one device, one saved profile, but two
  ///    people, each of whom picked their own gear on the deployment
  ///    screen. The controller keeps a loadout per seat.
  ///  * VS AI — one human owns the whole screen, so their gear is used
  ///    throughout (the AI has no shipyard of its own).
  Loadout _loadoutFor(bool halfIsP1) {
    if (_lan) {
      if (halfIsP1) return Loadout.of(context.read<ProfileStore>());
      final net = context.read<NetworkService>();
      return Loadout(
        shipSkinId: net.peerShipSkinId,
        cannonSkinId: net.peerCannonSkinId,
        themeId: net.peerThemeId,
        shipChosen: net.peerShipSkinChosen,
      );
    }
    if (context.read<GameController>().mode == GameMode.local) {
      return context.read<GameController>().localLoadouts[halfIsP1 ? 0 : 1];
    }
    // VS AI. The battlefield is the player's — it is their theme, on both
    // halves — but the FLEET and the GUN on the far side belong to the
    // opponent, so the AI sails the plain blue hulls and fires the
    // standard cannon. Handing the AI the player's own Cinder Hold and
    // Magma Bombard would make the two sides indistinguishable, which is
    // the one thing a battle screen cannot afford.
    final mine = Loadout.of(context.read<ProfileStore>());
    if (halfIsP1) return mine;
    return Loadout(themeId: mine.themeId);
  }

  /// How a half's fleet reads on screen — hull colour, chrome colour and
  /// readable ink — resolved by the shared rule in `fleet_identity.dart`
  /// so this screen, the deployment screen and the mode vote can never
  /// disagree about what colour a captain is.
  ///
  /// Skins apply to whichever fleet its owner actually chose. That is
  /// both halves in LAN and pass-and-play, and only the player's own half
  /// against the AI — whose loadout above is deliberately left plain, so
  /// "mine" and "theirs" stay instantly separable.
  FleetLook _lookFor(bool halfIsP1) {
    final lo = _loadoutFor(halfIsP1);
    return fleetLook(
      isRedSide: _fleetIsRed(halfIsP1),
      equippedShipSkinId: lo.shipSkinId,
      chosen: lo.shipChosen,
    );
  }

  ShipSkin _shipSkinFor(bool halfIsP1) => _lookFor(halfIsP1).skin;

  CannonSkin _cannonSkinFor(bool halfIsP1) => _loadoutFor(halfIsP1).cannonSkin;

  GameplayTheme _themeFor(bool halfIsP1) => _loadoutFor(halfIsP1).theme;

  // ------------------------------------------------ MANOEUVRE ACTIONS ---

  /// Live "where would this ship land" highlight while it's being dragged
  /// around your own grid.
  void _previewMove(GameController controller, ShipKind kind, int row, int col) {
    final ship = controller.boards[0].shipOfKind(kind);
    if (ship == null) return;
    final spec = ship.spec;
    var r = row;
    var c = col;
    if (ship.horizontal && c + spec.size > kBoardSize) {
      c = kBoardSize - spec.size;
    }
    if (!ship.horizontal && r + spec.size > kBoardSize) {
      r = kBoardSize - spec.size;
    }
    setState(() {
      _movePreview =
          PlacedShip(spec: spec, row: r, col: c, horizontal: ship.horizontal);
      _movePreviewValid =
          controller.boards[0].canRelocateTo(ship, r, c, ship.horizontal);
    });
  }

  void _commitMove(GameController controller, ShipKind kind, int row, int col) {
    final ship = controller.boards[0].shipOfKind(kind);
    setState(() => _movePreview = null);
    if (ship == null) return;
    var r = row;
    var c = col;
    if (ship.horizontal && c + ship.spec.size > kBoardSize) {
      c = kBoardSize - ship.spec.size;
    }
    if (!ship.horizontal && r + ship.spec.size > kBoardSize) {
      r = kBoardSize - ship.spec.size;
    }
    if (r == ship.row && c == ship.col) return; // no actual movement
    if (controller.relocateOwnShip(kind, r, c, ship.horizontal)) {
      SoundService.instance.place();
    } else {
      SoundService.instance.denied();
    }
  }

  /// Tapping a ship turns it on the spot, same as during deployment.
  void _rotateOwnShip(GameController controller, ShipKind kind) {
    final ship = controller.boards[0].shipOfKind(kind);
    if (ship == null) return;
    final horizontal = !ship.horizontal;
    var r = ship.row;
    var c = ship.col;
    if (horizontal && c + ship.spec.size > kBoardSize) {
      c = kBoardSize - ship.spec.size;
    }
    if (!horizontal && r + ship.spec.size > kBoardSize) {
      r = kBoardSize - ship.spec.size;
    }
    if (controller.relocateOwnShip(kind, r, c, horizontal)) {
      SoundService.instance.place();
    } else {
      SoundService.instance.denied();
    }
  }

  /// How far a half's cannon has slid out of its parked position: 0 =
  /// tucked at the BACK of its own grid (the far edge of the screen),
  /// 1 = out at the middle of that grid, marking its owner's turn.
  ///
  /// Two modes pin both cannons at the back for the whole match, and
  /// since every trajectory is derived from this same value (see
  /// `_cannonMouth`), that is also where their cannonballs launch from.
  ///
  ///  * CHAOS pins BOTH cannons at the back — there are no turns to mark
  ///    in the first place.
  ///
  ///  * MANOEUVRE pins only the cannon on YOUR OWN half, and only on
  ///    your own device. Parked in the middle of your grid it sits
  ///    directly on top of the fleet this mode is entirely about
  ///    dragging around, hiding the ships you are trying to move. The
  ///    opponent's cannon has no such problem — you never rearrange
  ///    anything on their water — so it still slides out to mark their
  ///    turn, which is what makes whose-turn-it-is readable without
  ///    getting in anyone's way.
  ///
  ///    The consequence is that the two devices deliberately draw the
  ///    SAME cannon differently, and that is the point rather than a
  ///    desync: your gun is parked at the back from where you sit, while
  ///    your opponent watches it roll out to the middle of your grid and
  ///    fire from there. Each end only ever pins the gun that would be
  ///    covering its own fleet.
  double _slideFor(bool halfIsP1) {
    if (_chaos) return 0.0;
    if (_manoeuvre && halfIsP1) return 0.0;
    return halfIsP1 ? _slideCtrl.value : 1 - _slideCtrl.value;
  }

  /// Unit direction from a half's cannon toward its grid mouth, in SCREEN
  /// space (+y = down the screen). Derived from the half's own muzzle
  /// direction (which points at its grid in the half's LOCAL space) and
  /// then flipped if the half itself is drawn rotated.
  Offset _mouthDir(_HalfGeom g) =>
      Offset(0, g.rotated ? -g.muzzleLocalDir : g.muzzleLocalDir);

  /// A half cannon CENTER (in that half's local, unrotated space),
  /// interpolated between its home position near the middle band (t=0)
  /// and the middle of its own grid (t=1, its firing position). Eased to
  /// match the little overshoot "pop" the cannon visually slides with —
  /// harmless at t=0/1 (both curves agree exactly at the endpoints,
  /// which is always where firing actually happens) and keeps the ball's
  /// spawn point consistent with the cannon's on-screen position at any
  /// other moment too.
  Offset _cannonCenterLocal(_HalfGeom g, double t) => Offset.lerp(
      g.cannonCenter, g.gridCenterLocal, Curves.easeOutBack.transform(t.clamp(0.0, 1.0)))!;

  /// Absolute screen position of a half's cannon MOUTH, accounting for the
  /// 180° rotation of the top half, given the cannon's slide amount [t].
  /// Uses `CannonWidget.muzzleFraction` — the SAME constant the redesigned,
  /// longer barrel is actually drawn out to — so the cannonball always
  /// visibly launches from the real muzzle tip instead of a stale offset
  /// left over from the old, much shorter cannon.
  Offset _cannonMouth(_HalfGeom g, double t, bool halfIsP1) {
    final c = _cannonCenterLocal(g, t);
    final lx = c.dx;
    // Per-gun, not per-game: the thematic families each have their own
    // barrel length, so the ball is born at THIS cannon's muzzle rather
    // than at a fixed distance that would leave a short mortar throwing
    // from thin air and a long autoloader swallowing its own shot.
    //
    // Multiplied by `cannonRenderSize`, not the shared base `cannonSize`
    // — a family gun is actually DRAWN bigger than that base size (see
    // `CannonWidget.gameplaySizeScaleOf`), so the muzzle fraction has to
    // scale against the size it's really drawn at, or the ball would
    // launch from where the old, smaller barrel USED to end.
    final ly = c.dy +
        g.muzzleLocalDir *
            g.cannonRenderSize *
            CannonWidget.muzzleFractionOf(_cannonSkinFor(halfIsP1));
    if (g.rotated) {
      return Offset(g.halfW - lx, g.halfTopY + (g.halfH - ly));
    }
    return Offset(lx, g.halfTopY + ly);
  }

  @override
  void dispose() {
    _cannon1Fire.close();
    _cannon2Fire.close();
    _cannon1Ready.close();
    _cannon2Ready.close();
    _projP1.dispose();
    _projP2.dispose();
    _slideCtrl.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- BUILD

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GameController>();
    final profile = context.watch<ProfileStore>();
    _refreshDerivedCache(controller);
    // The halves NEVER swap sides: the bottom one is always "P1" (in a LAN
    // match, always THIS device's own fleet) and the top one always "P2"
    // (the opponent). Only the "whose turn" flag changes. Whether the top
    // half is additionally drawn upside down depends on whether the two
    // players are sharing this screen — see `_mirrorTopHalf`.
    const bottomIsP1 = true;

    // BUGFIX (classic deck leaking through on notches / non-edge-to-edge
    // screens): the Scaffold body used to be one Container painted a
    // fixed `AppColors.coralVideo` — which is the CLASSIC theme's deck
    // colour by value, restated as a named constant — sitting BEHIND the
    // SafeArea. On a fully edge-to-edge phone the two halves' own themed
    // backgrounds always cover it completely, so nobody ever saw it. But
    // SafeArea deliberately does NOT paint into a display cutout, a
    // status bar, or a gesture/home-indicator strip — it leaves that
    // margin for whatever is behind it to show through. On a phone with
    // a notch (or any device that isn't rendering true edge-to-edge),
    // that margin IS this Container, so the strip right behind the
    // cannon at the top of the board — and the strip along the bottom —
    // stayed hard-coded to the classic look no matter what deck theme
    // was actually equipped. Each half already wears its OWN captain's
    // theme everywhere else on this screen (see the middle band below),
    // so the fix is the same idea applied to the one spot that was still
    // flat classic: split this background top/bottom to match.
    final topIsP1Fleet = !bottomIsP1;
    final bottomIsP1Fleet = bottomIsP1;
    final topDeckColor = _themeFor(topIsP1Fleet).deck;
    final bottomDeckColor = _themeFor(bottomIsP1Fleet).deck;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Column(
              children: [
                Expanded(child: Container(color: topDeckColor)),
                Expanded(child: Container(color: bottomDeckColor)),
              ],
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, full) {
              const bandH = 58.0;
              final halfH = (full.maxHeight - bandH) / 2;
              // Shake wrapper: a plain Transform.translate driven by
              // `_shakeCtrl`/`_shakeOffset` around the whole battle Stack,
              // so a hit/sunk impact nudges the entire board rather than
              // just one half — `child:` keeps the (large, mostly static)
              // Stack itself out of the AnimatedBuilder's rebuild scope,
              // so only the translate offset recomputes every shake tick.
              return AnimatedBuilder(
                animation: _shakeCtrl,
                builder: (context, child) => Transform.translate(
                  offset: _shakeOffset(_shakeCtrl.value),
                  child: child,
                ),
                child: Stack(
                  children: [
                  Column(
                    children: [
                      // ===== TOP HALF — the opponent's fleet =====
                      // Flipped 180° ONLY when both players share this
                      // screen (local pass-and-play / vs AI), so the
                      // person sitting opposite reads their own board
                      // right-side-up. A LAN opponent is on their own
                      // device, so here it stays upright and is laid out
                      // mirrored within the half instead — see
                      // `_mirrorTopHalf`.
                      SizedBox(
                        height: halfH,
                        child: Builder(builder: (context) {
                          final half = _buildHalf(
                            controller,
                            profile,
                            halfIsP1: !bottomIsP1,
                            isTopHalf: true,
                            halfH: halfH,
                            halfTopY: 0,
                            bottomIsP1: bottomIsP1,
                          );
                          return _mirrorTopHalf
                              ? RotatedBox(quarterTurns: 2, child: half)
                              : half;
                        }),
                      ),

                      // ===== MIDDLE BAND =====
                      _buildMiddleBand(controller, bottomIsP1, bandH),

                      // ===== BOTTOM HALF — P1, upright (fixed side) =====
                      SizedBox(
                        height: halfH,
                        child: _buildHalf(
                          controller,
                          profile,
                          halfIsP1: bottomIsP1,
                          isTopHalf: false,
                          halfH: halfH,
                          halfTopY: halfH + bandH,
                          bottomIsP1: bottomIsP1,
                        ),
                      ),
                    ],
                  ),

                  // ===== Cannonball flight (spans both halves) =====
                  // One layer per shooter, so two balls can be airborne at
                  // once — which is the normal state of affairs in chaos
                  // mode. Each only mounts while its own ball is flying.
                  if (_projP1.visible) _projectileLayer(_projP1),
                  if (_projP2.visible) _projectileLayer(_projP2),

                  // ===== Countdown overlay (mirrored) =====
                  if (_countingDown) _countdownOverlay(bandH),

                  // ===== Game-over bar: both grids reveal every ship the
                  // instant the match ends (see `gameOver` in _buildHalf),
                  // and this bar is what lets players actually take that
                  // in — it replaces the old fixed 1.5s auto-navigate
                  // timer, so the reveal stays on screen for as long as
                  // the player wants until they tap CONTINUE. =====
                  if (controller.phase == BattlePhase.finished)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: halfH,
                      height: bandH,
                      child: _gameOverBar(),
                    ),

                  // ===== Opponent dropped: the match is held open for a
                  // minute while they find their way back. =====
                  if (_lan && controller.phase == BattlePhase.battling)
                    _ReconnectOverlay(
                      onAbandon: () => _abandon(controller),
                    ),
                ],
              ),
            );
          },
        ),
      ),
        ],
      ),
    );
  }

  /// Give up on an opponent who has not come back. The match is void —
  /// no win, no loss, no RP for either side (see
  /// `GameController.abandonMatch`) — so this goes straight home rather
  /// than to a result screen that would have nothing to report.
  void _abandon(GameController controller) {
    controller.abandonMatch();
    controller.network.stop();
    _navigatedToResult = true;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// One airborne cannonball: the ball itself plus its two motion-trail
  /// ghosts, arcing from the firing cannon's muzzle to its target cell.
  Widget _projectileLayer(_Projectile p) {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: p.ctrl,
          builder: (context, _) {
            final t = p.ctrl.value;
            // Whose gun this shell came out of — the shell is part of the
            // cannon, not of the board it is crossing. A family cannon's
            // shell is keyed off the family; one of the nine originals has
            // no family, so its own catalogue id is what picks its shell
            // instead (see `legacy_shell_art.dart`).
            final shooterSkin = _cannonSkinFor(p.byP1);
            final shellFamily = FleetFamilies.byKey(shooterSkin.familyKey);
            final legacyShellId = shellFamily == null ? shooterSkin.id : null;
            // BUGFIX (pointy shells "just rotating" in place instead of
            // flying nose-first): every shell used to get the same
            // continuous free spin, which reads fine for a round shot
            // (it's a sphere; any face it shows is the right face) but
            // looked wrong for the directional rocket/dart shells —
            // Phantom Railgun's slug, the naval family's MK-IV sabot
            // shell, and Venom's warhead — which have an actual nose and
            // tail drawn into the art. Those are now oriented to the
            // shell's real instantaneous heading along the arc below
            // instead of spinning freely; round shells are untouched.
            final isDirectional = shellFamily != null
                ? familyShellIsDirectional(shellFamily.id)
                : legacyShellIsDirectional(legacyShellId!);
            // Vertical ARC for the up-and-down lob effect, reused for the
            // ball itself and its trail.
            Offset posAt(double tt) {
              final cl = tt.clamp(0.0, 1.0);
              final base = Offset.lerp(p.from, p.to, cl)!;
              final arc = math.sin(cl * math.pi) * p.cell * 3.0;
              return base - Offset(0, arc);
            }

            // The shell's instantaneous heading along the arc above,
            // as an angle `Transform.rotate` can use directly to turn the
            // art's authored nose-up orientation to face it. Derived
            // analytically from `posAt`'s own velocity (the straight-line
            // component plus the arc's rate of rise/fall) rather than
            // sampled by finite differences, so it's exact at every frame
            // — including the first and last, where a sampled derivative
            // would need special-casing.
            double angleAt(double tt) {
              final cl = tt.clamp(0.0, 1.0);
              final vx = p.to.dx - p.from.dx;
              final arcRate = math.pi * p.cell * 3.0 * math.cos(cl * math.pi);
              final vy = (p.to.dy - p.from.dy) - arcRate;
              if (vx == 0 && vy == 0) return 0;
              return math.atan2(vx, -vy);
            }

            // Cannonball launches noticeably LARGER than the target cell
            // and slowly SHRINKS the whole way there, settling to exactly
            // the grid cell's size right as it lands — a clear "incoming
            // shot" effect that telegraphs where the ball is about to hit.
            double diamAt(double tt) =>
                p.cell * (2.6 - 1.6 * tt.clamp(0.0, 1.0));

            final pos = posAt(t);
            final d = diamAt(t);
            // Round shells keep the classic continuous tumble-spin (sold
            // by the sphere's highlight sweeping around it); directional
            // ones face the way they're actually flying.
            final angle = isDirectional ? angleAt(t) : t * math.pi * 6;

            Widget ghost(double dt, double opacity, double scale) {
              final tt = t - dt;
              if (tt <= 0) return const SizedBox.shrink();
              final gp = posAt(tt);
              final gd = diamAt(tt) * scale;
              return Positioned(
                left: gp.dx - gd / 2,
                top: gp.dy - gd / 2,
                child: Opacity(
                    opacity: opacity,
                    child: Transform.rotate(
                      // Trailing ghosts of a directional shell face the
                      // same way the shell itself did at that point along
                      // the arc; round shells' ghosts were never rotated
                      // and still aren't.
                      angle: isDirectional ? angleAt(tt) : 0.0,
                      child: _cannonball(gd,
                          family: shellFamily, legacyId: legacyShellId),
                    )),
              );
            }

            return Stack(
              children: [
                // Faint motion-trail ghosts behind the ball.
                ghost(0.11, 0.14, 0.72),
                ghost(0.055, 0.26, 0.84),
                Positioned(
                  left: pos.dx - d / 2,
                  top: pos.dy - d / 2,
                  child: Transform.rotate(
                    angle: angle,
                    child: _cannonball(d,
                        family: shellFamily, legacyId: legacyShellId),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // -------------------------------------------------------------- HALVES

  /// PERF: the game's cooldown ticker fires `notifyListeners()` every
  /// 100ms for the whole battle so the cannons' reload rings stay smooth.
  /// This screen used to recompute BOTH grids' full 10×10 shot arrays and
  /// re-filter the entire combat-event log from scratch on every single
  /// one of those ticks — work that grows with how many shots have been
  /// fired, ten times a second, for the whole match. That's the "lags
  /// more the more hits/misses pile up" bug. It only actually needs to be
  /// recomputed when a shot is fired/resolved, so it's now cached and
  /// only rebuilt when [GameController.revision] (or the locally-tracked
  /// in-flight ball) actually changes.
  void _refreshDerivedCache(GameController controller) {
    // Everything built below is a pure function of `controller.events`
    // (which only grows via `_registerShot`, bumping `revision`), each
    // event's `impactAt` (which only ever gets set by `_resolveImpact`,
    // bumping `_impactResolutions`), and the two boards' ship lists (set
    // in `beginBattle`, which also bumps `revision`). So those two
    // counters fully cover the inputs. The in-flight ball used to be part
    // of this check too, but it never fed any of these outputs — it just
    // invalidated the cache needlessly on every shot fired.
    if (controller.revision == _cachedRevision &&
        _cachedImpactResolutions == _impactResolutions &&
        _shotsCache.isNotEmpty) {
      return;
    }
    _cachedRevision = controller.revision;
    _cachedImpactResolutions = _impactResolutions;
    for (final halfIsP1 in const [true, false]) {
      // PERF: reuse persistent mutable arrays instead of allocating new
      // 10×10 lists on every cache rebuild (happens on every shot). The
      // inner lists are created once and mutated in place; only the outer
      // list gets a fresh reference via List.of() to trip shouldRepaint.
      final cache = _shotsCache.putIfAbsent(
        halfIsP1,
        () => List.generate(kBoardSize, (_) => List.filled(kBoardSize, 0)),
      );
      for (var r = 0; r < kBoardSize; r++) {
        for (var c = 0; c < kBoardSize; c++) {
          cache[r][c] = 0;
        }
      }
      final evCache = _eventsCache.putIfAbsent(halfIsP1, () => []);
      evCache.clear();
      // PERF: the revealed-sunk-names set is built HERE, once per real
      // state change, rather than by re-scanning every event on every
      // build — it used to be recomputed 4× per rebuild (both halves +
      // both fleet status rows), and that scan grows with every shot
      // fired in the match.
      final sunkNames = <String>{};
      for (final e in controller.events) {
        if (e.byPlayer == halfIsP1 || e.impactAt == null) continue;
        final hit = e.result == ShotResult.hit || e.result == ShotResult.sunk;
        cache[e.row][e.col] = hit ? 2 : 1;
        evCache.add(CombatEventLike(e.row, e.col, e.result,
            sunkShipName: e.sunkShipName));
        if (e.result == ShotResult.sunk && e.sunkShipName != null) {
          sunkNames.add(e.sunkShipName!);
        }
      }
      _shotsCache[halfIsP1] = List.of(cache);
      _sunkNamesCache[halfIsP1] = sunkNames;

      // Build the landed-only view of this half's own ships from the same
      // `cache` grid — `cache[r][c] == 2` means a shot on that cell has
      // both been registered AND had its cannonball land (see the loop
      // above, which only fills `cache` from events with `impactAt` set).
      // Reusing it here keeps the ship damage crater and the grid's own
      // hit marker flipping to "hit" at exactly the same moment.
      final boardForVisible = halfIsP1 ? controller.boards[0] : controller.boards[1];
      _visibleOwnShipsCache[halfIsP1] = [
        for (final s in boardForVisible.ships)
          PlacedShip(
            spec: s.spec,
            row: s.row,
            col: s.col,
            horizontal: s.horizontal,
            hitIndices: {
              for (var i = 0; i < s.cells.length; i++)
                if (cache[s.cells[i][0]][s.cells[i][1]] == 2) i,
            },
          ),
      ];

      // PERF (this is the big one): `_StaticGridPainter.shouldRepaint`
      // compares `destroyedShips` by IDENTITY. This list used to be built
      // as a fresh literal inside `_buildHalf` on every single build, so
      // that identity check was ALWAYS true — meaning both grids fully
      // repainted, redrawing every accumulated hit/miss mark, on every
      // rebuild (which the 100ms cooldown tick was triggering 10× a
      // second). Cost therefore scaled directly with how many marks had
      // piled up, which is exactly the reported "fine early, bad mid/late
      // match" behavior. Building it here — in the cache pass that only
      // runs when the board state genuinely changed — gives it a stable
      // identity between real events, so the static layer now repaints
      // only when the board actually changes.
      final board = halfIsP1 ? controller.boards[0] : controller.boards[1];
      _destroyedShipsCache[halfIsP1] = [
        for (final s in board.ships)
          if (s.isSunk && sunkNames.contains(s.spec.name)) s
      ];
    }
  }

  /// Names of ships on the [halfIsP1] board whose SINKING SHOT has actually
  /// landed — i.e. the same "visually confirmed, not just logically
  /// decided" gate used everywhere else a sunk ship's wreck is revealed.
  /// Shared by the battle grid's own wreck reveal (`_buildHalf`) and the
  /// middle-band remaining-ships preview (`_buildMiddleBand`/`_statusRow`)
  /// so a ship's status-row icon and its on-grid wreck flip to "destroyed"
  /// at exactly the same moment, for both players and in every mode
  /// (vsAI/local/hotspot/online) — all of them funnel through the same
  /// `GameController.events` + `impactAt` pipeline this reads from.
  ///
  /// The model marks a ship sunk (`PlacedShip.isSunk`) the instant the shot
  /// is REGISTERED (tap time / AI decision time / network-result time),
  /// well before the cannonball has actually flown across the screen —
  /// reading that flag straight would flip the preview to "destroyed"
  /// ahead of the ball's flight animation, sunk sound and screen-shake.
  /// Gating on `events` (which only contains impact-LANDED shots — see
  /// `_refreshDerivedCache`) keeps the preview in lockstep with those
  /// instead, and since `events` only ever grows within a match, a name
  /// once added here can never disappear again on a later rebuild.
  Set<String> _revealedSunkNames(bool halfIsP1) =>
      _sunkNamesCache[halfIsP1] ?? const <String>{};

  /// One player's half of the table: their own grid + their own cannon.
  Widget _buildHalf(
    GameController controller,
    ProfileStore profile, {
    required bool halfIsP1,
    required bool isTopHalf,
    required double halfH,
    required double halfTopY,
    required bool bottomIsP1,
  }) {
    // NB: the cooldown fraction is deliberately NOT read here — it's read
    // inside the cannon's own `ValueListenableBuilder` below, so that a
    // cooldown change repaints only the cannon instead of this whole half.
    final cannonStream = halfIsP1 ? _cannon1Fire : _cannon2Fire;
    final readyStream = halfIsP1 ? _cannon1Ready : _cannon2Ready;
    // BUGFIX (both LAN captains were red): the fleet colour used to be
    // pinned to the HALF — bottom red, top blue — which is right when the
    // two players share one screen, but in a LAN match each device draws
    // its OWN fleet on the bottom, so both players saw themselves in red
    // and their opponent in blue. `_fleetIsRed` keys off the network role
    // instead (host red, joiner blue), so the two devices now agree on
    // who is which colour.
    // …and every piece of chrome belonging to that half — the turn scrim
    // tint and the cannon's ready glow — is tinted with the SAME identity
    // colour the hulls are painted in, so a captain wearing Emerald Tide
    // doesn't command green ships behind a red highlight.
    final look = _lookFor(halfIsP1);
    final accent = look.color;
    // Each half is painted in ITS OWNER's battlefield theme, so the
    // customisation a player paid for is what they sail on — and their
    // opponent sees it too, on the same half, on both devices.
    final gameplayTheme = _themeFor(halfIsP1);

    // VIDEO interaction model: the ACTIVE player's cannon sits at the
    // middle of their OWN grid (a "ready to fire" indicator). Tapping a
    // cell on the OPPONENT's grid fires at it immediately — a single tap
    // is the whole interaction.
    final inBattle = !_countingDown && controller.battling;

    // Which grid this device may tap right now.
    final bool gridFirable;
    if (_lan) {
      // One human per device: you only ever shoot at the OPPONENT's grid
      // (the top half). Your own board is never a target for you — the
      // shared-screen rule below would have made it one on the opponent's
      // "turn", letting you fire at your own fleet.
      final myTurn = _chaos || !_p2Active;
      gridFirable = !halfIsP1 && inBattle && myTurn && !_projP1.visible;
    } else {
      // Shared screen: the active player fires at the other half, whether
      // that other player is a human sitting opposite or the AI.
      // `_p2Active` is kept current by `_passTurn` in both those modes.
      gridFirable = (halfIsP1 == _p2Active) &&
          inBattle &&
          !_projP1.visible &&
          !_projP2.visible;
    }

    // MANOEUVRE mode: your own fleet can still run between shots. Only
    // ever on your OWN half, and locked while a shell is actually inbound
    // at this grid — a ship can't be yanked out from under a shot that is
    // already in the air.
    final manoeuvring = _manoeuvre &&
        halfIsP1 &&
        inBattle &&
        controller.phase == BattlePhase.battling &&
        !_projP2.visible;

    // Which half gets the scrim.
    final bool dimThisHalf;
    if (_chaos) {
      // No active side at all — nothing to signal.
      dimThisHalf = false;
    } else if (_manoeuvre) {
      // The scrim goes over the ENEMY grid while you can't shoot at it —
      // never over your own board, which is the one you need to see and
      // work on, and which stays lit whichever turn it is. (Your own
      // cannon is parked at the back in this mode so it can't sit on top
      // of the fleet you're rearranging — see `_slideFor` — so your half
      // carries no turn cue at all. Theirs carries both: their gun slides
      // out AND the scrim lifts.)
      dimThisHalf = !halfIsP1 && _p2Active;
    } else {
      // Spotlight: dim the firing player's own (inert) board so attention
      // stays on the live target grid.
      dimThisHalf = halfIsP1 != _p2Active;
    }

    final board = halfIsP1 ? controller.boards[0] : controller.boards[1];

    // Cannonball currently in flight toward THIS half's grid — drives the
    // targeting reticle below for exactly as long as the shot is airborne,
    // disappearing the instant it lands (`_tryResolveImpact` clears the
    // pending cell right as the hit/miss marker appears). Each half is only
    // ever the target of the OTHER half's gun.
    final aimCell = halfIsP1 ? _projP2.pendingCell : _projP1.pendingCell;

    // Once the match is over, both fleets are common knowledge — reveal
    // every ship on every grid (not just the sunk ones) as a final
    // "here's where everything was" recap before heading to the result
    // screen, instead of the empty-grid secrecy rule that applies mid-game.
    final gameOver = controller.phase == BattlePhase.finished;
    final fleetSkin = look.skin;

    // Whether this half's fleet is drawn on the board at all.
    //
    // The "empty grid" rule exists so a player can't read their
    // opponent's fleet off a shared screen. With one player per device
    // that no longer applies to your OWN board: those are your ships, on
    // your side of the water, and hiding them from you buys nothing — so
    // in every network mode and against the AI, your own fleet is drawn.
    // Local pass-and-play still hides both fleets, because there the two
    // players really are looking at the same screen.
    final showOwnFleet = (_lan || controller.mode == GameMode.vsAI) && halfIsP1;
    // Mid-match, draw the LANDED-only view (see `_visibleOwnShipsCache`) so
    // a hit crater / sunk graphic never appears on your own ship ahead of
    // its cannonball actually reaching the grid. Once the match is over
    // there's no more incoming fire to animate, so the raw board (both
    // fleets, fully revealed) is shown directly.
    final shipsOnGrid = gameOver
        ? board.ships
        : (showOwnFleet ? (_visibleOwnShipsCache[halfIsP1] ?? board.ships) : null);

    // Only show markers whose cannonball has already landed. (PERF: these
    // come from the per-frame cache refreshed once in build() — see
    // _refreshDerivedCache — instead of being recomputed here on every
    // 100ms cooldown tick.)
    final events = _eventsCache[halfIsP1] ?? const [];
    final shownShots = _shotsCache[halfIsP1] ??
        List.generate(kBoardSize, (_) => List.filled(kBoardSize, 0));

    // Ships that have been fully sunk on THIS half's own board get
    // revealed on the grid in their destroyed form — common knowledge to
    // both players once a ship goes down, regardless of the "empty grid"
    // rule that otherwise hides ship positions. Same gating (and the same
    // helper) drives the destroyed-ship preview in the middle status band
    // — see `_revealedSunkNames`.
    // Cached (stable identity between real state changes) — see the PERF
    // note in `_refreshDerivedCache`. Do NOT rebuild this list here: the
    // grid painter compares it by identity, so a fresh list every build
    // silently forces a full repaint of every mark on the board.
    final sunkShips = _destroyedShipsCache[halfIsP1] ?? const <PlacedShip>[];

    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        // Bigger board: the grid fills the half's full width/height with
        // no reserved side or top margin — same 10×10 grid, just as large
        // as the available space allows (still a perfect square). Every
        // mode uses this identical layout, chaos included: the only thing
        // chaos changes is that the cannon never leaves its parked spot,
        // and therefore where the cannonball is launched from.
        final gridSide = math.min(w, halfH);
        final cell = gridSide / kBoardSize;
        final gridLeft = (w - gridSide) / 2;
        final cannonSize = gridSide * 0.24;
        // A family skin's gun is drawn at its OWN, bigger widget size —
        // see `CannonWidget.gameplaySizeScaleOf` — so it reads at the
        // same on-screen size as a legacy gun instead of looking small
        // next to one. Legacy skins get a scale of 1.0, i.e. no change.
        final cannonRenderSize =
            cannonSize * CannonWidget.gameplaySizeScaleOf(_cannonSkinFor(halfIsP1));

        // Every half is laid out the same way in principle: grid against
        // the MIDDLE BAND, cannon out past the grid at the far edge of
        // the screen — the "back" of that player's own waters.
        //
        // Normally the 180° RotatedBox around the top half achieves that
        // for free, so both halves can use one identical local layout
        // (grid at local y=0, cannon below it). When that rotation is
        // switched off for LAN, the top half has to produce the same
        // ARRANGEMENT without it, so its grid moves to the bottom of the
        // half and its cannon sits above, muzzle pointing down.
        final flipLayout = isTopHalf && !_mirrorTopHalf;

        final gridTop = flipLayout ? halfH - gridSide : 0.0;

        // Where the cannon sits when it isn't slid out — just past the
        // grid's outer edge, the "back" of this player's own waters. The
        // same position in every mode; in chaos the cannon simply never
        // leaves it. Deliberately NOT clamped back inside the half — on
        // short/tight halves such a clamp used to pull the cannon in until
        // its circle covered the grid's outer rows. The half's Stack uses
        // Clip.none, so spilling past the half's own edge is fine and by
        // design; covering the board is not.
        final cannonCenter = flipLayout
            ? Offset(w / 2, gridTop - cannonRenderSize * 0.55)
            : Offset(w / 2, gridTop + gridSide + cannonRenderSize * 0.55);
        // Which way the barrel points, in this half's own local space.
        final muzzleLocalDir = flipLayout ? 1.0 : -1.0;

        // Cannon "ready" (active) position: the actual MIDDLE of this
        // player's own grid — a clear, unmissable "your turn" indicator.
        // Safe to overlap the grid here: a player's OWN grid is never
        // tappable during their OWN turn (only the opponent's grid is),
        // so sitting on top of it doesn't block anything. In chaos mode
        // the cannon never travels here at all (see `_slideFor`).
        final gridCenterLocal = Offset(w / 2, gridTop + gridSide / 2);

        // Record screen-space geometry (accounting for the top half's
        // rotation, where it applies) so cannonballs can fly between
        // halves.
        _geom[isTopHalf] = _HalfGeom(
          gridLeft: gridLeft,
          gridTop: gridTop,
          cell: cell,
          halfTopY: halfTopY,
          halfH: halfH,
          halfW: w,
          cannonCenter: cannonCenter,
          gridCenterLocal: gridCenterLocal,
          cannonSize: cannonSize,
          cannonRenderSize: cannonRenderSize,
          muzzleLocalDir: muzzleLocalDir,
          rotated: isTopHalf && _mirrorTopHalf,
        );

        return Container(
          width: double.infinity,
          height: halfH,
          color: gameplayTheme.deck,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Own grid
              Positioned(
                left: gridLeft,
                top: gridTop,
                child: SizedBox(
                  width: gridSide,
                  height: gridSide,
                  child: BattleGrid(
                    key: ValueKey('grid-$halfIsP1'),
                    shots: shownShots,
                    // The ENEMY's grid stays empty — guessing where their
                    // fleet hides is the game. Your own fleet is drawn
                    // (see `showOwnFleet`), and once the match is over
                    // both fleets are revealed as a final recap.
                    ships: shipsOnGrid,
                    skin: shipsOnGrid == null ? null : fleetSkin,
                    destroyedShips:
                        (gameOver || showOwnFleet) ? const [] : sunkShips,
                    enabled: gridFirable,
                    glowColor: gameplayTheme.accent,
                    cellColor: gameplayTheme.grid,
                    // Each half is painted in ITS OWNER's battlefield, so
                    // in a network match you fight across two different
                    // seas at once — your ice against their basalt.
                    boardFamily:
                        FleetFamilies.byKey(gameplayTheme.familyKey),
                    gridLineColor: gameplayTheme.gridLine,
                    recentEvents: events,
                    aimCell: aimCell,
                    previewShip: manoeuvring ? _movePreview : null,
                    previewValid: _movePreviewValid,
                    // Tapping the opponent's grid fires at it immediately.
                    onTapCell: gridFirable
                        ? (r, c) => _fireAtCell(controller, r: r, c: c)
                        : null,
                    // MANOEUVRE mode: your own undamaged ships can be
                    // dragged to new water between shots. Only ever wired
                    // up on your OWN half — see `manoeuvring`.
                    onShipDragUpdate:
                        manoeuvring ? (k, r, c) => _previewMove(controller, k, r, c) : null,
                    onShipDragEnd:
                        manoeuvring ? (k, r, c) => _commitMove(controller, k, r, c) : null,
                    onShipTap: manoeuvring ? (k) => _rotateOwnShip(controller, k) : null,
                    // Only hulls that are still undamaged may move; one
                    // hit pins a ship for the rest of the match.
                    movableShips: manoeuvring
                        ? {
                            for (final s in board.ships)
                              if (s.hitIndices.isEmpty) s.spec.kind
                          }
                        : null,
                  ),
                ),
              ),

              // Turn-highlight dim: a soft scrim over the ACTIVE player's
              // OWN grid (this half's owner is the one currently firing).
              // That grid isn't tappable right now — you fire at the
              // OPPONENT's grid, on the other half; see `gridFirable`
              // above — so dimming it acts as a spotlight: it
              // de-emphasizes the inert board you don't need and keeps
              // attention on the live, interactive target grid instead.
              // Uses a small FIXED glow margin (clamped to this half's own
              // bounds) instead of a percentage of gridSide — the old
              // percentage-based halo could balloon well past the grid
              // (and even past the screen edge) on larger boards, which
              // read as the effect "leaking" outside the grid.
              //
              // PERF (mobile jank): this used to be a `BackdropFilter`
              // Gaussian blur. Since `isActiveHalf` is true for one half
              // or the other for the ENTIRE match (turns just alternate
              // which one), that meant a live backdrop-sampled blur ran
              // continuously — not just during a brief transition — for
              // the whole game. BackdropFilter is one of the most
              // expensive operations Flutter can do per frame (it has to
              // re-sample and Gaussian-blur everything already painted
              // behind it), and unlike the grid's own repaint cost this
              // one didn't even scale with match progress — it was just a
              // constant, avoidable tax on every frame, brutal on
              // low/mid-range GPUs. A plain translucent scrim achieves the
              // same "de-emphasize this board" spotlight effect at
              // near-zero cost (a flat color fill, no backdrop sampling),
              // so the grid underneath just dims instead of blurring.
              Builder(builder: (context) {
                const haloMargin = 10.0;
                final haloLeft = math.max(0.0, gridLeft - haloMargin);
                final haloTop = math.max(0.0, gridTop - haloMargin);
                final haloRight =
                    math.min(w, gridLeft + gridSide + haloMargin);
                final haloBottom =
                    math.min(halfH, gridTop + gridSide + haloMargin);
                return Positioned(
                  left: haloLeft,
                  top: haloTop,
                  width: haloRight - haloLeft,
                  height: haloBottom - haloTop,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 320),
                      opacity: dimThisHalf && inBattle ? 1 : 0,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: Color.lerp(Colors.black, accent, 0.35)!
                              .withValues(alpha: 0.30),
                        ),
                      ),
                    ),
                  ),
                );
              }),

              // Own cannon. In a turn-based match it slides to the MIDDLE
              // of its own grid during its owner's turn — a big,
              // unmissable "your turn" indicator — with a little overshoot
              // bounce on the way in, and parks back at the BACK of its
              // grid the rest of the time. In chaos mode there are no
              // turns to signal, so it simply never leaves the back
              // (`_slideFor` pins it there) and every shot is lobbed the
              // full length of the board from behind its own waters.
              AnimatedBuilder(
                animation: _slideCtrl,
                builder: (context, _) {
                  final raw = _slideFor(halfIsP1);
                  final slide = Curves.easeOutBack.transform(raw.clamp(0.0, 1.0));
                  final pos =
                      Offset.lerp(cannonCenter, gridCenterLocal, slide)!;
                  return Positioned(
                    left: pos.dx - cannonRenderSize / 2,
                    top: pos.dy - cannonRenderSize / 2,
                    // The cannon is purely a visual indicator here (onFire
                    // is always null below — firing happens by tapping the
                    // enemy grid). IgnorePointer guarantees it can never
                    // swallow a tap meant for a grid cell underneath it,
                    // even if it still visually grazes the grid's edge on
                    // an unusual screen size.
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 250),
                        opacity: gameOver ? 0 : 1,
                        // PERF: the cooldown RING is the only thing on this
                        // screen that needs a 10Hz refresh, so it's the only
                        // thing subscribed to the 100ms tick now (see
                        // `GameController.cooldownTick`). Previously that
                        // tick called `notifyListeners()`, rebuilding — and
                        // repainting — the entire board 10× a second just to
                        // advance these two arcs.
                        child: ValueListenableBuilder<int>(
                          valueListenable: controller.cooldownTick,
                          builder: (context, _, __) {
                            final cannon = CannonWidget(
                              // Each side fires the gun ITS owner bought.
                              skin: _cannonSkinFor(halfIsP1),
                              cooldownFraction: halfIsP1
                                  ? controller.cooldownFraction1
                                  : controller.cooldownFraction2,
                              enabled: controller.battling && !_countingDown,
                              size: cannonRenderSize,
                              fireTrigger: cannonStream.stream,
                              readyTrigger: readyStream.stream,
                              accentOverride: accent,
                              // Firing happens with a single tap on the
                              // enemy grid cell (see gridFirable /
                              // onTapCell above); the cannon itself just
                              // reacts (recoil + muzzle flash) as a "shot
                              // fired" indicator.
                              onFire: null,
                            );
                            // CannonWidget always draws its barrel toward
                            // the top of its own box. When this half isn't
                            // rotated but its cannon sits ABOVE its grid
                            // (LAN top half), the barrel has to be spun to
                            // point back down at the water it's firing
                            // over — matching `muzzleLocalDir`, which is
                            // what the cannonball's spawn point uses.
                            return flipLayout
                                ? RotatedBox(quarterTurns: 2, child: cannon)
                                : cannon;
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),

            ],
          ),
        );
      },
    );
  }

  // -------------------------------------------------------- MIDDLE BAND

  Widget _buildMiddleBand(
      GameController controller, bool bottomIsP1, double bandH) {
    final topBoard = bottomIsP1 ? controller.boards[1] : controller.boards[0];
    final bottomBoard =
        bottomIsP1 ? controller.boards[0] : controller.boards[1];
    // BUGFIX (dim direction was backwards): whichever side is CURRENTLY
    // FIRING should have its own fleet row dimmed (a spotlight effect —
    // de-emphasize your own status strip while it's your turn to aim,
    // since it's not what you're looking at), and the WAITING opponent's
    // row should stay fully visible. The old formula (`faded: … !=
    // activeIsP1`) did the opposite: it dimmed the WAITING side and kept
    // the ACTIVE player's own row at full brightness — e.g. while player
    // 1 was firing, player 1's OWN row stayed bright and player 2's
    // dimmed, and vice versa on player 2's turn. Flipped to `==
    // activeIsP1` so the row that dims is always the row belonging to
    // whoever is currently firing.
    final activeIsP1 = !_p2Active;
    final topIsP1Fleet = !bottomIsP1;
    final bottomIsP1Fleet = bottomIsP1;
    // Chaos mode has no "currently firing" side, so neither row dims.
    bool fadedFor(bool isP1Fleet) => !_chaos && (isP1Fleet == activeIsP1);

    // Each row wears its OWN captain's battlefield deck. The top row used
    // to be a hardcoded steel blue, which meant Player 2's strip stayed
    // stubbornly blue whatever either of them had equipped — the one
    // patch of default palette left on a fully themed screen. A hairline
    // keeps the two rows readable as two rows now that they can be the
    // same colour.
    final topDeck = _themeFor(topIsP1Fleet).deck;
    final bottomDeck = _themeFor(bottomIsP1Fleet).deck;

    // Room for the chat tab on the left, and for the EXIT pill on the
    // right. Fixed regardless of whether the chat is open: the revealed
    // button floats over the band as an overlay (see the Positioned
    // below) instead of carving out extra padding, so opening it no
    // longer reflows — and doesn't shrink — the ships in either fleet
    // strip.
    const leftInset = 56.0;

    Widget row(Board board, bool isP1Fleet, Color deck) => Expanded(
          child: Container(
            color: deck,
            padding: const EdgeInsets.only(left: leftInset, right: 56),
            child: _statusRow(board,
                faded: fadedFor(isP1Fleet),
                isP1Fleet: isP1Fleet,
                revealedSunkNames: _revealedSunkNames(isP1Fleet)),
          ),
        );

    return SizedBox(
      height: bandH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            children: [
              row(topBoard, topIsP1Fleet, topDeck),
              Container(
                height: 1.5,
                color: AppColors.outline.withValues(alpha: 0.45),
              ),
              row(bottomBoard, bottomIsP1Fleet, bottomDeck),
            ],
          ),
          Positioned(
            left: -2,
            top: 4,
            bottom: 4,
            child: _DotsBadge(
              topLeft: 5 - topBoard.sunkCount,
              bottomLeft: 5 - bottomBoard.sunkCount,
              // Takes its colour from the same place the hulls do, so the
              // badge can't disagree with the ships it's counting —
              // whether that's the plain side colour or a skin.
              topColor: _lookFor(topIsP1Fleet).color,
              bottomColor: _lookFor(bottomIsP1Fleet).color,
            ),
          ),
          // The middle band is the one strip of this screen that isn't a
          // grid, which makes it the only place a chat control can live
          // without sitting on top of somebody's board. It stays a thin
          // tab beside the ship counter until it is swiped out. The
          // revealed button floats as an overlay on top of the fleet
          // strips (it's drawn last, after `row`, in this Stack) rather
          // than pushing their padding out, so the ships underneath never
          // resize when it opens.
          if (_lan)
            Positioned(
              left: 34,
              top: (bandH - 34) / 2,
              child: MatchChatReveal(size: 34),
            ),
          Positioned(
            right: -2,
            top: 2,
            bottom: 2,
            child: _ExitPill(onTap: () => _confirmSurrender(controller)),
          ),
        ],
      ),
    );
  }

  /// Whether the fleet on a given half flies RED colours.
  ///
  /// Shared screen (local pass-and-play / vs AI): Player 1 is red and
  /// Player 2 is blue, exactly as before. LAN: the two players are told
  /// apart by network role instead — the host commands red and whoever
  /// joined commands blue — so each device paints its own bottom-half
  /// fleet in ITS OWN colour and the opponent's top-half fleet in the
  /// other, and the two screens agree. Used for the ship skins, the turn
  /// accent, and the remaining-ships badge, so a side can never end up
  /// with two different colours in different corners of the screen.
  bool _fleetIsRed(bool isP1Fleet) => isP1Fleet != _iAmBlue;

  Widget _statusRow(Board board,
      {required bool faded,
      required bool isP1Fleet,
      required Set<String> revealedSunkNames}) {
    // The fleet strip shows each side's ships in that side's OWN skin, so
    // it always matches the hulls actually on the board — including the
    // red/blue fallback for a captain who hasn't equipped anything.
    final skin = _shipSkinFor(isP1Fleet);
    // Per-cell pixel unit for the fleet row: each icon is drawn at
    // `unit * spec.size` wide with a constant beam (height), so a
    // 5-cell carrier reads clearly longer than a 2-cell destroyer — the
    // same relative proportions those ships have on the actual battle
    // grid — instead of every icon sharing one fixed bounding box
    // regardless of the ship's real length.
    //
    // Measured rather than fixed, because the row's width is not fixed:
    // the chat tab takes a slice of it when it is swiped open, and a
    // narrow phone has less to give in the first place. At a hard 11.5
    // the five hulls total 195px of unshrinkable content and the Row
    // simply overflows once the space drops below that. The cap keeps
    // the size the strip has always had whenever there is room for it.
    const maxUnit = 11.5;
    // Total cells across the whole fleet (5+4+3+3+2), plus a little
    // breathing room so the ships never quite touch.
    const fleetCells = 17.0;
    return LayoutBuilder(builder: (context, box) {
      final unit = box.maxWidth.isFinite
          ? math.min(maxUnit, (box.maxWidth * 0.86) / fleetCells)
          : maxUnit;
      final beam = 26.0 * (unit / maxUnit);
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final spec in kFleet)
            Builder(builder: (context) {
              final ship = board.shipOfKind(spec.kind);
              // REDESIGN (destroyed ship preview): a ship only switches to
              // its destroyed model once its sinking shot has visually
              // landed (see `_revealedSunkNames`) — not the instant its last
              // cell is logically hit, and not on any earlier, non-final
              // hit either: the preview stays looking exactly like a normal
              // active ship right up until that moment (hitCount is only
              // ever passed once destroyed==true), matching "a ship remains
              // active until all of its cells are destroyed". No X overlay:
              // the destroyed state IS the ship's own wrecked model (charred
              // hull, damage craters, smoke — see ShipPainter), so it stays
              // recognizable as the same ship type instead of being replaced
              // by a generic icon.
              final destroyed = ship != null &&
                  ship.isSunk &&
                  revealedSunkNames.contains(spec.name);
              return Opacity(
                opacity: faded ? 0.38 : 1.0,
                child: AnimatedShip(
                  spec: spec,
                  skin: skin,
                  width: unit * spec.size,
                  height: beam,
                  sunk: destroyed,
                  hitCount: destroyed ? spec.size : 0,
                ),
              );
            }),
        ],
      );
    });
  }

  // ---------------------------------------------------------- OVERLAYS

  Widget _countdownOverlay(double bandH) {
    final label = _countdownGo ? 'GO!' : '$_countdownValue';
    Widget number({required bool mirrored}) => Center(
          child: RotatedBox(
            quarterTurns: mirrored ? 2 : 0,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 150,
                fontWeight: FontWeight.w900,
                color: Colors.white.withValues(alpha: 0.75),
                shadows: const [
                  Shadow(color: Color(0x55000000), blurRadius: 8),
                ],
              ),
            ),
          ),
        );
    return Positioned.fill(
      child: IgnorePointer(
        child: Column(
          children: [
            // The top copy is only flipped when someone is actually
            // sitting on that side of the device — on a LAN screen the
            // single player reads both copies the same way up.
            Expanded(child: number(mirrored: _mirrorTopHalf)),
            SizedBox(height: bandH),
            Expanded(child: number(mirrored: false)),
          ],
        ),
      ),
    );
  }

  /// Solid bar over the middle band once the match is finished — tapping
  /// CONTINUE is the only way to leave this screen at that point (see
  /// _goToResult), so both fleets stay fully revealed until the player
  /// is actually done looking.
  Widget _gameOverBar() {
    return Container(
      color: AppColors.navy,
      alignment: Alignment.center,
      child: NeonButton(
        label: 'CONTINUE',
        icon: Icons.arrow_forward,
        color: AppColors.seafoam,
        compact: true,
        onPressed: _goToResult,
      ),
    );
  }

  /// The projectile in flight.
  ///
  /// A shell belongs to the gun that fired it: a family cannon's shell is
  /// keyed off its family, and each of the nine originals now draws its
  /// own shell off its own catalogue id (see `legacy_shell_art.dart`) —
  /// the same shell already shown on its Shipyard card, so what you buy
  /// is what you fire. `legacyId` is only null in the defensive case
  /// where a loadout names neither a family nor a known original, which
  /// falls back to the plain iron ball rather than drawing nothing.
  Widget _cannonball(double d, {FleetFamily? family, String? legacyId}) {
    if (family != null) {
      // The design's shell box is taller than wide (the tail hangs below
      // the body), so the drawing is given that room and centred on the
      // same point the iron ball occupies.
      final h = d / kShellBoxAspect;
      return SizedBox(
        width: d,
        height: d,
        child: OverflowBox(
          maxWidth: d,
          maxHeight: h,
          child: CustomPaint(
            size: Size(d, h),
            painter: _FamilyShellPainter(family),
          ),
        ),
      );
    }
    if (legacyId != null) {
      // Legacy shells are authored in the same box as family ones (see
      // `legacy_shell_art.dart`), so the same letterboxing applies.
      final h = d / kShellBoxAspect;
      return SizedBox(
        width: d,
        height: d,
        child: OverflowBox(
          maxWidth: d,
          maxHeight: h,
          child: CustomPaint(
            size: Size(d, h),
            painter: _LegacyCannonballPainter(legacyId),
          ),
        ),
      );
    }
    return _ironBall(d);
  }

  Widget _ironBall(double d) => SizedBox(
        width: d,
        height: d,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Core sphere: richer three-stop metal gradient + a dark rim
            // stroke so it reads as a solid iron ball rather than a flat
            // dot, plus a soft drop shadow for weight.
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  center: Alignment(-0.38, -0.42),
                  radius: 0.95,
                  stops: [0.0, 0.45, 1.0],
                  colors: [
                    Color(0xFFC3CBD3),
                    Color(0xFF6E7883),
                    Color(0xFF1D232A),
                  ],
                ),
                border: Border.all(
                  color: const Color(0xFF12161B),
                  width: math.max(1.0, d * 0.045),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: d * 0.18,
                    offset: Offset(0, d * 0.10),
                  ),
                ],
              ),
            ),
            // REDESIGN: a faint cast-iron equatorial seam + a soft rim-light
            // opposite the main highlight — cheap (two strokes, no extra
            // particles) but enough to read as a forged iron ball rather
            // than a flat gradient dot.
            CustomPaint(size: Size(d, d), painter: const _CannonballDetailPainter()),
            // Small specular highlight — the "shine" that sells a hard,
            // polished sphere.
            Positioned(
              left: d * 0.17,
              top: d * 0.13,
              child: Container(
                width: d * 0.24,
                height: d * 0.17,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ),
          ],
        ),
      );

  Future<void> _confirmSurrender(GameController controller) async {
    // The original of the app-wide confirm box — now shown through
    // [showCartoonConfirm] so the shipyard's buy prompts and this one can
    // never drift apart in look or motion.
    final confirmed = await showCartoonConfirm(
      context,
      title: 'SURRENDER?',
      message: 'Abandon the battle?\nThis counts as a loss.',
      cancelLabel: 'FIGHT ON',
      confirmLabel: 'SURRENDER',
    );
    if (confirmed) controller.surrender();
  }
}

/// Adds a faint cast-iron equatorial seam and a soft opposite-side
/// rim-light to the cannonball — see `_cannonball`. Kept as a separate
/// tiny painter (rather than folded into the Container/BoxDecoration
/// sphere) since neither of those effects is expressible as a plain box
/// decoration. Stateless and const-constructible; `shouldRepaint` is safe
/// to leave `false` since the ball's shrink-over-flight effect already
/// forces a repaint via its changing `size`, not via any field here.
class _CannonballDetailPainter extends CustomPainter {
  const _CannonballDetailPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    canvas.drawOval(
      Rect.fromCenter(center: center, width: r * 1.86, height: r * 0.55),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.6, r * 0.05),
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r * 0.92),
      math.pi * 0.15,
      math.pi * 0.35,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.14)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.16
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _CannonballDetailPainter oldDelegate) => false;
}

/// One airborne cannonball. There is one of these per SHOOTER (see
/// `_projP1`/`_projP2`), so both sides can have a shot in the air at the
/// same time — the normal case in chaos mode.
class _Projectile {
  _Projectile({
    required this.byP1,
    required TickerProvider vsync,
    required Duration duration,
  }) : ctrl = AnimationController(vsync: vsync, duration: duration);

  /// True if this slot belongs to the BOTTOM half's owner. Also the value
  /// matched against `CombatEvent.byPlayer` when looking up what this
  /// shot actually did — see `_tryResolveImpact`.
  final bool byP1;

  final AnimationController ctrl;

  /// Flight path, in absolute screen coordinates.
  Offset from = Offset.zero;
  Offset to = Offset.zero;

  /// Target grid's cell size, which the ball is scaled against.
  double cell = 32;

  /// Whether a ball is airborne in this slot right now.
  bool visible = false;

  /// The cell this shot is headed for, held from launch until its impact
  /// is resolved. Doubles as the target half's aiming reticle.
  List<int>? pendingCell;

  void dispose() => ctrl.dispose();
}

/// Screen-space geometry of one half (used for cannonball trajectories).
class _HalfGeom {
  final double gridLeft;
  final double gridTop;
  final double cell;
  final double halfTopY;
  final double halfH;
  final double halfW;
  final Offset cannonCenter; // parked pos within the half (local space)
  final Offset gridCenterLocal; // grid center within the half (local space)
  final double cannonSize;

  /// The size the equipped gun is ACTUALLY drawn at — `cannonSize` for
  /// a legacy skin, or `cannonSize * CannonWidget.gameplaySizeScaleOf`
  /// for a family skin (see that getter for why a family gun needs to
  /// be drawn bigger to read at the same on-screen size as a legacy
  /// one). `_cannonMouth` reads THIS, not `cannonSize`, when it spawns
  /// the shell, so the ball keeps launching from the gun's real,
  /// currently-drawn muzzle tip regardless of which skin is equipped.
  final double cannonRenderSize;

  /// Which way this half's barrel points in the half's own LOCAL space:
  /// −1 toward local −y (cannon sits below its grid), +1 toward local +y
  /// (cannon sits above it). Always points AT the half's own grid, and so
  /// out across the board at the opponent.
  final double muzzleLocalDir;

  /// Whether this half is drawn inside a 180° RotatedBox — true for the
  /// top half only when both players share the screen.
  final bool rotated;

  const _HalfGeom({
    required this.gridLeft,
    required this.gridTop,
    required this.cell,
    required this.halfTopY,
    required this.halfH,
    required this.halfW,
    required this.cannonCenter,
    required this.gridCenterLocal,
    required this.cannonSize,
    required this.cannonRenderSize,
    required this.muzzleLocalDir,
    required this.rotated,
  });

  /// Absolute screen position of a grid cell center, accounting for the
  /// 180° rotation of the top half.
  Offset cellCenterScreen(int r, int c) {
    final lx = gridLeft + c * cell + cell / 2;
    final ly = gridTop + r * cell + cell / 2;
    if (rotated) {
      return Offset(halfW - lx, halfTopY + (halfH - ly));
    }
    return Offset(lx, halfTopY + ly);
  }
}

/// White pill badge pinned to the left edge of the status band showing
/// how many ships each side has left.
class _DotsBadge extends StatelessWidget {
  final int topLeft;
  final int bottomLeft;
  final Color topColor;
  final Color bottomColor;
  const _DotsBadge({
    required this.topLeft,
    required this.bottomLeft,
    required this.topColor,
    required this.bottomColor,
  });

  // The ring and the digit inside it are both painted straight in the
  // fleet's colour, sitting on the badge's fixed AppColors.cream disc.
  // That reads fine for the dark/mid-tone skins (Crimson Armada, Abyss
  // Ghost, Midnight Ops, the family sets, the red/blue side fallback…)
  // but Arctic Storm and Rime Wardens are near-white hulls, and a
  // near-white ring around a near-white number on a near-white disc is
  // effectively invisible — exactly the same failure the name chips
  // and vote badges had before [FleetLook.ink] started picking ink off
  // the hull's own luminance instead of trusting every hull to be dark
  // enough to read. Same fix here: past the luminance cutoff where a
  // hull stops contrasting with the cream disc, fall back to the fixed
  // dark outline colour instead of the washed-out hull tone.
  Color _legibleOn(Color color) =>
      color.computeLuminance() > 0.5 ? AppColors.outline : color;

  @override
  Widget build(BuildContext context) {
    Widget dot(Color color, int count) {
      final ink = _legibleOn(color);
      return Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.cream,
          border: Border.all(color: ink, width: 3),
        ),
        child: Center(
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w900,
              color: ink,
              height: 1,
            ),
          ),
        ),
      );
    }

    return Container(
      width: 34,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.horizontal(right: Radius.circular(18)),
        boxShadow: [BoxShadow(color: Color(0x33000000), offset: Offset(2, 2))],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          dot(topColor, topLeft),
          const SizedBox(height: 5),
          dot(bottomColor, bottomLeft),
        ],
      ),
    );
  }
}

/// Tall vertical EXIT pill pinned to the right edge of the status band.
class _ExitPill extends StatelessWidget {
  final VoidCallback onTap;
  const _ExitPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        SoundService.instance.click();
        onTap();
      },
      child: Container(
        width: 34,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.horizontal(left: Radius.circular(18)),
          boxShadow: [BoxShadow(color: Color(0x33000000), offset: Offset(-2, 2))],
        ),
        child: const Center(
          child: RotatedBox(
            quarterTurns: 1,
            child: Text(
              'EXIT',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12,
                letterSpacing: 2,
                color: AppColors.outline,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown over a live battle when the opponent's connection drops.
///
/// The match is NOT over: it is held open for
/// [NetworkService.kReconnectGraceSeconds] while the other player finds
/// their way back in (their device advertises the room again, so they can
/// rejoin from SCAN FOR GAMES — see `NetworkService._reopenForReturn`).
/// The waiting player can bail out early; either way, a match nobody
/// finished counts for nobody, so leaving from here records no result.
class _ReconnectOverlay extends StatelessWidget {
  final VoidCallback onAbandon;

  const _ReconnectOverlay({required this.onAbandon});

  @override
  Widget build(BuildContext context) {
    final net = context.watch<NetworkService>();
    if (!net.peerLost && !net.peerGone) return const SizedBox.shrink();

    final expired = net.peerGone;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.72),
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: cartoonBox(AppColors.navy, radius: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  expired ? Icons.person_off : Icons.wifi_tethering_off,
                  color: expired ? AppColors.hit : AppColors.gold,
                  size: 40,
                ),
                const SizedBox(height: 12),
                Text(
                  expired
                      ? '${net.peerName.toUpperCase()} DID NOT RETURN'
                      : '${net.peerName.toUpperCase()} LOST CONNECTION',
                  textAlign: TextAlign.center,
                  style: AppText.heading(size: 15),
                ),
                const SizedBox(height: 10),
                if (!expired) ...[
                  Text(
                    '${net.graceSecondsLeft}s',
                    style: AppText.title(size: 42, color: AppColors.gold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Holding the battle open. They can rejoin from\n'
                    'MULTIPLAYER → SCAN FOR GAMES.',
                    textAlign: TextAlign.center,
                    style: AppText.body(
                        size: 12,
                        color: AppColors.cream.withValues(alpha: 0.85)),
                  ),
                ] else
                  Text(
                    'The match is void — no win, no loss,\nand no RP for either captain.',
                    textAlign: TextAlign.center,
                    style: AppText.body(
                        size: 12,
                        color: AppColors.cream.withValues(alpha: 0.85)),
                  ),
                const SizedBox(height: 18),
                NeonButton(
                  label: expired ? 'BACK TO MENU' : 'LEAVE — NO RESULT',
                  icon: Icons.logout,
                  color: expired ? AppColors.blue : AppColors.inkSoft,
                  compact: true,
                  onPressed: onAbandon,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws a family's projectile into the flight layer.
///
/// Stateless and cheap — the shell has no animation of its own; the arc,
/// the shrink and the motion-trail ghosts all come from the projectile
/// layer, exactly as they did for the iron ball. Swapping the drawing
/// therefore changes what is in the air without touching how it flies.
class _FamilyShellPainter extends CustomPainter {
  final FleetFamily family;

  const _FamilyShellPainter(this.family);

  @override
  void paint(Canvas canvas, Size size) =>
      paintFamilyShell(canvas, size, family);

  @override
  bool shouldRepaint(covariant _FamilyShellPainter old) =>
      old.family.id != family.id;
}

/// Draws one of the nine original cannons' projectiles into the flight
/// layer — the [_FamilyShellPainter] counterpart for guns with no family.
/// Same reasoning: stateless, keyed off the cannon's own catalogue id
/// rather than anything that changes mid-flight.
class _LegacyCannonballPainter extends CustomPainter {
  final String cannonId;

  const _LegacyCannonballPainter(this.cannonId);

  @override
  void paint(Canvas canvas, Size size) =>
      paintLegacyShell(canvas, size, cannonId);

  @override
  bool shouldRepaint(covariant _LegacyCannonballPainter old) =>
      old.cannonId != cannonId;
}
