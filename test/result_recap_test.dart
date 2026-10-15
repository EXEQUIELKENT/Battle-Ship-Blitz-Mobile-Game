import 'package:battleship_blitz/models/game_models.dart';
import 'package:battleship_blitz/screens/result_screen.dart';
import 'package:battleship_blitz/services/game_controller.dart';
import 'package:battleship_blitz/services/network_service.dart';
import 'package:battleship_blitz/services/storage_service.dart';
import 'package:battleship_blitz/widgets/battle_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('match stats recap replays the real fleets', (tester) async {
    final profile = ProfileStore();
    final network = NetworkService();
    final controller = GameController(profile: profile, network: network);

    // A finished rose-on-rose match: blush hulls under rose fire on
    // rosé waters, one destroyer sunk, a hit and a miss recorded.
    controller.boards[1]
      ..place(kFleet[0], 0, 0, true)
      ..place(kFleet[4], 8, 0, true);
    controller.boards[1].ships[1].hitIndices.addAll([0, 1]);
    controller.myShots[8][0] = 2;
    controller.myShots[8][1] = 2;
    controller.myShots[1][1] = 1;
    controller.resultLoadouts = const [
      Loadout(
          shipSkinId: 'steel',
          cannonSkinId: 'rose',
          themeId: 'rose',
          shipChosen: true),
      Loadout(
          shipSkinId: 'blush',
          cannonSkinId: 'rose',
          themeId: 'rose',
          shipChosen: true),
    ];

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: profile),
        ChangeNotifierProvider.value(value: network),
        ChangeNotifierProvider.value(value: controller),
      ],
      child: const MaterialApp(home: ResultScreen()),
    ));
    // Staged reveal (1400ms) plus the wreck animation — stepped, never
    // settled, since the victory confetti loops forever.
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 800));

    // One recap grid, wearing the match's own gear: blush hulls, the
    // rosé-waters deck and rosé-cannon marks — not generic boxes.
    expect(find.byType(BattleGrid), findsOneWidget);
    final grid = tester.widget<BattleGrid>(find.byType(BattleGrid));
    expect(grid.skin?.id, 'blush');
    expect(grid.legacyBoardId, 'rose');
    expect(grid.cannonSkinId, 'rose');
    expect(grid.ships?.length, 2);
    expect(grid.destroyedShips?.length, 1);
  });
}
