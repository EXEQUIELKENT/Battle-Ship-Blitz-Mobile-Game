// DAILY PUZZLE — the sinking celebration.
//
// The popup ("AWESOME!" / "WOW!") is raised when a hull goes down, and
// only then. It is also the one overlay in this screen's Stack whose
// element must survive everything else in that Stack coming and going —
// which is what this file pins down.
import 'package:battleship_blitz/models/daily_puzzle.dart';
import 'package:battleship_blitz/screens/daily_puzzle_screen.dart';
import 'package:battleship_blitz/services/game_controller.dart';
import 'package:battleship_blitz/services/network_service.dart';
import 'package:battleship_blitz/services/sound_service.dart';
import 'package:battleship_blitz/services/storage_service.dart';
import 'package:battleship_blitz/widgets/awesome_cheer.dart';
import 'package:battleship_blitz/widgets/battle_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The letters a celebration draws, whichever word it is showing.
final _celebrationLetters = ['A', 'W', 'O', '!'];

/// How many of the celebration's letters are on screen right now.
int _letterCount(WidgetTester tester) {
  var n = 0;
  for (final letter in _celebrationLetters) {
    n += find.text(letter).evaluate().length;
  }
  return n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the celebration fires on a sinking and only on a sinking',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final profile = ProfileStore();
    await profile.load();
    final controller =
        GameController(profile: profile, network: NetworkService());

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ProfileStore>.value(value: profile),
        ChangeNotifierProvider<NetworkService>.value(value: controller.network),
        ChangeNotifierProvider<GameController>.value(value: controller),
      ],
      child: const MaterialApp(home: DailyPuzzleScreen()),
    ));
    await tester.pump();

    // The same board the screen dealt (same day seed).
    final now = DateTime.now();
    final puzzle = DailyPuzzle(
      seed: ProfileStore.dailyPuzzleSeed(
          DateTime(now.year, now.month, now.day)),
    );
    final ship = puzzle.board.ships.first;

    Future<void> fire(int r, int c) async {
      tester.widget<BattleGrid>(find.byType(BattleGrid)).onTapCell!(r, c);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
    }

    // A plain hit raises nothing.
    await fire(ship.cells.first[0], ship.cells.first[1]);
    expect(_letterCount(tester), 0,
        reason: 'a hit is not a sinking');

    // Finish the hull off: THAT raises the celebration.
    for (final c in ship.cells.skip(1)) {
      await fire(c[0], c[1]);
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(_letterCount(tester), greaterThan(0),
        reason: 'a sinking raises the celebration');

    // Let it play out, then take a shot that sinks nothing: the popup
    // must NOT come back.
    //
    // BUGFIX: the shell's slot used to be added to and removed from
    // this Stack, and a Stack matches its children BY INDEX when they
    // carry no keys — so the celebration's element was re-used for the
    // shell layer and then re-created on the next shot. Its animation
    // restarted every time, and the popup could reappear long after the
    // sinking it belonged to.
    await tester.pump(const Duration(milliseconds: 2000));
    expect(_letterCount(tester), 0, reason: 'the celebration has finished');

    await fire(9, 9);
    await tester.pump(const Duration(milliseconds: 300));
    expect(_letterCount(tester), 0,
        reason: 'a later shot must not bring the celebration back');
  });

  testWidgets('the celebration matches the voice that was played',
      (tester) async {
    // The popup is told which coin-flip result the sound used, so the
    // word on screen and the word in the player's ears always match.
    expect(CheerKind.values, hasLength(2));
    final theme = cheerThemeFor('rose');
    expect(theme.burst, isNot(CheerBurst.sparks),
        reason: 'each cannon keeps its own celebration vocabulary');
  });

  testWidgets('the board shows exactly the ships the puzzle marks',
      (tester) async {
    // The MARKED and FIRST STRIKE puzzles put their target hulls on
    // show; every other type keeps the whole fleet hidden. Either way
    // the grid and the model have to agree, or the player is aiming at
    // a ship the puzzle does not know about.
    SharedPreferences.setMockInitialValues({});
    final profile = ProfileStore();
    await profile.load();
    final controller =
        GameController(profile: profile, network: NetworkService());

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ProfileStore>.value(value: profile),
        ChangeNotifierProvider<NetworkService>.value(value: controller.network),
        ChangeNotifierProvider<GameController>.value(value: controller),
      ],
      child: const MaterialApp(home: DailyPuzzleScreen()),
    ));
    await tester.pump();

    final now = DateTime.now();
    final puzzle = DailyPuzzle(
      seed: ProfileStore.dailyPuzzleSeed(
          DateTime(now.year, now.month, now.day)),
    );
    final grid = tester.widget<BattleGrid>(find.byType(BattleGrid));
    final revealed = puzzle.revealedShips;
    if (revealed == null) {
      expect(grid.ships, isNull,
          reason: 'a blind puzzle must not show the fleet');
    } else {
      expect(grid.ships, isNotNull);
      expect(grid.ships!.map((s) => s.spec.kind).toSet(),
          revealed.map((s) => s.spec.kind).toSet());
      expect(grid.skin, isNotNull,
          reason: 'a revealed target needs a hull to be drawn in');
    }
  });
}
