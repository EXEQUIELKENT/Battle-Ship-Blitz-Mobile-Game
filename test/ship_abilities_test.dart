import 'package:battleship_blitz/models/game_models.dart';
import 'package:battleship_blitz/services/game_controller.dart';
import 'package:battleship_blitz/services/network_service.dart';
import 'package:battleship_blitz/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// One identity per hull, all passive in the model: destroyer Agile,
// submarine Elusive, cruiser Pickets.

Future<GameController> _controller(GameMode mode) async {
  SharedPreferences.setMockInitialValues({});
  final profile = ProfileStore();
  await profile.load();
  final c = GameController(profile: profile, network: NetworkService());
  c.mode = mode;
  return c;
}

Board _enemyWith(ShipSpec spec, int r, int c) =>
    Board()..place(spec, r, c, true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SUBMARINE — Elusive (model)', () {
    test('a damaged sub keeps running until it sinks', () {
      final b = Board()..place(kFleet[3], 0, 0, true); // sub, 3 cells
      b.receiveShot(0, 0);
      b.receiveShot(0, 1);
      final sub = b.shipOfKind(ShipKind.submarine)!;
      expect(sub.hitIndices.length, 2);
      expect(sub.isSunk, isFalse);
      expect(b.canRelocate(sub), isTrue);
      expect(b.relocate(ShipKind.submarine, 5, 5, true), isTrue);
      // ...but a wreck never moves.
      b.receiveShot(5, 5);
      b.receiveShot(5, 6);
      b.receiveShot(5, 7);
      expect(b.shipOfKind(ShipKind.submarine)!.isSunk, isTrue);
      expect(
          b.canRelocate(b.shipOfKind(ShipKind.submarine)!,
              ignoreDamage: true),
          isFalse);
    });

    test('hits on a sub resolve as ordinary damage', () {
      // No hit-to-miss conversion anywhere: a dodge-by-absence (moving
      // out from under a shell) is the only way a shot goes unanswered,
      // so a marked cell always means what it says and nothing can
      // become unsinkable.
      final b = Board()..place(kFleet[3], 0, 0, true);
      expect(b.receiveShot(0, 0).$1, ShotResult.hit);
      expect(b.receiveShot(0, 0).$1, ShotResult.duplicate);
      expect(b.receiveShot(0, 1).$1, ShotResult.hit);
      expect(b.receiveShot(0, 2).$1, ShotResult.sunk);
    });
  });

  group('DESTROYER — Agile (model)', () {
    test('one hit still runs, two hits pin', () {
      final b = Board()..place(kFleet[4], 0, 0, true);
      b.receiveShot(0, 0);
      expect(b.canRelocate(b.shipOfKind(ShipKind.destroyer)!), isTrue);
      expect(b.relocate(ShipKind.destroyer, 5, 5, true), isTrue);
      // A second hit on the moved hull's intact cell pins it like any
      // other ship (re-hitting the carried-over hole adds nothing).
      b.receiveShot(5, 6);
      final ship = b.shipOfKind(ShipKind.destroyer)!;
      expect(ship.hitIndices.length, 2);
      expect(b.canRelocate(ship), isFalse);
    });

    test('other hulls still pin on the first hit', () {
      final b = Board()..place(kFleet[2], 0, 0, true); // cruiser
      b.receiveShot(0, 0);
      expect(b.canRelocate(b.shipOfKind(ShipKind.cruiser)!), isFalse);
    });
  });

  group('CRUISER — Picket screen (model)', () {
    test('a cruiser hides in shot-up water, others cannot', () {
      Board fresh(ShipKind kind) =>
          Board()..place(kFleet.firstWhere((s) => s.kind == kind), 0, 0, true)
            ..receiveShot(5, 6);
      final cruiserBoard = fresh(ShipKind.cruiser);
      expect(
          cruiserBoard.relocate(ShipKind.cruiser, 5, 5, true), isTrue,
          reason: 'pickets ignore shot history');
      final destroyerBoard = fresh(ShipKind.destroyer);
      expect(
          destroyerBoard.relocate(ShipKind.destroyer, 5, 5, true), isFalse,
          reason: 'ordinary hulls still cannot');
    });
  });

  group('elusive subs (controller)', () {
    test('a hit sub stays draggable through the controller too', () async {
      final c = await _controller(GameMode.hotspot);
      c.lanBattleMode = LanBattleMode.rearrange;
      c.network.setMatchHost(true);
      c.attachNetwork();
      c.boards[0] = Board()..place(kFleet[3], 0, 0, true);
      c.beginBattle(enemyBoard: _enemyWith(kFleet.last, 9, 5));
      // Direct damage (as if a shell landed), then move while damaged.
      c.boards[0].receiveShot(0, 0);
      final ship = c.boards[0].shipOfKind(ShipKind.submarine)!;
      expect(ship.hitIndices, isNotEmpty);
      expect(c.relocateOwnShip(ShipKind.submarine, 5, 5, true), isTrue);
      c.dispose();
    });
  });

}
