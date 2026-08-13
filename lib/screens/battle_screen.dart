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
import '../widgets/ship_painter.dart';
import 'result_screen.dart';

/// Battle arena — 1:1 reference layout:
///  • Top half  : blue targeting grid with the player's BIG cannon and
///    translucent ghost circles overlapping it. TAP A CELL TO FIRE.
///  • Middle band: two rows of ship status icons (enemy = solid top row,
///    own fleet = faded bottom row), a white pill badge with blue/red
///    status dots on the left edge and the vertical EXIT pill on the right.
///  • Bottom half: coral field with your own grid (same size, no ships
///    drawn while hidden) and the small black peg.
/// The screen never flips — it stays still and simply swaps which player's
/// data is shown, with a blurred cannon popup on every turn change.
class BattleScreen extends StatefulWidget {
  const BattleScreen({super.key});

  @override
  State<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends State<BattleScreen>
    with TickerProviderStateMixin {
  final _cannon1Fire = StreamController<void>.broadcast();
  final _cannon2Fire = StreamController<void>.broadcast();

  bool _p2View = false; // local mode perspective
  bool _navigatedToResult = false;

  /// Local mode: whether the viewing player has revealed their fleet
  /// (their grid stays hidden until they fire at least once).
  bool _p1Revealed = false;
  bool _p2Revealed = false;

  /// Turn-change popup ("…when the other one turns, pop up their cannon").
  bool _showTurnPopup = false;
  bool _turnPopupForP1 = true;

  /// White crosshair briefly shown on the cell you fired at.
  List<int>? _lastTarget;
  Timer? _targetTimer;

  /// Projectile flight animation (cannon → tapped cell).
  late final AnimationController _projCtrl;
  late final Animation<Offset> _projPos;
  Offset _projFrom = Offset.zero;
  Offset _projTo = Offset.zero;
  bool _showProjectile = false;

  /// Turn popup animation.
  late final AnimationController _turnCtrl;
  late final Animation<double> _turnScale;
  late final Animation<double> _turnFade;

  @override
  void initState() {
    super.initState();
    context.read<GameController>().addListener(_onUpdate);

    _projCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) {
          setState(() => _showProjectile = false);
        }
      });
    _projPos = Tween<Offset>(begin: Offset.zero, end: Offset.zero).animate(
      CurvedAnimation(parent: _projCtrl, curve: Curves.easeInQuad),
    );

    _turnCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) {
          setState(() => _showTurnPopup = false);
        }
      });
    _turnScale = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 0.0, end: 1.12)
              .chain(CurveTween(curve: Curves.easeOutBack)),
          weight: 32),
      TweenSequenceItem(
          tween: Tween(begin: 1.12, end: 1.0)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 14),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 34),
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 0.0)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 20),
    ]).animate(_turnCtrl);
    _turnFade = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 0.0, end: 1.0)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 20),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 60),
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 0.0)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 20),
    ]).animate(_turnCtrl);
  }

  void _onUpdate() {
    final controller = context.read<GameController>();
    if (controller.events.isNotEmpty) {
      final e = controller.events.last;
      if (DateTime.now().difference(e.time).inMilliseconds < 150) {
        (e.byPlayer ? _cannon1Fire : _cannon2Fire).add(null);
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

  @override
  void dispose() {
    _cannon1Fire.close();
    _cannon2Fire.close();
    _projCtrl.dispose();
    _turnCtrl.dispose();
    _targetTimer?.cancel();
    super.dispose();
  }

  List<CombatEventLike> _eventsFor(GameController c, bool p1) => c.events
      .where((e) => e.byPlayer == p1)
      .map((e) => CombatEventLike(e.row, e.col, e.result))
      .toList();

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

  /// Tap-to-fire: tapping a cell on the enemy grid fires immediately,
  /// then the projectile flies from the big cannon to the tapped cell.
  void _fireAtCell(GameController controller, bool showingP1, int r, int c) {
    final trackingGrid = showingP1 ? controller.myShots : controller.p2Shots;
    if (trackingGrid[r][c] != 0) {
      _toast('Already fired there!');
      SoundService.instance.denied();
      return;
    }
    final res =
        showingP1 ? controller.fireAt(r, c) : controller.p2FireAt(r, c);
    if (res == ShotResult.cooldown) {
      _toast('Cannon reloading…');
      return;
    }
    if (res == ShotResult.duplicate) {
      _toast('Already fired there!');
      return;
    }

    // Crosshair + projectile are launched from build() using the grid's
    // layout rect — here we only remember which cell was targeted.
    setState(() {
      _lastTarget = [r, c];
      if (showingP1) {
        _p1Revealed = true;
      } else {
        _p2Revealed = true;
      }
    });
    _targetTimer?.cancel();
    _targetTimer = Timer(const Duration(milliseconds: 950), () {
      if (mounted) setState(() => _lastTarget = null);
    });

    // Local pass-and-play: reveal this player's fleet, then hand the
    // device over after a beat so the result of the shot is visible.
    if (controller.mode == GameMode.local) {
      // Fleet stays hidden — just hand the device over after a beat.
      Future.delayed(const Duration(milliseconds: 750), () {
        if (!mounted || controller.phase != BattlePhase.battling) return;
        _switchTurn(!_p2View);
      });
    }
  }

  /// Switch which player is shown. The screen itself never rotates — we
  /// just swap the data and pop the blurred cannon overlay.
  void _switchTurn(bool toP2) {
    setState(() {
      _p2View = toP2;
      _lastTarget = null;
      _showTurnPopup = true;
      _turnPopupForP1 = !toP2;
    });
    _turnCtrl.forward(from: 0);
    SoundService.instance.click();
  }

  // ------------------------------------------------------------------ BUILD

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GameController>();
    final profile = context.watch<ProfileStore>();
    final isLocal = controller.mode == GameMode.local;
    final showingP1 = !isLocal || !_p2View;

    // In non-local modes the opponent takes their shot after a short beat —
    // pop the blurred "their turn" cannon while they aim (reference style).
    if (!isLocal && controller.battling && controller.events.isNotEmpty) {
      final e = controller.events.last;
      final age = DateTime.now().difference(e.time).inMilliseconds;
      if (e.byPlayer && age < 200 && !_showTurnPopup) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _showTurnPopup) return;
          setState(() {
            _showTurnPopup = true;
            _turnPopupForP1 = false; // opponent's turn next
          });
          _turnCtrl.forward(from: 0);
        });
      }
    }

    final trackingGrid = showingP1 ? controller.myShots : controller.p2Shots;
    final ownBoard = showingP1 ? controller.boards[0] : controller.boards[1];
    final enemyTracking = showingP1 ? controller.p2Shots : controller.myShots;
    final cooldown =
        showingP1 ? controller.cooldownFraction1 : controller.cooldownFraction2;
    final cannonStream = showingP1 ? _cannon1Fire : _cannon2Fire;
    final enemyBoardForStatus =
        showingP1 ? controller.boards[1] : controller.boards[0];
    final ownBoardForStatus =
        showingP1 ? controller.boards[0] : controller.boards[1];

    // No ships are visible on the grids when the game starts. In local
    // pass-and-play the fleet ALWAYS stays hidden (the other player must
    // not see it during the hand-off). In solo/online modes your fleet is
    // revealed only after you fire your first shot.
    final ownRevealed =
        !isLocal && (showingP1 ? _p1Revealed : _p2Revealed);

    return Scaffold(
      body: Container(
        color: AppColors.coral,
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  // ================= TOP HALF — BLUE WATERS =================
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      color: AppColors.water,
                      child: LayoutBuilder(
                        builder: (context, box) {
                          final gridSide =
                              math.min(box.maxWidth, box.maxHeight);
                          final cannonSize = gridSide * 0.46;
                          final cannonCenter = Offset(
                            box.maxWidth / 2,
                            gridSide * 0.34,
                          );
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              // Targeting grid (tap to fire)
                              Center(
                                child: SizedBox(
                                  width: gridSide,
                                  height: gridSide,
                                  child: BattleGrid(
                                    key: ValueKey('enemy-$showingP1'),
                                    shots: trackingGrid,
                                    glowColor: AppColors.water,
                                    recentEvents:
                                        _eventsFor(controller, showingP1),
                                    enabled: controller.battling,
                                    crosshair: _lastTarget,
                                    onTapCell: (r, c) {
                                      final validTarget = trackingGrid[r][c] == 0;
                                      if (validTarget) {
                                        // Launch the projectile from the
                                        // cannon mouth toward this cell.
                                        final cell = gridSide / kBoardSize;
                                        final gridLeft =
                                            (box.maxWidth - gridSide) / 2;
                                        final gridTop =
                                            (box.maxHeight - gridSide) / 2;
                                        _projFrom = cannonCenter +
                                            Offset(0, -cannonSize * 0.22);
                                        _projTo = Offset(
                                          gridLeft + c * cell + cell / 2,
                                          gridTop + r * cell + cell / 2,
                                        );
                                        _projPos = Tween<Offset>(
                                          begin: _projFrom,
                                          end: _projTo,
                                        ).animate(CurvedAnimation(
                                          parent: _projCtrl,
                                          curve: Curves.easeInQuad,
                                        ));
                                        setState(() => _showProjectile = true);
                                        _projCtrl.forward(from: 0);
                                      }
                                      _fireAtCell(controller, showingP1, r, c);
                                    },
                                  ),
                                ),
                              ),

                              // Translucent ghost circles (reference blur
                              // spots) behind the cannon.
                              Positioned(
                                left: cannonCenter.dx - gridSide * 0.42,
                                top: cannonCenter.dy + gridSide * 0.08,
                                child: _ghostCircle(gridSide * 0.30),
                              ),
                              Positioned(
                                left: cannonCenter.dx - gridSide * 0.16,
                                top: cannonCenter.dy + gridSide * 0.20,
                                child: _ghostCircle(gridSide * 0.20),
                              ),
                              Positioned(
                                left: cannonCenter.dx + gridSide * 0.10,
                                top: cannonCenter.dy + gridSide * 0.24,
                                child: _ghostCircle(gridSide * 0.24),
                              ),

                              // The BIG cannon overlapping the grid.
                              Positioned(
                                left: cannonCenter.dx - cannonSize / 2,
                                top: cannonCenter.dy - cannonSize / 2,
                                child: IgnorePointer(
                                  child: CannonWidget(
                                    skin: profile.cannonSkin,
                                    cooldownFraction: cooldown,
                                    enabled: controller.battling,
                                    size: cannonSize,
                                    fireTrigger: cannonStream.stream,
                                  ),
                                ),
                              ),

                              // Small black peg below the cannon.
                              Positioned(
                                left: box.maxWidth / 2 - gridSide * 0.09,
                                top: gridSide * 0.66,
                                child: CustomPaint(
                                  size: Size.square(gridSide * 0.18),
                                  painter: _PegPainter(),
                                ),
                              ),

                              // Cannonball projectile (cannon → target).
                              if (_showProjectile)
                                AnimatedBuilder(
                                  animation: _projCtrl,
                                  builder: (context, _) {
                                    final p = _projPos.value;
                                    final arc = math.sin(
                                            _projCtrl.value * math.pi) *
                                        gridSide *
                                        0.14;
                                    final pos = p - Offset(0, arc);
                                    return Positioned(
                                      left: pos.dx - 7,
                                      top: pos.dy - 7,
                                      child: _cannonball(14),
                                    );
                                  },
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),

                  // ============== MIDDLE BAND — SHIP STATUS ROWS ============
                  SizedBox(
                    height: 58,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Column(
                          children: [
                            // Row 1 — enemy fleet status (SOLID, red).
                            Expanded(
                              child: Container(
                                color: AppColors.water,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 56),
                                child: _statusRow(
                                  enemyBoardForStatus,
                                  faded: false,
                                ),
                              ),
                            ),
                            // Row 2 — own fleet status (FADED).
                            Expanded(
                              child: Container(
                                color: AppColors.coral,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 56),
                                child: _statusRow(
                                  ownBoardForStatus,
                                  faded: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                        // Left white pill badge with blue/red dots.
                        Positioned(
                          left: -2,
                          top: 4,
                          bottom: 4,
                          child: _DotsBadge(
                            enemyLeft: 5 - controller.mySunk,
                            ownLeft: 5 - controller.enemySunk,
                          ),
                        ),
                        // Vertical EXIT pill on the right edge.
                        Positioned(
                          right: -2,
                          top: 2,
                          bottom: 2,
                          child: _ExitPill(
                              onTap: () => _confirmSurrender(controller)),
                        ),
                      ],
                    ),
                  ),

                  // ================= BOTTOM HALF — CORAL =================
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      color: AppColors.coral,
                      child: LayoutBuilder(
                        builder: (context, box) {
                          final gridSide =
                              math.min(box.maxWidth, box.maxHeight);
                          return Center(
                            child: SizedBox(
                              width: gridSide,
                              height: gridSide,
                              child: ownRevealed
                                  ? BattleGrid(
                                      key: ValueKey('own-$showingP1'),
                                      shots: enemyTracking,
                                      // No ships are visible until the
                                      // player reveals their fleet by
                                      // firing (fog of war).
                                      ships: ownBoard.ships,
                                      skin: profile.shipSkin,
                                      enabled: false,
                                      glowColor: AppColors.coralDeep,
                                      recentEvents: _eventsFor(
                                          controller, !showingP1),
                                    )
                                  : _HiddenFleet(
                                      label:
                                          '${showingP1 ? 'PLAYER 1' : 'PLAYER 2'}\nTAP THE TOP GRID TO FIRE',
                                    ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),

              // ---------- Turn-change popup: blurred field + big cannon ----------
              if (_showTurnPopup)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _turnCtrl,
                    builder: (context, _) {
                      final accent = _turnPopupForP1
                          ? profile.cannonSkin.projectile
                          : AppColors.hit;
                      return Opacity(
                        opacity: _turnFade.value,
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.18),
                            child: Center(
                              child: Transform.scale(
                                scale: _turnScale.value,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        _ghostCircle(150),
                                        _ghostCircle(110),
                                        SizedBox(
                                          width: 170,
                                          height: 170,
                                          child: CustomPaint(
                                            painter: CannonPainter(
                                              accent: accent,
                                              cooldown: 1,
                                              ready: true,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 18, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: AppColors.cream,
                                        borderRadius:
                                            BorderRadius.circular(14),
                                        border: Border.all(
                                            color: AppColors.outline,
                                            width: 3),
                                      ),
                                      child: Text(
                                        '${_turnPopupForP1 ? 'PLAYER 1' : 'PLAYER 2'} TURN',
                                        style: AppText.heading(
                                            size: 15,
                                            color: AppColors.outline),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// One row of five ship status icons — flat red = enemy fleet,
  /// flat blue = your fleet (matches the reference exactly).
  static const ShipSkin _enemyStatusSkin =
      ShipSkin('enemy', 'Enemy', AppColors.shipRed, AppColors.shipRedDark, 0);
  static const ShipSkin _ownStatusSkin =
      ShipSkin('own', 'Own', AppColors.shipBlue, AppColors.shipBlueDark, 0);

  Widget _statusRow(Board board, {required bool faded}) {
    final skin = faded ? _ownStatusSkin : _enemyStatusSkin;
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

  Widget _ghostCircle(double d) => Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.30),
        ),
      );

  Widget _cannonball(double d) => Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.outline,
          border: Border.all(color: Colors.black, width: 1.4),
          boxShadow: const [
            BoxShadow(color: Color(0x55000000), blurRadius: 2),
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
          style:
              AppText.body(size: 13, color: AppColors.cream.withValues(alpha: 0.85)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('FIGHT ON', style: AppText.label(color: AppColors.green)),
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

/// Small black peg below the cannon (reference: dark ring + grey core).
class _PegPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.48;
    // Ground shadow
    canvas.drawOval(
      Rect.fromCenter(
          center: c + Offset(0, r * 0.5), width: r * 2.1, height: r * 0.8),
      Paint()..color = Colors.black.withValues(alpha: 0.20),
    );
    // Black ring
    canvas.drawCircle(c, r, Paint()..color = AppColors.outline);
    // Dark grey inner
    canvas.drawCircle(
      c,
      r * 0.78,
      Paint()
        ..shader = CannonPainter.uiGradient(
            c, r * 0.78, const [Color(0xFF4A5661), Color(0xFF1E262E)]),
    );
    // Core dot
    canvas.drawCircle(
        c - Offset(0, r * 0.1), r * 0.30, Paint()..color = const Color(0xFF6B7884));
  }

  @override
  bool shouldRepaint(_PegPainter oldDelegate) => false;
}

/// White pill badge pinned to the left edge of the status band with the
/// blue dot (enemy ships left) and the red dot (own ships left).
class _DotsBadge extends StatelessWidget {
  final int enemyLeft;
  final int ownLeft;
  const _DotsBadge({required this.enemyLeft, required this.ownLeft});

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
          dot(AppColors.blue, enemyLeft),
          const SizedBox(height: 5),
          dot(AppColors.hit, ownLeft),
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

/// Cover panel shown over the viewing player's fleet until they fire.
/// Renders an empty water grid (so the layout matches) with a centered
/// lock + instruction chip on top.
class _HiddenFleet extends StatelessWidget {
  final String label;
  const _HiddenFleet({required this.label});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Empty water grid underneath (same chunky cells, no ships).
        BattleGrid(
          shots: List.generate(kBoardSize, (_) => List.filled(kBoardSize, 0)),
          enabled: false,
          glowColor: AppColors.coralDeep,
        ),
        // Frosted cover.
        Container(
          decoration: BoxDecoration(
            color: AppColors.coral.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.cream,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.outline, width: 3),
                  ),
                  child: const Icon(Icons.visibility_off,
                      color: AppColors.outline, size: 34),
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.navy,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.outline, width: 2.5),
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: AppText.label(size: 11, color: AppColors.cream),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
