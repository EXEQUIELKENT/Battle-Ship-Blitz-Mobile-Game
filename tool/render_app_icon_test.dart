// Regenerates every app-icon asset in the repo from the ONE canonical
// painter (lib/art/app_icon_art.dart — top-down steel battleship over open
// water; no foreground glow halo).
//
// Run:  flutter test tool/render_app_icon_test.dart
//
// Outputs:
//   assets/icon/app_icon.png                      1024x1024 master
//   android .../mipmap-*/ic_launcher*.png         launcher + round + foreground
//   ios .../AppIcon.appiconset/Icon-App-*.png     every entry in Contents.json
//   macos .../AppIcon.appiconset/app_icon_*.png   every entry in Contents.json
//   web/favicon.png, web/icons/*.png              favicon + PWA (maskable too)
//   windows/runner/resources/app_icon.ico         256px PNG-compressed ICO
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui show ImageByteFormat, PictureRecorder;

import 'package:battleship_blitz/art/app_icon_art.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

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
        AppIconVariant variant, double px, String path) async {
      // Paint straight into a picture recorder — no widget tree, so the
      // output is exactly px x px and nothing can leak the test surface in.
      final recorder = ui.PictureRecorder();
      AppIconPainter(variant: variant)
          .paint(Canvas(recorder, Rect.fromLTWH(0, 0, px, px)),
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
    final jobs = <(String, double, AppIconVariant)>[
      // Master.
      ('$root/assets/icon/app_icon.png', 1024, AppIconVariant.full),
      // Android launcher icons (48dp) + round + adaptive foreground (108dp).
      for (final dpi in androidDpis.entries) ...[
        ('$root/android/app/src/main/res/mipmap-${dpi.key}/ic_launcher.png',
            48 * dpi.value, AppIconVariant.full),
        ('$root/android/app/src/main/res/mipmap-${dpi.key}/ic_launcher_round.png',
            48 * dpi.value, AppIconVariant.round),
        (
          '$root/android/app/src/main/res/mipmap-${dpi.key}/ic_launcher_foreground.png',
          108 * dpi.value,
          AppIconVariant.foreground
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
            e.value, AppIconVariant.full),
      // macOS appiconset — mirrors the existing Contents.json exactly.
      for (final e in const <String, double>{
        'app_icon_16.png': 16.0,
        'app_icon_32.png': 32.0,
        'app_icon_64.png': 64.0,
        'app_icon_128.png': 128.0,
        'app_icon_256.png': 256.0,
        'app_icon_512.png': 512.0,
        'app_icon_1024.png': 1024.0,
      }.entries)
        ('$root/macos/Runner/Assets.xcassets/AppIcon.appiconset/${e.key}',
            e.value, AppIconVariant.full),
      // Web favicon + PWA icons (the maskable ones were missing entirely).
      ('$root/web/favicon.png', 16, AppIconVariant.full),
      ('$root/web/icons/Icon-192.png', 192, AppIconVariant.full),
      ('$root/web/icons/Icon-512.png', 512, AppIconVariant.full),
      ('$root/web/icons/Icon-maskable-192.png', 192, AppIconVariant.maskable),
      ('$root/web/icons/Icon-maskable-512.png', 512, AppIconVariant.maskable),
    ];

    for (final (path, px, variant) in jobs) {
      await renderAndWrite(variant, px, path);
    }

    // Explicit 256px render for the Windows .ico.
    final recorder = ui.PictureRecorder();
    const AppIconPainter(variant: AppIconVariant.full)
        .paint(Canvas(recorder, Rect.fromLTWH(0, 0, 256, 256)),
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
