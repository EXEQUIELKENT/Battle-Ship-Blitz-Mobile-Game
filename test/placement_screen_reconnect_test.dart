// PlacementScreen — the DEPLOY screen's own half of the pre-battle
// reconnect feature: a peer who drops here (before or after this player
// hit SAVE) gets the same reconnect overlay a mid-battle drop shows, and
// coming back re-triggers whatever this player was owed to send them.
//
// `_onNetForPeer` is the piece doing the work: on a drop it tears down the
// "WAITING FOR OPPONENT…" dialog (so the reconnect overlay underneath is
// actually visible) without discarding this player's own fleet — it is
// still owed the moment the peer returns, which is also tested here.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:battleship_blitz/models/game_models.dart';
import 'package:battleship_blitz/screens/placement_screen.dart';
import 'package:battleship_blitz/services/game_controller.dart';
import 'package:battleship_blitz/services/network_service.dart';
import 'package:battleship_blitz/services/online_service.dart';
import 'package:battleship_blitz/services/storage_service.dart';

Future<NetworkService> _pumpDeployScreen(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final profile = ProfileStore();
  await profile.load();
  final net = NetworkService();
  net.setMatchHost(true);
  final controller = GameController(profile: profile, network: net);
  controller.mode = GameMode.hotspot;
  controller.lanBattleMode = LanBattleMode.turns;
  // `startPlacement` always resets `boards[0]` itself — a plain
  // assignment beforehand would just be overwritten with an empty board.
  controller.startPlacement(preset: Board.random());

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ProfileStore>.value(value: profile),
        ChangeNotifierProvider<NetworkService>.value(value: net),
        ChangeNotifierProvider<OnlineService>.value(value: OnlineService()),
        ChangeNotifierProvider<GameController>.value(value: controller),
      ],
      child: const MaterialApp(home: PlacementScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(); // the screen's own post-first-frame geometry rebuild
  return net;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the overlay appears the moment the peer drops mid-deploy '
      '(before SAVE)', (tester) async {
    final net = await _pumpDeployScreen(tester);
    expect(find.textContaining('LOST CONNECTION'), findsNothing);

    net.openGraceWindowForTest();
    await tester.pump();

    expect(find.textContaining('LOST CONNECTION'), findsOneWidget);
    await net.stop(); // release the pending grace Timer
  });

  testWidgets(
      'a drop AFTER SAVE tears down the waiting dialog, and the fleet is '
      're-sent the moment the peer is back', (tester) async {
    final net = await _pumpDeployScreen(tester);

    await tester.tap(find.text('SAVE'));
    await tester.pump();
    expect(find.text('WAITING FOR OPPONENT…'), findsOneWidget);
    expect(net.sentForTest.where((m) => m['type'] == 'board'), hasLength(1));

    // The peer drops while we're still waiting on their fleet.
    net.openGraceWindowForTest();
    await tester.pump();

    expect(find.text('WAITING FOR OPPONENT…'), findsNothing,
        reason: 'the dialog must not sit on top of the reconnect overlay');
    expect(find.textContaining('LOST CONNECTION'), findsOneWidget);

    // They come back within the grace window.
    net.handleIncomingForTest(
        {'type': 'hello', 'name': 'Returner', 'rejoin': 1});
    await tester.pump();

    expect(net.peerLost, isFalse);
    expect(find.textContaining('LOST CONNECTION'), findsNothing);
    // Our fleet was sent before the drop, from a placement that (as far
    // as we know) no longer exists on their now-fresh device — it has to
    // go out again rather than assuming they still have the first copy.
    expect(net.sentForTest.where((m) => m['type'] == 'board'), hasLength(2),
        reason: 'the fleet is re-sent, not just the wait resumed');
    expect(find.text('WAITING FOR OPPONENT…'), findsOneWidget,
        reason: 'and we go back to waiting for THEIRS in turn');
  });

  testWidgets(
      'a drop BEFORE SAVE leaves this player free to keep placing — the '
      'overlay does not block editing', (tester) async {
    final net = await _pumpDeployScreen(tester);

    net.openGraceWindowForTest();
    await tester.pump();
    expect(find.textContaining('LOST CONNECTION'), findsOneWidget);
    // SAVE must still be there underneath — the overlay does not gate it,
    // it only reports what the peer is doing.
    expect(find.text('SAVE'), findsOneWidget);

    await net.stop();
  });
}
