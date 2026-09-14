import 'dart:async';

import 'package:flutter/material.dart';

import '../art/power_up_icons.dart';
import '../models/power_up.dart';
import '../services/sound_service.dart';

/// POWER PLAY's draw randomizer — the chunky ship's dial from the design
/// (`Power Play Redesign.dc.html` / `Power Play Live Simulation.dc.html`).
///
/// FEEDBACK ("add all of the power play designs, icons, effects,
/// randomizer"): a card used to appear in the corner with no ceremony at
/// all — one frame there was nothing, the next frame there was a text
/// chip. The draw is the most interesting moment of a POWER PLAY turn and
/// it was completely invisible.
///
/// Now it spins: a brass bezel over a dark well, a wedge wheel whirling
/// behind the pointer, then the drawn power-up's own icon popping in with
/// its name. Impatient players can SKIP straight to the reveal — the card
/// is already decided before the dial ever starts (see [card]), so
/// skipping only shortens the animation and can never change the outcome.
///
/// Deliberately a pure display widget: it is handed the card that was
/// already drawn and calls [onDone] when it has finished showing it.
class PowerUpDial extends StatefulWidget {
  /// The card the controller already drew. Shown at the reveal.
  final PowerUpCard card;

  /// How long the wheel spins before the reveal.
  final Duration spin;

  /// Called once the reveal has been on screen long enough to read.
  final VoidCallback onDone;

  const PowerUpDial({
    super.key,
    required this.card,
    required this.onDone,
    this.spin = const Duration(milliseconds: 900),
  });

  @override
  State<PowerUpDial> createState() => _PowerUpDialState();
}

/// The design's own palette for this overlay. Held here rather than in
/// `AppColors` because it is this one component's brass-and-well look,
/// not part of the app-wide theme.
const _scrim = Color(0xD11B222A);
const _brass = Color(0xFFB8894A);
const _well = Color(0xFF1B222A);
const _outline = Color(0xFF1E2A36);
const _cream = Color(0xFFFFF4EC);
const _gold = Color(0xFFF7B32B);

/// The wheel's seven wedges, in the design's order.
///
/// Each colour appears TWICE, against a pair of identical stops, because
/// the design's wheel is a `conic-gradient` with hard boundaries
/// (`#F25F5C 0deg 51deg, #4A789A 51deg 103deg, …`). A `SweepGradient`
/// given one stop per colour blends between them instead, which turns a
/// crisp fairground wheel into a smeared rainbow — doubling the stops is
/// what holds each wedge flat right up to its edge.
const _wedgeColors = [
  Color(0xFFF25F5C), Color(0xFFF25F5C), //
  Color(0xFF4A789A), Color(0xFF4A789A), //
  Color(0xFFF7B32B), Color(0xFFF7B32B), //
  Color(0xFF3D5468), Color(0xFF3D5468), //
  Color(0xFF5BB381), Color(0xFF5BB381), //
  Color(0xFF243646), Color(0xFF243646), //
  Color(0xFF35A3D6), Color(0xFF35A3D6), //
];

const _wedgeStops = [
  0.0, 1 / 7, //
  1 / 7, 2 / 7, //
  2 / 7, 3 / 7, //
  3 / 7, 4 / 7, //
  4 / 7, 5 / 7, //
  5 / 7, 6 / 7, //
  6 / 7, 1.0, //
];

