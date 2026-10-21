import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/sound_service.dart';

/// Center-screen "AWESOME!" celebration shown whenever a ship is destroyed
/// during gameplay — with a different design per cannon skin.
///
/// Every theme shares one skeleton (letters bouncing in one by one over a
/// 1.5s burst that floats up and fades), but each cannon brings its own
/// palette, its own particle burst and its own center emblem, all in the
/// voice of its firing identity: embers and flame tongues for Inferno,
/// arcing bolts for the Coilgun, gold coins and a crown for Royal,
/// imploding matter for Void, champagne petals and hearts for Rosé, and
/// so on. Nothing is shared between two cannons except the word itself.
///
/// Driven by [cheerId]: 0 means "never cheered" (renders nothing), and
/// every increment replays the animation from the top — so two quick
/// sinkings restart the burst rather than queueing a second one. Always
/// mount inside an `IgnorePointer`: it celebrates over the board, never
/// with it.
class AwesomeCheer extends StatelessWidget {
  final int cheerId;

  /// The cannon whose sinking this celebrates — selects the design.
  /// Null or unknown falls back to the MK-I's steel sparks.
  final String? cannonId;

  const AwesomeCheer({super.key, required this.cheerId, this.cannonId});

  @override
  Widget build(BuildContext context) => SinkingCheer(
        cheerId: cheerId,
        kind: CheerKind.awesome,
        cannonId: cannonId,
      );
}

/// The celebration for a destroyed ship, in whichever voice the coin flip
/// picked (see `SoundService.sinkingCheer`).
///
/// The two lines are NOT the same animation: "AWESOME!" springs up letter
/// by letter over a soft bloom, while "WOW!" slams down as one big word
/// on a double shockwave — so the popup always matches the sound that
/// was just heard, and the two never read as the same canned effect.
class SinkingCheer extends StatefulWidget {
  final int cheerId;

  /// Which voice this celebration is matching.
  final CheerKind kind;

  /// The cannon whose sinking this celebrates — selects the design.
  final String? cannonId;

  const SinkingCheer({
    super.key,
    required this.cheerId,
    this.kind = CheerKind.awesome,
    this.cannonId,
  });

  @override
  State<SinkingCheer> createState() => _SinkingCheerState();
}

/// How one cannon's burst behaves — one value per gun, never shared.
enum CheerBurst {
  sparks, // MK-I: plain powder sparks
  flames, // Inferno: flame tongues and cinders
  arcs, // Arctic Coilgun: jagged bolts and shards
  globs, // Venom: dripping acid globs
  coins, // Royal: fanning coins and star rays
  rings, // Abyss Railgun: counter-rotating rings and motes
  bubbles, // Emerald Cannon: hollow bubbles and a curl
  rays, // Coral Battery: rotating sunburst
  collapse, // Void Annihilator: matter falling inward
  petals, // Rosé Cannon: petals, hearts and fizz
  smoke, // Bell-Mouth Broadside: powder puffs and cinders
  sheets, // MK-IV Autoloader: disciplined twin sheets
  jets, // Pressure Battery: steam jets and a gear ring
  snow, // Icebreaker Mortar: drifting snowflakes
  magma, // Magma Bombard: crater, plume and arcing gobs
  lance, // Ion Lance: hex ripples and scan lines
}

/// One cannon's celebration identity: word colours plus burst.
@immutable
class CheerTheme {
  /// Word outline — doubled as the darkest particle tone.
  final Color deep;

  /// Main particle colour and the word gradient's foot.
  final Color pop;

  /// Highlights, rings, fizz — and the word gradient's crown.
  final Color light;
  final CheerBurst burst;

  const CheerTheme({
    required this.deep,
    required this.pop,
    required this.light,
    required this.burst,
  });
}

const Map<String, CheerTheme> _cheerThemes = {
  'mk1': CheerTheme(
      deep: Color(0xFF1E2A36),
      pop: Color(0xFF94A3B8),
      light: Color(0xFFE5E9EE),
      burst: CheerBurst.sparks),
  'inferno': CheerTheme(
      deep: Color(0xFF3A1206),
      pop: Color(0xFFEF4444),
      light: Color(0xFFFFD54A),
      burst: CheerBurst.flames),
  'tesla': CheerTheme(
      deep: Color(0xFF0B2530),
      pop: Color(0xFF22D3EE),
      light: Color(0xFFE0FBFF),
      burst: CheerBurst.arcs),
  'venom': CheerTheme(
      deep: Color(0xFF1A2A0A),
      pop: Color(0xFF84CC16),
      light: Color(0xFFD4F98A),
      burst: CheerBurst.globs),
  'royal': CheerTheme(
      deep: Color(0xFF3A2408),
      pop: Color(0xFFFBBF24),
      light: Color(0xFFFFF3C4),
      burst: CheerBurst.coins),
  'phantom': CheerTheme(
      deep: Color(0xFF181433),
      pop: Color(0xFFC084FC),
      light: Color(0xFFF1E3FF),
      burst: CheerBurst.rings),
  'kraken': CheerTheme(
      deep: Color(0xFF072E2A),
      pop: Color(0xFF5EEAD4),
      light: Color(0xFFB6FFF1),
      burst: CheerBurst.bubbles),
  'sunfire': CheerTheme(
      deep: Color(0xFF3A1710),
      pop: Color(0xFFFF9E7A),
      light: Color(0xFFFFF8D6),
      burst: CheerBurst.rays),
  'void': CheerTheme(
      deep: Color(0xFF05070D),
      pop: Color(0xFFEC4899),
      light: Color(0xFFFBCFE8),
      burst: CheerBurst.collapse),
  'rose': CheerTheme(
      deep: Color(0xFF7E2F4D),
      pop: Color(0xFFF472B6),
      light: Color(0xFFFCE7F3),
      burst: CheerBurst.petals),
  'f_pirate': CheerTheme(
      deep: Color(0xFF2A1B0F),
      pop: Color(0xFFF2B24C),
      light: Color(0xFFF5E6C8),
      burst: CheerBurst.smoke),
  'f_naval': CheerTheme(
      deep: Color(0xFF1B252D),
      pop: Color(0xFF8CA0AD),
      light: Color(0xFFCFE0EA),
      burst: CheerBurst.sheets),
  'f_steam': CheerTheme(
      deep: Color(0xFF241A10),
      pop: Color(0xFFC99A3F),
      light: Color(0xFFFFF1D6),
      burst: CheerBurst.jets),
  'f_arctic': CheerTheme(
      deep: Color(0xFF1A2730),
      pop: Color(0xFFBBDCEA),
      light: Color(0xFFEAFBFF),
      burst: CheerBurst.snow),
  'f_volcanic': CheerTheme(
      deep: Color(0xFF12100F),
      pop: Color(0xFFFF6A2B),
      light: Color(0xFFFFD9A0),
      burst: CheerBurst.magma),
  'f_scifi': CheerTheme(
      deep: Color(0xFF141A30),
      pop: Color(0xFF6FE7FF),
      light: Color(0xFFDDE9FF),
      burst: CheerBurst.lance),
};

