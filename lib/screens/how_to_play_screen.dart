import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../art/deck_debris.dart';
import '../art/impact_fx.dart';
import '../art/legacy_board_art.dart';
import '../art/legacy_cannon_art.dart';
import '../art/legacy_crosshair_art.dart';
import '../art/family_shell_art.dart';
import '../art/legacy_shell_art.dart';
import '../art/power_up_icons.dart';
import '../core/theme.dart';
import '../models/game_models.dart';
import '../models/power_up.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../widgets/cannon_widget.dart';
import '../widgets/motion.dart';
import '../widgets/ocean_background.dart';
import '../widgets/ship_painter.dart';
import '../widgets/wreck_reveal.dart';
import 'how_to_play_cards.dart';

/// HOW TO PLAY — a playable explanation rather than a wall of rules.
///
/// Every chapter runs the same two-grid arena the real battle screen
/// uses — their water above, your own fleet below — wired to that mode's
/// OWN rules, so the difference between modes is something the player
/// does rather than something they read. The rules come off the same
/// [LanBattleMode] flags a real match runs on ([LanBattleMode.hasTurns],
/// [LanBattleMode.recordsShots], [LanBattleMode.canRearrange],
/// [LanBattleMode.hasPowerUps]), which is what keeps a tutorial from
/// quietly drifting away from the game it is teaching.
///
/// Alongside it are the two things a first-time player cannot get from
/// prose: a LEGEND of every mark the board can show, drawn with the real
/// art, and — in POWER PLAY — diagrams of what each multi-shot card
/// actually covers, generated from `PowerUpShapes` rather than drawn by
/// hand so they cannot disagree with the cards.
///
/// The arena is deliberately NOT a `GameController`: a demo has no
/// opponent, no network and no match to record, and standing one up would
/// mean either faking half of it or letting a tutorial tap affect a real
/// profile.
class HowToPlayScreen extends StatefulWidget {
  const HowToPlayScreen({super.key});

  @override
  State<HowToPlayScreen> createState() => _HowToPlayScreenState();
}

/// A chapter of the guide: the basics, then one per battle mode.
class _Chapter {
  final String title;
  final String tagline;
  final String body;

  /// Null for the BASICS chapter, which teaches the shared rules every
  /// mode is a variation on.
  final LanBattleMode? mode;

  const _Chapter({
    required this.title,
    required this.tagline,
    required this.body,
    this.mode,
  });
}

class _HowToPlayScreenState extends State<HowToPlayScreen> {
  int _chapter = 0;
  final _navCtrl = ScrollController();

  late final List<_Chapter> _chapters = [
    const _Chapter(
      title: 'THE BASICS',
      tagline: 'Tap their water to fire',
      body:
          'Their fleet is hidden on the top grid. Yours is on the bottom '
          'one, where you can see it — they cannot. Tap any square of '
          'their water you have not tried yet.\n\n'
          'A HIT lets you fire again. A MISS hands the guns over. Sink '
          'every hull to win.',
    ),
    for (final mode in LanBattleMode.values)
      _Chapter(
        title: mode.label,
        tagline: mode.tagline,
        body: mode.blurb,
        mode: mode,
      ),
  ];

  @override
  void dispose() {
    _navCtrl.dispose();
    super.dispose();
  }

