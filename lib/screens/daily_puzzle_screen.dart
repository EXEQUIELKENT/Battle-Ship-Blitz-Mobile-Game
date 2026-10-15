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
import '../widgets/battle_grid.dart';
import '../widgets/cannon_widget.dart';
import '../widgets/neon_widgets.dart';
import '../widgets/ocean_background.dart';

/// Daily puzzle: one pre-seeded enemy fleet per calendar day — the same
/// board on every device — sink it within [DailyPuzzle.shotBudget]
/// shots. Solving (or failing) pays Doubloons once per day; replays are
/// free but pay nothing (see `ProfileStore.claimDailyPuzzleReward`).
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

  /// The in-flight shell's clock. Taps while a shell is airborne are
  /// refused with the standard denied blip rather than restarting the
  /// shell mid-air.
  late final AnimationController _shotCtrl;

  /// Cell the airborne shell is heading for (also the grid reticle).
  List<int>? _aimCell;
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
    final muzzle = Offset(
      _cannonCenterXPx,
      _cannonCenterYPx - _cannonRenderSizePx * _cannonMuzzleFrac,
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
      setState(() => _aimCell = null);
      return;
    }
    _fxEvents.add(CombatEventLike(r, c, res));
    switch (res) {
      case ShotResult.sunk:
        SoundService.instance.sunk(shipSkinId: profile.shipSkinId);
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
                  '${_today.month}/${_today.day}/${_today.year}  •  SINK THE FLEET IN ${DailyPuzzle.shotBudget} SHOTS',
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
                        'SUNK  ${_puzzle.sunkShips.length}/5'),
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
                          // Themed water behind the board — the equipped
                          // deck color, same as each battle half paints.
                          Positioned.fill(
                            child: Container(color: theme.deck),
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
                              ),
                            ),
                          ),
                          // The shell itself, arcing from the muzzle to
                          // whichever cell was tapped — this gun's own
                          // shell artwork, not a generic ball.
                          if (_aimCell != null) _shotLayer(skin),
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
  Widget _shotLayer(CannonSkin skin) {
    final shellFamily = FleetFamilies.byKey(skin.familyKey);
    final legacyShellId = shellFamily == null ? skin.id : null;
    final isDirectional = shellFamily != null
        ? familyShellIsDirectional(shellFamily.id)
        : legacyShellIsDirectional(legacyShellId!);
    return Positioned.fill(
      child: IgnorePointer(
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
