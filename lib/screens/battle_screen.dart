import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/game_models.dart';
import '../services/game_controller.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../widgets/battle_grid.dart';
import '../widgets/cannon_widget.dart';
import '../widgets/ship_painter.dart';
import 'placement_screen.dart';
import 'result_screen.dart';

/// Battle arena — 1:1 copy of the reference gameplay video:
///  • BOTH player halves are on screen at once. The opponent's half sits on
///    top rotated 180° (so it faces them across the table); the active
///    player's half is at the bottom, upright.
///  • Each half shows that player's OWN grid + their OWN cannon
///    (red ring = P1, blue ring = P2). You tap the OTHER player's grid to
///    fire at it (it lives on the opposite half).
///  • Middle band: two ship-status rows (top solid / bottom faded),
///    EXIT pill on the edge and the white dots badge.
///  • Battle starts with a giant translucent 3-2-1 countdown mirrored on
///    both halves, then a one-time "Your turn" badge after GO.
///  • Battle grids are EMPTY (ships hidden) — you guess where the enemy
///    fleet is. A HIT lets you fire again; only a MISS passes the turn.
class BattleScreen extends StatefulWidget {
  const BattleScreen({super.key});

  @override
  State<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends State<BattleScreen>
    with TickerProviderStateMixin {
  final _cannon1Fire = StreamController<void>.broadcast();
  final _cannon2Fire = StreamController<void>.broadcast();

  /// Local pass-and-play: which player's half is currently at the bottom.
  bool _p2Active = false;

  bool _navigatedToResult = false;
  bool _handoffPending = false;

  // ----- Countdown -----
  bool _countingDown = false;
  int _countdownValue = 3;
  bool _countdownGo = false;

  // ----- "Your turn" badge -----
  bool _showTurnBadge = false;
  late final AnimationController _badgeCtrl;
  late final Animation<double> _badgeScale;

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

  @override
  void initState() {
    super.initState();
    final controller = context.read<GameController>();
    controller.addListener(_onUpdate);

    _badgeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) {
          setState(() => _showTurnBadge = false);
        }
      });
    _badgeScale = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 0.0, end: 1.1)
              .chain(CurveTween(curve: Curves.easeOutBack)),
          weight: 30),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 45),
      TweenSequenceItem(
          tween: Tween(begin: 1.1, end: 0.0)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 25),
    ]).animate(_badgeCtrl);

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
      _showTurnBadge = true; // "Your turn" right after GO
    });
    _badgeCtrl.forward(from: 0);
  }

  void _onUpdate() {
    final controller = context.read<GameController>();
    if (controller.events.isNotEmpty) {
      final e = controller.events.last;
      final age = DateTime.now().difference(e.time).inMilliseconds;
      // Opponent (AI / remote) shots animate from their cannon here; the
      // local player's own ball is launched at tap time.
      if (!e.byPlayer && age < 200 && mounted) {
        _launchOpponentBall(e);
      }
    }
    if (controller.phase == BattlePhase.finished && !_navigatedToResult) {
      _navigatedToResult = true;
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ResultScreen()),
        );
      });
    }
  }

  /// AI / remote opponent fired at the BOTTOM player's grid.
  void _launchOpponentBall(CombatEvent e) {
    final top = _geom[true];
    final bottom = _geom[false];
    if (top == null || bottom == null || _projCtrl.isAnimating) {
      // No geometry yet (or ball already flying) — mark impact immediately.
      e.impactAt ??= DateTime.now();
      return;
    }
    final from = top.cannonMouthScreen;
    final to = bottom.cellCenterScreen(e.row, e.col);
    setState(() {
      _pendingByP1 = false;
      _pendingImpact = [e.row, e.col];
      _pendingResult = e.result;
      _projFrom = from;
      _projTo = to;
      _projCell = bottom.cell;
      _showProjectile = true;
    });
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
    // 1:1 video rule: a HIT lets the same player keep firing; only a MISS
    // passes the turn (and the device) to the other player.
    if (controller.mode == GameMode.local &&
        controller.phase == BattlePhase.battling &&
        result == ShotResult.miss &&
        !_handoffPending) {
      _handoffPending = true;
      Future.delayed(const Duration(milliseconds: 800), () {
        if (!mounted || controller.phase != BattlePhase.battling) {
          _handoffPending = false;
          return;
        }
        _handoffPending = false;
        _showHandoff();
      });
    }
  }

  // ------------------------------------------------------------- FIRING

  /// The active player tapped a cell on the opponent's grid (top half).
  void _fireFromTap(
    GameController controller, {
    required bool byP1,
    required int r,
    required int c,
  }) {
    if (_countingDown || _showProjectile) return;
    final tracking = byP1 ? controller.myShots : controller.p2Shots;
    if (tracking[r][c] != 0) {
      _toast('Already fired there!');
      SoundService.instance.denied();
      return;
    }
    final res = byP1 ? controller.fireAt(r, c) : controller.p2FireAt(r, c);
    if (res == ShotResult.cooldown) {
      _toast('Cannon reloading…');
      SoundService.instance.denied();
      return;
    }
    if (res == ShotResult.duplicate || res == ShotResult.invalid) {
      _toast('Already fired there!');
      SoundService.instance.denied();
      return;
    }
    final top = _geom[true];
    final bottom = _geom[false];
    if (top == null || bottom == null) return;
    setState(() {
      _pendingByP1 = byP1;
      _pendingImpact = [r, c];
      _pendingResult = res;
      _projFrom = bottom.cannonMouthScreen;
      _projTo = top.cellCenterScreen(r, c);
      _projCell = top.cell;
      _showProjectile = true;
    });
    (byP1 ? _cannon1Fire : _cannon2Fire).add(null);
    _projCtrl.forward(from: 0);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.navy,
        duration: const Duration(milliseconds: 900),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.outline, width: 2),
        ),
      ));
  }

  // ------------------------------------------------------------- HANDOFF

  Future<void> _showHandoff() async {
    final nextIsP2 = !_p2Active;
    SoundService.instance.whir();
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (ctx) => HandoffScreen(
        title: 'Pass the screen\nto your friend\nand don\'t look :-)',
        subtitle: nextIsP2 ? 'Player 2 — your turn!' : 'Player 1 — your turn!',
        buttonLabel: 'OK',
        onReady: () => Navigator.of(ctx).pop(),
      ),
    ));
    if (!mounted) return;
    // Swap which player is at the bottom. NO "Your turn" badge here —
    // the video only shows that badge once, right after the opening GO.
    setState(() => _p2Active = nextIsP2);
    SoundService.instance.whir();
  }

  @override
  void dispose() {
    _cannon1Fire.close();
    _cannon2Fire.close();
    _badgeCtrl.dispose();
    _projCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- BUILD

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GameController>();
    final profile = context.watch<ProfileStore>();
    final isLocal = controller.mode == GameMode.local;
    final bottomIsP1 = !isLocal || !_p2Active;

    return Scaffold(
      body: Container(
        color: AppColors.coralVideo,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, full) {
              const bandH = 58.0;
              final halfH = (full.maxHeight - bandH) / 2;
              return Stack(
                children: [
                  Column(
                    children: [
                      // ===== TOP HALF — opponent, rotated 180° =====
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

                      // ===== BOTTOM HALF — active player, upright =====
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
                            final p = Offset.lerp(_projFrom, _projTo, t)!;
                            final arc =
                                math.sin(t * math.pi) * _projCell * 3.0;
                            final pos = p - Offset(0, arc);
                            final d = _projCell * 0.52;
                            return Stack(
                              children: [
                                Positioned(
                                  left: pos.dx - d / 2,
                                  top: pos.dy - d / 2,
                                  child: _cannonball(d),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),

                  // ===== Countdown overlay (mirrored) =====
                  if (_countingDown) _countdownOverlay(bandH),

                  // ===== "Your turn" badge (mirrored) =====
                  if (_showTurnBadge) _turnBadgeOverlay(bottomIsP1, bandH),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------- HALVES

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
    // This half shows the OWNER's grid: the enemy's shots land here.
    final shotsOnThisGrid = halfIsP1 ? controller.p2Shots : controller.myShots;
    final cooldown =
        halfIsP1 ? controller.cooldownFraction1 : controller.cooldownFraction2;
    final cannonStream = halfIsP1 ? _cannon1Fire : _cannon2Fire;
    final accent = halfIsP1 ? AppColors.hit : AppColors.blue;

    // The ACTIVE player (bottom) fires at the top half's grid.
    final tappable = isTopHalf &&
        !_countingDown &&
        controller.battling &&
        !_showProjectile;

    // Only show markers whose cannonball has already landed.
    final events = controller.events
        .where((e) => e.byPlayer != halfIsP1 && e.impactAt != null)
        .map((e) => CombatEventLike(e.row, e.col, e.result))
        .toList();
    final shownShots = [
      for (var r = 0; r < kBoardSize; r++)
        [
          for (var c = 0; c < kBoardSize; c++)
            _shotVisible(shotsOnThisGrid, halfIsP1, r, c)
                ? shotsOnThisGrid[r][c]
                : 0
        ]
    ];

    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final gridSide = math.min(w, halfH * 0.78);
        final cell = gridSide / kBoardSize;
        final gridLeft = (w - gridSide) / 2;
        final gridTop = 6.0; // grid near the outer edge of the half
        final cannonSize = gridSide * 0.42;
        final cannonCenter =
            Offset(w / 2, gridTop + gridSide + (halfH - gridSide) * 0.52);

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
          cannonSize: cannonSize,
          rotated: isTopHalf,
        );

        return Container(
          width: double.infinity,
          height: halfH,
          color: AppColors.coralVideo,
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
                    key: ValueKey('grid-$halfIsP1-$bottomIsP1'),
                    shots: shownShots,
                    // 1:1 video: battle grids are EMPTY — you never see
                    // either player's ships, only your hit/miss markers.
                    // (Guessing where the enemy fleet hides IS the game.)
                    ships: null,
                    skin: null,
                    enabled: tappable,
                    glowColor: AppColors.steelBlueDark,
                    cellColor: AppColors.steelBlue,
                    recentEvents: events,
                    onTapCell: tappable
                        ? (r, c) => _fireFromTap(controller,
                            byP1: bottomIsP1, r: r, c: c)
                        : null,
                  ),
                ),
              ),

              // Own cannon below the grid (toward the middle band).
              Positioned(
                left: cannonCenter.dx - cannonSize / 2,
                top: cannonCenter.dy - cannonSize / 2,
                child: IgnorePointer(
                  child: CannonWidget(
                    skin: profile.cannonSkin,
                    cooldownFraction: cooldown,
                    enabled: controller.battling && !_countingDown,
                    size: cannonSize,
                    fireTrigger: cannonStream.stream,
                    accentOverride: accent,
                  ),
                ),
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
                      faded: false, isP1Fleet: !bottomIsP1),
                ),
              ),
              Expanded(
                child: Container(
                  color: AppColors.coralVideo,
                  padding: const EdgeInsets.symmetric(horizontal: 56),
                  child: _statusRow(bottomBoard,
                      faded: true, isP1Fleet: bottomIsP1),
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final spec in kFleet)
          Opacity(
            opacity: faded ? 0.38 : 1.0,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedShip(spec: spec, skin: skin, size: 40),
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

  /// Big circular white-outline "Your turn" badge, mirrored so both
  /// players can read it (video style).
  Widget _turnBadgeOverlay(bool bottomIsP1, double bandH) {
    final color = bottomIsP1 ? AppColors.hit : AppColors.blue;
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _badgeCtrl,
          builder: (context, _) {
            final scale = _badgeScale.value;
            Widget badge({required bool mirrored}) => Center(
                  child: RotatedBox(
                    quarterTurns: mirrored ? 2 : 0,
                    child: Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 180,
                        height: 180,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                          border: Border.all(color: Colors.white, width: 7),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x55000000),
                              blurRadius: 12,
                              offset: Offset(0, 5),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text(
                            'Your\nturn',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 32,
                              height: 1.05,
                              shadows: [
                                Shadow(color: Color(0x66000000), blurRadius: 4)
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
            return Column(
              children: [
                Expanded(child: badge(mirrored: true)),
                SizedBox(height: bandH),
                Expanded(child: badge(mirrored: false)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _cannonball(double d) => Container(
        width: d,
        height: d,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: Alignment(-0.35, -0.4),
            radius: 0.9,
            colors: [Color(0xFF8A949E), Color(0xFF2A323B)],
          ),
          boxShadow: [BoxShadow(color: Color(0x55000000), blurRadius: 2)],
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
  final Offset cannonCenter; // within the half (unrotated space)
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

  /// Absolute screen position of the cannon mouth.
  Offset get cannonMouthScreen {
    final lx = cannonCenter.dx;
    final ly = cannonCenter.dy - cannonSize * 0.25;
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
