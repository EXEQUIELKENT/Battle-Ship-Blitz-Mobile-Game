import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../art/family_shell_art.dart';
import '../art/fleet_family.dart';
import '../art/legacy_shell_art.dart';
import '../core/fleet_identity.dart';
import '../core/theme.dart';
import '../models/daily_puzzle.dart';
import '../models/game_models.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../widgets/awesome_cheer.dart';
import '../widgets/battle_grid.dart';
import '../widgets/cannon_widget.dart';
import '../widgets/neon_widgets.dart';
import '../widgets/ocean_background.dart';

/// Daily puzzle: one pre-seeded three-hull enemy fleet per calendar day
/// — the same board on every device — sink it within the dealt
/// shot budget. Solving (or failing) pays Doubloons once per day;
/// replays are free but pay nothing (see
/// `ProfileStore.claimDailyPuzzleReward`).
///
/// The cannon below the grid is the captain's own equipped gun (see
/// `ProfileStore.cannonSkin`, picked on the menu / shipyard) — its
/// silhouette, reload ring and shell artwork all follow it, and every
/// tap lobs that gun's shell from its real muzzle to the tapped cell.
class DailyPuzzleScreen extends StatefulWidget {
  const DailyPuzzleScreen({super.key});

  @override
  State<DailyPuzzleScreen> createState() => _DailyPuzzleScreenState();
}

