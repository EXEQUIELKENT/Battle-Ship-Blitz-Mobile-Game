// LanModeScreen — the mode-VOTE screen's own half of the pre-battle
// reconnect feature: when the peer drops here, `ReconnectOverlay` has to
// show, and when they come back the screen has to actually carry on
// into placement rather than getting stuck.
//
// BUGFIX covered here: `_onNet`'s guard used to be `_lockHold == null`.
// `_lockHold` is the 900ms "let both captains actually see which mode
// won" hold armed the instant the vote locks. A drop landing DURING that
// hold makes `_startMatch` bail out via its own `peerLost`/`peerGone`
// check when the timer fires — without ever resetting `_lockHold` back to
// null. Every `_onNet` firing after that (including the peer's own
// return) saw a non-null `_lockHold` and refused to re-arm it, so the
// match was permanently stuck on this screen: locked, the reconnect
// overlay gone (the peer really is back), but nobody ever navigates to
// placement. Fixed by checking `_lockHold?.isActive` instead of nullness.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:battleship_blitz/models/game_models.dart';
import 'package:battleship_blitz/screens/lan_mode_screen.dart';
import 'package:battleship_blitz/screens/placement_screen.dart';
import 'package:battleship_blitz/services/game_controller.dart';
import 'package:battleship_blitz/services/network_service.dart';
import 'package:battleship_blitz/services/storage_service.dart';

Future<NetworkService> _pumpLanModeScreen(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final profile = ProfileStore();
  await profile.load();
  final net = NetworkService();
  net.setMatchHost(true);
  final controller = GameController(profile: profile, network: net);

  // Mount the providers with a placeholder home FIRST, then push
  // `LanModeScreen` as a separate route in a follow-up frame — exactly
  // how it arrives in the real app (`NetworkService`'s provider lives at
  // the app root, long since done building by the time any match screen
  // is pushed). Mounting both in one `pumpWidget` call instead puts
  // `LanModeScreen.initState`'s `beginPreMatch()` — which calls
  // `notifyListeners()` — inside the SAME build pass as the provider
  // that owns it, which trips "setState() called during build" since
  // that provider element is still mounting.
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ProfileStore>.value(value: profile),
        ChangeNotifierProvider<NetworkService>.value(value: net),
        ChangeNotifierProvider<GameController>.value(value: controller),
      ],
      child: const MaterialApp(home: SizedBox()),
    ),
  );
  await tester.pump();
  final navigator = tester.state<NavigatorState>(find.byType(Navigator));
  navigator.push(
    MaterialPageRoute(builder: (_) => const LanModeScreen(mode: GameMode.hotspot)),
  );
  // NOT `pumpAndSettle`: `OceanBackground` (this screen's backdrop) runs
  // an unbounded `..repeat()` wave animation, so "settle" never arrives —
  // a fixed pump past the page-transition duration is what every other
  // widget test in this suite uses instead.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  return net;
}

/// Casts both picks and runs the 5-second lock-in countdown out, landing
/// on a freshly-armed (still-active) `_lockHold`.
Future<void> _voteAndLock(WidgetTester tester, NetworkService net) async {
  net.castVote(LanBattleMode.turns);
  net.handleIncomingForTest({'type': 'vote', 'm': LanBattleMode.turns.index});
  await tester.pump();
  // kVoteCountdownSeconds ticks, one second apart.
  await tester.pump(const Duration(seconds: 5));
  expect(net.lockedMode, LanBattleMode.turns, reason: 'the vote locked');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the overlay appears the moment the peer drops mid-vote',
      (tester) async {
    final net = await _pumpLanModeScreen(tester);
    expect(find.text('LOST CONNECTION', findRichText: true), findsNothing);

    net.openGraceWindowForTest();
    await tester.pump();

    expect(find.textContaining('LOST CONNECTION'), findsOneWidget);

    // `openGraceWindowForTest` armed a real `Timer.periodic` — the
    // widget test framework insists nothing is left pending at teardown.
    await net.stop();
  });

  testWidgets(
      'a drop mid-lock-hold does not strand the match once the peer '
      'returns', (tester) async {
    final net = await _pumpLanModeScreen(tester);
    await _voteAndLock(tester, net);

    // The 900ms "let them see the winning mode" hold is now running.
    // Drop the peer WHILE it's still in flight.
    net.openGraceWindowForTest();
    expect(net.peerLost, isTrue);

    // The hold's timer fires here — into a match with no peer, so the
    // old code left `_lockHold` stranded on a stale, already-fired Timer.
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.byType(PlacementScreen), findsNothing,
        reason: 'must not sail into placement while the peer is gone');

    // They come back within the grace window.
    net.handleIncomingForTest(
        {'type': 'hello', 'name': 'Returner', 'rejoin': 1});
    await tester.pump();
    expect(net.peerLost, isFalse);
    expect(net.peerGone, isFalse);

    // The hold has to run its course again from here.
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(); // the pushReplacement transition
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(PlacementScreen), findsOneWidget,
        reason: 'the match must resume once the peer is confirmed back — '
            'this is exactly what a stale `_lockHold` used to block');
  });

  testWidgets('a lock that resolves cleanly (no drop) still proceeds '
      'normally', (tester) async {
    final net = await _pumpLanModeScreen(tester);
    await _voteAndLock(tester, net);

    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(); // the pushReplacement transition
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(PlacementScreen), findsOneWidget);
  });
}