class _PowerUpDialState extends State<PowerUpDial>
    with TickerProviderStateMixin {
  late final AnimationController _spinCtrl;
  late final AnimationController _popCtrl;
  late final Animation<double> _popScale;
  late final Animation<double> _popFade;

  bool _revealed = false;
  Timer? _spinTimer;
  Timer? _holdTimer;

  /// How long the revealed icon stays up before handing control back.
  static const _hold = Duration(milliseconds: 900);

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    )..repeat();
    _popCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    // The design's `popIn`: overshoot to 1.15 at 60%, settle to 1.
    _popScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.3,
          end: 1.15,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.15,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
    ]).animate(_popCtrl);
    _popFade = CurvedAnimation(
      parent: _popCtrl,
      curve: const Interval(0, 0.4, curve: Curves.easeOut),
    );
    // The same whirring cue the deploy screen's RANDOM already spins to.
    SoundService.instance.whir();
    _spinTimer = Timer(widget.spin, _reveal);
  }

  void _reveal() {
    if (!mounted || _revealed) return;
    _spinTimer?.cancel();
    setState(() => _revealed = true);
    _spinCtrl.stop();
    _popCtrl.forward(from: 0);
    // Rarity lands in the ear as well as the eye — the same three-step
    // reading the ring's shape gives, mapped onto cues the game already
    // ships rather than new audio: a flat set-down for a common, the
    // gun's ready-chime for an uncommon, the countdown's GO blip for a
    // rare.
    switch (PowerUps.of(widget.card).rarity) {
      case PowerUpRarity.common:
        SoundService.instance.place();
      case PowerUpRarity.uncommon:
        SoundService.instance.cannonReady();
      case PowerUpRarity.rare:
        SoundService.instance.countGo();
    }
    _holdTimer = Timer(_hold, () {
      if (mounted) widget.onDone();
    });
  }

  /// SKIP jumps to the reveal. It cannot change WHAT was drawn — the card
  /// was decided by the controller before this widget was ever built.
  void _skip() {
    if (_revealed) return;
    SoundService.instance.click();
    _reveal();
  }

  @override
  void dispose() {
    _spinTimer?.cancel();
    _holdTimer?.cancel();
    _spinCtrl.dispose();
    _popCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final def = PowerUps.of(widget.card);
    return Positioned.fill(
      child: Container(
        color: _scrim,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 150,
              height: 150,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  // Brass bezel.
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _brass,
                      border: Border.all(color: _outline, width: 5),
                    ),
                  ),
                  // The dark well the wheel spins inside. `ClipOval` keeps
                  // the wheel's square gradient box inside the dial, and
                  // the well's own dark rim goes in `foregroundDecoration`
                  // so it draws OVER the clipped wheel rather than being
                  // hidden underneath it.
                  Padding(
                    padding: const EdgeInsets.all(9),
                    child: Container(
                      foregroundDecoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _outline, width: 4),
                      ),
                      child: ClipOval(
                        child: Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: _well,
                          ),
                          alignment: Alignment.center,
                          child: _revealed
                              ? _reveals(def)
                              : RotationTransition(
                                  turns: _spinCtrl,
                                  child: const DecoratedBox(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: SweepGradient(
                                        colors: _wedgeColors,
                                        stops: _wedgeStops,
                                      ),
                                    ),
                                    child: SizedBox.expand(),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                  // The pointer the wheel stops under.
                  Positioned(
                    top: -5,
                    child: CustomPaint(
                      size: const Size(20, 16),
                      painter: const _PointerPainter(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_revealed)
              FadeTransition(
                opacity: _popFade,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      def.name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _cream,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 260),
                      child: Text(
                        def.description,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFD9E8F2),
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'RANDOMIZING…',
                    style: TextStyle(
                      color: _cream,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _skip,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _gold,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _outline, width: 2),
                      ),
                      child: const Text(
                        'SKIP ▸▸',
                        style: TextStyle(
                          color: _outline,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _reveals(PowerUpDef def) => AnimatedBuilder(
    animation: _popCtrl,
    child: SizedBox(
      width: 88,
      height: 88,
      child: CustomPaint(painter: _IconPainter(widget.card)),
    ),
    builder: (context, child) => Opacity(
      opacity: _popFade.value.clamp(0.0, 1.0),
      child: Transform.scale(scale: _popScale.value, child: child),
    ),
  );
}

/// The gold arrow that marks where the wheel lands.
class _PointerPainter extends CustomPainter {
  const _PointerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = _gold);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = _outline,
    );
  }

  @override
  bool shouldRepaint(_PointerPainter oldDelegate) => false;
}

class _IconPainter extends CustomPainter {
  final PowerUpCard card;
  const _IconPainter(this.card);

  @override
  void paint(Canvas canvas, Size size) => paintPowerUpIcon(canvas, size, card);

  @override
  bool shouldRepaint(_IconPainter old) => old.card != card;
}