class _DailyPuzzleScreenState extends State<DailyPuzzleScreen>
    with TickerProviderStateMixin {
  late final DateTime _today;
  late DailyPuzzle _puzzle;
  final List<CombatEventLike> _fxEvents = [];
  bool _rewarded = false;
  int _reward = 0;

  /// Cannon fire trigger (recoil + muzzle flash), one shot at a time.
  final StreamController<void> _fireCtrl = StreamController<void>.broadcast();

  /// Sinking cheers: every increment replays the "AWESOME!" celebration
  /// over the middle of the board (see `AwesomeCheer`).
  final _cheer = ValueNotifier<int>(0);

  /// Whose gun the current cheer belongs to — always written in the same
  /// breath as [_cheer].
  String? _cheerCannon;

  /// Which voice the current cheer is matching ("awesome!" or "wow!").
  CheerKind _cheerKind = CheerKind.awesome;

  /// The in-flight shell's clock. Taps while a shell is airborne are
  /// refused with the standard denied blip rather than restarting the
  /// shell mid-air.
  late final AnimationController _shotCtrl;

  /// Cell the airborne shell is heading for (also the grid reticle).
  List<int>? _aimCell;

  /// Barrel swing off straight-up, in the same radians `CannonWidget`
  /// reads — set as the shot launches so the long barrel visibly bears
  /// on the tapped cell (the widget tweens the traverse itself), eased
  /// back to rest when the shell lands, exactly like battle aim.
  double _aim = 0;

  /// Battle's own traverse limit, so a corner tap swings the gun hard
  /// without ever laying it flat.
  static const _maxAimSwing = 0.85;

  Offset _shotFrom = Offset.zero;
  Offset _shotTo = Offset.zero;
  double _shotCell = 32;
  double _shotArc = 64;

  // Board/cannon geometry, cached each build from the same
  // `LayoutBuilder` math that positions the grid and cannon below, so a
  // tap converts straight into this `Stack`'s own local coordinate space.
  double _gridLeftPx = 0;
  double _gridTopPx = 0;
  double _gridSidePx = 1;
  double _cannonCenterXPx = 0;
  double _cannonCenterYPx = 0;
  double _cannonRenderSizePx = 0;
  double _cannonMuzzleFrac = CannonWidget.muzzleFraction;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    _puzzle = DailyPuzzle(seed: ProfileStore.dailyPuzzleSeed(_today));
    _shotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
  }

  @override
  void dispose() {
    _cheer.dispose();
    _fireCtrl.close();
    _shotCtrl.dispose();
    super.dispose();
  }

  void _newPuzzle() {
    setState(() {
      _puzzle = DailyPuzzle(seed: ProfileStore.dailyPuzzleSeed(_today));
      _fxEvents.clear();
      _rewarded = false;
      _reward = 0;
      _aimCell = null;
    });
  }

  void _fire(int r, int c) {
    if (_puzzle.done || _aimCell != null) {
      if (_aimCell != null) SoundService.instance.denied();
      return;
    }
    if (_puzzle.shots[r][c] != 0) {
      SoundService.instance.denied();
      return;
    }
    final cellSize = _gridSidePx / kBoardSize;
    final to = Offset(
      _gridLeftPx + (c + 0.5) * cellSize,
      _gridTopPx + (r + 0.5) * cellSize,
    );
    // Traverse the barrel onto the tapped cell BEFORE the shell is
    // born, so it launches from the rotated muzzle tip rather than
    // from beside a gun still pointing straight up.
    final aim = CannonWidget.aimAt(
      Offset(_cannonCenterXPx, _cannonCenterYPx),
      to,
      _maxAimSwing,
    );
    final reach = _cannonRenderSizePx * _cannonMuzzleFrac;
    final muzzle = Offset(
      _cannonCenterXPx + math.sin(aim) * reach,
      _cannonCenterYPx - math.cos(aim) * reach,
    );
    final profile = context.read<ProfileStore>();
    // Peak scales with the tap's real distance so a close tap gets a
    // small hop and a far one still gets a proper lob (see the matching
    // note on placement's `_firePreviewShot`).
    final dx = to.dx - muzzle.dx;
    final dy = to.dy - muzzle.dy;
    final dist = math.sqrt(dx * dx + dy * dy) / cellSize; // in cells
    setState(() {
      _aimCell = [r, c];
      _aim = aim;
      _shotFrom = muzzle;
      _shotTo = to;
      _shotCell = cellSize;
      _shotArc = cellSize * dist.clamp(1.0, 2.4);
    });
    SoundService.instance.cannonFire(cannonSkinId: profile.cannonSkinId);
    _fireCtrl.add(null);
    _shotCtrl.forward(from: 0).whenComplete(() {
      if (mounted) _resolveLanding(r, c);
    });
  }

  /// Scores the shot the moment its shell lands — the marker, wreck,
  /// sound and reward all key off impact, never off tap time.
  void _resolveLanding(int r, int c) {
    final profile = context.read<ProfileStore>();
    final res = _puzzle.fire(r, c);
    if (res == ShotResult.duplicate || res == ShotResult.invalid) {
      setState(() {
        _aimCell = null;
        _aim = 0;
      });
      return;
    }
    _fxEvents.add(CombatEventLike(r, c, res));
    switch (res) {
      case ShotResult.sunk:
        SoundService.instance.sunk(shipSkinId: profile.shipSkinId);
        // The coin flip picks "awesome!" or "wow!"; the popup is told
        // which, so the two always match.
        _cheerKind = SoundService.instance.sinkingCheer();
        _cheerCannon = profile.cannonSkinId;
        _cheer.value++;
        break;
      case ShotResult.hit:
        SoundService.instance.hit(cannonSkinId: profile.cannonSkinId);
        break;
      default:
        SoundService.instance.miss(
          themeId: profile.gameplayThemeId,
          cannonSkinId: profile.cannonSkinId,
        );
    }
    var reward = 0;
    var settledNow = false;
    if (_puzzle.done && !_rewarded) {
      _rewarded = true;
      settledNow = true;
      reward = profile.claimDailyPuzzleReward(
        solved: _puzzle.solved,
        now: _today,
      );
      if (_puzzle.solved) {
        SoundService.instance.victory();
      } else {
        SoundService.instance.defeat();
      }
    }
    setState(() {
      _aimCell = null;
      _aim = 0;
      if (settledNow) _reward = reward;
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileStore>();
    final skin = profile.cannonSkin;
    // The captain's equipped battlefield — same mapping the battle
    // screen uses, so the deck, gridlines, hit/miss marks and deck
    // debris all follow the menu/shipyard pick.
    final theme = profile.gameplayTheme;
    // Sunk wrecks sail the captain's own equipped hull (charred by the
    // wreck painter), falling back to the plain red side colour when no
    // hull was ever picked — the same `fleetLook` rule every other
    // screen resolves through.
    final fleetSkin = fleetLook(
      isRedSide: true,
      equippedShipSkinId: profile.shipSkinId,
      chosen: profile.shipSkinChosen,
    ).skin;
    final done = _puzzle.done;
    final rewardAvailable =
        profile.dailyPuzzleRewardAvailable(DateTime.now());
    return Scaffold(
      body: OceanBackground(
        showSonar: false,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back,
                          color: AppColors.cream),
                      onPressed: () {
                        SoundService.instance.click();
                        Navigator.pop(context);
                      },
                    ),
                    Expanded(
                      child: Text('DAILY PUZZLE',
                          style: AppText.title(size: 20)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppColors.gold,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.outline, width: 2.5),
                      ),
                      child: Text(
                        '🔥 ${profile.dailyPuzzleStreak}',
                        style: AppText.label(
                            size: 11, color: AppColors.outline),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${_today.month}/${_today.day}/${_today.year}  •  SINK ${_puzzle.board.ships.length} SHIPS IN ${_puzzle.shotBudget} SHOTS',
                  style: AppText.label(
                      size: 10,
                      color: AppColors.cream.withValues(alpha: 0.75)),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _chip('SHOTS LEFT  ${_puzzle.shotsLeft}'),
                    const SizedBox(width: 8),
                    _chip(
                        'SUNK  ${_puzzle.sunkShips.length}/${_puzzle.board.ships.length}'),
                    if (!rewardAvailable) ...[
                      const SizedBox(width: 8),
                      _chip('CLAIMED ✓'),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final w = constraints.maxWidth;
                      final h = constraints.maxHeight;
                      // The cannon parks past the grid's outer edge with
                      // the same 0.07 muzzle overlap the battle screen
                      // uses; reserve its strip so it never clips.
                      final scale =
                          CannonWidget.gameplaySizeScaleOf(skin);
                      final muzzleFrac =
                          CannonWidget.muzzleFractionOf(skin);
                      // Solve gridSide so grid + parked cannon fit: the
                      // cannon's center sits backOffset past the grid edge.
                      var gridSide = math.min(w, h * 0.86);
                      var cannonSize = gridSide * 0.24;
                      var renderSize = cannonSize * scale;
                      final backOffset =
                          renderSize * (muzzleFrac - 0.07);
                      final gridTop =
                          (h - gridSide - backOffset - renderSize / 2)
                              .clamp(0.0, h);
                      final gridLeft = (w - gridSide) / 2;
                      final cannonCenterY =
                          gridTop + gridSide + backOffset;
                      _gridLeftPx = gridLeft;
                      _gridTopPx = gridTop;
                      _gridSidePx = gridSide;
                      _cannonCenterXPx = w / 2;
                      _cannonCenterYPx = cannonCenterY;
                      _cannonRenderSizePx = renderSize;
                      _cannonMuzzleFrac = muzzleFrac;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // Deep water behind the board — the equipped
                          // deck's own colours sunk into a dark depth
                          // gradient with vignette, light rays and rising
                          // bubbles, so the puzzle reads deep rather than
                          // flat no matter which battlefield is equipped.
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _PuzzleDepthPainter(
                                deck: theme.deck,
                                accent: theme.accent,
                              ),
                            ),
                          ),
                          Positioned(
                            left: gridLeft,
                            top: gridTop,
                            width: gridSide,
                            height: gridSide,
                            child: BattleGrid(
                              shots: _puzzle.shots,
                              onTapCell: done ? null : _fire,
                              aimCell: _aimCell,
                              recentEvents: _fxEvents,
                              enabled: !done && _aimCell == null,
                              destroyedShips: _puzzle.sunkShips,
                              wreckShipSkinId: fleetSkin.id,
                              wreckShipSkin: fleetSkin,
                              // Themed water + hit/miss marks: a family
                              // battlefield replaces the flat cells (and
                              // brings its own markers), otherwise a
                              // legacy illustrated deck does. The per-gun
                              // impact particles and themed crosshair
                              // follow the equipped cannon.
                              glowColor: theme.accent,
                              cellColor: theme.grid,
                              boardFamily: FleetFamilies.byKey(
                                  theme.familyKey),
                              legacyBoardId: theme.legacy
                                  ? theme.id
                                  : null,
                              gridLineColor: theme.gridLine,
                              cannonSkinId: skin.id,
                            ),
                          ),
                          // The captain's own equipped gun, parked below
                          // the grid with its muzzle peeking onto the
                          // deck — recoil, flash and reload ring included.
                          Positioned(
                            left: w / 2 - renderSize / 2,
                            top: cannonCenterY - renderSize / 2,
                            width: renderSize,
                            height: renderSize,
                            child: IgnorePointer(
                              child: CannonWidget(
                                key: ValueKey(skin.id),
                                skin: skin,
                                cooldownFraction: 1,
                                size: renderSize,
                                fireTrigger: _fireCtrl.stream,
                                barrelAim: _aim,
                              ),
                            ),
                          ),
                          // The shell's slot is ALWAYS in the tree — an
                          // empty box when no shell is in flight.
                          //
                          // BUGFIX: a Stack matches its children BY INDEX
                          // when they carry no keys, so a child added or
                          // removed here shifted every later child along
                          // by one. The celebration overlay sits right
                          // after this slot and is a `Positioned.fill`
                          // just like it, so the overlay's element was
                          // re-used for the shell layer and then
                          // re-created on the next shot: its animation
                          // restarted on every shot, and the popup could
                          // pop up when no ship had been sunk at all.
                          // Keeping the slot (and its type) fixed means
                          // the overlay's element is never disturbed.
                          // The shell's slot is ALWAYS in the tree — an
                          // empty box when no shell is in flight.
                          //
                          // BUGFIX: a Stack matches its children BY INDEX
                          // when they carry no keys, so a child added or
                          // removed here shifted every later child along
                          // by one. The celebration overlay sits right
                          // after this slot and is a `Positioned.fill`
                          // just like it, so the overlay's element was
                          // re-used for the shell layer and then
                          // re-created on the next shot: its animation
                          // restarted every time, and the popup could
                          // pop up when no ship had been sunk at all.
                          // Keeping the slot (and its type) fixed means
                          // the overlay's element is never disturbed.
                          Positioned.fill(
                            child: _aimCell == null
                                ? const SizedBox.shrink()
                                : _shotLayer(skin),
                          ),
                          // Sinking cheer over the middle of the board.
                          Positioned.fill(
                            key: const ValueKey('sinking-cheer'),
                            child: IgnorePointer(
                              child: Center(
                                child: ValueListenableBuilder<int>(
                                  valueListenable: _cheer,
                                  builder: (context, cheerId, _) =>
                                      SinkingCheer(
                                          cheerId: cheerId,
                                          kind: _cheerKind,
                                          cannonId: _cheerCannon),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                if (done) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration:
                        cartoonBox(AppColors.navy, radius: 16),
                    child: Column(
                      children: [
                        Text(
                          _puzzle.solved ? 'PUZZLE SOLVED!' : 'OUT OF SHOTS',
                          style: AppText.heading(
                              size: 18,
                              color: _puzzle.solved
                                  ? AppColors.gold
                                  : AppColors.hit),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _reward > 0
                              ? '+$_reward Doubloons'
                              : 'Already claimed today — replay is free',
                          style: AppText.body(
                              size: 12, color: AppColors.cream),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: NeonButton(
                          label: 'PLAY AGAIN',
                          icon: Icons.refresh,
                          color: AppColors.green,
                          compact: true,
                          onPressed: _newPuzzle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: NeonButton(
                          label: 'MAIN MENU',
                          icon: Icons.home,
                          color: AppColors.blue,
                          compact: true,
                          onPressed: () => Navigator.of(context)
                              .popUntil((route) => route.isFirst),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cream, width: 1.5),
      ),
      child: Text(text,
          style: AppText.label(size: 10, color: AppColors.cream)),
    );
  }

  /// The in-flight shell: this cannon's own artwork (family gun, legacy
  /// gun, or plain iron ball) arcing muzzle-to-cell with motion ghosts.
  ///
  /// The CONTENT of the shell slot — the slot itself is a stable
  /// `Positioned.fill` in the Stack, so the celebration overlay beside it
  /// is never disturbed by a shell appearing or landing (see the note
  /// there).
  Widget _shotLayer(CannonSkin skin) {
    final shellFamily = FleetFamilies.byKey(skin.familyKey);
    final legacyShellId = shellFamily == null ? skin.id : null;
    final isDirectional = shellFamily != null
        ? familyShellIsDirectional(shellFamily.id)
        : legacyShellIsDirectional(legacyShellId!);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _shotCtrl,
        builder: (context, _) {
          final t = _shotCtrl.value;

          Offset posAt(double tt) {
            final cl = tt.clamp(0.0, 1.0);
            final base = Offset.lerp(_shotFrom, _shotTo, cl)!;
            final arc = math.sin(cl * math.pi) * _shotArc;
            return base - Offset(0, arc);
          }

          double angleAt(double tt) {
            final cl = tt.clamp(0.0, 1.0);
            final vx = _shotTo.dx - _shotFrom.dx;
            final arcRate =
                math.pi * _shotArc * math.cos(cl * math.pi);
            final vy = (_shotTo.dy - _shotFrom.dy) - arcRate;
            if (vx == 0 && vy == 0) return 0;
            return math.atan2(vx, -vy);
          }

          double diamAt(double tt) =>
              _shotCell * (2.6 - 1.6 * tt.clamp(0.0, 1.0));

          double impactFadeAt(double tt) {
            const fadeStart = 0.92;
            if (tt <= fadeStart) return 1.0;
            return (1 - (tt - fadeStart) / (1 - fadeStart))
                .clamp(0.0, 1.0);
          }

          final pos = posAt(t);
          final d = diamAt(t);
          final fade = impactFadeAt(t);
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
                opacity: opacity * impactFadeAt(tt),
                child: Transform.rotate(
                  angle: isDirectional ? angleAt(tt) : 0.0,
                  child: _shellPaint(
                    gd,
                    family: shellFamily,
                    legacyId: legacyShellId,
                  ),
                ),
              ),
            );
          }

          return Stack(
            clipBehavior: Clip.none,
            children: [
              ghost(0.11, 0.14, 0.72),
              ghost(0.055, 0.26, 0.84),
              Positioned(
                left: pos.dx - d / 2,
                top: pos.dy - d / 2,
                child: Opacity(
                  opacity: fade,
                  child: Transform.rotate(
                    angle: angle,
                    child: _shellPaint(
                      d,
                      family: shellFamily,
                      legacyId: legacyShellId,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// This cannon's projectile: family artwork, legacy shell artwork,
  /// or a fallback iron ball.
  Widget _shellPaint(double d, {FleetFamily? family, String? legacyId}) {
    if (family != null) {
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
    return Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.35, -0.4),
          radius: 0.95,
          stops: [0.0, 0.45, 1.0],
          colors: [Color(0xFFC3CBD3), Color(0xFF6E7883), Color(0xFF1D232A)],
        ),
        border: Border.all(
          color: const Color(0xFF12161B),
          width: math.max(1.0, d * 0.05),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: d * 0.18,
            offset: Offset(0, d * 0.1),
          ),
        ],
      ),
    );
  }
}

/// Deep-sea backdrop for the puzzle board: the equipped deck's own
/// colours running from dim surface light at the top down into near-black
/// depth, closed off by a vignette, with slanting light rays, a soft
/// accent glow behind the cannon's end of the water, and a scatter of
/// rising bubbles. Static by design — one paint, no ticker — since a
/// background must never cost frames.
class _PuzzleDepthPainter extends CustomPainter {
  final Color deck;
  final Color accent;

  const _PuzzleDepthPainter({required this.deck, required this.accent});

  double _jit(int i) {
    var x = i * 668265263 + 0x5F3759;
    x = (x ^ (x >> 13)) * 1274126177;
    return ((x ^ (x >> 16)) & 0x7FFFFFF) / 0x7FFFFFF;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // Surface light up top, the deck's own water through the middle,
    // true depth at the bottom.
    final surface = Color.lerp(deck, Colors.white, 0.10)!;
    final abyss = const Color(0xFF05090F);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [surface, deck, abyss],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(Offset.zero & size),
    );
    // Slanting light rays from the surface.
    for (var i = 0; i < 3; i++) {
      final x = w * (0.2 + 0.3 * i) + (_jit(i) - 0.5) * w * 0.1;
      canvas.drawPath(
        Path()
          ..moveTo(x, 0)
          ..lineTo(x + w * 0.10, 0)
          ..lineTo(x + w * 0.02, h)
          ..lineTo(x - w * 0.08, h)
          ..close(),
        Paint()..color = Colors.white.withValues(alpha: 0.05),
      );
    }
    // Accent glow behind the cannon's end of the water.
    canvas.drawCircle(
      Offset(w / 2, h * 0.92),
      w * 0.55,
      Paint()
        ..shader = RadialGradient(
          colors: [
            accent.withValues(alpha: 0.20),
            accent.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(
            center: Offset(w / 2, h * 0.92), radius: w * 0.55)),
    );
    // Rising bubbles, deterministic per index.
    for (var i = 0; i < 14; i++) {
      final x = _jit(i + 11) * w;
      final y = _jit(i + 47) * h;
      final r = 1.5 + _jit(i + 83) * 3;
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Colors.white
              .withValues(alpha: 0.10 + _jit(i + 5) * 0.12),
      );
    }
    // Vignette to close off the edges.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.75,
          colors: const [
            Color(0x00000000),
            Color(0x73000000),
          ],
          stops: const [0.55, 1.0],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant _PuzzleDepthPainter old) =>
      old.deck != deck || old.accent != accent;
}

/// Draws a family's projectile into the flight layer.
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
/// layer.
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
