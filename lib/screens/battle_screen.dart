import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/game_models.dart';
import '../services/game_controller.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../widgets/battle_grid.dart';
import '../widgets/cannon_widget.dart';
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
  GameplayTheme get gameplayTheme => context.read<ProfileStore>().gameplayTheme;

  final _cannon1Fire = StreamController<void>.broadcast();
  final _cannon2Fire = StreamController<void>.broadcast();
  final _cannon1Ready = StreamController<void>.broadcast();
  final _cannon2Ready = StreamController<void>.broadcast();

  /// Local pass-and-play: whose turn it is (P1's grid stays on the BOTTOM,
  /// P2's on TOP — the halves never swap sides; players sit across from
  /// each other). Only the "whose turn" flag changes.
  bool _p2Active = false;

  bool _navigatedToResult = false;

  // ----- Countdown -----
  bool _countingDown = false;
  int _countdownValue = 3;
  bool _countdownGo = false;

  // ----- Cannonball flight + impact -----
  late final AnimationController _projCtrl;
  Offset _projFrom = Offset.zero;
  Offset _projTo = Offset.zero;
  double _projCell = 32;
  bool _showProjectile = false;
  List<int>? _pendingImpact; // cell waiting for the ball to land
  bool _pendingByP1 = true; // who fired the ball in flight
  ShotResult? _pendingResult; // outcome of the ball in flight

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
  List<int>? _cachedPendingImpactKey;
  bool _cachedPendingByP1 = true;
  final Map<bool, List<List<int>>> _shotsCache = {};
  final Map<bool, List<CombatEventLike>> _eventsCache = {};

  // Prevent the same AI event from being scheduled more than once while
  // the deliberate firing delay is waiting to expire.
  final Set<CombatEvent> _delayedOpponentEvents = <CombatEvent>{};

  @override
  void initState() {
    super.initState();
    SoundService.instance.stopMenuMusic();
    final controller = context.read<GameController>();
    controller.addListener(_onUpdate);

    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
      value: 1.0, // P1 starts active: P1 out at its grid, P2 parked at home
    );

    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );

    _projCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 430),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) {
          setState(() => _showProjectile = false);
          _resolveImpact();
        }
      });

    // Start-of-battle countdown (video: big 3-2-1 over both halves).
    if (controller.battling) {
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
      if (!e.byPlayer && age < 200 && mounted) {
        if (_projCtrl.isAnimating) {
          // Another ball is already mid-flight, so this event's impact is
          // shown immediately with no travel animation of its own — play
          // its sound right now too, since `_resolveImpact` (which will
          // fire later) is resolving a DIFFERENT, earlier pending shot.
          if (e.impactAt == null) {
            e.impactAt = null;
          }
        } else if (!_delayedOpponentEvents.contains(e)) {
          _delayedOpponentEvents.add(e);
          _launchOpponentBall(e);
        }
      }
    }
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
    if (top == null || bottom == null || _projCtrl.isAnimating) {
      // Never play an impact sound before the projectile reaches its cell.
      // If geometry is unavailable, keep the event pending for the next
      // frame instead of resolving it early.
      return;
    }
    // The AI's cannon may be slid out to its grid center (during its turn)
    // or parked at home — fire from wherever it currently sits.
    // P2/AI uses the inverse of the P1 slide controller.
    // During the AI turn the cannon moves out from home to the AI grid,
    // so the projectile must spawn from that same visible cannon position.
    final from = _cannonMouth(top, 1 - _slideCtrl.value);
    final to = bottom.cellCenterScreen(e.row, e.col) +
        _mouthDir(bottom) * (bottom.cannonSize * 0.25);
    setState(() {
      _pendingByP1 = false;
      _pendingImpact = [e.row, e.col];
      _pendingResult = e.result;
      _projFrom = from;
      _projTo = to;
      _projCell = bottom.cell;
      _showProjectile = true;
    });
    SoundService.instance.cannonFire();
    _cannon2Fire.add(null);
    _projCtrl.forward(from: 0);
  }

  void _resolveImpact() {
    final cell = _pendingImpact;
    final byP1 = _pendingByP1;
    final result = _pendingResult;
    _pendingImpact = null;
    _pendingResult = null;
    if (cell == null) return;
    final controller = context.read<GameController>();
    for (final e in controller.events.reversed) {
      if (e.row == cell[0] &&
          e.col == cell[1] &&
          e.byPlayer == byP1 &&
          e.impactAt == null) {
        e.impactAt = DateTime.now();
        break;
      }
    }
    controller.touch();
    // Hit/sunk/miss sound, right as the ball actually lands — synced to
    // the same moment as the shake below and the hit/miss/wreckage reveal
    // (see `sunkShips` in `_buildHalf`), instead of firing back at tap
    // time before the ball has visually gone anywhere.
    if (result != null) _playImpactSound(result);
    // Screen shake, right as the ball actually lands — never on a miss
    // (there's nothing to "hit"). Sinking a ship shakes harder than a
    // plain hit so a killing blow reads as more impactful.
    if (result == ShotResult.sunk) {
      _shake(_shakeSunkMagnitude);
    } else if (result == ShotResult.hit) {
      _shake(_shakeHitMagnitude);
    }
    // 1:1 video rule: a HIT lets the same player keep firing; only a MISS
    // passes the turn to the other player (local AND vs AI — same rule).
    // The handoff is seamless (no popup): the active flag flips, the
    // cannons slide (outgoing → home, incoming → its grid center) and the
    // newly-active cannon flashes "ready".
    if (controller.phase == BattlePhase.battling &&
        result == ShotResult.miss &&
        (controller.mode == GameMode.local ||
            controller.mode == GameMode.vsAI)) {
      final passToP2 = byP1; // P1 missed → P2's turn; P2/AI missed → P1's
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted || controller.phase != BattlePhase.battling) return;
        _passTurn(passToP2);
      });
    }
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
    if (_countingDown || _showProjectile) return;
    final byP1 = !_p2Active;
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
    _launchBall(controller, byP1: byP1, r: r, c: c, res: res);
  }

  /// Shared ball-launch used by the player's cannon tap.
  void _launchBall(
    GameController controller, {
    required bool byP1,
    required int r,
    required int c,
    required ShotResult res,
  }) {
    final top = _geom[true];
    final bottom = _geom[false];
    if (top == null || bottom == null) return;
    // The shooter fires from wherever its cannon currently sits (slid out
    // to its grid center during its turn). The ball arcs toward the aimed
    // cell on the OPPONENT's grid.
    final shooterGeom = byP1 ? bottom : top;
    final targetGeom = byP1 ? top : bottom;
    final from =
        _cannonMouth(shooterGeom, byP1 ? _slideCtrl.value : 1 - _slideCtrl.value);
    final to = targetGeom.cellCenterScreen(r, c) +
        _mouthDir(targetGeom) * (targetGeom.cannonSize * 0.25);
    setState(() {
      _pendingByP1 = byP1;
      _pendingImpact = [r, c];
      _pendingResult = res;
      _projFrom = from;
      _projTo = to;
      _projCell = targetGeom.cell;
      _showProjectile = true;
    });
    SoundService.instance.cannonFire();
    (byP1 ? _cannon1Fire : _cannon2Fire).add(null);
    _projCtrl.forward(from: 0);
  }

  // ----------------------------------------------------- CANNON SLIDE ---

  /// Unit direction from a half's cannon toward its grid mouth, in SCREEN
  /// space (+y = down the screen). For the upright bottom half the mouth
  /// faces up (−y); for the 180°-rotated top half it faces down (+y).
  Offset _mouthDir(_HalfGeom g) => Offset(0, g.rotated ? 1.0 : -1.0);

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
  Offset _cannonMouth(_HalfGeom g, double t) {
    final c = _cannonCenterLocal(g, t);
    final lx = c.dx;
    final ly = c.dy - g.cannonSize * 0.25;
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
    _projCtrl.dispose();
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
    // LOCAL FIX: the halves NEVER swap sides — P1 is always on the bottom
    // (upright) and P2 always on top (rotated 180°), because the players
    // sit across from each other. Only the "whose turn" flag changes.
    const bottomIsP1 = true;

    return Scaffold(
      body: Container(
        color: AppColors.coralVideo,
        child: SafeArea(
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
                      // ===== TOP HALF — P2, rotated 180° (fixed side) =====
                      SizedBox(
                        height: halfH,
                        child: RotatedBox(
                          quarterTurns: 2,
                          child: _buildHalf(
                            controller,
                            profile,
                            halfIsP1: !bottomIsP1,
                            isTopHalf: true,
                            halfH: halfH,
                            halfTopY: 0,
                            bottomIsP1: bottomIsP1,
                          ),
                        ),
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
                  if (_showProjectile)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _projCtrl,
                          builder: (context, _) {
                            final t = _projCtrl.value;
                            // Vertical ARC for the up-and-down lob effect,
                            // reused for the ball itself and its trail.
                            Offset posAt(double tt) {
                              final cl = tt.clamp(0.0, 1.0);
                              final p = Offset.lerp(_projFrom, _projTo, cl)!;
                              final arc = math.sin(cl * math.pi) * _projCell * 3.0;
                              return p - Offset(0, arc);
                            }

                            // Cannonball launches noticeably LARGER than
                            // the target cell and slowly SHRINKS the whole
                            // way there, settling to exactly the grid
                            // cell's size right as it lands — a clear
                            // "incoming shot" effect that telegraphs
                            // where the ball is about to hit.
                            double diamAt(double tt) =>
                                _projCell * (2.6 - 1.6 * tt.clamp(0.0, 1.0));

                            final pos = posAt(t);
                            final d = diamAt(t);
                            // Continuous spin while airborne, sold by the
                            // sphere's highlight sweeping around it.
                            final spin = t * math.pi * 6;

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
                                  child: _cannonball(gd),
                                ),
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
                                    angle: spin,
                                    child: _cannonball(d),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),

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
                ],
              ),
            );
          },
        ),
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
    final pendingKey = _pendingImpact;
    final samePending = pendingKey == null
        ? _cachedPendingImpactKey == null
        : (_cachedPendingImpactKey != null &&
            _cachedPendingImpactKey![0] == pendingKey[0] &&
            _cachedPendingImpactKey![1] == pendingKey[1]);
    if (controller.revision == _cachedRevision &&
        samePending &&
        _cachedPendingByP1 == _pendingByP1 &&
        _shotsCache.isNotEmpty) {
      return; // nothing relevant changed since the last build — reuse it.
    }
    _cachedRevision = controller.revision;
    _cachedPendingImpactKey = pendingKey == null ? null : [pendingKey[0], pendingKey[1]];
    _cachedPendingByP1 = _pendingByP1;
    for (final halfIsP1 in const [true, false]) {
      final shotsOnThisGrid = halfIsP1 ? controller.p2Shots : controller.myShots;
      _shotsCache[halfIsP1] = [
        for (var r = 0; r < kBoardSize; r++)
          [
            for (var c = 0; c < kBoardSize; c++)
              _shotVisible(shotsOnThisGrid, halfIsP1, r, c)
                  ? shotsOnThisGrid[r][c]
                  : 0
          ]
      ];
      _eventsCache[halfIsP1] = controller.events
          .where((e) => e.byPlayer != halfIsP1 && e.impactAt != null)
          .map((e) => CombatEventLike(e.row, e.col, e.result,
              sunkShipName: e.sunkShipName))
          .toList();
    }
  }

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
    final cooldown =
        halfIsP1 ? controller.cooldownFraction1 : controller.cooldownFraction2;
    final cannonStream = halfIsP1 ? _cannon1Fire : _cannon2Fire;
    final readyStream = halfIsP1 ? _cannon1Ready : _cannon2Ready;
    final accent = halfIsP1 ? AppColors.hit : AppColors.blue;
    final gameplayTheme = context.watch<ProfileStore>().gameplayTheme;

    // VIDEO interaction model: the ACTIVE player's cannon sits at the
    // middle of their OWN grid (a "ready to fire" indicator). Tapping a
    // cell on the OPPONENT's grid fires at it immediately — a single tap
    // is the whole interaction.
    //
    // This half is the ACTIVE player's own half when halfIsP1 == !_p2Active.
    // `_p2Active` tracks whose turn it is and is kept in sync by
    // `_passTurn` for BOTH local pass-and-play and vs-AI (a miss hands the
    // flag over in either mode). Previously only local mode consulted this
    // flag here, so vs-AI always left the human's grid tappable even
    // during the AI's turn — fixed by treating vs-AI the same as local.
    // Hotspot/online each represent a single human player on this device,
    // so they stay unrestricted here; the peer enforces turn order.
    final turnTracked = controller.mode == GameMode.local ||
        controller.mode == GameMode.vsAI;
    final thisIsOpponentOfActive =
        turnTracked ? (halfIsP1 == _p2Active) : !halfIsP1;
    final inBattle = !_countingDown && controller.battling && !_showProjectile;

    // The OPPONENT's grid is tappable to fire, on your turn.
    final gridFirable = thisIsOpponentOfActive && inBattle;

    // This half belongs to whoever is currently active (the flip side of
    // thisIsOpponentOfActive) — used to highlight "whose turn it is" with
    // a soft blur glow behind their own grid.
    final isActiveHalf = !thisIsOpponentOfActive;

    final board = halfIsP1 ? controller.boards[0] : controller.boards[1];

    // Cannonball currently in flight toward THIS half's grid — drives the
    // targeting reticle below for exactly as long as the shot is
    // airborne, disappearing the instant it lands (see _resolveImpact,
    // which clears _pendingImpact right as the hit/miss marker appears).
    final aimCell = (_pendingImpact != null && _pendingByP1 != halfIsP1)
        ? _pendingImpact
        : null;

    // Once the match is over, both fleets are common knowledge — reveal
    // every ship on every grid (not just the sunk ones) as a final
    // "here's where everything was" recap before heading to the result
    // screen, instead of the empty-grid secrecy rule that applies mid-game.
    final gameOver = controller.phase == BattlePhase.finished;
    final revealSkin = halfIsP1 ? _p1StatusSkin : _p2StatusSkin;

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
    // rule that otherwise hides ship positions.
    //
    // Gated on the SAME `events` (impact-landed) list as the hit/miss
    // markers above rather than reading `board.ships`' sunk flag directly.
    // The model marks a ship sunk the instant the shot is registered (tap
    // time), which is well before the cannonball has actually flown across
    // the screen — reading that flag straight would make the wreckage pop
    // onto the grid immediately on tap, ahead of its own flight animation,
    // sound and screen-shake, all of which wait for the ball to land. This
    // keeps the reveal in lockstep with those instead.
    final revealedSunkNames = {
      for (final e in events)
        if (e.result == ShotResult.sunk && e.sunkShipName != null)
          e.sunkShipName,
    };
    final sunkShips = [
      for (final s in board.ships)
        if (s.isSunk && revealedSunkNames.contains(s.spec.name)) s
    ];

    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        // Bigger board: the grid fills the half's full width/height with
        // no reserved side or top margin — same 10×10 grid, just as large
        // as the available space allows (still a perfect square).
        final gridSide = math.min(w, halfH);
        final cell = gridSide / kBoardSize;
        final gridLeft = (w - gridSide) / 2;
        final gridTop = 0.0; // no top margin — grid sits flush at the edge
        final cannonSize = gridSide * 0.24;
        // Cannon HOME: tucked just past the grid's edge, toward the
        // middle band, while it's not this player's turn. Deliberately
        // NOT clamped to halfH — on short/tight halves that clamp used to
        // pull the cannon back UP so its circle overlapped the grid's
        // bottom two rows, making those cells untappable. The half's
        // Stack uses Clip.none, so letting the cannon spill past the
        // half's own bottom edge (into the middle band) is fine and by
        // design; overlapping the tappable grid is not.
        final cannonCenter =
            Offset(w / 2, gridTop + gridSide + cannonSize * 0.55);
        // Cannon "ready" (active) position: the actual MIDDLE of this
        // player's own grid — a clear, unmissable "your turn" indicator.
        // Safe to overlap the grid here: a player's OWN grid is never
        // tappable during their OWN turn (only the opponent's grid is),
        // so sitting on top of it doesn't block anything.
        final gridCenterLocal = Offset(w / 2, gridTop + gridSide / 2);

        // Record screen-space geometry (accounting for the 180° rotation
        // of the top half) so the cannonball can fly between halves.
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
          rotated: isTopHalf,
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
                    // 1:1 video: battle grids are EMPTY — you never see
                    // either player's ships, only your hit/miss markers.
                    // (Guessing where the enemy fleet hides IS the game.)
                    // Sunk ships are one exception — see destroyedShips.
                    // The other: once the game is over (gameOver above),
                    // every ship on both fleets is revealed as a final
                    // recap of the match.
                    ships: gameOver ? board.ships : null,
                    skin: gameOver ? revealSkin : null,
                    destroyedShips: gameOver ? const [] : sunkShips,
                    enabled: gridFirable,
                    glowColor: gameplayTheme.accent,
                    cellColor: gameplayTheme.grid,
                    gridLineColor: gameplayTheme.gridLine,
                    recentEvents: events,
                    aimCell: aimCell,
                    // Tapping the opponent's grid fires at it immediately.
                    onTapCell: gridFirable
                        ? (r, c) => _fireAtCell(controller, r: r, c: c)
                        : null,
                  ),
                ),
              ),

              // Turn-highlight blur: a soft frosted-glass halo over the
              // ACTIVE player's OWN grid (this half's owner is the one
              // currently firing). That grid isn't tappable right now —
              // you fire at the OPPONENT's grid, on the other half; see
              // `gridFirable` above — so blurring it acts as a spotlight:
              // it de-emphasizes the inert board you don't need and keeps
              // attention on the live, interactive target grid instead.
              // Uses a small FIXED glow margin (clamped to this half's own
              // bounds) instead of a percentage of gridSide — the old
              // percentage-based halo could balloon well past the grid
              // (and even past the screen edge) on larger boards, which
              // read as the blur effect "leaking" outside the grid.
              // Placed AFTER the grid in the Stack so the BackdropFilter
              // blurs the grid contents (destroyed ships, hit cells, miss
              // cells) in addition to the background — kept deliberately
              // light (sigma 3) so the blurred grid still reads:
              // gridlines and hit/miss/destroyed markers stay visible
              // through the haze instead of dissolving into a solid
              // smear.
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
                      opacity: isActiveHalf && inBattle ? 1 : 0,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              color: accent.withValues(alpha: 0.16),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),

              // Own cannon. During its owner's turn it slides to the
              // MIDDLE of its own grid — a big, unmissable "your turn"
              // indicator — with a little overshoot bounce on the way in.
              // Otherwise it sits parked at home near the middle band.
              // P1 = _slideCtrl.value, P2 = 1-value.
              AnimatedBuilder(
                animation: _slideCtrl,
                builder: (context, _) {
                  final raw =
                      halfIsP1 ? _slideCtrl.value : 1 - _slideCtrl.value;
                  final slide = Curves.easeOutBack.transform(raw.clamp(0.0, 1.0));
                  final pos =
                      Offset.lerp(cannonCenter, gridCenterLocal, slide)!;
                  return Positioned(
                    left: pos.dx - cannonSize / 2,
                    top: pos.dy - cannonSize / 2,
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
                        child: CannonWidget(
                          skin: profile.cannonSkin,
                          cooldownFraction: cooldown,
                          enabled: controller.battling && !_countingDown,
                        size: cannonSize,
                        fireTrigger: cannonStream.stream,
                        readyTrigger: readyStream.stream,
                        accentOverride: accent,
                        // Firing now happens with a single tap on the enemy
                        // grid cell (see gridFirable / onTapCell above); the
                        // cannon itself just reacts (recoil + muzzle flash)
                        // as a "shot fired" indicator.
                          onFire: null,
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

  /// Hide cells whose shot is still "in flight" (impact hasn't landed).
  bool _shotVisible(List<List<int>> shots, bool halfIsP1, int r, int c) {
    if (shots[r][c] == 0) return false;
    if (_pendingImpact != null &&
        _pendingImpact![0] == r &&
        _pendingImpact![1] == c &&
        _pendingByP1 != halfIsP1) {
      // A ball is flying toward a cell on this grid.
      return false;
    }
    return true;
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
    return SizedBox(
      height: bandH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            children: [
              Expanded(
                child: Container(
                  color: AppColors.steelBlueDark,
                  padding: const EdgeInsets.symmetric(horizontal: 56),
                  child: _statusRow(topBoard,
                      faded: topIsP1Fleet == activeIsP1,
                      isP1Fleet: topIsP1Fleet),
                ),
              ),
              Expanded(
                child: Container(
                  color: gameplayTheme.deck,
                  padding: const EdgeInsets.symmetric(horizontal: 56),
                  child: _statusRow(bottomBoard,
                      faded: bottomIsP1Fleet == activeIsP1,
                      isP1Fleet: bottomIsP1Fleet),
                ),
              ),
            ],
          ),
          Positioned(
            left: -2,
            top: 4,
            bottom: 4,
            child: _DotsBadge(
              topLeft: 5 - topBoard.sunkCount,
              bottomLeft: 5 - bottomBoard.sunkCount,
            ),
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

  static const ShipSkin _p1StatusSkin =
      ShipSkin('p1', 'P1', AppColors.shipRed, AppColors.shipRedDark, 0);
  static const ShipSkin _p2StatusSkin =
      ShipSkin('p2', 'P2', AppColors.shipBlue, AppColors.shipBlueDark, 0);

  Widget _statusRow(Board board,
      {required bool faded, required bool isP1Fleet}) {
    final skin = isP1Fleet ? _p1StatusSkin : _p2StatusSkin;
    // Per-cell pixel unit for the fleet row: each icon is drawn at
    // `unit * spec.size` wide with a constant beam (height), so a
    // 5-cell carrier reads clearly longer than a 2-cell destroyer — the
    // same relative proportions those ships have on the actual battle
    // grid — instead of every icon sharing one fixed bounding box
    // regardless of the ship's real length.
    const unit = 11.5;
    const beam = 26.0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final spec in kFleet)
          Opacity(
            opacity: faded ? 0.38 : 1.0,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedShip(
                  spec: spec,
                  skin: skin,
                  width: unit * spec.size,
                  height: beam,
                ),
                if (board.shipOfKind(spec.kind)?.isSunk ?? false)
                  const Icon(Icons.close, color: AppColors.hit, size: 22),
              ],
            ),
          ),
      ],
    );
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
            Expanded(child: number(mirrored: true)),
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

  Widget _cannonball(double d) => SizedBox(
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

  void _confirmSurrender(GameController controller) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navy,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.outline, width: 3),
        ),
        title: Text('SURRENDER?', style: AppText.heading(size: 16)),
        content: Text(
          'Abandon the battle?\nThis counts as a loss.',
          style: AppText.body(
              size: 13, color: AppColors.cream.withValues(alpha: 0.85)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                Text('FIGHT ON', style: AppText.label(color: AppColors.green)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              controller.surrender();
            },
            child: Text('SURRENDER', style: AppText.label(color: AppColors.hit)),
          ),
        ],
      ),
    );
  }
}

/// Screen-space geometry of one half (used for cannonball trajectories).
class _HalfGeom {
  final double gridLeft;
  final double gridTop;
  final double cell;
  final double halfTopY;
  final double halfH;
  final double halfW;
  final Offset cannonCenter; // home pos within the half (unrotated space)
  final Offset gridCenterLocal; // grid center within the half (unrotated)
  final double cannonSize;
  final bool rotated; // top half is drawn rotated 180°

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
  const _DotsBadge({required this.topLeft, required this.bottomLeft});

  @override
  Widget build(BuildContext context) {
    Widget dot(Color color, int count) => Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.cream,
            border: Border.all(color: color, width: 3),
          ),
          child: Center(
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w900,
                color: color,
                height: 1,
              ),
            ),
          ),
        );
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
          dot(AppColors.blue, topLeft),
          const SizedBox(height: 5),
          dot(AppColors.hit, bottomLeft),
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
