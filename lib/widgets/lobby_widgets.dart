/// Shared furniture for the three lobby screens — HOTSPOT / LAN, ONLINE's
/// friends list, and its matchmaking page.
///
/// The three used to be built out of whatever each screen happened to
/// reach for: a `ListTile` here, a bare `Text` there, three different
/// spellings of "a room code". A captain moving between them was really
/// moving between three separate designs of the same idea — find someone,
/// see who they are, join them.
///
/// These are the pieces that idea is actually made of, defined once: a
/// code as tiles or as a pill, a captain as an avatar and a rank line, a
/// room as a signal badge with a status, a wait as a bar with a clock on
/// it. Every one of them draws in the game's own palette and type
/// (`AppColors`/`AppText`) — the layout is what is shared here, never a
/// colour.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// One character of a room code in its own chunky box.
///
/// A code is read aloud across a room ("ex, vee, jay, pee") far more often
/// than it is read off a screen, and a single run-together word is the
/// worst shape for that. Splitting it into tiles gives the eye a stop
/// between characters, and gives the four letters the weight they deserve
/// as the one thing the other captain actually needs.
class CodeTiles extends StatelessWidget {
  final String code;

  /// Tile fill. The default reads on a dark panel; pass a deeper tone when
  /// these sit on a light card.
  final Color color;
  final Color textColor;
  final double size;

  const CodeTiles({
    super.key,
    required this.code,
    this.color = AppColors.cream,
    this.textColor = AppColors.outline,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final chars = code.trim().toUpperCase().split('');
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final ch in chars)
          Container(
            width: size,
            height: size * 1.06,
            margin: EdgeInsets.symmetric(horizontal: size * 0.07),
            alignment: Alignment.center,
            decoration: cartoonBox(color, radius: size * 0.24),
            child: Text(
              ch,
              style: AppText.title(size: size * 0.52, color: textColor),
            ),
          ),
      ],
    );
  }
}

/// A room code at list size — small, boxed, and set apart from the name
/// beside it so the two never read as one string.
class CodePill extends StatelessWidget {
  final String code;
  final Color color;

  /// Set where the pill carries a colour it does not choose — a friend's
  /// own hull tint, say — and the default ink would not read on it.
  final Color textColor;

  const CodePill({
    super.key,
    required this.code,
    this.color = AppColors.cream,
    this.textColor = AppColors.outline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.outline, width: 2),
      ),
      child: Text(
        code.toUpperCase(),
        style: AppText.label(size: 10, color: textColor),
      ),
    );
  }
}

/// A captain as a single lettered tile.
///
/// Every player here is a name and a rank and nothing else — there are no
/// avatars to load — so the initial is what carries identity in a list.
/// Colour is derived from the name so the same captain keeps the same tile
/// everywhere they appear, without needing anything stored for it.
class CaptainAvatar extends StatelessWidget {
  final String name;
  final double size;

  /// Overrides the name-derived colour (the local player's own card uses
  /// the section's accent instead of a random-looking one).
  final Color? color;

  const CaptainAvatar({
    super.key,
    required this.name,
    this.size = 44,
    this.color,
  });

  /// The palette a tile can land on — all drawn from the game's own
  /// colours, and all dark enough for cream lettering to read on.
  static const _palette = [
    AppColors.shipRed,
    AppColors.blue,
    AppColors.seafoam,
    AppColors.ember,
    AppColors.navy,
    AppColors.waterDark,
  ];

  static Color colorFor(String name) {
    if (name.isEmpty) return _palette.first;
    var hash = 0;
    for (final unit in name.toUpperCase().codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return _palette[hash % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: cartoonBox(color ?? colorFor(trimmed), radius: size * 0.28),
      child: Text(
        initial,
        style: AppText.title(size: size * 0.5, color: AppColors.cream),
      ),
    );
  }
}

/// A short state label — OPEN, FULL, IN PROGRESS, REJOIN.
class StatusPill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;

  const StatusPill({
    super.key,
    required this.text,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppColors.outline, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: AppColors.cream),
            const SizedBox(width: 4),
          ],
          Text(text, style: AppText.label(size: 9, color: AppColors.cream)),
        ],
      ),
    );
  }
}

/// The square badge that opens a room row, carrying the row's state in
/// both its colour and its icon — colour alone would be the only thing
/// separating "open" from "full" for a colour-blind player.
class RoomBadge extends StatelessWidget {
  final Color color;
  final IconData icon;
  final double size;

  const RoomBadge({
    super.key,
    required this.color,
    required this.icon,
    this.size = 38,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: cartoonBox(color, radius: size * 0.26),
      child: Icon(icon, size: size * 0.5, color: AppColors.cream),
    );
  }
}

/// A progress bar in the game's flat-cartoon frame.
///
/// [progress] of null is indeterminate — used where there is genuinely no
/// end time to show (a search that runs until it finds someone), rather
/// than faking a bar that fills toward nothing.
class LobbyProgressBar extends StatelessWidget {
  final double? progress;
  final Color color;
  final double height;

