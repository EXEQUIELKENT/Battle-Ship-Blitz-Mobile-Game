// The wreck a sunk ship leaves on the board wears its owner's OWN hull.
//
// FEEDBACK ("the destroyed ships on the deck during gameplay all have the
// same design and it does not vary depending on what ship skins is
// equipped"): every sunk hull used to collapse to the one generic,
// skin-agnostic grey wreck, so a Blackpowder galleon, a Helios Drift
// catamaran and a plain Steel Fleet cruiser all died into the identical
// hulk. The grid now draws each wreck in its board owner's resolved skin —
// charred by the painter's sunk path — so the silhouette and detail of the
// fleet the player actually equipped survive the sinking.
import 'package:battleship_blitz/models/game_models.dart';
import 'package:battleship_blitz/services/storage_service.dart';
import 'package:battleship_blitz/widgets/battle_grid.dart';
import 'package:battleship_blitz/widgets/ship_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The one sunk-hull painter on the grid under test (each wreck is exactly
/// one `CustomPaint` with a sunk `ShipPainter`).
ShipPainter? _wreckPainter(WidgetTester tester) {
  final paints = tester.widgetList<CustomPaint>(
    find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is ShipPainter),
  );
  for (final p in paints) {
    final painter = p.painter! as ShipPainter;
    if (painter.sunk) return painter;
  }
  return null;
}

Widget _grid({ShipSkin? wreckSkin, String? wreckSkinId, bool vertical = false}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 450,
          height: 450,
          child: BattleGrid(
            shots: List.generate(kBoardSize, (_) => List.filled(kBoardSize, 0)),
            destroyedShips: [
              PlacedShip(
                spec: kFleet.last, // the 2-cell destroyer
                row: vertical ? 2 : 4,
                col: vertical ? 4 : 2,
                horizontal: !vertical,
              ),
            ],
            wreckShipSkinId: wreckSkinId,
            wreckShipSkin: wreckSkin,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a wreck draws in its owner’s skin, not the generic hull',
      (tester) async {
    final family = Catalog.shipById('f_pirate'); // Blackpowder Fleet
    await tester.pumpWidget(_grid(wreckSkin: family, wreckSkinId: family.id));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final painter = _wreckPainter(tester);
    expect(painter, isNotNull, reason: 'the sunk hull must be on the grid');
    expect(painter!.sunk, isTrue);
    expect(painter.skin.id, 'f_pirate',
        reason: 'the wreck must keep its owner’s hull identity — the '
            'generic grey wreck was exactly the "all the same design" bug');
  });

  testWidgets('a legacy-skin wreck draws in that legacy hull', (tester) async {
    final crimson = Catalog.shipById('crimson'); // Crimson Armada
    await tester.pumpWidget(
        _grid(wreckSkin: crimson, wreckSkinId: crimson.id));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(_wreckPainter(tester)!.skin.id, 'crimson');
  });

  testWidgets('a vertical wreck draws in its owner’s skin too', (tester) async {
    final scifi = Catalog.shipById('f_scifi'); // Helios Drift
    await tester.pumpWidget(
        _grid(wreckSkin: scifi, wreckSkinId: scifi.id, vertical: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(_wreckPainter(tester)!.skin.id, 'f_scifi');
  });

  testWidgets('without a known owner skin the wreck falls back to the '
      'generic hull', (tester) async {
    await tester.pumpWidget(_grid());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(_wreckPainter(tester)!.skin.id, 'wreck',
        reason: 'a caller that does not know the owner’s gear keeps the '
            'old skin-agnostic wreck');
  });
}
