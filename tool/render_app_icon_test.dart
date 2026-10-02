// Regenerates every app-icon asset in the repo from one painter.
//
// Run:  flutter test tool/render_app_icon_test.dart
//
// The design is the game itself, shrunk: the navy battle grid the player
// fights on, a top-down destroyer crossing it, and the amber "HIT" burst
// that decides every match — the exact loop of Battleship Blitz.
//
// Outputs:
//   assets/icon/app_icon.png                      1024x1024 master
//   android .../mipmap-*/ic_launcher*.png         launcher + round + foreground
//   ios .../AppIcon.appiconset/Icon-App-*.png     every entry in Contents.json
//   web/favicon.png, web/icons/*.png              favicon + PWA (maskable too)
//   windows/runner/resources/app_icon.ico         256px PNG-compressed ICO
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui show ImageByteFormat, PictureRecorder;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

enum IconVariant { full, round, foreground, maskable }

class AppIconPainter extends CustomPainter {
  AppIconPainter(this.variant);
  final IconVariant variant;

  // Pulled from the game's own palette (storage_service.dart fleet themes).
  static const _bgTop = Color(0xFF2A5480);
  static const _bgMid = Color(0xFF123252);
  static const _bgDeep = Color(0xFF0A1A2E);
  static const _grid = Color(0xFFCFE0EA);
  static const _foam = Color(0xFFE6F0F7);
  static const _hull = Color(0xFF1B2B3D);
  static const _deck = Color(0xFF94A3B8);
  static const _turret = Color(0xFF4A789A); // the 'mk1' naval blue
  static const _structure = Color(0xFF33475E);
  static const _burstOuter = Color(0xFFFF7A2E);
  static const _burstMid = Color(0xFFFFB84D);
  static const _burstCore = Color(0xFFFFE9C8);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    if (variant == IconVariant.round) {
      canvas.clipPath(Path()..addOval(Offset.zero & Size(s, s)));
    }
    if (variant != IconVariant.foreground) _paintBackground(canvas, s);

