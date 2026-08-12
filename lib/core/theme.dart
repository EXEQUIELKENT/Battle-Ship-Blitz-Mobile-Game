import 'package:flutter/material.dart';

/// Flat-cartoon theme inspired by the reference UI:
/// coral/salmon deck, navy header, chunky blue water grid,
/// flat red ships with bold black outlines.
class AppColors {
  AppColors._();

  // Deck & structure
  static const Color coral = Color(0xFFF5A28C); // main deck background
  static const Color coralLight = Color(0xFFFDB9A4);
  static const Color coralDeep = Color(0xFFED8F77);
  static const Color navy = Color(0xFF3D5468); // header / panels
  static const Color navyDark = Color(0xFF2E4152);
  static const Color navyDeep = Color(0xFF243646);

  // Water grid
  static const Color water = Color(0xFF4E9CC4);
  static const Color waterLight = Color(0xFF6FB3D4);
  static const Color waterDark = Color(0xFF3D86AC);
  static const Color gridLine = Color(0xFF3D5468);
  static const Color cellBorder = Color(0xFF3A7FA6);

  // Flat ships
  static const Color shipRed = Color(0xFFF25F5C);
  static const Color shipRedDark = Color(0xFFD64545);
  static const Color shipBlue = Color(0xFF35A3D6);
  static const Color shipBlueDark = Color(0xFF2489B8);
  static const Color outline = Color(0xFF1E2A36);

  // Combat feedback
  static const Color hit = Color(0xFFE63946);
  static const Color hitGlow = Color(0xFFFF8FA3);
  static const Color miss = Color(0xFF8FB3C7);
  static const Color crosshair = Color(0xFFFFFFFF);

  // UI accents
  static const Color green = Color(0xFF3CB54A); // SAVE button
  static const Color greenDark = Color(0xFF2E9E3C);
  static const Color blue = Color(0xFF2E8BC0); // RANDOM button
  static const Color blueDark = Color(0xFF24719E);
  static const Color gold = Color(0xFFF7B32B);
  static const Color cream = Color(0xFFFFF4EC);
  static const Color inkSoft = Color(0xFF43566B);

  // ---- Legacy aliases (old neon palette → new cartoon palette) ----
  static const Color abyss = navyDeep;
  static const Color deepSea = navyDark;
  static const Color ink = navyDark;
  static const Color sonar = blue;
  static const Color sonarDim = blueDark;
  static const Color radar = Color(0xFFBEE3F8);
  static const Color ember = Color(0xFFF77F3F);
  static const Color fire = hit;
  static const Color danger = hit;
  static const Color victory = green;
  static const Color steel = Color(0xFF7C93A8);
  static const Color fog = Color(0xFF9DB4C6);
  static const Color mist = Color(0xFFD9E8F2);
  static const Color hitRed = hit;
}

class AppText {
  AppText._();

  static TextStyle title({double size = 28, Color color = AppColors.cream}) =>
      TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.5,
        height: 1.05,
        color: color,
      );

  static TextStyle heading({double size = 18, Color color = AppColors.cream}) =>
      TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.4,
        color: color,
      );

  static TextStyle body({double size = 14, Color color = AppColors.cream}) =>
      TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w600,
        color: color,
      );

  static TextStyle label({double size = 11, Color color = AppColors.cream}) =>
      TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
        color: color,
      );
}

/// Chunky cartoon button shape shared across the app.
BoxDecoration cartoonBox(Color fill, {double radius = 14, Color? border}) =>
    BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border ?? AppColors.outline, width: 3),
      boxShadow: const [
        BoxShadow(
          color: Color(0x55000000),
          offset: Offset(0, 4),
          blurRadius: 0,
        ),
      ],
    );
