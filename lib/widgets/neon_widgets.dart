import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/sound_service.dart';

/// Glowing neon button with press animation.
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
    this.color = AppColors.sonar,
    this.compact = false,
  });

  @override
  State<NeonButton> createState() => _NeonButtonState();
}

class _NeonButtonState extends State<NeonButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween(begin: 1.0, end: 0.94).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return GestureDetector(
      onTapDown: enabled ? (_) => _ctrl.forward() : null,
      onTapUp: enabled
          ? (_) {
              _ctrl.reverse();
              SoundService.instance.click();
              widget.onPressed!();
            }
          : null,
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: enabled ? 1 : 0.45,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 16 : 26,
              vertical: widget.compact ? 10 : 15,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  widget.color.withValues(alpha: 0.22),
                  widget.color.withValues(alpha: 0.08),
                ],
              ),
              border: Border.all(color: widget.color, width: 1.6),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.35),
                  blurRadius: 16,
                  spreadRadius: -2,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, color: widget.color, size: widget.compact ? 16 : 20),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    widget.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: widget.compact ? 12 : 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.8,
                      color: widget.color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small HUD chip (timer, RP, streak).
class HudChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final bool pulse;

  const HudChip({
    super.key,
    required this.icon,
    required this.text,
    this.color = AppColors.sonar,
    this.pulse = false,
  });

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.ink.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.7), width: 1.2),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 10),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
              letterSpacing: 1,
              color: color,
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
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.65, end: 1.0).animate(_ctrl),
      child: widget.child,
    );
  }
}