    // Adaptive-icon foregrounds sit in a transparent 108dp canvas whose
    // content must survive the circular 72dp mask; maskable PWA icons keep
    // content inside the outer 10% on every side.
    final contentScale = switch (variant) {
      IconVariant.foreground => 0.60,
      IconVariant.maskable => 0.80,
      _ => 1.0,
    };
    canvas.save();
    canvas.translate(s / 2, s / 2);
    canvas.scale(contentScale, contentScale);
    canvas.translate(-s / 2, -s / 2);
    _paintShip(canvas, s);
    _paintBurst(canvas, s);
    canvas.restore();
  }

  void _paintBackground(Canvas canvas, double s) {
    final rect = Offset.zero & Size(s, s);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: [_bgTop, _bgMid, _bgDeep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(rect),
    );
    // A soft glow behind the ship, top-left, so the gradient is not flat.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.45, -0.45),
          radius: 1.0,
          colors: [Color(0x26FFFFFF), Color(0x00FFFFFF)],
        ).createShader(rect),
    );

    // The 10x10 battle grid, ghosted under everything.
    final gridPaint = Paint()
      ..color = _grid.withValues(alpha: 0.13)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.0024;
    for (var i = 1; i < 10; i++) {
      final p = i * s / 10;
      canvas.drawLine(Offset(p, 0), Offset(p, s), gridPaint);
      canvas.drawLine(Offset(0, p), Offset(s, p), gridPaint);
    }
  }

  /// Top-down destroyer, bow pointing up-right. Drawn around (0,0) in ship
  /// space after the caller has translated/rotated.
  void _paintShip(Canvas canvas, double s) {
    canvas.save();
    canvas.translate(s * 0.50, s * 0.52);
    canvas.rotate(0.34);

    final hull = _hullPath(s);

    // Soft drop shadow for lift off the grid.
    canvas.save();
    canvas.translate(s * 0.006, s * 0.010);
    canvas.drawPath(
      hull,
      Paint()
        ..color = const Color(0x59000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.restore();

    canvas.drawPath(hull, Paint()..color = _hull);
    // Deck rim: the hull silhouette traced in the slate accent.
    canvas.drawPath(
      hull,
      Paint()
        ..color = _deck.withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.006,
    );

    // Superstructure + bridge.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(0, s * 0.035), width: s * 0.085, height: s * 0.135),
        Radius.circular(s * 0.016),
      ),
      Paint()..color = _structure,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(0, -s * 0.080), width: s * 0.052, height: s * 0.055),
        Radius.circular(s * 0.010),
      ),
      Paint()..color = _structure,
    );
    // Funnel dot.
    canvas.drawCircle(Offset(0, s * 0.125), s * 0.016,
        Paint()..color = _bgDeep.withValues(alpha: 0.9));

    // Bow + stern turrets in the mk1 naval blue.
    canvas.drawCircle(
        Offset(0, -s * 0.170), s * 0.024, Paint()..color = _turret);
    canvas.drawCircle(
        Offset(0, s * 0.205), s * 0.024, Paint()..color = _turret);

    canvas.restore();
  }

  Path _hullPath(double s) {
    final w = s * 0.068; // half beam
    final bowY = -s * 0.31;
    final deckY = -s * 0.12;
    final sternY = s * 0.24;
    final sternBotY = s * 0.30;
    return Path()
      ..moveTo(0, bowY)
      ..quadraticBezierTo(w * 0.95, bowY + s * 0.09, w, deckY)
      ..lineTo(w, sternY)
      ..quadraticBezierTo(w, sternBotY, w * 0.55, sternBotY)
      ..lineTo(-w * 0.55, sternBotY)
      ..quadraticBezierTo(-w, sternBotY, -w, sternY)
      ..lineTo(-w, deckY)
      ..quadraticBezierTo(-w * 0.95, bowY + s * 0.09, 0, bowY)
      ..close();
  }

  /// The amber HIT burst — placed on the bow turret, where a shell lands.
  void _paintBurst(Canvas canvas, double s) {
    // World position of the ship-local bow turret (0, -0.170s) after the
    // ship's translate (0.50, 0.52) and rotate(0.34).
    const a = 0.34;
    const lx = 0.0, ly = -0.170;
    final px = s * 0.50 + (lx * math.cos(a) - ly * math.sin(a)) * s;
    final py = s * 0.52 + (lx * math.sin(a) + ly * math.cos(a)) * s;
    final c = Offset(px, py);

    canvas.drawCircle(
        c, s * 0.105, Paint()..color = _burstOuter.withValues(alpha: 0.30));
    canvas.drawCircle(
        c,
        s * 0.115,
        Paint()
          ..color = _foam.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.008);
    canvas.drawPath(
        _starPath(c, s * 0.085, s * 0.034), Paint()..color = _burstMid);
    canvas.drawCircle(c, s * 0.030, Paint()..color = _burstCore);

    // Foam spray dots kicked up around the impact.
    for (var i = 0; i < 6; i++) {
      final angle = i * math.pi / 3 + 0.4;
      canvas.drawCircle(
        c + Offset(math.cos(angle), math.sin(angle)) * s * 0.145,
        s * 0.009,
        Paint()..color = _foam.withValues(alpha: 0.85),
      );
    }
  }

  Path _starPath(Offset c, double outer, double inner) {
    final path = Path();
    const spikes = 10;
    for (var i = 0; i < spikes * 2; i++) {
      final r = i.isEven ? outer : inner;
      final t = (i * math.pi) / spikes - math.pi / 2;
      final p = c + Offset(math.cos(t), math.sin(t)) * r;
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    return path..close();
  }

  @override
  bool shouldRepaint(covariant AppIconPainter oldDelegate) =>
      oldDelegate.variant != variant;
}

/// A single 256x256 PNG-compressed icon wrapped in a minimal Vista-style
/// .ico container (what the Windows runner template expects).
void writeIco(Uint8List png256, String path) {
  final b = BytesBuilder();
  b.add(Uint8List.fromList([0, 0, 1, 0, 1, 0])); // reserved, type, count
  b.add(Uint8List.fromList(
      [0, 0, 0, 0, 1, 0, 32, 0])); // w, h, colors, rsvd, planes, bpp
  final size = ByteData(4)..setUint32(0, png256.length, Endian.little);
  b.add(size.buffer.asUint8List());
  b.add(Uint8List.fromList([22, 0, 0, 0])); // data offset
  b.add(png256);
  File(path).writeAsBytesSync(b.takeBytes());
}

