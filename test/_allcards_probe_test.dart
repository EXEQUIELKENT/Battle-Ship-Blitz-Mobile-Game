// Scratch harness — not a real test.
import 'package:battleship_blitz/models/game_models.dart';
import 'package:battleship_blitz/models/power_up.dart';
import 'package:battleship_blitz/screens/how_to_play_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> runFor(WidgetTester tester, int ms) async {
  final until = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(until)) {
    await tester.pump(const Duration(milliseconds: 16));
    await Future<void>.delayed(const Duration(milliseconds: 8));
  }
  await tester.pump();
}

void main() {
  testWidgets('every card in the deck can be drawn and spent',
      (tester) async {
    tester.view.physicalSize = const Size(460, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: HowToPlayScreen()));
    await tester.pump(const Duration(milliseconds: 80));
    final steps = 1 + LanBattleMode.values.indexOf(LanBattleMode.powerPlay);
    for (var i = 0; i < steps; i++) {
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pump(const Duration(milliseconds: 60));
    }

    final enemy = tester.getRect(find.descendant(
        of: find.byKey(const ValueKey('guide-enemy-grid')),
        matching: find.byType(AspectRatio)));
    final own = tester.getRect(find.descendant(
        of: find.byKey(const ValueKey('guide-own-grid')),
        matching: find.byType(AspectRatio)));
    final cell = enemy.width / 10;

    final spent = <String>{};
    // Any hint that is NOT the generic fallback proves the card did
    // something it chose to say. The fallback is "<NAME> spent.".
    final inert = <String>{};

    await tester.runAsync(() async {
      for (var turn = 0; turn < 500 && spent.length < PowerUps.deck.length;
          turn++) {
        PowerUpDef? held;
        for (final d in PowerUps.deck) {
          if (find.text('${d.name} — USE IT').evaluate().isNotEmpty) {
            held = d;
            break;
          }
        }
        if (held != null) {
          await tester.tap(find.text('${held.name} — USE IT'));
          await tester.pump(const Duration(milliseconds: 40));
          if (held.needsTarget) {
            final box = held.targetsOwnGrid ? own : enemy;
            // Aim at a hull for the own-grid cards, interior otherwise.
            final rc = held.targetsOwnGrid ? (4, 6) : (4, 4);
            await tester.tapAt(Offset(box.left + cell * (rc.$2 + 0.5),
                box.top + cell * (rc.$1 + 0.5)));
            await runFor(tester, 300);
          }
          spent.add(held.name);
          if (find.text('${held.name} spent.').evaluate().isNotEmpty) {
            inert.add(held.name);
          }
        }
        final box = enemy;
        await tester.tapAt(Offset(box.left + cell * ((turn % 10) + 0.5),
            box.top + cell * (((turn ~/ 10) % 10) + 0.5)));
        await runFor(tester, 2400);
      }
    });

    final missing =
        PowerUps.deck.map((d) => d.name).toSet().difference(spent);
    // ignore: avoid_print
    print('SPENT ${spent.length}/${PowerUps.deck.length}');
    // ignore: avoid_print
    print('NEVER DRAWN: $missing');
    // ignore: avoid_print
    print('DID NOTHING (generic fallback): $inert');
  });
}
