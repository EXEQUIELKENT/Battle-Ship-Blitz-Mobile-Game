import 'package:flutter_test/flutter_test.dart';
import 'package:battleship_blitz/models/game_models.dart';

void main() {
  group('Board', () {
    test('random board places all 5 ships without overlap', () {
      final board = Board.random();
      expect(board.ships.length, kFleet.length);

      final occupied = <String>{};
      for (final ship in board.ships) {
        for (final cell in ship.cells) {
          final key = '${cell[0]},${cell[1]}';
          expect(occupied.contains(key), isFalse,
              reason: 'overlap at $key');
          occupied.add(key);
          expect(cell[0], inInclusiveRange(0, kBoardSize - 1));
          expect(cell[1], inInclusiveRange(0, kBoardSize - 1));
        }
      }
      expect(occupied.length, 17); // 5+4+3+3+2
    });

    test('receiveShot detects hit, miss, duplicate and sunk', () {
      final board = Board();
      board.place(kFleet.last, 0, 0, true); // destroyer size 2 at (0,0)-(0,1)

      expect(board.receiveShot(5, 5).$1, ShotResult.miss);
      expect(board.receiveShot(5, 5).$1, ShotResult.duplicate);
      expect(board.receiveShot(0, 0).$1, ShotResult.hit);
      final (result, sunk) = board.receiveShot(0, 1);
      expect(result, ShotResult.sunk);
      expect(sunk, isNotNull);
      expect(board.shipOfKind(ShipKind.destroyer)!.isSunk, isTrue);
    });

    test('canPlace respects boundaries', () {
      final board = Board();
      expect(board.canPlace(kFleet.first, 0, 6, true), isFalse); // carrier off-grid
      expect(board.canPlace(kFleet.first, 0, 5, true), isTrue);
      expect(board.canPlace(kFleet.first, 6, 0, false), isFalse);
    });
  });

  group('Fleet', () {
    test('has exactly five classic ships', () {
      expect(kFleet.length, 5);
      expect(kFleet.map((s) => s.size).toList(), [5, 4, 3, 3, 2]);
    });
  });
}