void main() {
  testWidgets('render every app-icon asset', (tester) async {
    Future<void> renderAndWrite(
        AppIconPainter painter, double px, String path) async {
      // Paint straight into a picture recorder — no widget tree, so the
      // output is exactly px x px and nothing can leak the test surface in.
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder, Rect.fromLTWH(0, 0, px, px)),
          Size.square(px));
      final picture = recorder.endRecording();
      final image = (await tester
              .runAsync(() => picture.toImage(px.round(), px.round())))!;
      final bytes = (await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.png)))!;
      File(path)
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes.buffer.asUint8List());
      image.dispose();
    }

    const root = 'c:/xampp/htdocs/Battle-Ship-Blitz-Mobile-Game';
    const androidDpis = <String, double>{
      'mdpi': 1.0,
      'hdpi': 1.5,
      'xhdpi': 2.0,
      'xxhdpi': 3.0,
      'xxxhdpi': 4.0,
    };
    final jobs = <(String, double, IconVariant)>[
      // Master.
      ('$root/assets/icon/app_icon.png', 1024, IconVariant.full),
      // Android launcher icons (48dp) + round + adaptive foreground (108dp).
      for (final dpi in androidDpis.entries) ...[
        ('$root/android/app/src/main/res/mipmap-${dpi.key}/ic_launcher.png',
            48 * dpi.value, IconVariant.full),
        ('$root/android/app/src/main/res/mipmap-${dpi.key}/ic_launcher_round.png',
            48 * dpi.value, IconVariant.round),
        (
          '$root/android/app/src/main/res/mipmap-${dpi.key}/ic_launcher_foreground.png',
          108 * dpi.value,
          IconVariant.foreground
        ),
      ],
      // iOS appiconset — mirrors the existing Contents.json exactly.
      for (final e in const <String, double>{
        'Icon-App-20x20@1x.png': 20.0,
        'Icon-App-20x20@2x.png': 40.0,
        'Icon-App-20x20@3x.png': 60.0,
        'Icon-App-29x29@1x.png': 29.0,
        'Icon-App-29x29@2x.png': 58.0,
        'Icon-App-29x29@3x.png': 87.0,
        'Icon-App-40x40@1x.png': 40.0,
        'Icon-App-40x40@2x.png': 80.0,
        'Icon-App-40x40@3x.png': 120.0,
        'Icon-App-60x60@2x.png': 120.0,
        'Icon-App-60x60@3x.png': 180.0,
        'Icon-App-76x76@1x.png': 76.0,
        'Icon-App-76x76@2x.png': 152.0,
        'Icon-App-83.5x83.5@2x.png': 167.0,
        'Icon-App-1024x1024@1x.png': 1024.0,
      }.entries)
        ('$root/ios/Runner/Assets.xcassets/AppIcon.appiconset/${e.key}',
            e.value, IconVariant.full),
      // Web favicon + PWA icons (the maskable ones were missing entirely).
      ('$root/web/favicon.png', 16, IconVariant.full),
      ('$root/web/icons/Icon-192.png', 192, IconVariant.full),
      ('$root/web/icons/Icon-512.png', 512, IconVariant.full),
      ('$root/web/icons/Icon-maskable-192.png', 192, IconVariant.maskable),
      ('$root/web/icons/Icon-maskable-512.png', 512, IconVariant.maskable),
    ];

    for (final (path, px, variant) in jobs) {
      await renderAndWrite(AppIconPainter(variant), px, path);
    }

    // Explicit 256px render for the Windows .ico.
    final recorder = ui.PictureRecorder();
    AppIconPainter(IconVariant.full).paint(
        Canvas(recorder, Rect.fromLTWH(0, 0, 256, 256)),
        const Size.square(256));
    final picture = recorder.endRecording();
    final image = (await tester.runAsync(() => picture.toImage(256, 256)))!;
    final bytes = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.png)))!;
    writeIco(bytes.buffer.asUint8List(),
        '$root/windows/runner/resources/app_icon.ico');
    image.dispose();
  });
}
