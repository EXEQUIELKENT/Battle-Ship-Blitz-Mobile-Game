import 'dart:io';
import 'dart:ui' as ui;

import 'package:battleship_blitz/art/legacy_ship_art.dart';
import 'package:battleship_blitz/models/game_models.dart';
import 'package:battleship_blitz/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dump hulls for silhouette comparison', () async {
    const w = 600.0, h = 200.0;
    const wi = 600, hi = 200;
    Future<void> dump(String skinId, ShipKind kind) async {
      final skin = Catalog.shipById(skinId);
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      canvas.drawRect(const Rect.fromLTWH(0, 0, w, h),
          Paint()..color = const Color(0xFF1A2E4A));
      paintLegacyShip(canvas, const Size(w, h), skin, kind);
      final img = await rec.endRecording().toImage(wi, hi);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      await File(
              'C:/Users/Kent/AppData/Local/Temp/opencode/hull_${skinId}_${kind.name}.png')
          .writeAsBytes(data!.buffer.asUint8List());
    }

    for (final s in Catalog.shipSkins.where((s) => s.familyKey == null)) {
      for (final k in ShipKind.values) {
        await dump(s.id, k);
      }
    }
  });
}
