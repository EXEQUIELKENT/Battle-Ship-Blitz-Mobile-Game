import 'package:battleship_blitz/models/game_models.dart';
import 'package:battleship_blitz/models/power_up.dart';
import 'package:battleship_blitz/services/game_controller.dart';
import 'package:battleship_blitz/services/network_service.dart';
import 'package:battleship_blitz/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<GameController> _controller() async {
  SharedPreferences.setMockInitialValues({});
  final profile = ProfileStore();
  await profile.load();
  final c = GameController(profile: profile, network: NetworkService());
  c.mode = GameMode.vsAI;
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('shotStats counts shots and hits', () {
    final grid =
        List.generate(kBoardSize, (_) => List.filled(kBoardSize, 0));
    grid[0][0] = 1;
    grid[1][1] = 2;
    grid[2][2] = 2;
    final s = GameController.shotStats(grid);
    expect(s.shots, 3);
    expect(s.hits, 2);
  });

  test('accuracy is null with no shots, else hits/shots', () async {
    final c = await _controller();
    expect(c.accuracyP1, isNull);
    c.boards[0] = Board()..place(kFleet.first, 5, 0, true);
    c.beginBattle(enemyBoard: Board()..place(kFleet.last, 0, 0, true));
    c.fireAt(0, 0); // hit on the destroyer at (0,0)
    expect(c.accuracyP1, 1.0);
    c.cooldown1 = 0;
    c.fireAt(9, 9); // miss
    expect(c.accuracyP1, 0.5);
    c.dispose();
  });

  test('usedPowerUps records cards and resets each match', () async {
    final c = await _controller();
    c.mode = GameMode.hotspot;
    c.network.setMatchHost(true);
    c.lanBattleMode = LanBattleMode.powerPlay;
    c.boards[0] = Board()..place(kFleet.first, 5, 0, true);
    c.beginBattle(enemyBoard: Board()..place(kFleet.first, 9, 5, true));
    expect(c.usedPowerUps, isEmpty);
    c.myPowerUp = PowerUpCard.doubleTap;
    expect(c.usePowerUp(), isTrue);
    expect(c.usedPowerUps, [PowerUpCard.doubleTap]);
    c.resetForRematch();
    expect(c.usedPowerUps, isEmpty);
    c.dispose();
  });
}