/// The celebration identity for [cannonId] — the MK-I's steel sparks for
/// an unknown or absent gun, never nothing.
CheerTheme cheerThemeFor(String? cannonId) =>
    _cheerThemes[cannonId] ?? _cheerThemes['mk1']!;

class _SinkingCheerState extends State<SinkingCheer>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 1500);
  static const _awesomeLetters = ['A', 'W', 'E', 'S', 'O', 'M', 'E', '!'];
  static const _wowLetters = ['W', 'O', 'W', '!'];

  late final AnimationController _ctrl;
  bool _played = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _duration);
    // A fresh mount already holding a cheer (the overlay slot swaps
    // between the awesome and wow words) plays at once — otherwise it
    // would sit idle waiting for an update that never comes.
    if (widget.cheerId > 0) {
      _played = true;
      _ctrl.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(SinkingCheer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.cheerId != oldWidget.cheerId ||
            widget.cannonId != oldWidget.cannonId ||
            widget.kind != oldWidget.kind) &&
        widget.cheerId > 0) {
      _played = true;
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = cheerThemeFor(widget.cannonId);
    final wow = widget.kind == CheerKind.wow;
    final letters = wow ? _wowLetters : _awesomeLetters;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        // Idle (never cheered) and settled (burst fully faded) both draw
        // nothing at all — the overlay is only ever alive mid-burst.
        if (!_played || t >= 1.0) return const SizedBox.shrink();
        // "AWESOME!" blooms up and floats away over the last 30%; "WOW!"
        // holds its punch longer, then snaps out upward.
        final exit =
            ((t - (wow ? 0.76 : 0.70)) / (wow ? 0.24 : 0.30)).clamp(0.0, 1.0);
        final fade = 1 - exit;
        final rise = -(wow ? 44 : 26) * Curves.easeIn.transform(exit);
        final bloom = wow
            ? Curves.easeOutBack.transform((t / 0.16).clamp(0.0, 1.0))
            : Curves.easeOutBack.transform((t / 0.22).clamp(0.0, 1.0));
        return Opacity(
          opacity: fade.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, rise),
            child: Transform.rotate(
              angle: wow ? 0.02 : -0.05,
              child: Transform.scale(
                scale: bloom,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: 320,
                    height: 240,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: wow
                                ? _WowFxPainter(t, theme)
                                : _CheerFxPainter(t, theme),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < letters.length; i++)
                              _CheerLetter(
                                  letter: letters[i],
                                  t: t,
                                  index: i,
                                  theme: theme,
                                  drop: wow),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One letter of the word. "AWESOME!" springs up letter by letter on an
/// elastic; "WOW!" slams down as one heavier word that lands and bounces.
class _CheerLetter extends StatelessWidget {
  final String letter;
  final double t;
  final int index;
  final CheerTheme theme;

  /// The WOW choreography: a drop from above with a bounce, bigger and
  /// heavier than the awesome letters.
  final bool drop;

  const _CheerLetter(
      {required this.letter,
      required this.t,
      required this.index,
      required this.theme,
      this.drop = false});

  @override
  Widget build(BuildContext context) {
    final size = drop ? 54.0 : 36.0;
    final stroke = drop ? 9.0 : 6.0;
    late final double s;
    late final Offset offset;
    late final double angle;
    if (drop) {
      final fall = (t - index * 0.03).clamp(0.0, 1.0);
      s = Curves.easeOutBack.transform(
          ((t - 0.01 - index * 0.03) / 0.20).clamp(0.0, 1.0));
      // Falls in from above, lands with a bounce, and settles.
      offset = Offset(0, -190 * (1 - Curves.bounceOut.transform(fall)));
      angle = (0.06 - index * 0.04) * s;
    } else {
      final local =
          ((t - 0.05 - index * 0.045) / 0.45).clamp(0.0, 1.0);
      s = Curves.elasticOut.transform(local);
      offset = Offset(0, -14 * (1 - s));
      angle = (-0.09 + index * 0.025) * s;
    }
    if (s <= 0.01) return SizedBox(width: size * 0.66);
    return Transform.translate(
      offset: offset,
      child: Transform.rotate(
        angle: angle,
        child: Transform.scale(
          scaleX: s,
          scaleY: s,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Dark outline behind, so the word reads over any deck.
              Text(
                letter,
                style: TextStyle(
                  fontSize: size,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = stroke
                    ..strokeJoin = StrokeJoin.round
                    ..color = theme.deep,
                ),
              ),
              // Champagne gradient fill, light on top melting to pop.
              ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    theme.light,
                    theme.light,
                    theme.pop,
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ).createShader(bounds),
                child: Text(
                  letter,
                  style: TextStyle(
                    fontSize: size,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The burst behind the word — one vocabulary per cannon (see
/// [CheerBurst]), all in that cannon's own [CheerTheme] colours.
class _CheerFxPainter extends CustomPainter {
  final double t;
  final CheerTheme theme;

  _CheerFxPainter(this.t, this.theme);

  double _jit(int seed, int i) {
    var x = seed * 374761393 + i * 668265263;
    x = (x ^ (x >> 13)) * 1274126177;
    return ((x ^ (x >> 16)) & 0x7FFFFFF) / 0x7FFFFFF;
  }

  Paint _fill(Color c, double a) =>
      Paint()..color = c.withValues(alpha: a.clamp(0.0, 1.0));

  Paint _stroke(Color c, double a, double w) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = w
    ..color = c.withValues(alpha: a.clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2;
    final pop = theme.pop;
    final light = theme.light;
    final deep = theme.deep;
    final fade = 1 - ((t - 0.55) / 0.45).clamp(0.0, 1.0);
    final flight =
        Curves.easeOutCubic.transform((t / 0.55).clamp(0.0, 1.0));

    // Hot opening flash in this cannon's own light.
    if (t < 0.2) {
      canvas.drawCircle(
        center,
        r * 0.30 * (1 - t * 2),
        _fill(light, (1 - t / 0.2) * 0.85),
      );
    }

    switch (theme.burst) {
      case CheerBurst.sparks:
        _ring(canvas, center, r * (0.25 + 0.65 * flight), light, 4, fade);
        for (var i = 0; i < 10; i++) {
          final a = (i / 10) * 2 * math.pi + _jit(3, i) * 0.3;
          final len =
              r * (0.25 + 0.60 * flight) * (0.5 + _jit(3, i + 9) * 0.7);
          canvas.drawLine(
            center + Offset(math.cos(a), math.sin(a)) * r * 0.15,
            center + Offset(math.cos(a), math.sin(a)) * len,
            _stroke(i.isEven ? light : pop, fade, 3.5),
          );
        }
        for (var i = 0; i < 6; i++) {
          final a = (i / 6) * 2 * math.pi + 0.5;
          canvas.drawCircle(
            center + Offset(math.cos(a), math.sin(a)) * r * 0.7 * flight,
            3 * fade + 1,
            _fill(pop, fade),
          );
        }

      case CheerBurst.flames:
        _ring(canvas, center, r * (0.25 + 0.65 * flight), pop, 4, fade);
        for (var i = 0; i < 7; i++) {
          final a = -math.pi / 2 + (i - 3) * 0.38;
          final h = r * (0.35 + 0.45 * flight) * (0.7 + _jit(5, i) * 0.5);
          final tip = center + Offset(math.cos(a), math.sin(a)) * h;
          final base = center + Offset(math.cos(a), math.sin(a)) * r * 0.12;
          final side = Offset(-math.sin(a), math.cos(a)) * 9;
          canvas.drawPath(
            Path()
              ..moveTo(base.dx - side.dx, base.dy - side.dy)
              ..lineTo(tip.dx, tip.dy)
              ..lineTo(base.dx + side.dx, base.dy + side.dy)
              ..close(),
            _fill(i.isEven ? pop : light, fade * 0.9),
          );
        }
        for (var i = 0; i < 6; i++) {
          final p = center +
              Offset((_jit(5, i + 20) - 0.5) * r, -r * (0.2 + 0.9 * flight));
          canvas.drawCircle(p, 2.5 * fade + 1, _fill(light, fade * 0.9));
        }
        canvas.drawCircle(center, r * 0.14, _fill(light, fade));

      case CheerBurst.arcs:
        _ring(canvas, center, r * (0.25 + 0.65 * flight), light, 3, fade);
        for (var i = 0; i < 5; i++) {
          final a = (i / 5) * 2 * math.pi + 0.4;
          final path = Path()..moveTo(center.dx, center.dy);
          for (var k = 1; k <= 3; k++) {
            final rr = r * 0.7 * flight * (k / 3);
            final off = (_jit(7, i * 5 + k) - 0.5) * 0.9;
            path.lineTo(center.dx + math.cos(a + off) * rr,
                center.dy + math.sin(a + off) * rr);
          }
          canvas.drawPath(path, _stroke(light, fade * 0.95, 3));
        }
        for (var i = 0; i < 8; i++) {
          final a = (i / 8) * 2 * math.pi + 0.2;
          final inner = r * 0.55 * flight;
          canvas.drawLine(
            center + Offset(math.cos(a), math.sin(a)) * inner,
            center + Offset(math.cos(a), math.sin(a)) * (inner + 14),
            _stroke(pop, fade, 3),
          );
        }
        canvas.drawCircle(center, 5 * fade + 1, _fill(light, fade));

      case CheerBurst.globs:
        _ring(canvas, center, r * (0.25 + 0.65 * flight), pop, 4, fade);
        for (var i = 0; i < 9; i++) {
          final a = (i / 9) * 2 * math.pi + _jit(9, i) * 0.4 + math.pi / 2 * 0.4;
          final d = r * (0.2 + 0.55 * flight) * (0.6 + _jit(9, i + 7) * 0.7);
          final p = center + Offset(math.cos(a) * d, math.sin(a) * d);
          canvas.drawCircle(
              p, (4 + 5 * _jit(9, i + 13)) * fade + 1, _fill(pop, fade * 0.9));
          canvas.drawLine(
            p,
            p.translate(0, 12 * flight),
            _stroke(pop, fade * 0.5, 3),
          );
        }
        canvas.drawCircle(center, r * 0.12, _fill(light, fade));

      case CheerBurst.coins:
        _ring(canvas, center, r * (0.25 + 0.65 * flight), pop, 4, fade);
        for (var i = 0; i < 8; i++) {
          final a = -math.pi / 2 + (i - 3.5) * 0.30;
          final d = r * (0.25 + 0.6 * flight);
          final p = center + Offset(math.cos(a) * d, math.sin(a) * d);
          final s = 8 * fade + 2;
          canvas.save();
          canvas.translate(p.dx, p.dy);
          canvas.rotate(a + t * 3);
          canvas.drawPath(
            Path()
              ..moveTo(0, -s)
              ..lineTo(s * 0.7, 0)
              ..lineTo(0, s)
              ..lineTo(-s * 0.7, 0)
              ..close(),
            _fill(pop, fade),
          );
          canvas.restore();
        }
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4 + t * 0.6;
          final len = r * (i.isEven ? 0.62 : 0.34) * flight;
          canvas.drawLine(
            center,
            center + Offset(math.cos(a), math.sin(a)) * len,
            _stroke(light, fade * 0.85, 3),
          );
        }
        // Mini crown at the middle.
        final crown = Path()
          ..moveTo(center.dx - 14, center.dy + 8)
          ..lineTo(center.dx - 14, center.dy - 4)
          ..lineTo(center.dx - 7, center.dy + 2)
          ..lineTo(center.dx, center.dy - 8)
          ..lineTo(center.dx + 7, center.dy + 2)
          ..lineTo(center.dx + 14, center.dy - 4)
          ..lineTo(center.dx + 14, center.dy + 8)
          ..close();
        canvas.drawPath(crown, _fill(pop, fade));
        canvas.drawCircle(center + const Offset(0, 2), 3, _fill(light, fade));

      case CheerBurst.rings:
        _ring(canvas, center, r * (0.2 + 0.7 * flight), pop, 5, fade);
        _ring(canvas, center, r * (0.12 + 0.5 * (flight * 0.8 + 0.2 * t)),
            light, 3, fade * 0.8);
        for (var i = 0; i < 6; i++) {
          final a = (i / 6) * 2 * math.pi + t * 2.2;
          final p =
              center + Offset(math.cos(a), math.sin(a)) * r * 0.55 * flight;
          canvas.drawCircle(p, 3 * fade + 1, _fill(light, fade * 0.9));
        }
        // Hollow hex heart of the railgun.
        _poly(canvas, center, r * 0.16, 6, t * 0.8, pop, 3, fade);

      case CheerBurst.bubbles:
        _ring(canvas, center, r * (0.25 + 0.65 * flight), light, 4, fade);
        for (var i = 0; i < 8; i++) {
          final rise = (t * 1.0 + i * 0.14 + _jit(13, i) * 0.2) % 1.0;
          final p = center +
              Offset(
                (((i * 0.41) % 1) - 0.5) * 2 * r * 0.8,
                r * (0.7 - 1.5 * rise),
              );
          canvas.drawCircle(
            p,
            3 + (i % 3) * 2.5,
            _stroke(light, (1 - rise) * 0.9, 2),
          );
        }
        for (var i = 0; i < 5; i++) {
          final a = (i / 5) * 2 * math.pi + 0.9;
          canvas.drawCircle(
            center + Offset(math.cos(a), math.sin(a)) * r * 0.5 * flight,
            3.5 * fade + 1,
            _fill(pop, fade),
          );
        }
        // Tentacle curl at the middle.
        canvas.drawPath(
          Path()
            ..moveTo(center.dx - r * 0.22, center.dy + r * 0.1)
            ..cubicTo(center.dx - r * 0.1, center.dy - r * 0.16,
                center.dx + r * 0.12, center.dy - r * 0.14, center.dx + r * 0.1, center.dy + r * 0.04)
            ..cubicTo(center.dx + r * 0.08, center.dy + r * 0.14,
                center.dx - r * 0.04, center.dy + r * 0.14, center.dx - r * 0.02, center.dy + r * 0.06),
          _stroke(pop, fade, 4),
        );

      case CheerBurst.rays:
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4 + t * 0.7;
          final tip = center +
              Offset(math.cos(a), math.sin(a)) * r * (0.35 + 0.5 * flight);
          final base = center +
              Offset(math.cos(a), math.sin(a)) * r * 0.18;
          final side = Offset(-math.sin(a), math.cos(a)) * 8;
          canvas.drawPath(
            Path()
              ..moveTo(base.dx - side.dx, base.dy - side.dy)
              ..lineTo(tip.dx, tip.dy)
              ..lineTo(base.dx + side.dx, base.dy + side.dy)
              ..close(),
            _fill(pop, fade * 0.9),
          );
        }
        canvas.drawCircle(center, r * 0.16 * flight + 4, _fill(pop, fade));
        canvas.drawCircle(center, r * 0.07, _fill(light, fade));
        _ring(canvas, center, r * (0.3 + 0.55 * flight), light, 3, fade * 0.8);

      case CheerBurst.collapse:
        // The only burst that falls INWARD: debris converges while the
        // ring contracts around a dark, flashing core.
        final inward = Curves.easeIn.transform(t);
        _ring(canvas, center, r * (0.9 - 0.45 * inward), pop, 4, fade);
        for (var i = 0; i < 8; i++) {
          final a = (i / 8) * 2 * math.pi + _jit(17, i) * 0.5;
          final d = r * 0.75 * (1 - inward);
          canvas.drawCircle(
            center + Offset(math.cos(a) * d, math.sin(a) * d),
            3.5 * fade + 1,
            _fill(pop, fade * 0.9),
          );
        }
        canvas.drawCircle(center, r * 0.22, _fill(deep, fade * 0.9));
        final flash = (1 - (t - 0.55).abs() * 5).clamp(0.0, 1.0);
        canvas.drawCircle(center, r * 0.1 * flash + 1, _fill(light, flash));

      case CheerBurst.petals:
        for (var i = 0; i < 8; i++) {
          final a = (i / 8) * 2 * math.pi + 0.3 + _jit(11, i) * 0.4;
          final d = r * (0.15 + 0.75 * flight) * (0.7 + 0.5 * _jit(11, i + 8));
          final p = center + Offset(math.cos(a) * d, math.sin(a) * d);
          canvas.save();
          canvas.translate(p.dx, p.dy);
          canvas.rotate(a + t * 4 * (i.isEven ? 1 : -1));
          canvas.drawOval(
            Rect.fromCenter(
                center: Offset.zero,
                width: 26 * fade + 4,
                height: 13 * fade + 2),
            _fill(i.isEven ? pop : light, fade),
          );
          canvas.restore();
        }
        _ring(canvas, center, r * (0.25 + 0.65 * flight), light, 3, fade * 0.8);
        for (var i = 0; i < 5; i++) {
          final a = -math.pi / 2 + i * 2 * math.pi / 5 + t * 0.9;
          final p = center +
              Offset(math.cos(a), math.sin(a)) * r * (0.25 + 0.65 * flight);
          canvas.drawCircle(p, 5 * fade + 1, _fill(pop, fade));
        }
        for (var i = 0; i < 10; i++) {
          final rise = (t * 1.1 + i * 0.13 + _jit(29, i) * 0.2) % 1.0;
          final p = center +
              Offset(
                (((i * 0.37) % 1) - 0.5) * 2 * r * 0.85,
                r * (0.9 - 1.8 * rise),
              );
          canvas.drawCircle(
            p,
            2.5 + (i % 3) * 1.8,
            _stroke(light, (1 - rise) * 0.85, 1.6),
          );
        }
        for (var i = 0; i < 6; i++) {
          final a = (i / 6) * 2 * math.pi + 0.55;
          final p = center + Offset(math.cos(a), math.sin(a)) * r * 0.78;
          final tw = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(t * 22 + i * 1.7));
          final s = 9 * tw * fade + 1;
          canvas.drawPath(
            _spark(p, s),
            _fill(light, (tw * fade).clamp(0.0, 1.0)),
          );
        }
        for (var i = 0; i < 3; i++) {
          final drift = (t * 0.7 + i * 0.33) % 1.0;
          final p = center +
              Offset((i - 1) * r * 0.55, r * (0.45 - 1.0 * drift));
          _heart(canvas, p, 7 * (1 - drift * 0.4),
              pop.withValues(alpha: ((1 - drift) * fade).clamp(0.0, 1.0)));
        }

      case CheerBurst.smoke:
        _ring(canvas, center, r * (0.25 + 0.65 * flight), pop, 3, fade * 0.6);
        for (var i = 0; i < 6; i++) {
          final a = (i / 6) * 2 * math.pi + 0.7;
          final p =
              center + Offset(math.cos(a), math.sin(a)) * r * 0.45 * flight;
          canvas.drawCircle(
            p,
            (10 + 26 * t) * fade + 2,
            _fill(light, fade * 0.35),
          );
          canvas.drawCircle(
            p,
            (10 + 26 * t) * fade + 2,
            _stroke(pop, fade * 0.5, 2),
          );
        }
        for (var i = 0; i < 6; i++) {
          final a = -math.pi / 2 + (i - 2.5) * 0.4;
          final d = r * (0.3 + 0.55 * flight);
          canvas.drawCircle(
            center + Offset(math.cos(a) * d, math.sin(a) * d - r * 0.15 * t),
            3.5 * fade + 1,
            _fill(pop, fade),
          );
        }
        canvas.drawCircle(center, r * 0.12, _fill(pop, fade));

      case CheerBurst.sheets:
        // Two disciplined sheets thrown left and right — no scatter.
        for (final dir in [-1.0, 1.0]) {
          final path = Path()
            ..moveTo(center.dx, center.dy)
            ..quadraticBezierTo(
              center.dx + dir * r * 0.4 * flight,
              center.dy - r * 0.35 * flight,
              center.dx + dir * r * 0.72 * flight,
              center.dy + r * 0.08 * flight,
            );
          canvas.drawPath(path, _stroke(light, fade * 0.9, 5));
        }
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: center, width: r * (0.5 + 0.9 * flight), height: r * (0.32 + 0.6 * flight)),
            const Radius.circular(8),
          ),
          _stroke(pop, fade * 0.8, 3.5),
        );
        for (var i = 0; i < 6; i++) {
          final a = (i / 6) * 2 * math.pi + 0.2;
          final p =
              center + Offset(math.cos(a), math.sin(a)) * r * 0.6 * flight;
          canvas.save();
          canvas.translate(p.dx, p.dy);
          canvas.rotate(a + t * 2);
          canvas.drawRect(
            Rect.fromCenter(center: Offset.zero, width: 9, height: 9),
            _fill(light, fade * 0.9),
          );
          canvas.restore();
        }
        // Twin chevrons locking on at the middle.
        for (var k = 0; k < 2; k++) {
          final o = k * 12.0;
          canvas.drawPath(
            Path()
              ..moveTo(center.dx - 16 - o, center.dy - 12)
              ..lineTo(center.dx - 4 - o, center.dy)
              ..lineTo(center.dx - 16 - o, center.dy + 12),
            _stroke(pop, fade, 3.5),
          );
          canvas.drawPath(
            Path()
              ..moveTo(center.dx + 16 + o, center.dy - 12)
              ..lineTo(center.dx + 4 + o, center.dy)
              ..lineTo(center.dx + 16 + o, center.dy + 12),
            _stroke(pop, fade, 3.5),
          );
        }

      case CheerBurst.jets:
        for (var i = -1; i <= 1; i++) {
          canvas.drawLine(
            Offset(center.dx + i * 20, center.dy + r * 0.1),
            Offset(center.dx + i * 26, center.dy - r * (0.35 + 0.5 * flight)),
            _stroke(light, fade * 0.9, 5),
          );
        }
        for (var i = 0; i < 12; i++) {
          final a = i * math.pi / 6 + t * 1.2;
          final rr = r * 0.5 * flight + 10;
          canvas.drawLine(
            center + Offset(math.cos(a), math.sin(a)) * rr,
            center + Offset(math.cos(a), math.sin(a)) * (rr + 10),
            _stroke(pop, fade * 0.9, 4),
          );
        }
        canvas.drawCircle(center, r * (0.2 + 0.3 * flight),
            _stroke(pop, fade * 0.8, 4));
        for (var i = 0; i < 4; i++) {
          canvas.drawCircle(
            center + Offset((i - 1.5) * 22, -r * 0.55 * flight),
            (6 + 8 * t) * fade + 1,
            _fill(light, fade * 0.4),
          );
        }

      case CheerBurst.snow:
        _poly(canvas, center, r * (0.3 + 0.55 * flight), 6, 0.3, light, 3,
            fade * 0.9);
        for (var i = 0; i < 10; i++) {
          final drift = (t * 0.6 + i * 0.17) % 1.0;
          final p = center +
              Offset(
                (((i * 0.43) % 1) - 0.5) * 2 * r * 0.9 +
                    math.sin(drift * 9 + i) * 8,
                r * (0.75 - 1.5 * drift),
              );
          final s = 5.0 + (i % 3) * 2;
          canvas.drawLine(
              p.translate(-s, 0), p.translate(s, 0), _stroke(light, (1 - drift) * fade, 2.2));
          canvas.drawLine(
              p.translate(-s * 0.7, -s * 0.7),
              p.translate(s * 0.7, s * 0.7),
              _stroke(light, (1 - drift) * fade, 2.2));
        }
        canvas.drawCircle(center, 5 * fade + 1, _fill(light, fade));

      case CheerBurst.magma:
        canvas.drawCircle(center, r * 0.30, _fill(deep, fade * 0.85));
        _ring(canvas, center, r * 0.30, pop, 3.5, fade);
        canvas.drawPath(
          Path()
            ..moveTo(center.dx - r * 0.13, center.dy)
            ..quadraticBezierTo(center.dx - r * 0.05,
                center.dy - r * 0.55 * flight, center.dx, center.dy - r * 0.62 * flight)
            ..quadraticBezierTo(center.dx + r * 0.05,
                center.dy - r * 0.55 * flight, center.dx + r * 0.13, center.dy)
            ..close(),
          _fill(pop, fade * 0.9),
        );
        for (var i = 0; i < 7; i++) {
          final a = -math.pi / 2 + (i - 3) * 0.38;
          final d = r * (0.35 + 0.45 * flight);
          final p = center +
              Offset(math.cos(a) * d, math.sin(a) * d + r * 0.3 * t * t);
          canvas.drawCircle(p, (4 + 2 * _jit(31, i)) * fade + 1,
              _fill(i.isEven ? pop : light, fade * 0.95));
        }
        _ring(canvas, center, r * (0.4 + 0.5 * flight), light, 3, fade * 0.5);

      case CheerBurst.lance:
        canvas.drawLine(
          center.translate(0, -r * 0.85),
          center.translate(0, r * 0.85),
          _stroke(pop, fade * 0.9, 5),
        );
        canvas.drawLine(
          center.translate(-r * 0.85, 0),
          center.translate(r * 0.85, 0),
          _stroke(pop, fade * 0.4, 3),
        );
        _poly(canvas, center, r * (0.2 + 0.5 * flight), 6, t, light, 3,
            fade * 0.8);
        _poly(canvas, center, r * (0.12 + 0.3 * flight), 6, -t * 1.3, pop, 2.5,
            fade * 0.9);
        for (var i = 0; i < 4; i++) {
          final y = center.dy + (i - 1.5) * 26;
          canvas.drawLine(
            Offset(center.dx - r * 0.5 * fade, y),
            Offset(center.dx + r * 0.5 * fade, y),
            _stroke(light, fade * 0.5, 2),
          );
        }
        canvas.drawCircle(center, 5 * fade + 1, _fill(light, fade));
    }
  }

  void _ring(Canvas canvas, Offset c, double rad, Color color, double w,
      double a) {
    canvas.drawCircle(
        c, rad, _stroke(color, a * 0.9, w * (0.4 + 0.6 * a)));
  }

  void _poly(Canvas canvas, Offset c, double rad, int sides, double rot,
      Color color, double w, double a) {
    final path = Path();
    for (var k = 0; k < sides; k++) {
      final ang = rot + k * 2 * math.pi / sides;
      final pt = c + Offset(math.cos(ang) * rad, math.sin(ang) * rad);
      if (k == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    canvas.drawPath(path, _stroke(color, a, w));
  }

  Path _spark(Offset p, double s) => Path()
    ..moveTo(p.dx, p.dy - s)
    ..lineTo(p.dx + s * 0.28, p.dy - s * 0.28)
    ..lineTo(p.dx + s, p.dy)
    ..lineTo(p.dx + s * 0.28, p.dy + s * 0.28)
    ..lineTo(p.dx, p.dy + s)
    ..lineTo(p.dx - s * 0.28, p.dy + s * 0.28)
    ..lineTo(p.dx - s, p.dy)
    ..lineTo(p.dx - s * 0.28, p.dy - s * 0.28)
    ..close();

  void _heart(Canvas canvas, Offset p, double s, Color color) {
    final paint = _fill(color, 1);
    canvas.drawCircle(
        Offset(p.dx - s * 0.32, p.dy - s * 0.12), s * 0.36, paint);
    canvas.drawCircle(
        Offset(p.dx + s * 0.32, p.dy - s * 0.12), s * 0.36, paint);
    canvas.drawPath(
      Path()
        ..moveTo(p.dx - s * 0.62, p.dy + s * 0.05)
        ..lineTo(p.dx + s * 0.62, p.dy + s * 0.05)
        ..lineTo(p.dx, p.dy + s * 0.68)
        ..close(),
      paint,
    );
  }

  @override
  bool shouldRepaint(_CheerFxPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.theme != theme;
}

/// The burst behind the WOW! word — the same sixteen cannons, the same
/// sixteen palettes, but a different vocabulary from the AWESOME! burst:
/// where "AWESOME!" blooms and scatters, "WOW!" SLAMS — a hard double
/// shockwave and one emphatic gesture per gun.
class _WowFxPainter extends CustomPainter {
  final double t;
  final CheerTheme theme;

  _WowFxPainter(this.t, this.theme);

  double _jit(int seed, int i) {
    var x = seed * 374761393 + i * 668265263;
    x = (x ^ (x >> 13)) * 1274126177;
    return ((x ^ (x >> 16)) & 0x7FFFFFF) / 0x7FFFFFF;
  }

  Paint _fill(Color c, double a) =>
      Paint()..color = c.withValues(alpha: a.clamp(0.0, 1.0));

  Paint _stroke(Color c, double a, double w) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = w
    ..color = c.withValues(alpha: a.clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2;
    final pop = theme.pop;
    final light = theme.light;
    final deep = theme.deep;
    final fade = 1 - ((t - 0.55) / 0.45).clamp(0.0, 1.0);
    // The slam: the shockwave races out early and fast.
    final shock = Curves.easeOutQuart.transform((t / 0.45).clamp(0.0, 1.0));
    final settle = Curves.easeOutCubic.transform((t / 0.30).clamp(0.0, 1.0));

    // The double shockwave every WOW! shares — the one thing that makes
    // it read as a slam rather than a bloom.
    for (final k in const [0.0, 0.18]) {
      final p = ((shock - k) / (1 - k)).clamp(0.0, 1.0);
      if (p <= 0) continue;
      canvas.drawCircle(
        center,
        r * 1.05 * p,
        _stroke(light, (1 - p) * 0.9, 10 * (1 - p) + 1),
      );
    }
    // The impact flash, right at the word.
    canvas.drawCircle(
      center,
      r * 0.42 * (1 - t * 1.6).clamp(0.0, 1.0),
      _fill(light, (1 - t / 0.35).clamp(0.0, 1.0) * 0.8),
    );

    switch (theme.burst) {
      case CheerBurst.sparks:
        // One hard cross of sparks, four directions.
        for (final dir in const [-1.0, 1.0]) {
          canvas.drawLine(
            center + Offset(-r * 0.9 * dir, 0),
            center + Offset(r * 0.9 * dir, 0),
            _stroke(light, fade, 5),
          );
          canvas.drawLine(
            center + Offset(0, -r * 0.9 * dir),
            center + Offset(0, r * 0.9 * dir),
            _stroke(pop, fade, 5),
          );
        }

      case CheerBurst.flames:
        // A solid cone of flame punched straight out.
        canvas.drawPath(
          Path()
            ..moveTo(center.dx - r * 0.5, center.dy)
            ..lineTo(center.dx + r * 0.5, center.dy)
            ..lineTo(center.dx, center.dy - r * 1.1 * settle)
            ..close(),
          _fill(pop, fade * 0.9),
        );
        canvas.drawPath(
          Path()
            ..moveTo(center.dx - r * 0.2, center.dy)
            ..lineTo(center.dx + r * 0.2, center.dy)
            ..lineTo(center.dx, center.dy - r * 0.7 * settle)
            ..close(),
          _fill(light, fade),
        );

      case CheerBurst.arcs:
        // Four lightning forks striking in at once.
        for (var i = 0; i < 4; i++) {
          final a = i * math.pi / 2 + 0.4;
          final path = Path()..moveTo(center.dx, center.dy);
          for (var k = 1; k <= 3; k++) {
            final rr = r * 1.0 * settle * (k / 3);
            final off = (_jit(7, i * 5 + k) - 0.5) * 0.8;
            path.lineTo(center.dx + math.cos(a + off) * rr,
                center.dy + math.sin(a + off) * rr);
          }
          canvas.drawPath(path, _stroke(light, fade, 4));
        }

      case CheerBurst.globs:
        // Heavy splats flung outward, sagging.
        for (var i = 0; i < 7; i++) {
          final a = (i / 7) * 2 * math.pi + 0.3;
          final d = r * 0.95 * settle;
          final p = center + Offset(math.cos(a) * d, math.sin(a) * d * 0.8);
          canvas.drawCircle(p, 9 * fade + 2, _fill(pop, fade));
        }

      case CheerBurst.coins:
        // A neat gold medallion stamped dead centre.
        canvas.drawCircle(center, r * 0.34, _fill(pop, fade));
        canvas.drawCircle(
          center,
          r * 0.34,
          _stroke(light, fade, 4),
        );
        canvas.drawCircle(center, r * 0.16, _fill(light, fade));

      case CheerBurst.rings:
        // One solid violet disc punched through.
        canvas.drawCircle(center, r * 0.36, _fill(deep, fade * 0.95));
        canvas.drawCircle(center, r * 0.36, _stroke(pop, fade, 5));
        canvas.drawCircle(center, r * 0.12, _fill(light, fade));

      case CheerBurst.bubbles:
        // Three big bubbles bursting apart.
        for (var i = 0; i < 3; i++) {
          final a = (i / 3) * 2 * math.pi + 0.5;
          final d = r * 0.7 * settle;
          final p = center + Offset(math.cos(a) * d, math.sin(a) * d);
          canvas.drawCircle(
            p,
            14 * fade + 2,
            _stroke(light, fade, 3),
          );
        }

      case CheerBurst.rays:
        // Twelve straight rays, a hard sun.
        for (var i = 0; i < 12; i++) {
          final a = i * math.pi / 6;
          final inner = r * 0.30;
          final outer = r * (i.isEven ? 1.05 : 0.72) * settle;
          canvas.drawLine(
            center + Offset(math.cos(a) * inner, math.sin(a) * inner),
            center + Offset(math.cos(a) * outer, math.sin(a) * outer),
            _stroke(i.isEven ? pop : light, fade, i.isEven ? 5 : 3),
          );
        }

      case CheerBurst.collapse:
        // Everything rushes INWARD and a black hole flashes.
        final inward = Curves.easeIn.transform(t);
        canvas.drawCircle(
          center,
          r * 0.9 * (1 - inward),
          _stroke(pop, fade, 6),
        );
        canvas.drawCircle(center, r * 0.2, _fill(deep, fade));
        final flash = (1 - (t - 0.6).abs() * 6).clamp(0.0, 1.0);
        canvas.drawCircle(center, r * 0.1 * flash + 1, _fill(light, flash));

      case CheerBurst.petals:
        // A tight ring of petals bursting outward like a bloom.
        for (var i = 0; i < 10; i++) {
          final a = (i / 10) * 2 * math.pi + 0.2;
          final d = r * 0.95 * settle;
          final p = center + Offset(math.cos(a) * d, math.sin(a) * d);
          canvas.save();
          canvas.translate(p.dx, p.dy);
          canvas.rotate(a);
          canvas.drawOval(
            Rect.fromCenter(
                center: Offset.zero, width: 22 * fade + 4, height: 10 * fade + 2),
            _fill(i.isEven ? pop : light, fade),
          );
          canvas.restore();
        }

      case CheerBurst.smoke:
        // One thick rolling smoke ball.
        for (var i = 0; i < 4; i++) {
          canvas.drawCircle(
            center + Offset((i - 1.5) * r * 0.2, 0),
            r * (0.34 + 0.2 * t) * (1 - t * 0.4),
            _fill(light, fade * 0.3),
          );
        }

      case CheerBurst.sheets:
        // Two hard plates slamming in from the sides.
        for (final dir in [-1.0, 1.0]) {
          final w = r * 0.9 * settle;
          canvas.drawRect(
            Rect.fromLTWH(
              dir < 0 ? center.dx - w : center.dx,
              center.dy - r * 0.3,
              w,
              r * 0.6,
            ),
            _fill(pop, fade * 0.8),
          );
        }

      case CheerBurst.jets:
        // Three hard steam jets punching up.
        for (var i = -1; i <= 1; i++) {
          canvas.drawLine(
            Offset(center.dx + i * 22, center.dy + r * 0.25),
            Offset(center.dx + i * 22, center.dy - r * 0.95 * settle),
            _stroke(light, fade, 7),
          );
        }

      case CheerBurst.snow:
        // A hard snowflake cross.
        for (var i = 0; i < 3; i++) {
          final a = i * math.pi / 3;
          canvas.drawLine(
            center - Offset(math.cos(a) * r * 0.95, math.sin(a) * r * 0.95),
            center + Offset(math.cos(a) * r * 0.95, math.sin(a) * r * 0.95),
            _stroke(light, fade, 5),
          );
        }

      case CheerBurst.magma:
        // A single tall gout of molten rock.
        canvas.drawPath(
          Path()
            ..moveTo(center.dx - r * 0.26, center.dy + r * 0.2)
            ..lineTo(center.dx + r * 0.26, center.dy + r * 0.2)
            ..lineTo(center.dx, center.dy - r * 1.1 * settle)
            ..close(),
          _fill(pop, fade),
        );
        canvas.drawCircle(center, r * 0.22, _fill(light, fade));

      case CheerBurst.lance:
        // A single beam straight through the middle.
        canvas.drawLine(
          center.translate(0, -r * 1.1),
          center.translate(0, r * 1.1),
          _stroke(pop, fade, 9),
        );
        canvas.drawLine(
          center.translate(0, -r * 1.1),
          center.translate(0, r * 1.1),
          _stroke(light, fade * 0.7, 3),
        );
    }
  }

  @override
  bool shouldRepaint(_WowFxPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.theme != theme;
}