  void _goTo(int i) {
    if (i < 0 || i >= _chapters.length) return;
    SoundService.instance.click();
    setState(() => _chapter = i);
    // Drag the strip along with the stepper, so the two controls never
    // disagree about where you are.
    if (_navCtrl.hasClients) {
      _navCtrl.animateTo(
        (i * 118.0 - 100).clamp(0.0, _navCtrl.position.maxScrollExtent),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final chapter = _chapters[_chapter];
    return Scaffold(
      body: OceanBackground(
        showSonar: false,
        child: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                color: AppColors.navy,
                padding: const EdgeInsets.fromLTRB(8, 10, 14, 14),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back,
                        color: AppColors.cream,
                      ),
                      onPressed: () {
                        SoundService.instance.click();
                        Navigator.pop(context);
                      },
                    ),
                    Expanded(
                      child: Text(
                        'HOW TO PLAY',
                        style: AppText.title(size: 18),
                      ),
                    ),
                  ],
                ),
              ),
              _stepper(chapter),
              _chapterStrip(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                  children: [
                    _guideCard(chapter),
                    const SizedBox(height: 12),
                    // Keyed by chapter so switching mode starts that
                    // mode's arena fresh rather than inheriting the last
                    // one's half-finished board.
                    _ModeArena(key: ValueKey(_chapter), mode: chapter.mode),
                    const SizedBox(height: 12),
                    if (chapter.mode == LanBattleMode.powerPlay) ...[
                      const _ShapeGuide(),
                      const SizedBox(height: 12),
                      // Every card in the deck, each with a picture of
                      // what it does to the water.
                      const PowerUpGuide(),
                      const SizedBox(height: 12),
                    ],
                    const _Legend(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// FEEDBACK ("the top nav is not scrollable"): the strip below always
  /// could be dragged, but nothing said so — eight chapters ran off the
  /// edge of the screen with no arrow, no fade and no cut-off chip to
  /// hint at it. This stepper is the fix: it reaches every chapter with
  /// no dragging at all, and it drives the strip so the two agree.
  Widget _stepper(_Chapter chapter) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Row(
        children: [
          _navArrow(
            Icons.chevron_left,
            _chapter > 0,
            () => _goTo(_chapter - 1),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  chapter.title,
                  textAlign: TextAlign.center,
                  style: AppText.heading(size: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_chapter + 1} OF ${_chapters.length}',
                  style: AppText.label(size: 9, color: AppColors.mist),
                ),
              ],
            ),
          ),
          _navArrow(
            Icons.chevron_right,
            _chapter < _chapters.length - 1,
            () => _goTo(_chapter + 1),
          ),
        ],
      ),
    );
  }

  Widget _navArrow(IconData icon, bool enabled, VoidCallback onTap) {
    return Opacity(
      opacity: enabled ? 1 : 0.3,
      child: Pressable(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: cartoonBox(AppColors.navy, radius: 12),
          child: Icon(icon, color: AppColors.cream, size: 22),
        ),
      ),
    );
  }

  Widget _chapterStrip() {
    return SizedBox(
      height: 44,
      child: ShaderMask(
        // Fading edges are the affordance the bare strip was missing:
        // a chip half-dissolved at the margin reads as "there is more
        // this way" in a way a hard cut never does.
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ],
          stops: [0.0, 0.05, 0.95, 1.0],
        ).createShader(rect),
        blendMode: BlendMode.dstIn,
        child: ListView.separated(
          controller: _navCtrl,
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          itemCount: _chapters.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final selected = i == _chapter;
            return Center(
              child: Pressable(
                onTap: () => _goTo(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: cartoonBox(
                    selected ? AppColors.gold : AppColors.navyDark,
                    radius: 12,
                  ),
                  child: Text(
                    _chapters[i].title,
                    style: AppText.label(
                      size: 10,
                      color: selected ? AppColors.outline : AppColors.cream,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _guideCard(_Chapter chapter) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: cartoonBox(AppColors.navy, radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            chapter.tagline.toUpperCase(),
            style: AppText.label(size: 10, color: AppColors.gold),
          ),
          const SizedBox(height: 6),
          Text(
            chapter.body,
            style: AppText.body(size: 12, color: AppColors.cream),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Visualization guide
// ---------------------------------------------------------------------------

/// Every mark the board can put on the water, drawn with the REAL art.
///
/// The one thing a new player cannot work out from playing: a miss plate,
/// a spotted hull and an armed mine are all "a thing in a square" until
/// somebody says which is which.
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: cartoonBox(AppColors.navy, radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.visibility, color: AppColors.gold, size: 18),
              const SizedBox(width: 8),
              Text('READING THE BOARD', style: AppText.heading(size: 14)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final mark in _LegendMark.values)
                SizedBox(
                  width: 88,
                  child: Column(
                    children: [
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: CustomPaint(painter: _MarkPainter(mark)),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        mark.label,
                        textAlign: TextAlign.center,
                        style: AppText.label(size: 8),
                      ),
                      Text(
                        mark.blurb,
                        textAlign: TextAlign.center,
                        style: AppText.body(size: 8, color: AppColors.mist),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

enum _LegendMark { hit, miss, sunk, spotted, mine, spy }

extension on _LegendMark {
  String get label => switch (this) {
    _LegendMark.hit => 'HIT',
    _LegendMark.miss => 'MISS',
    _LegendMark.sunk => 'SUNK',
    _LegendMark.spotted => 'SPOTTED',
    _LegendMark.mine => 'YOUR MINE',
    _LegendMark.spy => 'SCOUT',
  };

  String get blurb => switch (this) {
    _LegendMark.hit => 'You found a hull',
    _LegendMark.miss => 'Spent water',
    _LegendMark.sunk => 'The whole hull is gone',
    _LegendMark.spotted => 'A hull is here — not fired at yet',
    _LegendMark.mine => 'Armed on your own water',
    _LegendMark.spy => 'A SPY SHIP on station',
  };
}

class _MarkPainter extends CustomPainter {
  final _LegendMark mark;
  const _MarkPainter(this.mark);

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width;
    final centre = Offset(cell / 2, cell / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(cell * 0.16)),
      Paint()..color = AppColors.steelBlue,
    );
    switch (mark) {
      case _LegendMark.hit:
        paintLegacyHit(canvas, centre, cell, 'mk1');
      case _LegendMark.miss:
        paintLegacyMiss(canvas, centre, cell, 'mk1');
      case _LegendMark.sunk:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(2, 2, cell - 4, cell - 4),
            Radius.circular(cell * 0.14),
          ),
          Paint()..color = AppColors.outline,
        );
        paintLegacyHit(canvas, centre, cell * 0.8, 'mk1');
      case _LegendMark.spotted:
        canvas.drawCircle(
          centre,
          cell * 0.30,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = cell * 0.07
            ..color = AppColors.cream,
        );
        canvas.drawCircle(
          centre,
          cell * 0.12,
          Paint()..color = AppColors.cream,
        );
      case _LegendMark.mine:
        final r = cell * 0.22;
        final d = Path()
          ..moveTo(centre.dx, centre.dy - r)
          ..lineTo(centre.dx + r, centre.dy)
          ..lineTo(centre.dx, centre.dy + r)
          ..lineTo(centre.dx - r, centre.dy)
          ..close();
        canvas.drawPath(d, Paint()..color = AppColors.gold);
        canvas.drawPath(
          d,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = cell * 0.05
            ..color = AppColors.outline,
        );
      case _LegendMark.spy:
        canvas.drawCircle(
          centre,
          cell * 0.34,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = cell * 0.05
            ..color = AppColors.gold.withValues(alpha: 0.85),
        );
        final hull = Path()
          ..moveTo(centre.dx - cell * 0.22, centre.dy + cell * 0.02)
          ..lineTo(centre.dx + cell * 0.22, centre.dy + cell * 0.02)
          ..lineTo(centre.dx + cell * 0.13, centre.dy + cell * 0.17)
          ..lineTo(centre.dx - cell * 0.13, centre.dy + cell * 0.17)
          ..close();
        canvas.drawPath(hull, Paint()..color = AppColors.cream);
        canvas.drawLine(
          Offset(centre.dx + cell * 0.04, centre.dy + cell * 0.02),
          Offset(centre.dx + cell * 0.04, centre.dy - cell * 0.18),
          Paint()
            ..strokeWidth = cell * 0.06
            ..strokeCap = StrokeCap.round
            ..color = AppColors.outline,
        );
        canvas.drawCircle(
          Offset(centre.dx + cell * 0.04, centre.dy - cell * 0.20),
          cell * 0.06,
          Paint()..color = AppColors.gold,
        );
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.mark != mark;
}

/// What each multi-shot power-up actually covers.
///
/// Generated from `PowerUpShapes` rather than drawn by hand, so a diagram
/// can never claim a shape the card does not fire — including the edge
/// SLIDE, which is the part players get wrong: a CROSS FIRE tapped in the
/// corner does not lose shots, it moves.
class _ShapeGuide extends StatelessWidget {
  const _ShapeGuide();

  static const _cards = [
    (PowerUpCard.salvo, 2, 2),
    (PowerUpCard.depthCharge, 2, 2),
    (PowerUpCard.crossFire, 2, 2),
    (PowerUpCard.crossFire, 0, 0),
  ];

  static List<(int, int)> _cells(PowerUpCard card, int r, int c) =>
      switch (card) {
        PowerUpCard.salvo => PowerUpShapes.salvo(r, c),
        PowerUpCard.depthCharge => PowerUpShapes.depthCharge(r, c),
        PowerUpCard.crossFire => PowerUpShapes.crossFire(r, c),
        _ => [(r, c)],
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: cartoonBox(AppColors.navy, radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.grid_on, color: AppColors.gold, size: 18),
              const SizedBox(width: 8),
              Text('WHAT EACH CARD COVERS', style: AppText.heading(size: 14)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Blue is the square you tap. Red is what it fires at. Tapped '
            'against an edge a shape SLIDES back on-board — it never loses '
            'a shot.',
            style: AppText.body(size: 10, color: AppColors.mist),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final (card, r, c) in _cards)
                SizedBox(
                  width: 92,
                  child: Column(
                    children: [
                      SizedBox(
                        width: 82,
                        height: 82,
                        child: CustomPaint(
                          painter: _ShapePainter(
                            aim: (r, c),
                            cells: _cells(card, r, c),
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        PowerUps.of(card).name,
                        textAlign: TextAlign.center,
                        style: AppText.label(size: 8),
                      ),
                      if (r == 0 && c == 0)
                        Text(
                          'at a corner',
                          style: AppText.body(size: 8, color: AppColors.gold),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShapePainter extends CustomPainter {
  final (int, int) aim;
  final List<(int, int)> cells;
  const _ShapePainter({required this.aim, required this.cells});

  static const _n = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / _n;
    final fired = cells.toSet();
    for (var r = 0; r < _n; r++) {
      for (var c = 0; c < _n; c++) {
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(c * cell + 1, r * cell + 1, cell - 2, cell - 2),
          Radius.circular(cell * 0.2),
        );
        var color = AppColors.steelBlue;
        if (fired.contains((r, c))) color = AppColors.hit;
        canvas.drawRRect(rect, Paint()..color = color);
        if ((r, c) == aim) {
          canvas.drawRRect(
            rect,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5
              ..color = AppColors.shipBlue,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_ShapePainter old) => old.cells != cells;
}

// ---------------------------------------------------------------------------
// The playable arena
// ---------------------------------------------------------------------------

/// The guide's board is the REAL board.
///
/// BUGFIX ("the hit and miss is misaligned"): it was a 6×6 board — but
/// `paintLegacyBoard` draws its gridlines from a fixed 10×10 lattice
/// (`_grid40`, ten divisions of a 400-unit box), the same one the real
/// game plays on. So the guide painted ten columns of water and then
/// placed its marks on a six-column grid: every hit and miss landed
/// between the lines instead of in a square, and the further from the
/// top-left corner it was, the worse it looked.
///
/// Matching `kBoardSize` fixes the alignment at the root — no mark can
/// disagree with a line that is derived from the same number — and it is
/// the honest answer to "make it look like the gameplay" as well: the
/// game is played on ten by ten.
const int _demoSize = kBoardSize;

/// One hull on the demo board.
class _DemoShip {
  int row;
  int col;
  bool horizontal;
  final int length;
  final Set<int> hits = {};

  /// When this hull went down, so the guide can play the same wreck
  /// reveal the real board does instead of the wreck simply appearing.
  /// Null until it sinks.
  DateTime? sankAt;

  _DemoShip(this.row, this.col, this.horizontal, this.length);

  bool get sunk => hits.length >= length;

  /// 0→1 over the wreck reveal, 1 once it has settled.
  double get wreckT {
    final at = sankAt;
    if (at == null) return 1;
    return (DateTime.now().difference(at).inMilliseconds / 900)
        .clamp(0.0, 1.0);
  }

  List<(int, int)> get cells => [
    for (var i = 0; i < length; i++)
      horizontal ? (row, col + i) : (row + i, col),
  ];

  int? indexAt(int r, int c) {
    final list = cells;
    for (var i = 0; i < list.length; i++) {
      if (list[i].$1 == r && list[i].$2 == c) return i;
    }
    return null;
  }
}


/// Where everything sits inside the guide's arena, so a shell can be
/// aimed from a muzzle at a cell across the board.
class _ArenaGeom {
  final double cell;
  final double theirGridTop;
  final double myGridTop;
  final Offset theirMuzzle;
  final Offset myMuzzle;
  final double gun;

  const _ArenaGeom({
    required this.cell,
    required this.theirGridTop,
    required this.myGridTop,
    required this.theirMuzzle,
    required this.myMuzzle,
    required this.gun,
  });
}
/// One thing the guide is currently asking the player to do.
class _Goal {
  final String text;
  final bool Function(_ModeArenaState s) done;
  const _Goal(this.text, this.done);
}

/// Two grids, a middle band and a live opponent — the real battle screen's
/// shape, at tutorial scale, playing by one mode's rules.
class _ModeArena extends StatefulWidget {
  final LanBattleMode? mode;
  const _ModeArena({super.key, required this.mode});

  @override
  State<_ModeArena> createState() => _ModeArenaState();
}

class _ModeArenaState extends State<_ModeArena> with TickerProviderStateMixin {
  final _rng = Random(4);

  late List<_DemoShip> _enemy;
  late List<_DemoShip> _mine;

  /// 0 unknown, 1 miss, 2 hit — the same encoding the real board uses.
  late List<List<int>> _myShots; // what I have fired at THEM
  late List<List<int>> _theirShots; // what they have fired at ME

  final Map<int, DateTime> _myMarkedAt = {};
  final Map<int, _Fx> _fxEnemy = {};
  final Map<int, _Fx> _fxMine = {};

  /// Taps on the enemy grid waiting to ripple. The real board answers a
  /// tap the instant it lands, before the shell has even left the gun —
  /// which is what makes it feel responsive rather than laggy — so the
  /// guide has to do it too.
  final Map<int, DateTime> _tapFx = {};

  /// The square the player's shell is currently flying at, or null when
  /// nothing is in the air — what the targeting reticle locks onto.
  (int, int)? _aimCell;
  late final AnimationController _fxCtrl;

  bool _myTurn = true;
  String _hint = '';
  /// FEEDBACK ("on POWER PLAY make sure all of the power-ups are
  /// usable"): the chapter dealt one card — SALVO — forever, so
  /// twenty-three of the twenty-four were things the guide described and
  /// the player could never touch. The arena draws from the real deck
  /// now (`PowerUps.draw`, the same weighted draw a match uses) and every
  /// card it can deal does something on the board.
  ///
  /// The card in hand, or null when there is none.
  PowerUpCard? _card;

  /// The card is armed and waiting for the player to pick a square.
  bool _armed = false;
  bool _hasCard = false;

  /// Enemy water this turn's intel has lit up — SONAR, SPOTTER, RECON
  /// SWEEP and SPY SHIP all write here, and the board draws it as a gold
  /// ring the way the real grid draws `spottedEnemyCells`.
  final Set<int> _revealed = {};

  /// My own water that is mined or trapped (MINEFIELD / TRAP LINE).
  final Set<int> _mined = {};

  /// Hulls of mine wearing ARMOUR PLATE this turn, by index into [_mine].
  final Set<int> _armoured = {};

  /// Rules this turn's card has bent: a miss that does not end the turn
  /// (DOUBLE TAP), a free second shot (RAPID FIRE), and so on.
  bool _missIsFree = false;
  int _extraShots = 0;
  bool _jammed = false;

  /// COUNTER BATTERY: "the next hit on you earns you an extra shot on
  /// your next turn."
  bool _counterArmed = false;

  /// Shots the counter has earned, banked until the turn actually
  /// starts — see the expiry sweep in `_handBack`.
  int _counterPayout = 0;

  /// DECOY: "the next hit on you is reported as a miss, and takes no
  /// damage."
  bool _decoyArmed = false;

  /// HOT SHOT: "your next hit also damages the nearest unhit cell of that
  /// same hull."
  bool _hotShot = false;

  /// Index into [_mine] of the hull holding AUTO DODGE, or null.
  int? _dodgeShip;

  /// Whether the card in hand wants a square of YOUR water rather than
  /// theirs. Read straight off the real definition, so the guide arms
  /// the same grid a match would.
  bool get _cardTargetsOwnGrid =>
      _card != null && PowerUps.of(_card!).targetsOwnGrid;
  double _reload = 1;
  Timer? _reloadTimer;
  Timer? _theirReloadTimer;
  Timer? _aiTimer;

  int _shotsFired = 0;
  int _hitsScored = 0;
  bool _usedCard = false;
  bool _sawFleetMove = false;
  bool _tookFire = false;
  int _goal = 0;

  /// Index of the "move your fleet" goal, so the board being asked for
  /// can ring itself — the guide already does this for the enemy water
  /// on the "fire your first shell" goal. −1 in modes that have no such
  /// goal, which never matches [_goal].
  int get _fleetGoal =>
      _goals.indexWhere((g) => g.text.startsWith('Your fleet can run'));


  // ---- Real gear, real flight ----
  //
  // FEEDBACK ("add the default cannon, ships, deck, with projectile
  // animation fire and reload and fire"): the guide used to draw flat
  // rectangles on flat blue. It now runs the gear a brand-new profile
  // actually sails with — the MK-I gun, its deck, its shell, and the
  // Steel Fleet hulls — and a shot really crosses the water before it
  // lands, with the gun reloading afterwards.
  static const double _arenaMaxWidth = 340;
  /// Height of the status band between the two decks.
  ///
  /// Two rows now, like the real one (`_buildMiddleBand`), so it needs
  /// real room: the old 26px strip held a two-line hint inside 6px of
  /// padding and clipped the fleet counts either side of it clean off.
  static const double _bandH = 44;

  /// How far each deck runs out past its own board — the margin the real
  /// screen gets for free by giving the whole half the deck colour.
  static const double _deckPad = 6;

  /// The board the guide sails on. One lookup, so the deck behind the
  /// grid and the board drawn inside it can never be two different
  /// themes.
  static final GameplayTheme _theme =
      Catalog.gameplayThemeById(_ArenaPainter.kDefaultCannon);

  /// One half's deck — the surface a board and its gun sit on.
  Widget _deck({required bool top}) => DecoratedBox(
        decoration: BoxDecoration(
          color: _theme.deck,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(top ? 14 : 4),
            bottom: Radius.circular(top ? 4 : 14),
          ),
          border: Border.all(color: AppColors.outline, width: 2),
        ),
      );

  final CannonSkin _gunSkin = Catalog.cannonById('mk1');
  final _myFire = StreamController<void>.broadcast();
  final _myReady = StreamController<void>.broadcast();
  final _theirFire = StreamController<void>.broadcast();

  /// Where each gun's barrel is pointing, in radians off dead ahead —
  /// the same barrel-only traverse the real battle screen uses.
  double _myAim = 0;
  double _theirAim = 0;

  double _theirReload = 1;

  /// Laid out fresh each build; null until the arena has been measured
  /// once, which is why every shot checks it before taking off.
  _ArenaGeom? _geom;

  /// Shells currently crossing the water.
  final List<_Shell> _shells = [];

  /// Cells still to fire for the action in progress — one for an
  /// ordinary shot, three for a SALVO. Kept so a volley's shells leave
  /// the muzzle one after another rather than all at once.
  final List<(int, int)> _queue = [];

  /// True when the player is allowed to pull the trigger right now.
  bool get _canFire =>
      _reload >= 1 && (!_hasTurns || _myTurn) && !_myShellInAir;

  /// Whether one of MY shells is still crossing. Only mine: an incoming
  /// shell must not lock my gun, or CHAOS cannot happen — see [_Shell.mine].
  bool get _myShellInAir => _shells.any((s) => s.mine && !s.landed);

  /// Points [gun] at a cell and returns the angle, so the shell can leave
  /// the muzzle the barrel has actually swung to.
  double _aimAt(Offset muzzle, Offset target, {required bool mine}) {
    // Rest heading: my gun points up the screen, theirs points down.
    final rest = mine ? -pi / 2 : pi / 2;
    var delta = (target - muzzle).direction - rest;
    while (delta > pi) {
      delta -= 2 * pi;
    }
    while (delta <= -pi) {
      delta += 2 * pi;
    }
    return delta.clamp(-0.85, 0.85);
  }

  /// Sends a shell from [mine ? my gun : theirs] at a cell of the other
  /// side's deck, and calls [onLand] when it arrives.
  ///
  /// Nothing about the shot is decided here — the mark, the sound and the
  /// turn all wait for the shell to actually land, which is the whole
  /// point of showing the flight at all.
  void _launchShell({
    required bool mine,
    required int r,
    required int c,
    required VoidCallback onLand,
  }) {
    final g = _geom;
    if (g == null) {
      onLand();
      return;
    }
    final from = mine ? g.myMuzzle : g.theirMuzzle;
    final gridTop = mine ? g.theirGridTop : g.myGridTop;
    final to = Offset(
      c * g.cell + g.cell / 2,
      gridTop + r * g.cell + g.cell / 2,
    );
    final aim = _aimAt(from, to, mine: mine);
    final muzzle = from +
        Offset.fromDirection(
          (mine ? -pi / 2 : pi / 2) + aim,
          g.gun * CannonWidget.muzzleFractionOf(_gunSkin),
        );
    setState(() {
      if (mine) {
        _myAim = aim;
        _reload = 0;
        // The reticle locks onto the square the shell is flying at and
        // stays there for the flight, exactly as `BattleGrid`'s own
        // `_Crosshair` does — it is how the real board tells you WHICH
        // square is about to be answered while the shell is still in the
        // air, and the guide was leaving the player to guess.
        _aimCell = (r, c);
      } else {
        _theirAim = aim;
        _theirReload = 0;
      }
      _shells.add(_Shell(
        from: muzzle,
        to: to,
        arc: g.cell * 2.2,
        mine: mine,
        onLand: onLand,
      ));
    });
    (mine ? _myFire : _theirFire).add(null);
    SoundService.instance.cannonFire(cannonSkinId: _gunSkin.id);
    if (!_fxCtrl.isAnimating) _fxCtrl.repeat();
  }

  /// Advances every shell in the air and lands the ones that have
  /// arrived. Driven by the same ticker the impact effects run on.
  void _tickShells() {
    if (_shells.isEmpty) return;
    final landed = _shells.where((s) => s.t >= 1 && !s.landed).toList();
    for (final s in landed) {
      s.landed = true;
    }
    _shells.removeWhere((s) => s.landed);
    for (final s in landed) {
      s.onLand();
    }
  }
  bool get _recordsShots => widget.mode?.recordsShots ?? true;
  bool get _hasTurns => widget.mode?.hasTurns ?? true;
  bool get _canRearrange => widget.mode?.canRearrange ?? false;
  bool get _hasPowerUps => widget.mode?.hasPowerUps ?? false;
  bool get _isPhantom => widget.mode == LanBattleMode.phantom;

  /// What the guide walks the player through, in order. Built from the
  /// same flags the arena itself plays by, so a chapter can never ask for
  /// something its own mode does not do.
  late final List<_Goal> _goals = [
    _Goal(
      'Tap their water (the top grid) to fire your first shell.',
      (s) => s._shotsFired > 0,
    ),
    _Goal(
      'Keep hunting — land a HIT and you fire again straight away.',
      (s) => s._hitsScored > 0,
    ),
    if (!_recordsShots)
      _Goal(
        'Watch your mark fade. This mode records nothing — only your '
        'memory keeps score.',
        (s) => s._shotsFired >= 3,
      ),
    if (_isPhantom)
      _Goal(
        'Fire into a hole you already made. In PHANTOM a repeat is '
        'wasted — it scores nothing.',
        (s) => s._shotsFired >= 4,
      ),
    if (_canRearrange)
      _Goal(
        'Your fleet can run. Press and hold one of your own undamaged '
        'hulls and drag it to new water — or tap it to turn it. Damaged '
        'hulls are stuck.',
        (s) => s._sawFleetMove,
      ),
    if (_hasPowerUps)
      _Goal(
        'You are holding a card — a different one each turn, from the '
        'real deck. Tap it to spend it; the aimed ones then want a '
        'square.',
        (s) => s._usedCard,
      ),
    if (_hasTurns)
      _Goal(
        'Miss, and the guns pass over. Let them take a shot at you.',
        (s) => s._tookFire,
      )
    else
      _Goal(
        'No turns here — fire whenever your gun has reloaded.',
        (s) => s._shotsFired >= 4,
      ),
    _Goal(
      'That is the whole game. Sink their fleet, or try another mode '
      'from the strip above.',
      (s) => false,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _reset();
    _fxCtrl =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 800),
        )..addListener(() {
          if (!mounted) return;
          // One ticker drives everything that moves on its own: shells in
          // flight, impact effects burning down, and marks fading out.
          _tickShells();
          setState(() {
            _fxEnemy.removeWhere((_, f) => f.done);
            _fxMine.removeWhere((_, f) => f.done);
            final now = DateTime.now();
            _tapFx.removeWhere(
                (_, at) => now.difference(at).inMilliseconds > 400);
            // BUGFIX: the ticker used to stop the moment the impacts had
            // burned down — which is BEFORE a wreck reveal (900ms) or a
            // tap ripple has finished, so a sinking hull froze halfway
            // through its roll and sat there. Anything still animating
            // keeps the one ticker alive; it still shuts off the instant
            // nothing on the board is moving, which is the point of
            // stopping it at all.
            final sinking = [..._enemy, ..._mine]
                .any((s) => s.sunk && s.wreckT < 1);
            if (_fxEnemy.isEmpty &&
                _fxMine.isEmpty &&
                _shells.isEmpty &&
                _tapFx.isEmpty &&
                !sinking &&
                _recordsShots) {
              _fxCtrl.stop();
            }
          });
        });
  }

  void _reset() {
    // The REAL fleet — all five hulls at their real lengths, one per
    // `kFleet` spec and in the same order, so the guide teaches the fleet
    // the player is actually given and the status strip below can show
    // the same five ships a match's does.
    //
    // Hand-placed rather than randomised: a tutorial should look the same
    // every time it is opened, and these spreads keep a hull within a few
    // taps of wherever a first-time player starts poking.
    _enemy = [
      _DemoShip(1, 2, true, 5), // carrier
      _DemoShip(3, 6, false, 4), // battleship
      _DemoShip(5, 1, true, 3), // cruiser
      _DemoShip(7, 4, true, 3), // submarine
      _DemoShip(8, 8, false, 2), // destroyer
    ];
    _mine = [
      _DemoShip(0, 4, true, 5),
      _DemoShip(2, 1, false, 4),
      _DemoShip(4, 5, true, 3),
      _DemoShip(6, 2, true, 3),
      _DemoShip(8, 7, true, 2),
    ];
    _myShots = List.generate(_demoSize, (_) => List.filled(_demoSize, 0));
    _theirShots = List.generate(_demoSize, (_) => List.filled(_demoSize, 0));
    _myMarkedAt.clear();
    _fxEnemy.clear();
    _fxMine.clear();
    _tapFx.clear();
    _aimCell = null;
    _myAim = 0;
    _theirAim = 0;
    _theirReloadTimer?.cancel();
    _theirReload = 1;
    _myTurn = true;
    _armed = false;
    _card = _hasPowerUps ? PowerUps.draw(_rng) : null;
    _hasCard = _hasPowerUps;
    _revealed.clear();
    _mined.clear();
    _armoured.clear();
    _dodgeShip = null;
    _missIsFree = false;
    _extraShots = 0;
    _jammed = false;
    _counterArmed = false;
    _counterPayout = 0;
    _decoyArmed = false;
    _hotShot = false;
    _reload = 1;
    _shotsFired = 0;
    _hitsScored = 0;
    _usedCard = false;
    _sawFleetMove = false;
    _tookFire = false;
    _goal = 0;
    _hint = _hasTurns ? 'Your turn.' : 'Fire whenever you like.';
    // In a no-turn mode the opponent starts shooting straight away and
    // keeps shooting, whatever you do — see [_scheduleChaosShot].
    _aiTimer?.cancel();
    _scheduleChaosShot();
  }

  @override
  void dispose() {
    _reloadTimer?.cancel();
    _theirReloadTimer?.cancel();
    _aiTimer?.cancel();
    _fxCtrl.dispose();
    _myFire.close();
    _myReady.close();
    _theirFire.close();
    super.dispose();
  }

  _DemoShip? _shipAt(List<_DemoShip> fleet, int r, int c) {
    for (final s in fleet) {
      if (s.indexAt(r, c) != null) return s;
    }
    return null;
  }

  /// Advances the guide past every goal the player has now met.
  void _advanceGoals() {
    while (_goal < _goals.length - 1 && _goals[_goal].done(this)) {
      _goal++;
    }
  }

  void _tapEnemy(int r, int c) {
    // Before any of the rules below get a say: the tap itself is
    // acknowledged. The real board pulses the cell the moment a finger
    // lands on it, whether or not the shot turns out to be legal, which
    // is the difference between "nothing happened" and "I heard you, but
    // no". Doing this only on a VALID shot — as the guide did — made a
    // blocked tap feel like a dropped one.
    _tapFx[r * _demoSize + c] = DateTime.now();
    _tapFx.removeWhere(
      (_, at) => DateTime.now().difference(at).inMilliseconds > 400,
    );
    if (!_fxCtrl.isAnimating) _fxCtrl.repeat();
    if (_myShellInAir) {
      // One of MY shells is still crossing. Firing over it would let the
      // guide resolve two of my shots at once. Theirs is not my problem —
      // in CHAOS the two are supposed to pass each other.
      SoundService.instance.denied();
      return;
    }
    if (_reload < 1) {
      SoundService.instance.denied();
      _hint = 'Still reloading — watch the ring on your gun.';
      setState(() {});
      return;
    }
    if (_hasTurns && !_myTurn) {
      SoundService.instance.denied();
      _hint = 'Not your turn — they are firing.';
      setState(() {});
      return;
    }
    if (_recordsShots && _myShots[r][c] != 0) {
      SoundService.instance.denied();
      _hint = 'Already tried that square.';
      setState(() {});
      return;
    }
    if (_armed) {
      _resolveCardAt(r, c);
      setState(() {});
      return;
    }
    _queue
      ..clear()
      ..add((r, c));
    _fireNextQueued();
    _advanceGoals();
    setState(() {});
  }

  /// Spends the card in hand.
  ///
  /// [r]/[c] is the square the player picked, and is meaningless for the
  /// cards that need no target — those resolve straight out of
  /// [_useCard]. Every branch here does what that card's own
  /// `description` says it does, because the descriptions are the strings
  /// the guide prints beside them: a card that claimed one thing and did
  /// another would be worse than one that did nothing.
  void _resolveCardAt(int r, int c) {
    final card = _card;
    if (card == null) return;
    final def = PowerUps.of(card);
    _armed = false;
    _hasCard = false;
    _card = null;
    _usedCard = true;

    // Shaped shots: fire every cell of the shape, one shell at a time, so
    // a volley reads as several shots rather than a single flash. The
    // shapes come from `PowerUpShapes` — the same code the real cards
    // fire through — so a guide volley cannot cover different water than
    // the card does.
    List<(int, int)>? shape;
    switch (card) {
      case PowerUpCard.salvo:
        shape = PowerUpShapes.salvo(r, c);
      case PowerUpCard.depthCharge:
        shape = PowerUpShapes.depthCharge(r, c);
      case PowerUpCard.crossFire:
        shape = PowerUpShapes.crossFire(r, c);
      case PowerUpCard.spray:
        // Two cells: the one you picked and a random other.
        shape = PowerUpShapes.spray((r, c), _randomFreeCell() ?? (r, c));
      case PowerUpCard.chainShot:
        final extra = _neighbourOf(r, c) ?? (r, c);
        shape = [(r, c), if (extra != (r, c)) extra];
      default:
        shape = null;
    }
    if (shape != null) {
      _queue
        ..clear()
        ..addAll(shape);
      _hint = '${def.name} — ${shape.length} shells for one action.';
      _fireNextQueued();
      _advanceGoals();
      return;
    }

    switch (card) {
      // ---- intel: light up enemy water without firing at it ----
      case PowerUpCard.sonar:
        var count = 0;
        for (var dr = -1; dr <= 1; dr++) {
          for (var dc = -1; dc <= 1; dc++) {
            final rr = r + dr, cc = c + dc;
            if (rr < 0 || rr >= _demoSize || cc < 0 || cc >= _demoSize) {
              continue;
            }
            _revealed.add(rr * _demoSize + cc);
            if (_shipAt(_enemy, rr, cc) != null) count++;
          }
        }
        _hint = 'SONAR: $count hull ${count == 1 ? 'cell' : 'cells'} in '
            'that 3×3 — the count, not which ones.';
      case PowerUpCard.reconSweep:
        var any = false;
        for (var cc = 0; cc < _demoSize; cc++) {
          _revealed.add(r * _demoSize + cc);
          if (_shipAt(_enemy, r, cc) != null) any = true;
        }
        _hint = any
            ? 'RECON SWEEP: something is in that row.'
            : 'RECON SWEEP: that row is empty water.';

      // ---- your own water ----
      case PowerUpCard.minefield:
        _mined.add(r * _demoSize + c);
        _hint = 'MINEFIELD — that square of YOUR water is armed.';
      case PowerUpCard.trapLine:
        for (final p in PowerUpShapes.salvo(r, c)) {
          _mined.add(p.$1 * _demoSize + p.$2);
        }
        _hint = 'TRAP LINE — three squares of your water are armed.';
      case PowerUpCard.armourPlate:
        final i = _mine.indexWhere((s) => s.indexAt(r, c) != null);
        if (i >= 0) {
          _armoured.add(i);
          _hint = 'ARMOUR PLATE — that hull shrugs off the next hit.';
        } else {
          _hint = 'No hull there. The card is spent.';
        }
      case PowerUpCard.autoDodge:
        final i = _mine.indexWhere((s) => s.indexAt(r, c) != null);
        if (i >= 0) {
          _dodgeShip = i;
          _hint = 'AUTO DODGE — that hull will slip the next shell.';
        } else {
          _hint = 'No hull there. The card is spent.';
        }
      case PowerUpCard.hardTurn:
        // Targeted in the real deck — you pick WHICH hull comes about —
        // so it turns the one under the finger, pivoting on that cell so
        // the ship does not swing its bow across the board.
        final s = _mine.firstWhere((s) => s.indexAt(r, c) != null,
            orElse: () => _mine.first);
        final idx = s.indexAt(r, c);
        if (idx == null || s.hits.isNotEmpty) {
          _hint = 'HARD TURN — pick an undamaged hull of your own. Spent.';
        } else {
          final row = s.horizontal ? r - idx : r;
          final col = s.horizontal ? c : c - idx;
          _hint = _moveShip(s, row, col, horizontal: !s.horizontal)
              ? 'HARD TURN — that hull has come about.'
              : 'HARD TURN — no room to turn there. Spent.';
        }
      case PowerUpCard.spyShip:
        _revealed.add(r * _demoSize + c);
        _hint = 'SPY SHIP — an outpost on their water. It reports what '
            'sails past until they find it.';
      default:
        _hint = '${def.name} spent.';
    }
    _advanceGoals();
  }

  /// Tapping the card in hand.
  ///
  /// A card that needs a square goes into "armed" and waits for the tap;
  /// everything else resolves right here. That split is the real one —
  /// `PowerUpDef.needsTarget` — so the guide arms exactly the cards a
  /// match arms and no others.
  void _useCard() {
    final card = _card;
    if (card == null) return;
    final def = PowerUps.of(card);
    SoundService.instance.click();

    if (def.needsTarget) {
      setState(() {
        _armed = !_armed;
        _hint = _armed
            ? '${def.name} — tap ${def.targetsOwnGrid ? 'your own' : 'their'} '
                'water to aim it.'
            : '${def.name} put away.';
      });
      return;
    }

    _hasCard = false;
    _card = null;
    _usedCard = true;

    switch (card) {
      // ---- rules that bend for a turn ----
      case PowerUpCard.doubleTap:
        _missIsFree = true;
        _hint = 'DOUBLE TAP — a miss will not end your turn.';
      case PowerUpCard.rapidFire:
        _extraShots += 1;
        _hint = 'RAPID FIRE — you get a second shot this turn.';
      case PowerUpCard.hotShot:
        // NOT an extra shot — which is what this did before, and is a
        // different card entirely. Its own text is "your next hit also
        // damages the nearest unhit cell of that same hull", so it is
        // bonus damage on the hull you hit, resolved in [_fire].
        _hotShot = true;
        _hint = 'HOT SHOT — your next hit carries into the same hull.';
      case PowerUpCard.jam:
        _jammed = true;
        _hint = 'JAM — their next card is dead in their hand.';

      // ---- BARRAGE fires without being aimed ----
      case PowerUpCard.barrage:
        // BUGFIX (found by auditing every card against its own
        // definition): BARRAGE is `needsTarget: false`, so it resolves
        // HERE — but its four shots were only wired into the aimed path
        // in `_resolveCardAt`, which an unaimed card never reaches. It
        // fell through to "BARRAGE spent." and did nothing at all.
        final shape = PowerUpShapes.barrage(_rng, _firedCells());
        if (shape.isEmpty) {
          _hint = 'BARRAGE — no unfired water left. Spent.';
        } else {
          _queue
            ..clear()
            ..addAll(shape);
          _hint = 'BARRAGE — ${shape.length} shots into unfired water.';
          _fireNextQueued();
        }

      case PowerUpCard.counterBattery:
        // Was a hint and nothing else. Now it arms, and the next hit YOU
        // take pays you a shot — resolved where their shell lands.
        _counterArmed = true;
        _hint = 'COUNTER BATTERY — the next hit on you buys you a shot.';
      case PowerUpCard.decoy:
        // Also a hint and nothing else before this.
        _decoyArmed = true;
        _hint = 'DECOY — their next hit on you finds a ghost instead.';

      // ---- your own fleet ----
      case PowerUpCard.repair:
      case PowerUpCard.patchCrew:
        final hurt = _mine
            .where((s) => s.hits.isNotEmpty && !s.sunk)
            .toList()
          ..sort((a, b) => b.hits.length.compareTo(a.hits.length));
        if (hurt.isEmpty) {
          _hint = '${def.name} — nothing of yours is damaged. Spent.';
        } else {
          final mend = card == PowerUpCard.patchCrew ? 2 : 1;
          for (var i = 0; i < mend && hurt.first.hits.isNotEmpty; i++) {
            hurt.first.hits.remove(hurt.first.hits.last);
          }
          _hint = '${def.name} — ${hurt.first.length}-cell hull patched up.';
        }
      case PowerUpCard.scramble:
        final moved = _scrambleOne();
        _hint = moved
            ? 'SCRAMBLE — one of your hulls has slipped to new water.'
            : 'SCRAMBLE — no room to run. Spent.';
      case PowerUpCard.spotter:
        final cell = _unknownEnemyHullCell();
        if (cell == null) {
          _hint = 'SPOTTER — nothing left to find. Spent.';
        } else {
          _revealed.add(cell.$1 * _demoSize + cell.$2);
          _hint = 'SPOTTER — one of their hulls is sitting right there.';
        }
      default:
        _hint = '${def.name} spent.';
    }
    setState(() => _advanceGoals());
  }

  /// Moves one undamaged hull of mine somewhere else legal — SCRAMBLE.
  bool _scrambleOne() {
    final free = _mine.where((s) => s.hits.isEmpty).toList();
    if (free.isEmpty) return false;
    return _scrambleShip(free[_rng.nextInt(free.length)]);
  }

  /// Moves THIS hull somewhere else legal — what AUTO DODGE does to the
  /// ship a shell is about to land on.
  bool _scrambleShip(_DemoShip ship) {
    for (var attempt = 0; attempt < 60; attempt++) {
      final h = _rng.nextBool();
      final row = _rng.nextInt(_demoSize);
      final col = _rng.nextInt(_demoSize);
      if (_moveShip(ship, row, col, horizontal: h)) return true;
    }
    return false;
  }

  /// A cell holding an enemy hull that has not been found yet — what
  /// SPOTTER hands you.
  (int, int)? _unknownEnemyHullCell() {
    final hidden = <(int, int)>[
      for (final s in _enemy)
        if (!s.sunk)
          for (final p in s.cells)
            if (_myShots[p.$1][p.$2] == 0 &&
                !_revealed.contains(p.$1 * _demoSize + p.$2))
              p,
    ];
    if (hidden.isEmpty) return null;
    return hidden[_rng.nextInt(hidden.length)];
  }

  /// A cell nobody has fired at yet, for the cards that pick their own.
  (int, int)? _randomFreeCell() {
    final free = <(int, int)>[
      for (var r = 0; r < _demoSize; r++)
        for (var c = 0; c < _demoSize; c++)
          if (_myShots[r][c] == 0) (r, c),
    ];
    if (free.isEmpty) return null;
    return free[_rng.nextInt(free.length)];
  }

  /// Everything already fired at, so a card that picks its own cells does
  /// not waste a shell on water it has already covered.
  Set<(int, int)> _firedCells() => {
        for (var r = 0; r < _demoSize; r++)
          for (var c = 0; c < _demoSize; c++)
            if (_myShots[r][c] != 0) (r, c),
      };

  /// A free square next to (r, c) — CHAIN SHOT's bonus shell.
  (int, int)? _neighbourOf(int r, int c) {
    final near = <(int, int)>[
      for (final d in const [(0, 1), (0, -1), (1, 0), (-1, 0)])
        if (r + d.$1 >= 0 &&
            r + d.$1 < _demoSize &&
            c + d.$2 >= 0 &&
            c + d.$2 < _demoSize &&
            _myShots[r + d.$1][c + d.$2] == 0)
          (r + d.$1, c + d.$2),
    ];
    if (near.isEmpty) return null;
    return near[_rng.nextInt(near.length)];
  }

  /// Sends the next shell of the current action on its way. The shot is
  /// only RESOLVED when it lands, which is what makes the flight mean
  /// something rather than being decoration over an instant result.
  void _fireNextQueued() {
    if (_queue.isEmpty) return;
    final (r, c) = _queue.removeAt(0);
    final last = _queue.isEmpty;
    _launchShell(
      mine: true,
      r: r,
      c: c,
      onLand: () {
        if (!mounted) return;
        _fire(r, c, passTurn: last);
        if (!last) {
          _fireNextQueued();
        } else {
          _startReload();
        }
        _advanceGoals();
        setState(() {});
      },
    );
  }

  void _fire(int r, int c, {required bool passTurn}) {
    final ship = _shipAt(_enemy, r, c);
    var hit = ship != null;
    // PHANTOM: a shell into a hole already there is wasted.
    if (_isPhantom && ship != null) {
      final idx = ship.indexAt(r, c)!;
      if (ship.hits.contains(idx)) hit = false;
    }
    if (hit && ship != null) ship.hits.add(ship.indexAt(r, c)!);
    // HOT SHOT: "your next hit also damages the nearest unhit cell of
    // that same hull." Spent on the first hit it sees, whether or not
    // that hit finishes the ship.
    if (hit && ship != null && _hotShot) {
      _hotShot = false;
      final struck = ship.indexAt(r, c)!;
      int? nearest;
      for (var i = 0; i < ship.length; i++) {
        if (ship.hits.contains(i)) continue;
        if (nearest == null ||
            (i - struck).abs() < (nearest - struck).abs()) {
          nearest = i;
        }
      }
      if (nearest != null) {
        ship.hits.add(nearest);
        // Mark the carried cell on the board too, or the hull would show
        // damage on a square the tracking grid still calls unfired.
        final p = ship.cells[nearest];
        _myShots[p.$1][p.$2] = 2;
        _myMarkedAt[p.$1 * _demoSize + p.$2] = DateTime.now();
        _fxEnemy[p.$1 * _demoSize + p.$2] =
            _Fx(p.$1, p.$2, true, recorded: _recordsShots);
        _hint = 'HOT SHOT carried into the next cell of that hull.';
      }
    }
    // Whether THIS shell is the one that finished the hull — the same
    // distinction `ShotResult.sunk` draws on the real board, and the one
    // that earns the big burst and the sinking sound instead of the
    // ordinary hit pair.
    final sank = hit && ship != null && ship.sunk && ship.sankAt == null;
    if (sank) ship.sankAt = DateTime.now();
    _myShots[r][c] = hit ? 2 : 1;
    _myMarkedAt[r * _demoSize + c] = DateTime.now();
    _fxEnemy[r * _demoSize + c] = _Fx(
      r,
      c,
      hit,
      sunk: sank,
      // PHANTOM and GHOST FLEET never write the tracking cache, so there
      // is no mark for the arrival transition to deliver.
      recorded: _recordsShots,
    );
    if (!_fxCtrl.isAnimating) _fxCtrl.repeat();
    // The shell has arrived, so the reticle has nothing left to mark.
    _aimCell = null;
    _shotsFired++;
    if (hit) _hitsScored++;
    if (sank) {
      // The real match announces a kill with the STRUCK hull's own
      // sinking sound, not another hit thud.
      SoundService.instance.sunk(shipSkinId: _defaultShipSkin.id);
    } else if (hit) {
      SoundService.instance.hit();
    } else {
      SoundService.instance.miss();
    }

    if (_enemy.every((s) => s.sunk)) {
      _hint = 'Their fleet is sunk. That is a win.';
      return;
    }
    if (hit) {
      _hint = _isPhantom
          ? 'Something out there — PHANTOM never tells you what.'
          : 'HIT — fire again.';
    } else {
      _hint = _hasTurns ? 'Miss — the guns pass over.' : 'Miss. Reload.';
    }
    if (!passTurn) return;
    if (_hasTurns && !hit) {
      // DOUBLE TAP buys one free miss; RAPID FIRE and HOT SHOT buy an
      // extra shot. Either way the guns stay with you for one more shot
      // instead of passing over.
      if (_missIsFree) {
        _missIsFree = false;
        _hint = "DOUBLE TAP — that miss is free. Fire again.";
      } else if (_extraShots > 0) {
        _extraShots--;
        _hint = "One more shot in hand. Fire again.";
      } else {
        _endTurn();
      }
    }
  }

  /// Moves one of the player's OWN undamaged hulls, which is the half of
  /// the rule they can actually watch happen.
  /// Whether [ship] may legally stand at (row, col) on the given heading.
  ///
  /// The rule the real game enforces (`GameController` / `Board`): on the
  /// board, clear of every other hull, and never onto water the opponent
  /// has already shot — a ship cannot reverse into a known hit.
  bool _fits(_DemoShip ship, int row, int col, bool horizontal) {
    final trial = _DemoShip(row, col, horizontal, ship.length);
    return trial.cells.every(
      (p) =>
          p.$1 >= 0 &&
          p.$1 < _demoSize &&
          p.$2 >= 0 &&
          p.$2 < _demoSize &&
          _theirShots[p.$1][p.$2] == 0 &&
          _mine.every(
            (o) => identical(o, ship) || o.indexAt(p.$1, p.$2) == null,
          ),
    );
  }

  /// FEEDBACK ("in the modes where ships can be moved, make them movable
  /// by the user"): they were not. The guide picked an undamaged hull at
  /// random and teleported it somewhere legal between shots, and the goal
  /// asked the player to WATCH it happen — which teaches that your fleet
  /// moves on its own, the opposite of the rule. MANOEUVRE and the modes
  /// that share `canRearrange` let you drag your own hulls around your
  /// own water, so the guide lets you drag them too (see `_myGrid`'s
  /// drag handlers); this is only the legality check they share.
  ///
  /// The hull being dragged, and which of its cells the finger grabbed —
  /// so a ship picked up by its stern does not jump forward to put its
  /// bow under the finger.
  _DemoShip? _dragShip;
  int _dragGrab = 0;

  void _dragStart(int r, int c) {
    if (!_canRearrange) return;
    for (final s in _mine) {
      final idx = s.indexAt(r, c);
      if (idx == null) continue;
      // A damaged hull is pinned: the rule is that a ship which has
      // already been hit cannot run, which is what stops a player simply
      // walking a wounded ship away from every follow-up shot.
      if (s.hits.isNotEmpty) {
        SoundService.instance.denied();
        setState(() => _hint = 'That hull is damaged — damaged ships '
            'cannot run.');
        return;
      }
      setState(() {
        _dragShip = s;
        _dragGrab = idx;
      });
      return;
    }
  }

  void _dragTo(int r, int c) {
    final s = _dragShip;
    if (s == null) return;
    // Put the grabbed cell under the finger, not the bow.
    final row = s.horizontal ? r : r - _dragGrab;
    final col = s.horizontal ? c - _dragGrab : c;
    if (row == s.row && col == s.col) return;
    if (_moveShip(s, row, col)) {
      setState(() => _hint = 'Your fleet is on the move.');
    }
  }

  void _dragEnd() {
    if (_dragShip == null) return;
    setState(() {
      _dragShip = null;
      _advanceGoals();
    });
  }

  /// Turns the hull under (r, c) about the cell the finger is on.
  void _rotateAt(int r, int c) {
    if (!_canRearrange) return;
    for (final s in _mine) {
      final idx = s.indexAt(r, c);
      if (idx == null) continue;
      if (s.hits.isNotEmpty) {
        SoundService.instance.denied();
        setState(() => _hint = 'That hull is damaged — damaged ships '
            'cannot run.');
        return;
      }
      // Pivot about the tapped cell so a hull turns in place instead of
      // swinging its bow across the board.
      final row = s.horizontal ? r - idx : r;
      final col = s.horizontal ? c : c - idx;
      if (_moveShip(s, row, col, horizontal: !s.horizontal)) {
        SoundService.instance.click();
        setState(() {
          _hint = 'Turned. Tap a hull to turn it, drag it to move it.';
          _advanceGoals();
        });
      } else {
        SoundService.instance.denied();
        setState(() => _hint = 'No room to turn there.');
      }
      return;
    }
  }

  /// Returns false when the hull cannot go there, so the caller can leave
  /// it where it was rather than dropping it into an illegal square.
  bool _moveShip(_DemoShip ship, int row, int col, {bool? horizontal}) {
    if (ship.hits.isNotEmpty) return false;
    final h = horizontal ?? ship.horizontal;
    if (!_fits(ship, row, col, h)) return false;
    ship
      ..row = row
      ..col = col
      ..horizontal = h;
    _sawFleetMove = true;
    return true;
  }

  void _endTurn() {
    _myTurn = false;
    // The guide has to demonstrate what the game actually does: in a
    // turn-based mode both barrels stand down to rest on the handoff (see
    // `BattleScreen._passTurn`), rather than staying frozen on the square
    // they last fired at for the whole of the other side's turn.
    _myAim = 0;
    _theirAim = 0;
    _aiTimer?.cancel();
    _aiTimer = Timer(const Duration(milliseconds: 700), _opponentFires);
  }

  /// Sets the opponent shooting on their OWN clock, for the modes that
  /// have no turns at all.
  ///
  /// BUGFIX ("on the no-turn modes the other cannon does not fire; it
  /// only fires once the player fires"): the opponent's only trigger was
  /// `_endTurn`, and `_endTurn` only runs in a mode that HAS turns — so
  /// in CHAOS, BLITZ and the rest the enemy gun never fired at all until
  /// something else nudged the arena. That is precisely backwards for
  /// these modes: the whole point of them is that both guns fire freely
  /// and neither waits for the other.
  ///
  /// Re-armed after each of their shots lands (see [_opponentFires]), so
  /// they fire at their own reload speed rather than in lockstep with
  /// yours.
  void _scheduleChaosShot() {
    if (_hasTurns) return;
    _aiTimer?.cancel();
    // A little jitter, so the two guns do not fall into a metronome.
    _aiTimer = Timer(
      Duration(milliseconds: 900 + _rng.nextInt(700)),
      _opponentFires,
    );
  }

  /// The demo opponent takes a shot at the player's own grid, so incoming
  /// fire is something they SEE crossing the water rather than something
  /// they are told about.
  void _opponentFires() {
    if (!mounted) return;
    final free = <(int, int)>[
      for (var r = 0; r < _demoSize; r++)
        for (var c = 0; c < _demoSize; c++)
          if (_theirShots[r][c] == 0) (r, c),
    ];
    if (free.isEmpty) {
      if (_hasTurns) _handBack();
      return;
    }
    // In a no-turn mode their gun has to be loaded, exactly as yours
    // does — they fire on their own cooldown, not on demand.
    if (!_hasTurns &&
        (_theirReload < 1 || _shells.any((s) => !s.mine && !s.landed))) {
      _scheduleChaosShot();
      return;
    }
    // JAM: the opponent draws a card at the top of their turn exactly as
    // you do, and this is the turn it dies in their hand. They still get
    // their ordinary shot — JAM kills the card, not the turn — which is
    // what the card's own text says it does.
    if (_jammed) {
      _jammed = false;
      _hint = 'JAM worked — their card was dead in their hand. They still '
          'get their shot.';
    }
    final (r, c) = free[_rng.nextInt(free.length)];
    _launchShell(
      mine: false,
      r: r,
      c: c,
      onLand: () {
        if (!mounted) return;
        var ship = _shipAt(_mine, r, c);

        // The defensive cards get their say before the shell scores.
        // Each of these is the point of the card — a card the player
        // spends and then never sees do anything is not usable, it is
        // just spent.
        if (ship != null) {
          final idx = _mine.indexOf(ship);
          if (_dodgeShip == idx) {
            // AUTO DODGE: the hull slips to new water and the shell finds
            // the hole where it used to be.
            _dodgeShip = null;
            if (_scrambleShip(ship)) {
              _hint = 'AUTO DODGE — your hull slipped the shell.';
              ship = null;
            }
          } else if (_armoured.contains(idx)) {
            // ARMOUR PLATE: soaks exactly one hit, then is gone.
            _armoured.remove(idx);
            _hint = 'ARMOUR PLATE held. That shell did nothing.';
            ship = null;
          } else if (_decoyArmed) {
            // DECOY: "the next hit on you is reported as a miss, and
            // takes no damage" — so the shell scores as a miss and the
            // hull is untouched.
            _decoyArmed = false;
            _hint = 'DECOY — they think that was a miss. It was your ghost.';
            ship = null;
          } else if (_counterArmed) {
            // COUNTER BATTERY: "the next hit on you earns you an extra
            // shot on your next turn." The hit still lands.
            _counterArmed = false;
            _counterPayout += 1;
            _hint = 'COUNTER BATTERY — that hit just bought you a shot.';
          }
        }
        if (_mined.remove(r * _demoSize + c)) {
          // MINEFIELD / TRAP LINE: they fired into armed water.
          _hint = 'Your trap sprang — that shell went off in their face.';
        }

        if (ship != null) ship.hits.add(ship.indexAt(r, c)!);
        // Losing a hull has to read exactly as taking one does — same
        // big burst, same sinking sound, same wreck reveal. See [_fire].
        final sank = ship != null && ship.sunk && ship.sankAt == null;
        if (sank) ship.sankAt = DateTime.now();
        _theirShots[r][c] = ship != null ? 2 : 1;
        _fxMine[r * _demoSize + c] = _Fx(
          r,
          c,
          ship != null,
          sunk: sank,
          recorded: _recordsShots,
        );
        if (!_fxCtrl.isAnimating) _fxCtrl.repeat();
        _tookFire = true;
        if (sank) {
          SoundService.instance.sunk(shipSkinId: _defaultShipSkin.id);
        } else if (ship != null) {
          SoundService.instance.hit();
        } else {
          SoundService.instance.miss();
        }
        // Their gun reloads after ITS shot, on its own timer, the way
        // yours does after yours — see [_startReload].
        _startTheirReload();
        if (_hasTurns) {
          _handBack();
        } else {
          // No turns to hand back: they simply line up their next shot.
          _scheduleChaosShot();
        }
      },
    );
  }

  /// Gives the guns back to the player and announces it.
  void _handBack() {
    setState(() {
      _myTurn = true;
      _reload = 1;
      // Both guns come back to rest — see [_endTurn]. The opponent's
      // barrel is the one that has just fired, so without this it would
      // sit trained on the player's deck all through their turn.
      _myAim = 0;
      _theirAim = 0;
      if (_hasPowerUps) {
        // A fresh card every turn, drawn from the real weighted deck —
        // so the guide deals the same spread of cards a match does, and
        // a player who keeps playing eventually meets all of them.
        _card = PowerUps.draw(_rng);
        _hasCard = true;
        _armed = false;
        // Rules bent by LAST turn's card expire with it.
        //
        // BUGFIX: this used to blank `_extraShots` unconditionally, which
        // silently ate COUNTER BATTERY — that card's whole promise is "an
        // extra shot on your NEXT TURN", it is paid out while THEIR shell
        // is landing, and then this ran a moment later and wiped it
        // before the player could ever spend it. The counter's payout is
        // banked separately and handed over AFTER the expiry sweep.
        _missIsFree = false;
        _extraShots = 0;
        _jammed = false;
        if (_counterPayout > 0) {
          _extraShots += _counterPayout;
          _counterPayout = 0;
        }
      }
      _hint = _hasPowerUps
          ? 'Your turn — and a fresh card is in hand.'
          : 'Your turn again.';
      _advanceGoals();
    });
    _myReady.add(null);
  }

  /// Runs the PLAYER's gun back up to ready.
  ///
  /// BUGFIX ("the opponent also reloads when the player fires and hits"):
  /// this used to drive `_theirReload` off the player's own reload on
  /// every tick, so landing a hit — which keeps the turn and starts your
  /// reload — spun the opponent's cooldown ring too, as though they had
  /// just fired. They had not; they had not moved at all. A gun's
  /// cooldown belongs to the gun that fired it, so the opponent's is
  /// touched only where the opponent actually shoots (`_launchShell` with
  /// `mine: false`) and where its own shell lands.
  void _startReload() {
    _reload = 0;
    _reloadTimer?.cancel();
    _reloadTimer = Timer.periodic(const Duration(milliseconds: 60), (t) {
      if (!mounted) return;
      setState(() {
        _reload = (_reload + 0.05).clamp(0.0, 1.0);
        if (_reload >= 1) {
          t.cancel();
          // The gun flashes ready, exactly as it does mid-match, so the
          // fire-reload-fire cycle has a visible end as well as a start.
          _myReady.add(null);
          if (!_hasTurns || _myTurn) _hint = 'Reloaded — fire again.';
        }
      });
    });
  }

  /// The opponent's gun coming back up after THEIR shot — its own timer,
  /// so the two guns reload independently exactly as two real guns do.
  void _startTheirReload() {
    _theirReload = 0;
    _theirReloadTimer?.cancel();
    _theirReloadTimer = Timer.periodic(const Duration(milliseconds: 60), (t) {
      if (!mounted) return;
      setState(() {
        _theirReload = (_theirReload + 0.05).clamp(0.0, 1.0);
        if (_theirReload >= 1) t.cancel();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      decoration: cartoonBox(AppColors.navy, radius: 18),
      child: Column(
        children: [
          _coach(),
          const SizedBox(height: 10),
          _gridLabel('THEIR WATER — TAP TO FIRE', AppColors.shipBlue),
          const SizedBox(height: 4),
          // Both decks, both guns and every shell in flight share ONE
          // coordinate space, the way the real battle screen does — which
          // is what lets a shell actually arc from a muzzle to a cell
          // instead of being drawn inside whichever grid it happens to
          // belong to.
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _arenaMaxWidth),
              child: LayoutBuilder(
                builder: (context, box) {
                  final w = box.maxWidth;
                  final cell = w / _demoSize;
                  // FEEDBACK ("the layout should look like the actual
                  // gameplay"): every number below used to be a
                  // hand-picked fraction that only approximated the real
                  // screen. They are the REAL screen's own formulas now,
                  // so the guide's arena is laid out by the same rules a
                  // match is and cannot drift away from it.
                  //
                  // `_buildHalf`: the gun is 0.24 of the board, scaled up
                  // for the families whose art is drawn smaller, and it
                  // parks just past the board's outer edge with its
                  // muzzle tip peeking exactly 0.07 of its own size back
                  // over the deck — which is what produces the "pointy
                  // part showing" look instead of a gun either buried
                  // behind the board or floating off it.
                  final gun =
                      w * 0.24 * CannonWidget.gameplaySizeScaleOf(_gunSkin);
                  final backOffset =
                      gun * (CannonWidget.muzzleFractionOf(_gunSkin) - 0.07);
                  // BUGFIX ("the cannons are covering the deck"): the real
                  // screen parks a gun by its CENTRE —
                  // `cannonCenter = gridTop + gridSide + backOffset` — and
                  // this was applying `backOffset` to the gun's box EDGE
                  // instead, which dropped the whole gun half its own
                  // height further onto the water. With a 0.62 muzzle
                  // fraction that is most of the gun sitting on the
                  // board's outer rows, covering the deck exactly as
                  // reported. Positioned by centre, the breech sits off
                  // the water and only the muzzle tip laps over it.
                  final theirGunTop = 0.0;
                  final theirGridTop = backOffset + gun / 2;
                  final bandTop = theirGridTop + w + _deckPad;
                  final myGridTop = bandTop + _bandH + _deckPad;
                  final myGunTop = myGridTop + w + backOffset - gun / 2;
                  _geom = _ArenaGeom(
                    cell: cell,
                    theirGridTop: theirGridTop,
                    myGridTop: myGridTop,
                    theirMuzzle: Offset(w / 2, theirGunTop + gun / 2),
                    myMuzzle: Offset(w / 2, myGunTop + gun / 2),
                    gun: gun,
                  );
                  return SizedBox(
                    width: w,
                    height: myGunTop + gun,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Each half sails on its own DECK, the way
                        // `_buildHalf` paints one — `Container(color:
                        // gameplayTheme.deck)` with the board centred on
                        // it. The guide used to stand both boards
                        // straight on the navy card, so the gun had
                        // nothing to sit on and the whole arena read as
                        // two diagrams rather than as a table.
                        Positioned(
                          top: theirGunTop,
                          left: -_deckPad,
                          width: w + _deckPad * 2,
                          height: theirGridTop + w + _deckPad - theirGunTop,
                          child: _deck(top: true),
                        ),
                        Positioned(
                          top: myGridTop - _deckPad,
                          left: -_deckPad,
                          width: w + _deckPad * 2,
                          height: myGunTop + gun - myGridTop + _deckPad,
                          child: _deck(top: false),
                        ),
                        Positioned(
                          top: theirGridTop,
                          width: w,
                          height: w,
                          child: _grid(
                            key: const ValueKey('guide-enemy-grid'),
                            shots: _myShots,
                            fleet: _enemy,
                            fx: _fxEnemy,
                            showShips: false,
                            markedAt: _myMarkedAt,
                            onTap: _tapEnemy,
                            highlight: _goal == 0,
                          ),
                        ),
                        Positioned(
                          top: bandTop,
                          width: w,
                          height: _bandH,
                          child: _band(),
                        ),
                        Positioned(
                          top: myGridTop,
                          width: w,
                          height: w,
                          child: _grid(
                            // Keyed for the same reason the enemy grid
                            // is: so a test can aim at this board rather
                            // than guessing where it sits.
                            key: const ValueKey('guide-own-grid'),
                            shots: _theirShots,
                            fleet: _mine,
                            fx: _fxMine,
                            showShips: true,
                            markedAt: const {},
                            onTap: null,
                            // Drag to move, tap to turn — but only in the
                            // modes whose rules actually allow it.
                            draggableFleet: _canRearrange,
                            // Your own fleet is drawn as widgets so it
                            // can animate its moves and carry its rotate
                            // arrows — see [_GuideShip].
                            fleetAsWidgets: true,
                            highlight: _canRearrange && _goal == _fleetGoal,
                          ),
                        ),
                        Positioned(
                          top: myGunTop,
                          left: (w - gun) / 2,
                          child: CannonWidget(
                            skin: _gunSkin,
                            size: gun,
                            cooldownFraction: _reload,
                            enabled: _canFire,
                            fireTrigger: _myFire.stream,
                            readyTrigger: _myReady.stream,
                            barrelAim: _myAim,
                          ),
                        ),
                        // Both guns AFTER both boards, so each muzzle
                        // peeks over its own board's edge instead of
                        // being buried behind it — the z-order
                        // `BattleScreen._buildHalf` uses, and the whole
                        // reason the park position is computed to leave
                        // exactly 0.07 of the gun overlapping.
                        Positioned(
                          top: theirGunTop,
                          left: (w - gun) / 2,
                          // Their gun faces down across the water at you.
                          child: RotatedBox(
                            quarterTurns: 2,
                            child: CannonWidget(
                              skin: _gunSkin,
                              size: gun,
                              cooldownFraction: _theirReload,
                              enabled: false,
                              fireTrigger: _theirFire.stream,
                              barrelAim: _theirAim,
                            ),
                          ),
                        ),
                        // Shells last, over everything, so one crossing
                        // the middle band is not cut in half by it.
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _ShellPainter(
                                  shells: _shells, cell: cell),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 6),
          _gridLabel('YOUR FLEET — THEY CANNOT SEE IT', AppColors.hit),
          const SizedBox(height: 8),
          _statusBar(),
        ],
      ),
    );
  }

  /// The step the guide is on, with its own progress dots.
  Widget _coach() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: cartoonBox(AppColors.navyDark, radius: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.school, color: AppColors.gold, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _goals[_goal].text,
                  style: AppText.body(size: 11, color: AppColors.cream),
                ),
                // The running commentary on the last shot. It used to sit
                // in the band between the decks, but the band now shows
                // what the real one shows — the two fleets — and a match
                // does not narrate itself there. The coach is where the
                // guide already speaks, so it speaks here.
                const SizedBox(height: 4),
                Text(
                  _hint,
                  style: AppText.body(size: 10, color: AppColors.gold),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (var i = 0; i < _goals.length; i++)
                      Container(
                        margin: const EdgeInsets.only(right: 4),
                        width: i == _goal ? 14 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: i <= _goal
                              ? AppColors.gold
                              : AppColors.inkSoft,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Pressable(
            onTap: () {
              SoundService.instance.click();
              setState(_reset);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: cartoonBox(AppColors.navy, radius: 9),
              child: Text('RESET', style: AppText.label(size: 8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gridLabel(String text, Color color) => Row(
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 6),
      Text(text, style: AppText.label(size: 8, color: AppColors.mist)),
    ],
  );

  /// The strip between the two decks.
  ///
  /// FEEDBACK ("the layout should look like the actual gameplay"): the
  /// real band (`BattleScreen._buildMiddleBand`) is two rows — one per
  /// fleet, each wearing that captain's own deck colour — with the
  /// remaining-hull counter pinned to its left edge as a stack of two
  /// filled chips. This was a single flat strip with the two counts as
  /// plain text at either end, and at 26px tall it clipped both of them.
  Widget _band() {
    final theirsLeft = _enemy.where((s) => !s.sunk).length;
    final mineLeft = _mine.where((s) => !s.sunk).length;

    // FEEDBACK ("the ship status preview does not look like the
    // gameplay"): it did not, because it was not one — it was the words
    // "THEIRS"/"YOURS" and a count. The real band (`_statusRow`) draws
    // that fleet's FIVE HULLS, in that fleet's own skin, each sized by
    // its real length, and flips a hull to its wrecked model the moment
    // the shot that sank it lands. That is the thing a player actually
    // reads mid-match to see what is left, and it is now what the guide
    // shows, from the same `ShipPreviewBox` measurements so the two rows
    // cannot drift apart.
    Widget row(List<_DemoShip> fleet) => Expanded(
          child: Container(
            color: _theme.deck,
            padding: const EdgeInsets.only(left: 36, right: 6),
            child: LayoutBuilder(builder: (context, box) {
              final unit = box.maxWidth.isFinite
                  ? min(9.0, (box.maxWidth * 0.9) / ShipPreviewBox.fleetUnits)
                  : 9.0;
              final beam = ShipPreviewBox.beam(unit);
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (var i = 0; i < kFleet.length; i++)
                    Builder(builder: (context) {
                      final spec = kFleet[i];
                      // The demo fleets are built one-per-spec in the same
                      // order (see `_reset`), so index is identity here.
                      final sunk = i < fleet.length && fleet[i].sunk;
                      return AnimatedShip(
                        spec: spec,
                        skin: _defaultShipSkin,
                        width: ShipPreviewBox.width(spec, unit),
                        height: beam,
                        sunk: sunk,
                        hitCount: sunk ? spec.size : 0,
                        shooterCannonId: _ArenaPainter.kDefaultCannon,
                      );
                    }),
                ],
              );
            }),
          ),
        );

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.outline, width: 2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Stack(
          children: [
            Column(
              children: [
                row(_enemy),
                Container(
                  height: 1.5,
                  color: AppColors.outline.withValues(alpha: 0.45),
                ),
                row(_mine),
              ],
            ),
            // The fleet counter, pinned to the left edge exactly as
            // `_DotsBadge` is.
            Positioned(
              left: 0,
              top: 2,
              bottom: 2,
              child: _CountBadge(
                topLeft: theirsLeft,
                bottomLeft: mineLeft,
                topColor: AppColors.shipBlue,
                bottomColor: AppColors.hit,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _grid({
    Key? key,
    required List<List<int>> shots,
    required List<_DemoShip> fleet,
    required Map<int, _Fx> fx,
    required bool showShips,
    required Map<int, DateTime> markedAt,
    required void Function(int, int)? onTap,
    required bool highlight,
    /// Your own fleet can be dragged around this board — MANOEUVRE and
    /// friends. Never true for the enemy's water.
    bool draggableFleet = false,
    /// Draw this board's fleet as real WIDGETS over the grid rather than
    /// inside its painter.
    ///
    /// FEEDBACK ("missing arrows and missing animations when flipping or
    /// changing position"): a `CustomPainter` has nothing to animate —
    /// every hull was simply drawn at its current square, so a move or a
    /// flip was a teleport between two frames and there was no affordance
    /// anywhere saying a ship could be turned at all. The real board
    /// renders each hull as a widget precisely so it can carry an
    /// `AnimatedPositioned`, an `AnimatedRotation` and its own pair of
    /// rotate arrows (`_ShipWithRotate`); this does the same, with the
    /// same durations and curves.
    bool fleetAsWidgets = false,
  }) {
    // Capped: the grid is square, so on a wide screen an uncapped one
    // would be as tall as the screen is wide and push everything else
    // off the page. A board bigger than this gains nothing anyway.
    return Center(
      key: key,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _arenaMaxWidth),
        child: AspectRatio(
          aspectRatio: 1,
          child: LayoutBuilder(
            builder: (context, box) {
              final cell = box.maxWidth / _demoSize;
              final board = CustomPaint(
                painter: _ArenaPainter(
                  shots: shots,
                  fleet: fleet,
                  fx: fx,
                  // The painter still draws the ENEMY's revealed wrecks;
                  // it just stops drawing a fleet that the widget layer
                  // below is now responsible for.
                  showShips: showShips && !fleetAsWidgets,
                  markedAt: markedAt,
                  fadeMarks: !_recordsShots && markedAt.isNotEmpty,
                  // Only the grid you can actually tap shows tap pulses
                  // and the reticle — both belong to the shot YOU are
                  // taking, which is only ever at their water.
                  tapFx: onTap == null ? const {} : _tapFx,
                  aimCell: onTap == null ? null : _aimCell,
                  // Intel lights up THEIR water; traps arm YOUR OWN.
                  marked: showShips ? const {} : _revealed,
                  mines: showShips ? _mined : const {},
                  repaint: _fxCtrl,
                ),
              );
              // The fleet layer sits between the water and the effects,
              // the same order the real board stacks them in.
              final grid = !fleetAsWidgets
                  ? board
                  : Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(child: board),
                        for (final ship in fleet)
                          _GuideShip(
                            key: ValueKey(ship),
                            ship: ship,
                            cell: cell,
                            showRotate: draggableFleet &&
                                ship.hits.isEmpty &&
                                !ship.sunk,
                          ),
                      ],
                    );
              return AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(cell * 0.2),
                  // The one thing the guide is asking for is ringed, so a
                  // player who has stopped reading still knows where to tap.
                  border: Border.all(
                    color: highlight ? AppColors.gold : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: (onTap == null &&
                        !draggableFleet &&
                        !(_armed && _cardTargetsOwnGrid))
                    ? grid
                    : GestureDetector(
                        onTapUp: (d) {
                          final c = (d.localPosition.dx / cell).floor();
                          final r = (d.localPosition.dy / cell).floor();
                          if (r < 0 ||
                              r >= _demoSize ||
                              c < 0 ||
                              c >= _demoSize) {
                            return;
                          }
                          if (onTap == null) {
                            // This is YOUR water. An armed card that
                            // targets your own grid — MINEFIELD, TRAP
                            // LINE, ARMOUR PLATE, AUTO DODGE, HARD TURN —
                            // is spent here.
                            //
                            // BUGFIX: without this those five cards could
                            // be armed and then never resolved, because
                            // the only board that accepted a tap was the
                            // enemy's. Arming one was a dead end that ate
                            // the card and the turn.
                            if (_armed && _cardTargetsOwnGrid) {
                              _resolveCardAt(r, c);
                              setState(() {});
                            } else if (draggableFleet) {
                              // Otherwise a tap turns the hull under the
                              // finger, the way tap-to-rotate does on the
                              // deploy screen.
                              _rotateAt(r, c);
                            }
                            return;
                          }
                          onTap(r, c);
                        },
                        // Your own hulls are moved by PRESS AND HOLD, then
                        // dragging — not a plain drag.
                        //
                        // BUGFIX (caught by driving the drag in a test —
                        // the page scrolled 2.6px and the ship never
                        // moved): the guide's arena lives inside the
                        // page's ListView, and a plain pan on the board
                        // loses the gesture arena to that scrollable
                        // every time. The real `BattleGrid` gets away
                        // with a plain pan only because the battle screen
                        // is not scrollable at all.
                        //
                        // A long press is the standard answer — a
                        // scrollable does not claim a stationary press,
                        // so the board wins cleanly — and it has the
                        // happy side effect that scrolling the guide can
                        // no longer nudge a ship by accident.
                        onLongPressStart: !draggableFleet
                            ? null
                            : (d) => _dragStart(
                                  (d.localPosition.dy / cell).floor(),
                                  (d.localPosition.dx / cell).floor(),
                                ),
                        onLongPressMoveUpdate: !draggableFleet
                            ? null
                            : (d) => _dragTo(
                                  (d.localPosition.dy / cell).floor(),
                                  (d.localPosition.dx / cell).floor(),
                                ),
                        onLongPressEnd:
                            !draggableFleet ? null : (_) => _dragEnd(),
                        child: grid,
                      ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _statusBar() {
    final chips = <Widget>[];
    if (_hasTurns) {
      chips.add(
        _chip(
          _myTurn ? 'YOUR TURN' : 'THEIR TURN',
          _myTurn ? AppColors.green : AppColors.inkSoft,
        ),
      );
    } else {
      chips.add(
        _chip(
          _reload >= 1 ? 'READY' : 'RELOADING',
          _reload >= 1 ? AppColors.green : AppColors.inkSoft,
        ),
      );
    }
    if (!_recordsShots) chips.add(_chip('MARKS FADE', AppColors.blue));
    if (_canRearrange) chips.add(_chip('FLEET MOVES', AppColors.blue));
    // The card in hand, drawn as the real badge is: the card's own icon
    // and its own name, not a hardcoded "SALVO".
    final card = _card;
    if (_hasPowerUps && _hasCard && card != null) {
      final def = PowerUps.of(card);
      chips.add(
        Pressable(
          onTap: _useCard,
          child: Container(
            padding: const EdgeInsets.fromLTRB(5, 3, 9, 3),
            decoration: cartoonBox(
              _armed ? AppColors.gold : AppColors.hit,
              radius: 9,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PowerUpIcon(card: card, size: 20),
                const SizedBox(width: 6),
                Text(
                  _armed
                      ? 'TAP ${def.targetsOwnGrid ? 'YOUR' : 'THEIR'} WATER'
                      : '${def.name} — USE IT',
                  style: AppText.label(size: 9),
                ),
              ],
            ),
          ),
        ),
      );
      // A card that needs no target still wants its one line of
      // explanation, since the player cannot discover it by aiming.
      chips.add(
        Container(
          constraints: const BoxConstraints(maxWidth: 210),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: cartoonBox(AppColors.navyDark, radius: 9),
          child: Text(
            def.description,
            style: AppText.body(size: 8.5, color: AppColors.mist),
          ),
        ),
      );
    }
    return Wrap(spacing: 6, runSpacing: 6, children: chips);
  }

  Widget _chip(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: cartoonBox(color, radius: 9),
    child: Text(text, style: AppText.label(size: 9)),
  );
}

/// One hull of the player's own fleet, as a real widget.
///
/// The twin of `BattleGrid`'s `_ShipWithRotate`, with the same two
/// animations and the same pair of corner arrows — and deliberately the
/// same 420ms `easeInOutCubic` on both, so a ship moved or turned in the
/// guide travels exactly as one does in a match.
///
/// It has to be a widget for that to be possible at all: the guide used
/// to draw its fleet inside the arena's `CustomPainter`, where a move is
/// just a different pair of numbers next frame and there is nothing to
/// tween between.
class _GuideShip extends StatelessWidget {
  final _DemoShip ship;
  final double cell;

  /// Whether this hull may be turned right now — the arrows say so.
  final bool showRotate;

  const _GuideShip({
    super.key,
    required this.ship,
    required this.cell,
    required this.showRotate,
  });

  static const _moveDuration = Duration(milliseconds: 420);

  @override
  Widget build(BuildContext context) {
    final long = ship.length * cell;
    final short = cell;
    final w = ship.horizontal ? long : short;
    final h = ship.horizontal ? short : long;
    final spec = kFleet.firstWhere((s) => s.size == ship.length,
        orElse: () => kFleet.last);

    final hull = SizedBox(
      width: long - 2,
      height: short - 2,
      child: CustomPaint(
        size: Size(long - 2, short - 2),
        painter: ShipPainter(
          spec: spec,
          skin: _defaultShipSkin,
          sunk: ship.sunk,
          hitCount: ship.hits.length,
          hitIndices: ship.hits,
          shooterCannonId: _ArenaPainter.kDefaultCannon,
        ),
      ),
    );

    // Arrows hug the hull's natural (pre-rotation) corners and turn with
    // it, so they never need their own orientation cases. Always in the
    // tree and merely transparent when hidden, so they fade rather than
    // pop — the same reason the real board keeps them mounted.
    final assembly = Stack(
      clipBehavior: Clip.none,
      children: [
        hull,
        Positioned(
          left: -cell * 0.22,
          top: -cell * 0.22,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: showRotate ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: _arrow(Icons.rotate_left),
            ),
          ),
        ),
        Positioned(
          right: -cell * 0.22,
          bottom: -cell * 0.22,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: showRotate ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: _arrow(Icons.rotate_right),
            ),
          ),
        ),
      ],
    );

    return AnimatedPositioned(
      duration: _moveDuration,
      curve: Curves.easeInOutCubic,
      left: ship.col * cell + w / 2 - (long) / 2,
      top: ship.row * cell + h / 2 - (short) / 2,
      width: long,
      height: short,
      child: Center(
        child: AnimatedRotation(
          turns: ship.horizontal ? 0.0 : 0.25,
          duration: _moveDuration,
          curve: Curves.easeInOutCubic,
          child: assembly,
        ),
      ),
    );
  }

  static Widget _arrow(IconData icon) => Icon(
        icon,
        size: 22,
        color: AppColors.outline,
        shadows: const [Shadow(color: Colors.white, blurRadius: 2)],
      );
}

/// The remaining-hull counter on the left edge of the guide's band.
///
/// Deliberately the same object as the battle screen's own `_DotsBadge`,
/// down to the ink-on-fill rule: a filled chip in each fleet's colour,
/// dark outlined body, pinned flush to the band's left edge. It is
/// private to that screen, so this is the smaller twin rather than a
/// shared widget — extracting it would mean pulling a piece of the battle
/// screen's chrome into a public API for the sake of a tutorial.
class _CountBadge extends StatelessWidget {
  final int topLeft;
  final int bottomLeft;
  final Color topColor;
  final Color bottomColor;

  const _CountBadge({
    required this.topLeft,
    required this.bottomLeft,
    required this.topColor,
    required this.bottomColor,
  });

  /// Ink chosen against the CHIP's own fill — a pale fleet colour with
  /// cream on top of it is unreadable.
  Color _inkOn(Color fill) =>
      fill.computeLuminance() > 0.55 ? AppColors.outline : AppColors.cream;

  @override
  Widget build(BuildContext context) {
    Widget chip(Color color, int count) => Container(
          width: 24,
          height: 15,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: AppColors.outline, width: 1.5),
          ),
          alignment: Alignment.center,
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: _inkOn(color),
              height: 1,
            ),
          ),
        );

    return Container(
      width: 32,
      padding: const EdgeInsets.only(left: 2),
      decoration: const BoxDecoration(
        color: AppColors.navyDeep,
        borderRadius: BorderRadius.horizontal(right: Radius.circular(15)),
        border: Border(
          top: BorderSide(color: AppColors.outline, width: 2),
          right: BorderSide(color: AppColors.outline, width: 2),
          bottom: BorderSide(color: AppColors.outline, width: 2),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [chip(topColor, topLeft), chip(bottomColor, bottomLeft)],
      ),
    );
  }
}

/// One transient impact on a demo grid.
class _Fx {
  final int row;
  final int col;
  final bool hit;

  /// This shot finished a hull off. Drives the BIG burst, exactly as
  /// `ShotResult.sunk` does on the real board.
  final bool sunk;

  /// This shot left a permanent mark on the deck, so a mark-arrival
  /// transition has something to deliver. False in PHANTOM and GHOST
  /// FLEET, which record nothing — the same gate `CellFx.recorded` is.
  final bool recorded;

  final DateTime start = DateTime.now();
  _Fx(this.row, this.col, this.hit,
      {this.sunk = false, this.recorded = true});

  double get t =>
      (DateTime.now().difference(start).inMilliseconds / 800).clamp(0.0, 1.0);
  bool get done => t >= 1;
}

class _ArenaPainter extends CustomPainter {
  final List<List<int>> shots;
  final List<_DemoShip> fleet;
  final Map<int, _Fx> fx;
  final bool showShips;
  final Map<int, DateTime> markedAt;
  final bool fadeMarks;

  /// Taps waiting to ripple — the same "yes, that registered" pulse the
  /// real grid answers a tap with (`_FxGridPainter._drawTapRipple`).
  final Map<int, DateTime> tapFx;

  /// The square a shell is currently flying at, if any — see the note on
  /// `_ModeArenaState._aimCell`.
  final (int, int)? aimCell;

  /// Enemy water this side's intel has lit up, and your own water that is
  /// armed — the POWER PLAY overlays.
  final Set<int> marked;
  final Set<int> mines;

  _ArenaPainter({
    required this.shots,
    required this.fleet,
    required this.fx,
    required this.showShips,
    required this.markedAt,
    required this.fadeMarks,
    required this.tapFx,
    required this.aimCell,
    required this.marked,
    required this.mines,
    required Listenable repaint,
  }) : super(repaint: repaint);

  /// How long a mark lingers in the modes that record nothing.
  static const _fadeMs = 1400;

  /// The gear a brand-new profile sails with, so the guide shows the
  /// player exactly what they will actually be looking at on their first
  /// match rather than a stand-in: the MK-I's deck, its hit and miss
  /// marks, its shell, and the Steel Fleet hulls.
  static const String kDefaultCannon = 'mk1';

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / _demoSize;
    final rect = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(cell * 0.18));
    canvas.save();
    canvas.clipRRect(rect);

    // The real illustrated battlefield, not a flat blue rectangle — the
    // same `paintLegacyBoard` the match itself draws.
    paintLegacyBoard(canvas, size, kDefaultCannon);

    // Your own fleet is drawn in the real hull art; theirs stays hidden
    // until a hull goes down, which is public knowledge in every mode.
    for (final ship in fleet) {
      if (!showShips && !ship.sunk) continue;
      final spec = kFleet.firstWhere((s) => s.size == ship.length,
          orElse: () => kFleet.last);
      final long = ship.length * cell - 2;
      final short = cell - 2;
      canvas.save();
      canvas.translate(ship.col * cell + 1, ship.row * cell + 1);
      if (!ship.horizontal) {
        // Drawn along its long axis and then stood on end, the same way
        // `_ShipWithRotate` does it, so a vertical hull is a rotation
        // rather than a squashed copy.
        canvas.translate(short, 0);
        canvas.rotate(pi / 2);
      }
      // A wreck does not simply appear on the real board — it is revealed
      // with the fleet's own motion (`WreckReveal`), which is most of what
      // sinking a ship FEELS like. The guide read as a ship blinking from
      // intact to wrecked between one frame and the next; it plays the
      // same reveal now, from the same `wreckRevealFrame` table, so a kill
      // in the tutorial lands the way a kill in a match does.
      var layered = false;
      if (ship.sunk && ship.wreckT < 1) {
        final f = wreckRevealFrame(
          wreckMotionForShipSkin(_defaultShipSkin.id),
          ship.wreckT,
          long,
        );
        canvas.translate(long / 2 + f.dx, short / 2 + f.dy);
        canvas.rotate(f.rotation);
        canvas.scale(f.scaleX, f.scaleY);
        canvas.translate(-long / 2, -short / 2);
        if (f.opacity < 1) {
          canvas.saveLayer(
            Rect.fromLTWH(-long, -short, long * 3, short * 3),
            Paint()
              ..color =
                  Colors.white.withValues(alpha: f.opacity.clamp(0.0, 1.0)),
          );
          layered = true;
        }
      }
      ShipPainter(
        spec: spec,
        skin: _defaultShipSkin,
        sunk: ship.sunk,
        hitCount: ship.hits.length,
        hitIndices: ship.hits,
        shooterCannonId: kDefaultCannon,
      ).paint(canvas, Size(long, short));
      if (layered) canvas.restore();
      canvas.restore();
    }

    final now = DateTime.now();
    for (var r = 0; r < _demoSize; r++) {
      for (var c = 0; c < _demoSize; c++) {
        final v = shots[r][c];
        if (v == 0) continue;
        var alpha = 1.0;
        if (fadeMarks) {
          final at = markedAt[r * _demoSize + c];
          if (at == null) continue;
          final age = now.difference(at).inMilliseconds;
          if (age > _fadeMs) continue;
          alpha = 1 - (age / _fadeMs);
        }
        final centre = Offset(c * cell + cell / 2, r * cell + cell / 2);
        canvas.saveLayer(
          Rect.fromCircle(center: centre, radius: cell),
          Paint()
            ..color = Colors.white.withValues(alpha: alpha.clamp(0.0, 1.0)),
        );
        if (v == 2) {
          paintLegacyHit(canvas, centre, cell, kDefaultCannon);
        } else {
          paintLegacyMiss(canvas, centre, cell, kDefaultCannon);
        }
        canvas.restore();
      }
    }

    // The same impact vocabulary the real board uses, in the same ORDER
    // it uses it, so the demo reads as the game rather than as a diagram
    // of it: the deck's own debris underneath, then the gun's splash,
    // then its burst, then the mark being delivered.
    //
    // FEEDBACK ("the how to play still needs to mimic the real gameplay
    // more"): this used to stop after the splash and the burst. The deck
    // debris and the mark-arrival transition are both things the player
    // sees on every single shot of a real match, and leaving them out is
    // exactly the sort of gap that makes a tutorial feel like a mock-up.
    final profile = impactFxForCannon(kDefaultCannon);
    final deck = deckFxFor(legacyBoardId: kDefaultCannon);
    fx.forEach((key, f) {
      final centre = Offset(f.col * cell + cell / 2, f.row * cell + cell / 2);
      paintDeckDebris(canvas, centre, cell, f.t, deck, key,
          hit: f.hit || f.sunk);
      paintImpactSplash(canvas, centre, cell, f.t, profile, key);
      if (f.hit || f.sunk) {
        paintImpactBurst(canvas, centre, cell, f.t, profile, key,
            big: f.sunk);
      }
      if (f.recorded) paintMarkArrival(canvas, centre, cell, f.t, profile);
    });

    // POWER PLAY intel and traps. The real grid draws these too
    // (`spottedEnemyCells` in gold, `minedCells` on your own water); a
    // card whose whole effect is invisible is a card the player cannot
    // tell they used.
    for (final key in marked) {
      final centre = Offset(
        (key % _demoSize) * cell + cell / 2,
        (key ~/ _demoSize) * cell + cell / 2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: centre, width: cell * 0.8, height: cell * 0.8),
          Radius.circular(cell * 0.18),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.08
          ..color = AppColors.gold.withValues(alpha: 0.9),
      );
    }
    for (final key in mines) {
      final centre = Offset(
        (key % _demoSize) * cell + cell / 2,
        (key ~/ _demoSize) * cell + cell / 2,
      );
      canvas.drawCircle(
        centre,
        cell * 0.2,
        Paint()..color = AppColors.hit.withValues(alpha: 0.85),
      );
      canvas.drawCircle(
        centre,
        cell * 0.2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.05
          ..color = AppColors.outline,
      );
    }

    // The targeting reticle, locked on the square the shell is heading
    // for — the real board's `_Crosshair`, in this gun's own art.
    final aim = aimCell;
    if (aim != null) {
      canvas.save();
      canvas.translate(aim.$2 * cell, aim.$1 * cell);
      paintLegacyCrosshair(canvas, Size(cell, cell), kDefaultCannon);
      canvas.restore();
    }

    // The tap pulse, last and on top — it answers the finger, so nothing
    // should ever be drawn over it.
    tapFx.forEach((key, started) {
      final t = now.difference(started).inMilliseconds / 260;
      if (t >= 1.0) return;
      final centre = Offset(
        (key % _demoSize) * cell + cell / 2,
        (key ~/ _demoSize) * cell + cell / 2,
      );
      final e = t.clamp(0.0, 1.0);
      final alpha = (1 - e) * 0.85;
      canvas.drawCircle(
        centre,
        cell * (0.16 + 0.42 * Curves.easeOut.transform(e)),
        Paint()
          ..color = Colors.white.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.09 * (1 - e * 0.5),
      );
      canvas.drawCircle(centre, cell * 0.05,
          Paint()..color = Colors.white.withValues(alpha: alpha));
    });
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ArenaPainter old) => true;
}

/// The hull every profile starts with — see `_ArenaPainter.kDefaultCannon`.
final ShipSkin _defaultShipSkin = Catalog.shipById('steel');

/// One shell in the air over the guide's arena.
class _Shell {
  final Offset from;
  final Offset to;
  final double arc;

  /// Whose shell this is.
  ///
  /// BUGFIX: the guide used to gate firing on "is ANY shell in the air",
  /// which quietly made CHAOS impossible — the mode whose whole
  /// definition is that "both fleets fire the moment their own cannon has
  /// reloaded, so shots cross in mid-air" (see `LanBattleMode.chaos`).
  /// An incoming shell locked your gun until it landed, so nothing ever
  /// crossed. Each side now waits only on its OWN shell.
  final bool mine;
  final DateTime start = DateTime.now();
  final VoidCallback onLand;
  bool landed = false;

  _Shell({
    required this.from,
    required this.to,
    required this.arc,
    required this.mine,
    required this.onLand,
  });

  /// The real flight time (`kShellFlight`), not a guide-only value — a
  /// shot has to take as long to cross the water here as it does in a
  /// match, or the guide teaches the wrong rhythm.
  static int get flightMs => kShellFlight.inMilliseconds;

  double get t =>
      (DateTime.now().difference(start).inMilliseconds / flightMs)
          .clamp(0.0, 1.0);

  /// Where the shell is at [tt]: a straight line with a sine lob laid
  /// over it, the same shape the real screen's `_launchBall` flies.
  Offset positionAt(double tt) {
    final p = Offset.lerp(from, to, tt)!;
    return Offset(p.dx, p.dy - sin(tt * pi) * arc);
  }

  Offset get position => positionAt(t);

  /// The shell's instantaneous heading, for the guns whose shell is drawn
  /// with a nose and a tail — the same `angleAt` the real flight layer
  /// turns a directional shell by.
  double angleAt(double tt) {
    final vx = to.dx - from.dx;
    final vy = (to.dy - from.dy) - pi * arc * cos(tt * pi);
    if (vx == 0 && vy == 0) return 0;
    return atan2(vx, -vy);
  }
}

/// Draws the shells in flight over the whole arena.
///
/// BUGFIX ("the projectile is too small — use the same animation and size
/// as the gameplay"): it was a flat `cell * 0.66` square that never grew,
/// shrank, turned or trailed — two thirds of a cell for the whole flight,
/// against a real shell that launches at 2.6 cells and is still a full
/// cell across when it lands. Every number here is now the flight
/// layer's own (`BattleScreen`'s `diamAt`/`impactFadeAt`/`angleAt` and
/// its two trail ghosts), so a shell in the guide is the same object,
/// the same size, doing the same thing.
class _ShellPainter extends CustomPainter {
  final List<_Shell> shells;
  final double cell;

  _ShellPainter({required this.shells, required this.cell})
      : super(repaint: null);

  /// Launches noticeably LARGER than the target cell and shrinks the
  /// whole way in, settling to exactly one cell as it lands — the
  /// "incoming shot" telegraph.
  double _diamAt(double tt) => cell * (2.6 - 1.6 * tt.clamp(0.0, 1.0));

  /// Fades over the last stretch so the shell sinks into the splash
  /// instead of popping out of existence a frame before it.
  double _fadeAt(double tt) {
    const fadeStart = 0.92;
    if (tt <= fadeStart) return 1.0;
    return (1 - (tt - fadeStart) / (1 - fadeStart)).clamp(0.0, 1.0);
  }

  /// One shell at one point along its arc, at [scale] of full size.
  void _draw(Canvas canvas, _Shell s, double tt, double opacity,
      double scale, bool directional) {
    if (tt <= 0) return;
    final d = _diamAt(tt) * scale;
    final o = opacity * _fadeAt(tt);
    if (o <= 0.01) return;
    final p = s.positionAt(tt);
    // The shell art is authored in a box taller than it is wide (the tail
    // hangs below the body), and the real layer letterboxes it into the
    // square the ball would occupy rather than squashing it.
    final h = d / kShellBoxAspect;
    // A round shell tumbles freely; one with a nose and a tail points
    // where it is actually going.
    final angle = directional ? s.angleAt(tt) : tt * pi * 6;

    canvas.save();
    canvas.translate(p.dx, p.dy);
    canvas.rotate(angle);
    if (o < 1) {
      canvas.saveLayer(
        Rect.fromCenter(center: Offset.zero, width: d * 2, height: d * 2),
        Paint()..color = Colors.white.withValues(alpha: o),
      );
    }
    canvas.translate(-d / 2, -h / 2);
    paintLegacyShell(canvas, Size(d, h), _ArenaPainter.kDefaultCannon);
    if (o < 1) canvas.restore();
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final directional =
        legacyShellIsDirectional(_ArenaPainter.kDefaultCannon);
    for (final s in shells) {
      if (s.landed) continue;
      final t = s.t;
      // Two faint motion-trail ghosts behind the shell, at the same
      // lags, opacities and scales the real one leaves.
      _draw(canvas, s, t - 0.11, 0.14, 0.72, directional);
      _draw(canvas, s, t - 0.055, 0.26, 0.84, directional);
      _draw(canvas, s, t, 1.0, 1.0, directional);
    }
  }

  @override
  bool shouldRepaint(_ShellPainter old) => true;
}
