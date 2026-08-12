import 'package:flutter/material.dart';

/// Central color palette for the "Abyss Protocol" dark-naval theme.
class AppColors {
  AppColors._();

  // Ocean depths
  static const Color abyss = Color(0xFF03121F);
  static const Color deepSea = Color(0xFF06263E);
  static const Color oceanMid = Color(0xFF0A3D5C);
  static const Color wave = Color(0xFF12567E);

  // Neon accents
  static const Color sonar = Color(0xFF22D3EE);
  static const Color sonarDim = Color(0xFF0E7490);
  static const Color radar = Color(0xFF67E8F9);

  // Combat
  static const Color fire = Color(0xFFFF6B35);
  static const Color ember = Color(0xFFFFB454);
  static const Color danger = Color(0xFFEF4444);
  static const Color hitRed = Color(0xFFE11D48);

  // Neutral
  static const Color steel = Color(0xFF94A3B8);
  static const Color fog = Color(0xFF64748B);
  static const Color mist = Color(0xFFCBD5E1);
  static const Color ink = Color(0xFF0B1724);

  // Success / reward
  static const Color gold = Color(0xFFFBBF24);
  static const Color victory = Color(0xFF34D399);

  static const List<Color> oceanGradient = [deepSea, abyss];
}

class AppText {
  AppText._();

  static const String fontFamily = 'monospace';

  static TextStyle title({double size = 28, Color color = AppColors.radar}) =>
      TextStyle(
        fontFamily: fontFamily,
        fontSize: size,
        fontWeight: FontWeight.w900,
        letterSpacing: 3,
        color: color,
        shadows: [
          Shadow(color: color.withValues(alpha: 0.6), blurRadius: 18),
          Shadow(color: color.withValues(alpha: 0.3), blurRadius: 40),
        ],
      );

  static TextStyle heading({double size = 18, Color color = Colors.white}) =>
      TextStyle(
        fontFamily: fontFamily,
        fontSize: size,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.6,
        color: color,
      );

  static TextStyle body({double size = 14, Color color = AppColors.mist}) =>
      TextStyle(
        fontFamily: fontFamily,
        fontSize: size,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.6,
        color: color,
      );

  static TextStyle label({double size = 11, Color color = AppColors.steel}) =>
      TextStyle(
        fontFamily: fontFamily,
        fontSize: size,
        fontWeight: FontWeight.w700,
        letterSpacing: 2,
        color: color,
      );
}
