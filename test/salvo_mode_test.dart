import 'package:battleship_blitz/models/game_models.dart';
import 'package:battleship_blitz/services/game_controller.dart';
import 'package:battleship_blitz/services/network_service.dart';
import 'package:battleship_blitz/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// SALVO: each turn fires one shell per surviving hull, then the guns
// pass whether the salvo hit or not.

Future<GameController> _newSalvoController({bool host = true}) async {
  SharedPreferences.setMockInitialValues({});
  final profile = ProfileStore();
  await profile.load();
  final net = NetworkService();
  net.setMatchHost(host);
  final c = GameController(profile: profile, network: net);
  c.mode = GameMode.hotspot;
  c.lanBattleMode = LanBattleMode.salvo;
  return c;
}

Board _harmlessEnemyBoard() => Board()..place(kFleet.first, 9, 5, true);

Future<void> _incomingFire(GameController c, int r, int col, int seq) async {
  c.network
      .handleIncomingForTest({'type': 'fire', 'r': r, 'c': col, 'seq': seq});
  await pumpEventQueue();
  c.landIncomingShellsForTest();
  await pumpEventQueue();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LanBattleMode.salvo — the rules it turns on', () {
    test('turn-based with records, no rearranging, no power-ups', () {
      expect(LanBattleMode.salvo.hasTurns, isTrue);
      expect(LanBattleMode.salvo.recordsShots, isTrue);
      expect(LanBattleMode.salvo.canRearrange, isFalse);
      expect(LanBattleMode.salvo.hasPowerUps, isFalse);
      expect(LanBattleMode.salvo.movesWhenDamaged, isFalse);
    });

    test('isSalvoBattle only for a protocol match voted salvo', () async {
      final c = await _newSalvoController();
      expect(c.isSalvoBattle, isTrue);
      c.lanBattleMode = LanBattleMode.turns;
      expect(c.isSalvoBattle, isFalse);
    });
  });

  group('salvo sizing', () {
    test('the opener is armed to a full fleet', () async {
      final c = await _newSalvoController(host: true);
      c.boards[0] = Board()..place(kFleet.last, 0, 0, true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      // Host opens: P1's salvo over their own (single-ship) fleet.
      expect(c.salvoLeft, 1);
    });

    test('beginSalvoTurn sizes to survivors', () async {
      final c = await _newSalvoController(host: true);
      c.boards[0] = Board()
        ..place(kFleet.first, 0, 0, true)
        ..place(kFleet.last, 9, 0, true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      expect(c.salvoLeft, 2);
      // Lose the destroyer: the next turn is a single shell.
      c.boards[0].shipOfKind(ShipKind.destroyer)!.hitIndices.addAll({0, 1});
      c.beginSalvoTurn(true);
      expect(c.salvoLeft, 1);
    });

    test('afloatCount counts live hulls per seat', () async {
      final c = await _newSalvoController(host: true);
      c.boards[0] = Board()
        ..place(kFleet.first, 0, 0, true)
        ..place(kFleet.last, 9, 0, true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      expect(c.afloatCount(true), 2);
      expect(c.afloatCount(false), 1);
    });
  });

  group('salvo spending', () {
    test('resolved shots spend the current turn, either seat', () async {
      final c = await _newSalvoController(host: true);
      c.boards[0] = Board()
        ..place(kFleet.first, 0, 0, true)
        ..place(kFleet.last, 9, 0, true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      // Opponent's turn with a 2-shell salvo over their single ship.
      c.peerHasTurn = true;
      c.beginSalvoTurn(false);
      expect(c.salvoLeft, 1);
      await _incomingFire(c, 5, 5, 0); // miss on our water
      expect(c.salvoLeft, 0);
      // A fresh turn re-arms.
      c.beginSalvoTurn(false);
      expect(c.salvoLeft, 1);
    });

    test('outside salvo nothing is spent', () async {
      final c = await _newSalvoController(host: true);
      c.lanBattleMode = LanBattleMode.turns;
      c.boards[0] = Board()..place(kFleet.last, 0, 0, true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      c.attachNetwork();
      await _incomingFire(c, 5, 5, 0);
      expect(c.salvoLeft, 0);
    });
  });
}
