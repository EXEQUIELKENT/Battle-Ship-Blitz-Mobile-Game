import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/sound_service.dart';

/// Chunky flat-cartoon button with hard drop shadow and press squash.
/// (Kept under the legacy name NeonButton so call sites stay the same.)
class NeonButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color color;
  final bool compact;

  const NeonButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.color = AppColors.blue,
    this.compact = false,
  });

  @override
  State<NeonButton> createState() => _NeonButtonState();
}

class _NeonButtonState extends State<NeonButton> {
  bool _pressed = false;

  Color _shade(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness * 0.82).clamp(0.0, 1.0)).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTap: enabled
          ? () {
              setState(() => _pressed = false);
              SoundService.instance.click();
              widget.onPressed!();
            }
          : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        transform: Matrix4.translationValues(0, _pressed ? 3 : 0, 0),
        padding: EdgeInsets.symmetric(
          horizontal: widget.compact ? 14 : 22,
          vertical: widget.compact ? 10 : 15,
        ),
        decoration: BoxDecoration(
          color: enabled ? widget.color : AppColors.miss,
          borderRadius: BorderRadius.circular(widget.compact ? 12 : 14),
          border: Border.all(color: AppColors.outline, width: 3),
          boxShadow: [
            BoxShadow(
              color: enabled ? _shade(widget.color) : AppColors.inkSoft,
              offset: Offset(0, _pressed ? 1 : 4),
              blurRadius: 0,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.icon != null) ...[
              Icon(widget.icon,
                  color: AppColors.cream, size: widget.compact ? 17 : 21),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                widget.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: widget.compact ? 12 : 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                  color: AppColors.cream,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small rounded HUD chip (timer, RP, streak).
class HudChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final bool pulse;

  const HudChip({
    super.key,
    required this.icon,
    required this.text,
    this.color = AppColors.navy,
    this.pulse = false,
  });

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outline, width: 2.5),
        boxShadow: const [
          BoxShadow(color: Color(0x44000000), offset: Offset(0, 3), blurRadius: 0),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.cream, size: 15),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12.5,
                letterSpacing: 0.5,
                color: AppColors.cream,
              ),
            ),
          ),
        ],
      ),
    );
    if (!pulse) return chip;
    return _Pulsing(child: chip);
  }
}

class _Pulsing extends StatefulWidget {
  final Widget child;
  const _Pulsing({required this.child});

  @override
  State<_Pulsing> createState() => _PulsingState();
}

class _PulsingState extends State<_Pulsing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween(begin: 0.97, end: 1.04).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
      ),
      child: widget.child,
    );
  }
}
