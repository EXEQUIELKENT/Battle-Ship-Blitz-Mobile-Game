import 'package:battleship_blitz/services/storage_service.dart';
import 'package:battleship_blitz/widgets/awesome_cheer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('an idle cheer draws no letters', (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AwesomeCheer(cheerId: 0))));
    expect(find.text('A'), findsNothing);
    expect(find.text('!'), findsNothing);
  });

  testWidgets('a sinking pops AWESOME!, settles, and replays on the next',
      (tester) async {
    var cheerId = 0;
    late StateSetter bump;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (context, setState) {
        bump = setState;
        return Scaffold(body: AwesomeCheer(cheerId: cheerId));
      }),
    ));
    expect(find.text('A'), findsNothing);

    // First sinking: the word bounces in letter by letter. (The plain
    // pump starts the replay — a timed pump first would burn its own
    // duration before the controller even starts. Each letter is two
    // Texts: the rosewood outline plus the gradient fill.)
    bump(() => cheerId++);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('A'), findsNWidgets(2));
    expect(find.text('W'), findsNWidgets(2));
    // The `!` leans in last — give it its beat.
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('!'), findsNWidgets(2));

    // The 1.5s burst plays out and leaves nothing behind.
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump();
    expect(find.text('A'), findsNothing);

    // A second sinking replays the whole burst.
    bump(() => cheerId++);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('A'), findsNWidgets(2));
    await tester.pumpAndSettle();
    expect(find.text('A'), findsNothing);
  });

  test('every cannon owns its own cheer design, none shared', () {
    final bursts = <CheerBurst>{};
    for (final cannon in Catalog.cannonSkins) {
      bursts.add(cheerThemeFor(cannon.id).burst);
    }
    expect(bursts, hasLength(Catalog.cannonSkins.length),
        reason: 'two cannons celebrating identically is the bug');
    // Unknown guns still celebrate — as steel sparks, never nothing.
    expect(cheerThemeFor('not_a_cannon').burst, CheerBurst.sparks);
    expect(cheerThemeFor(null).burst, CheerBurst.sparks);
  });

  testWidgets('every cannon cheers without overflowing', (tester) async {
    String? cannonId;
    var cheerId = 0;
    late StateSetter bump;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (context, setState) {
        bump = setState;
        return Scaffold(
            body: AwesomeCheer(cheerId: cheerId, cannonId: cannonId));
      }),
    ));
    for (final cannon in Catalog.cannonSkins) {
      bump(() {
        cannonId = cannon.id;
        cheerId++;
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('A'), findsNWidgets(2), reason: cannon.id);
      await tester.pumpAndSettle();
      expect(find.text('A'), findsNothing, reason: cannon.id);
    }
  });
}