  const LobbyProgressBar({
    super.key,
    this.progress,
    this.color = AppColors.seafoam,
    this.height = 10,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.coralLight,
        borderRadius: BorderRadius.circular(height),
        border: Border.all(color: AppColors.outline, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: LinearProgressIndicator(
        value: progress,
        backgroundColor: Colors.transparent,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}

/// A countdown the player is waiting out, shown as the number AND the bar
/// draining with it — the number says how long, the bar says how much of
/// the wait is gone without having to remember what it started at.
class CountdownBar extends StatelessWidget {
  final Duration remaining;
  final Duration total;
  final Color color;

  const CountdownBar({
    super.key,
    required this.remaining,
    required this.total,
    this.color = AppColors.seafoam,
  });

  static String format(Duration d) {
    final secs = d.inSeconds.clamp(0, 5999);
    return '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final left = remaining.inMilliseconds.clamp(0, total.inMilliseconds);
    final fraction = total.inMilliseconds == 0
        ? 0.0
        : left / total.inMilliseconds;
    // Runs red for the last quarter: the point of a countdown is that it
    // is about to matter, and that has to be visible without reading it.
    final urgent = fraction <= 0.25;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Text(
            format(remaining),
            style: AppText.title(
              size: 30,
              color: urgent ? AppColors.hit : AppColors.navy,
            ),
          ),
        ),
        const SizedBox(height: 8),
        LobbyProgressBar(
          progress: fraction,
          color: urgent ? AppColors.hit : color,
        ),
      ],
    );
  }
}

/// Who has said yes so far, as two labelled marks rather than a sentence.
///
/// A pairing needs BOTH captains, and "waiting for them" reads very
/// differently from "they are waiting for you" — which is exactly what a
/// line of prose is worst at making obvious at a glance.
class AcceptPair extends StatelessWidget {
  final bool youAccepted;
  final bool peerAccepted;
  final String peerName;

  const AcceptPair({
    super.key,
    required this.youAccepted,
    required this.peerAccepted,
    required this.peerName,
  });

  Widget _mark(String label, bool accepted) {
    return Column(
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: accepted
              ? cartoonBox(AppColors.green, radius: 22)
              : BoxDecoration(
                  color: AppColors.cream.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.inkSoft.withValues(alpha: 0.55),
                    width: 2.5,
                  ),
                ),
          child: Icon(
            accepted ? Icons.check : Icons.hourglass_empty,
            size: 22,
            color: accepted ? AppColors.cream : AppColors.inkSoft,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: AppText.label(
            size: 9.5,
            color: accepted ? AppColors.green : AppColors.inkSoft,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _mark('YOU', youAccepted),
        const SizedBox(width: 34),
        _mark(peerName.toUpperCase(), peerAccepted),
      ],
    );
  }
}

/// The section card every lobby block sits in: an accent-tinted icon, a
/// title, an optional line of explanation, then the block's own content.
class LobbyCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final String? subtitle;
  final Widget child;
  final Color fill;

  const LobbyCard({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.child,
    this.subtitle,
    this.fill = AppColors.cream,
  });

  @override
  Widget build(BuildContext context) {
    final onDark = fill == AppColors.navy || fill == AppColors.navyDark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cartoonBox(fill, radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: AppColors.outline, width: 2),
                ),
                child: Icon(icon, color: AppColors.cream, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: AppText.title(
                    size: 15,
                    color: onDark ? AppColors.cream : AppColors.navy,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              style: AppText.body(
                size: 11.5,
                color: onDark
                    ? AppColors.cream.withValues(alpha: 0.75)
                    : AppColors.inkSoft,
              ),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// The small print under a control — the rule that saves a captain a
/// failed attempt ("codes never use I, O, 0 or 1"), rather than an error
/// message after they have already typed one.
class LobbyHint extends StatelessWidget {
  final String text;
  final TextAlign align;

  const LobbyHint(this.text, {super.key, this.align = TextAlign.left});

  @override
  Widget build(BuildContext context) => Text(
        text,
        textAlign: align,
        style: AppText.label(size: 8.5, color: AppColors.inkSoft),
      );
}

/// The scanning dial: rings, a rotating sweep, and one blip per room the
/// scan has actually turned up, so the dial reports a real count rather
/// than decorating the wait.
class ScanDial extends StatelessWidget {
  final double sweep;
  final int blips;
  final double size;

  const ScanDial({
    super.key,
    required this.sweep,
    this.blips = 0,
    this.size = 74,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _ScanDialPainter(sweep: sweep, blips: blips),
      );
}

class _ScanDialPainter extends CustomPainter {
  final double sweep;
  final int blips;

  const _ScanDialPainter({required this.sweep, required this.blips});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 2;

    canvas.drawCircle(c, r, Paint()..color = AppColors.mist);

    final rings = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = AppColors.waterDark.withValues(alpha: 0.45);
    for (final f in const [0.68, 0.36]) {
      canvas.drawCircle(c, r * f, rings);
    }

    // The sweep, drawn as a wedge rather than a full-circle gradient: it
    // reads as a beam at this size, where a soft gradient just reads as a
    // smudge.
    final start = sweep * 2 * math.pi - math.pi / 2;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      start,
      0.9,
      true,
      Paint()..color = AppColors.seafoam.withValues(alpha: 0.55),
    );

    // One blip per room found, spaced around the dial. Seeded off the
    // index alone so they hold still between repaints instead of
    // scattering on every frame of the sweep.
    for (var i = 0; i < blips.clamp(0, 6); i++) {
      final a = i * 2.4 + 0.6;
      final d = r * (0.35 + 0.16 * (i % 3));
      canvas.drawCircle(
        c + Offset(math.cos(a) * d, math.sin(a) * d),
        3.4,
        Paint()..color = AppColors.shipRed,
      );
    }

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = AppColors.outline,
    );
  }

  @override
  bool shouldRepaint(_ScanDialPainter old) =>
      old.sweep != sweep || old.blips != blips;
}
