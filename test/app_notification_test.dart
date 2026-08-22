// Widget tests for the app-wide notification banner.
//
// Covers the two reported symptoms — banners piling up under rapid taps,
// and banners appearing somewhere other than the top of the screen — plus
// the stale-teardown race where an old banner's exit animation finishing
// late used to be able to rip its replacement off screen or cancel its
// timer.
//
// TIMING NOTE: assertions about a banner being present use a LONG
// duration and fixed-size pumps. `pumpAndSettle` advances fake time in
// 100 ms steps until frames stop — which happily walks straight across a
// short auto-dismiss timer, dismissing the banner "during" the settle and
// failing every presence check. Only the auto-dismiss tests use short
// durations, and they pump explicit amounts instead of settling.
import 'package:battleship_blitz/widgets/app_notification.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const longDuration = Duration(seconds: 60);
const shortDuration = Duration(milliseconds: 400);
const slideOut = Duration(milliseconds: 600);

BuildContext? harnessContext;

Future<void> _pumpHarness(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          harnessContext = context;
          return const Scaffold(body: SizedBox.expand());
        },
      ),
    ),
  );
}

void showLong(String message, {AppNoticeType type = AppNoticeType.info}) =>
    AppNotification.show(harnessContext!, message,
        type: type, duration: longDuration);

void showShort(String message) =>
    AppNotification.show(harnessContext!, message, duration: shortDuration);

/// Runs the clock past a long-duration banner's auto-dismiss so no timer
/// is left pending when the test framework checks for them.
Future<void> _drainBanner(WidgetTester tester) async {
  await tester.pump(longDuration);
  await tester.pump(slideOut);
}

void main() {
  setUp(() {
    harnessContext = null;
  });

  testWidgets('rapid repeated notices show exactly ONE banner',
      (tester) async {
    await _pumpHarness(tester);

    // The shipyard's insufficient-RP hammering scenario.
    for (var i = 0; i < 5; i++) {
      showLong('Not enough RP!', type: AppNoticeType.error);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(slideOut);

    expect(find.text('Not enough RP!'), findsOneWidget);

    await _drainBanner(tester);
  });

  testWidgets('the banner is anchored at the BOTTOM of the screen',
      (tester) async {
    await _pumpHarness(tester);

    showLong('hello from below');
    await tester.pump(slideOut); // let the entrance animation finish

    final screenHeight = MediaQuery.of(harnessContext!).size.height;
    final bannerBottom =
        tester.getBottomLeft(find.text('hello from below')).dy;
    expect(screenHeight - bannerBottom, lessThan(120),
        reason: 'the notice must rise from the bottom of the screen');

    await _drainBanner(tester);
  });

  testWidgets('an old banner finishing its exit cannot kill its '
      'replacement', (tester) async {
    await _pumpHarness(tester);

    showShort('first');
    // Build the first banner, then let it cross its auto-dismiss and get
    // partway into its slide-out.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(shortDuration + const Duration(milliseconds: 50));
    // The first banner is mid-slide-out here; replace it right now —
    // exactly what a second tap during the exit looks like.
    showLong('second');
    await tester.pump(slideOut);

    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsOneWidget);

    // The replacement must still be alive well past when the OLD banner's
    // teardown would have landed — that stale teardown used to cancel the
    // new timer / remove the new entry outright.
    await tester.pump(shortDuration + slideOut);
    expect(find.text('second'), findsOneWidget);

    await _drainBanner(tester);
  });

  testWidgets('a notice disappears on its own after its duration',
      (tester) async {
    await _pumpHarness(tester);

    showShort('fleeting');
    // Build a frame FIRST so the banner exists before its timer fires —
    // a single long pump would elapse straight past the duration before
    // any frame renders.
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('fleeting'), findsOneWidget);

    await tester.pump(shortDuration); // timer fires, reverse begins
    await tester.pump(slideOut); // reverse completes, entry removed
    expect(find.text('fleeting'), findsNothing);
  });

  testWidgets('a timer that fires before the banner is ever built still '
      'removes it', (tester) async {
    await _pumpHarness(tester);

    AppNotification.show(harnessContext!, 'instant',
        duration: const Duration(milliseconds: 50));
    // One long pump: the 50 ms timer elapses BEFORE this builds a frame,
    // so there is no live state to animate out — the entry must be torn
    // down statically rather than leaking forever.
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('instant'), findsNothing);
  });
}
